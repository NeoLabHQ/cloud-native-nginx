# Nginx Security Stack

Production-ready security layer for web applications. Single Docker image with WAF, rate limiting, and OWASP protection.

**Features**:
- OWASP ModSecurity CRS v4 (WAF with 15 custom rules)
- Rate limiting per IP (auth: 5 req/min, API: 100 req/min)
- SQL injection, XSS, SSRF, path traversal protection
- Scanner/bot detection (sqlmap, nikto, nmap, burpsuite)
- HTTPS backend proxy support (for backends on HTTPS:8443)
- JSON audit logging for all blocked requests
- Optional monitoring: CrowdSec IPS, Loki, Grafana

## Prerequisites

- Docker 20.10+
- 512MB RAM minimum (1GB recommended with monitoring)
- SSL certificates (for HTTPS termination, optional)

## Quick Start

```bash
# 1. Build the image
make build

# 2. Run with your backend
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -p 80:8080 \
  neolab/nginx-security

# 3. Verify
curl http://localhost/healthz
```

### Cloudbankin Deployment (HTTPS backend)

```bash
docker run -d --name nginx-security \
  -e BACKEND=https://paapapayperf.uat.cloudbankin.com:8443 \
  -e PROXY_SSL=on \
  -e PROXY_SSL_VERIFY=off \
  -p 80:8080 -p 443:8443 \
  neolab/nginx-security
```

### With SSL Termination

```bash
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -p 80:8080 -p 443:8443 \
  -v /path/to/fullchain.pem:/etc/nginx/certs/fullchain.pem:ro \
  -v /path/to/privkey.pem:/etc/nginx/certs/privkey.pem:ro \
  neolab/nginx-security
```

## Development Mode

Uses docker-compose with httpbin test backend:

```bash
cp .env.example .env
make start          # Starts nginx-waf + crowdsec + httpbin
make test           # Run security + false positive tests
make stop           # Stop everything
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND` | `http://localhost:80` | Backend URL to proxy to |
| `PORT` | `8080` | HTTP listen port |
| `SSL_PORT` | `8443` | HTTPS listen port |
| `SERVER_NAME` | `_` | Nginx server_name |
| `MODSEC_RULE_ENGINE` | `On` | WAF mode: `On`, `DetectionOnly`, `Off` |
| `PARANOIA` | `1` | OWASP CRS paranoia level (1-4, higher = stricter) |
| `ANOMALY_INBOUND` | `5` | Inbound anomaly score threshold |
| `ANOMALY_OUTBOUND` | `4` | Outbound anomaly score threshold |
| `PROXY_TIMEOUT` | `60` | Backend proxy timeout (seconds) |
| `PROXY_SSL` | `off` | Enable SSL to backend (`on`/`off`) |
| `PROXY_SSL_VERIFY` | `off` | Verify backend SSL cert (`on`/`off`) |
| `PROXY_SSL_PROTOCOLS` | `TLSv1.2 TLSv1.3` | Allowed SSL protocols to backend |
| `SET_REAL_IP_FROM` | — | Trusted proxy CIDR (for LB/CDN) |
| `REAL_IP_HEADER` | `X-Forwarded-For` | Header containing real client IP |

## Add Monitoring (Optional)

The monitoring stack runs as separate containers alongside the main image:

```bash
# Start CrowdSec + Loki + Promtail + nginx-exporter
docker compose -f docker-compose.monitoring.yml up -d

# With Grafana dashboards
docker compose -f docker-compose.monitoring.yml --profile grafana up -d

# With CrowdSec firewall bouncer (IP blocking)
docker compose -f docker-compose.monitoring.yml --profile bouncer up -d

# Check health
make health-monitoring

# Stop
make stop-monitoring
```

Monitoring services share logs via host-mounted `./logs/` volume.

**Ports**: nginx-exporter (9113), CrowdSec (6060), Loki (3100), Grafana (3000)

### Connect to Existing Grafana (Loki Data Source)

If Cloudbankin already has Grafana, add Loki as a data source instead of running a separate Grafana:

```bash
# Start monitoring without Grafana
docker compose -f docker-compose.monitoring.yml up -d
```

In your existing Grafana, add data source:
- **Type**: Loki
- **URL**: `http://<monitoring-host>:3100`
- **Access**: Server

Example queries:
- All blocked requests: `{job="nginx", type="access"} |= "403"`
- ModSecurity audit events: `{job="modsecurity"}`
- Rate-limited requests: `{job="nginx", type="access"} |= "429"`

## Configuration Reference

### Paranoia Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| 1 | Standard detection, minimal false positives | Production (default) |
| 2 | Extended detection, some false positives | Sensitive APIs |
| 3 | Aggressive detection, more false positives | High-security |
| 4 | Maximum detection, many false positives | Testing/audit only |

### Rate Limiting

| Zone | Rate | Burst | Endpoints |
|------|------|-------|-----------|
| `auth` | 5 req/min | 3 | Login, register, verify, OTP, authentication |
| `api` | 100 req/min | 20 | `/api/*`, `/graphql` |

Auth rate limiting matches Cloudbankin URL patterns:
- `/api/auth/login`
- `/cloudbankin/api/v1/public/los/login`
- `/cloudbankin/api/v1/authentication`
- `/cloudbankin/api/v1/public/los/borrower-login-verify`

### Custom WAF Rules (15 rules)

- Advanced SQL injection detection
- XSS (script, javascript:, event handlers)
- Command injection with path traversal
- Path traversal (plain, URL-encoded, double-encoded)
- Sensitive file access (.env, .git, /etc/passwd)
- Null byte injection
- Scanner/bot User-Agent detection
- SSRF protection (internal IPs, cloud metadata)
- HTTP method restriction (GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD)

## Verification

```bash
# Health check
curl http://localhost:8080/healthz

# WAF test (should return 403)
curl "http://localhost:8080/?id=1'+OR+'1'='1"

# Rate limit test (6th request should return 429)
for i in {1..6}; do
  curl -s -o /dev/null -w "%{http_code} " -X POST http://localhost:8080/api/auth/login
done

# Run full test suite (requires development mode)
make test-security
make test-false-pos
```

## Troubleshooting

### False Positives (Legitimate Requests Blocked)

```bash
# 1. Check which rule is blocking
docker exec nginx-waf tail -100 /var/log/modsecurity/audit.log | jq '.transaction.messages[].ruleId'

# 2. Add exclusion to config/modsecurity/exclusions.conf:
# SecRuleRemoveById <rule_id>

# 3. Rebuild image
make build
```

### Emergency WAF Disable

```bash
# Switch to detection-only mode (logs but doesn't block)
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -e MODSEC_RULE_ENGINE=DetectionOnly \
  -p 80:8080 \
  neolab/nginx-security

# Disable WAF completely
# -e MODSEC_RULE_ENGINE=Off
```

### Load Balancer / CDN Configuration

When behind a load balancer, set these to get real client IPs for rate limiting:

```bash
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -e SET_REAL_IP_FROM=10.0.0.0/8 \
  -e REAL_IP_HEADER=X-Forwarded-For \
  -p 80:8080 \
  neolab/nginx-security
```

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │         neolab/nginx-security            │
  Client ──────►   │  Nginx + ModSecurity CRS v4              │  ──────► Backend
  (HTTP/HTTPS)     │  ┌─────────┐  ┌──────────┐  ┌────────┐  │          (HTTP/HTTPS)
                    │  │  Rate   │─►│   WAF    │─►│ Proxy  │  │
                    │  │ Limiter │  │(15 rules)│  │        │  │
                    │  └─────────┘  └──────────┘  └────────┘  │
                    └────────────────────┬────────────────────┘
                                         │ logs (volume mount)
                    ┌────────────────────┴────────────────────┐
                    │     Monitoring (optional, separate)      │
                    │  CrowdSec │ Loki │ Promtail │ Grafana   │
                    └─────────────────────────────────────────┘
```

## File Structure

```
cloud-native-nginx/
├── Dockerfile                          # Single-image build
├── .dockerignore                       # Build context exclusions
├── Makefile                            # All commands
├── docker-compose.yml                  # Development env (with httpbin)
├── docker-compose.monitoring.yml       # Monitoring stack (optional)
├── .env.example                        # Environment variable template
│
├── config/
│   ├── nginx/
│   │   └── default.conf.template       # Nginx config (rate limiting, proxy)
│   ├── modsecurity/
│   │   ├── custom-rules.conf           # 15 custom WAF rules
│   │   └── exclusions.conf             # False positive exclusions
│   ├── crowdsec/                       # CrowdSec IPS config
│   ├── loki/
│   │   └── loki-config.yml             # Log aggregation config
│   └── promtail/
│       └── promtail-config.yml         # Log collector config
│
├── scripts/
│   ├── test-security.sh                # Attack tests (SQLi, XSS, SSRF, etc.)
│   └── test-false-positives.sh         # Legitimate traffic tests
│
├── docs/
│   ├── QUICK_REFERENCE.md              # Command reference
│   └── EMERGENCY.md                    # Emergency procedures
│
├── certs/                              # SSL certificates (not in image)
├── logs/                               # Shared log volume
│   ├── nginx/
│   └── modsecurity/
└── monitoring/
    └── prometheus-scrape-config.yml    # Prometheus config template
```

## Docs

- [Quick Reference](docs/QUICK_REFERENCE.md) - All commands and manual operations
- [Emergency Procedures](docs/EMERGENCY.md) - Incident response playbook
