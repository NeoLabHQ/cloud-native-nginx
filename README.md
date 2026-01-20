# Nginx Security Stack

Docker-based security stack with WAF (ModSecurity + OWASP CRS), CrowdSec, and Rate Limiting for protecting web applications.

## Features

| Feature | Protection | Status |
|---------|------------|--------|
| WAF (ModSecurity + OWASP CRS) | SQL Injection, XSS, Command Injection | Included |
| Rate Limiting | Brute-force, DoS (L7) | Included |
| Security Headers | HSTS, CSP, X-Frame-Options | Included |
| IP Banning | Automatic ban after attacks | Included (CrowdSec) |
| TLS 1.2/1.3 | MitM, SSL Stripping | Configurable |
| Prometheus Metrics | nginx-exporter, CrowdSec | Included |

## Architecture

```
Internet → nginx-waf (ModSecurity + OWASP CRS) → CrowdSec Bouncer → Backend App
                    ↓
              CrowdSec (IP reputation)
                    ↓
           Prometheus Metrics (ports 9113, 6060)
```

## Quick Start

### Step 1: Clone and Setup

```bash
cd cloud-native-nginx

# Copy environment file
cp .env.example .env

# Edit .env with your backend URL
nano .env
```

### Step 2: Configure Backend

Edit `.env`:
```bash
# Your backend application
BACKEND=your-app:3000

# Or for host machine backend
BACKEND=host.docker.internal:3000
```

### Step 3: Generate SSL Certificates (for testing)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout certs/privkey.pem \
    -out certs/fullchain.pem \
    -subj "/CN=localhost"
```

### Step 4: Start Services

```bash
# Start core services
docker-compose up -d nginx-waf crowdsec crowdsec-bouncer nginx-exporter

# Register CrowdSec bouncer (first time only)
docker exec crowdsec cscli bouncers add nginx-bouncer
# Copy the API key to .env: CROWDSEC_BOUNCER_KEY=<key>

# Restart bouncer with API key
docker-compose up -d crowdsec-bouncer
```

### Step 5: Verify

```bash
# Run security tests
./scripts/test-security.sh

# Run false positive tests
./scripts/test-false-positives.sh

# Check metrics
curl http://localhost:9113/metrics  # nginx-exporter
curl http://localhost:6060/metrics  # CrowdSec
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND` | `app:3000` | Backend application address |
| `MODSEC_RULE_ENGINE` | `On` | WAF mode: `On`, `DetectionOnly`, `Off` |
| `PARANOIA` | `1` | OWASP CRS paranoia level (1-4) |
| `CROWDSEC_BOUNCER_KEY` | - | CrowdSec bouncer API key |
| `NGINX_HTTP_PORT` | `80` | Nginx HTTP port |
| `NGINX_HTTPS_PORT` | `443` | Nginx HTTPS port |

### Rate Limiting

Default rate limits configured in `config/nginx/nginx.conf`:

| Endpoint | Rate | Burst | Purpose |
|----------|------|-------|---------|
| `/api/auth/verify-otp` | 3/min | 2 | OTP verification |
| `/api/auth/send-otp` | 3/min | 2 | OTP sending |
| `/api/auth/login` | 5/min | 3 | Login attempts |
| `/api/export`, `/api/reports` | 10/min | 5 | Heavy endpoints |
| `/api/*` | 100/min | 50 | General API |

To adjust rate limits, edit `config/nginx/nginx.conf`:
```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=200r/m;  # Increase to 200/min
```

### ModSecurity Rules

Custom rules are in `config/modsecurity/custom-rules.conf`.
Rule exclusions are in `config/modsecurity/exclusions.conf`.

To disable a specific rule:
```apache
# In exclusions.conf
SecRuleRemoveById 942100
```

To disable for a specific URL:
```apache
SecRule REQUEST_URI "@beginsWith /api/upload" \
    "id:900200,phase:1,pass,nolog,ctl:ruleRemoveById=942100"
```

### CrowdSec Setup

```bash
# List current decisions (bans)
docker exec crowdsec cscli decisions list

# Ban an IP manually
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 4h --reason "manual ban"

# Unban an IP
docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# List installed collections
docker exec crowdsec cscli collections list

# Update CrowdSec hub
docker exec crowdsec cscli hub update
```

## Metrics & Monitoring

### Available Endpoints

| Service | Endpoint | Port | Metrics |
|---------|----------|------|---------|
| nginx-exporter | `/metrics` | 9113 | Connections, requests, status |
| CrowdSec | `/metrics` | 6060 | Alerts, decisions, parsers |

### Prometheus Scrape Config

Add to your Prometheus `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'nginx-waf'
    static_configs:
      - targets: ['<host>:9113']
    scrape_interval: 15s

  - job_name: 'crowdsec'
    static_configs:
      - targets: ['<host>:6060']
    scrape_interval: 30s
```

See `monitoring/prometheus-scrape-config.yml` for full configuration.

### Key Metrics

**Nginx Exporter:**
- `nginx_connections_active` - Active connections
- `nginx_http_requests_total` - Total requests
- `nginx_up` - Nginx status

**CrowdSec:**
- `cs_active_decisions{action="ban"}` - Active bans
- `cs_bucket_overflowed_total` - Attacks detected
- `cs_alerts_total` - Total alerts

### Recommended Alerts

See `monitoring/alerting-rules.yml` for pre-configured alerts:
- Nginx WAF down
- CrowdSec unreachable
- High attack rate
- WAF blocking many requests
- Rate limiting triggered frequently

## Troubleshooting

### How to Disable WAF (Emergency)

**Option 1: Detection-Only Mode (Recommended)**

WAF logs but doesn't block:
```bash
# Edit .env
MODSEC_RULE_ENGINE=DetectionOnly

# Restart
docker-compose up -d nginx-waf
```

**Option 2: Disable WAF Completely**
```bash
# Edit .env
MODSEC_RULE_ENGINE=Off

# Restart
docker-compose up -d nginx-waf
```

### How to Disable Rate Limiting

Comment out `limit_req` lines in `config/nginx/nginx.conf`:
```nginx
location /api/auth/verify-otp {
    # limit_req zone=otp burst=2 nodelay;
    # limit_req_status 429;
    proxy_pass http://backend;
    ...
}
```

Then restart:
```bash
docker-compose restart nginx-waf
```

### How to Disable Custom Rules Only

```bash
# Rename to disable
mv config/modsecurity/custom-rules.conf config/modsecurity/custom-rules.conf.disabled

# Restart
docker-compose restart nginx-waf

# To re-enable
mv config/modsecurity/custom-rules.conf.disabled config/modsecurity/custom-rules.conf
docker-compose restart nginx-waf
```

### How to Rollback Configuration

Using git:
```bash
# Commit current working config
git add config/
git commit -m "Working config"

# Make changes...

# If something breaks, rollback
git checkout HEAD -- config/
docker-compose restart nginx-waf
```

### View Logs

```bash
# Nginx access/error logs
docker-compose logs -f nginx-waf
cat logs/nginx/access.log | jq .  # JSON formatted

# ModSecurity audit log
docker exec nginx-waf cat /var/log/modsecurity/audit.log | jq .

# CrowdSec logs
docker-compose logs -f crowdsec

# Find what rule blocked a request
docker exec nginx-waf cat /var/log/modsecurity/audit.log | jq '.transaction.messages'
```

### Common Issues

**1. Backend not reachable**
```bash
# Check if backend is accessible from nginx container
docker exec nginx-waf curl -v http://your-backend:3000/healthz
```

**2. False positives blocking legitimate traffic**
```bash
# 1. Find the blocking rule
docker exec nginx-waf cat /var/log/modsecurity/audit.log | jq '.transaction.messages[].ruleId'

# 2. Add exclusion
echo 'SecRuleRemoveById <RULE_ID>' >> config/modsecurity/exclusions.conf

# 3. Restart
docker-compose restart nginx-waf
```

**3. Rate limiting too aggressive**

Edit rate limits in `config/nginx/nginx.conf` and restart.

**4. CrowdSec bouncer not working**
```bash
# Check bouncer key
docker exec crowdsec cscli bouncers list

# Regenerate if needed
docker exec crowdsec cscli bouncers delete nginx-bouncer
docker exec crowdsec cscli bouncers add nginx-bouncer
# Update CROWDSEC_BOUNCER_KEY in .env
docker-compose up -d crowdsec-bouncer
```

## Testing

### Security Tests

```bash
# Run all security tests
./scripts/test-security.sh

# Test against specific host
./scripts/test-security.sh yourdomain.com https
```

Expected results:
- SQL Injection → 403
- XSS → 403
- Command Injection → 403
- Path Traversal → 403/404
- Rate limiting → 429 after threshold

### False Positive Tests

```bash
# Verify legitimate requests aren't blocked
./scripts/test-false-positives.sh
```

These should NOT return 403:
- Phone numbers: `(123)456-7890`
- Wildcard search: `test*`
- Math expressions: `2*(3+4)`
- JSON payloads
- GraphQL queries

### Manual Tests

```bash
# SQL Injection (should be 403)
curl "http://localhost/?id=1' OR '1'='1"

# XSS (should be 403)
curl "http://localhost/?q=<script>alert(1)</script>"

# Rate limit test (should see 429 after 3 requests)
for i in {1..6}; do curl -X POST http://localhost/api/auth/verify-otp; done

# Health check (should be 200)
curl http://localhost/healthz
```

## Maintenance

### Log Rotation

Logs are stored in `logs/` directory. Configure logrotate:

```bash
# /etc/logrotate.d/nginx-security
/path/to/cloud-native-nginx/logs/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        docker exec nginx-waf nginx -s reload
    endscript
}
```

### Certificate Renewal

For Let's Encrypt:
```bash
# Stop nginx temporarily
docker-compose stop nginx-waf

# Renew certificates
certbot renew

# Copy new certs
cp /etc/letsencrypt/live/yourdomain/fullchain.pem certs/
cp /etc/letsencrypt/live/yourdomain/privkey.pem certs/

# Start nginx
docker-compose up -d nginx-waf
```

### Updating CrowdSec Rules

```bash
# Update hub
docker exec crowdsec cscli hub update

# Upgrade all components
docker exec crowdsec cscli hub upgrade --all

# Restart CrowdSec
docker-compose restart crowdsec
```

### Updating Docker Images

```bash
# Pull latest images
docker-compose pull

# Recreate containers
docker-compose up -d
```

## File Structure

```
cloud-native-nginx/
├── README.md                              # This file
├── docker-compose.yml                     # Docker services
├── .env.example                           # Environment template
├── config/
│   ├── nginx/
│   │   ├── nginx.conf                     # Main nginx config
│   │   ├── security-headers.conf          # Security headers
│   │   └── proxy-headers.conf             # Proxy headers
│   ├── modsecurity/
│   │   ├── custom-rules.conf              # Custom WAF rules
│   │   └── exclusions.conf                # Rule exclusions
│   └── crowdsec/
│       └── config.yaml.local              # CrowdSec config
├── monitoring/
│   ├── prometheus-scrape-config.yml       # Prometheus config
│   └── alerting-rules.yml                 # Alert rules
├── scripts/
│   ├── test-security.sh                   # Security tests
│   └── test-false-positives.sh            # False positive tests
├── certs/                                 # SSL certificates
└── logs/                                  # Log files
```

## Support

- ModSecurity: https://github.com/owasp-modsecurity/ModSecurity
- OWASP CRS: https://coreruleset.org/
- CrowdSec: https://doc.crowdsec.net/
- Nginx: https://nginx.org/en/docs/
