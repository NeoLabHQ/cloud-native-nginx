# Nginx Security Stack

Reverse proxy with built-in WAF, rate limiting, and OWASP protection. Single Docker image — put it in front of your backend.

## 1. Run

The only required setting is `BACKEND` — the URL of your application.

```bash
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -p 80:8080 \
  viktorpalchynskyi/nginx-security
```

Check that it works:

```bash
curl http://localhost/healthz
```

Done. WAF and rate limiting are enabled by default.

## 2. Add HTTPS (optional)

Provide your SSL certificate and key:

```bash
docker run -d --name nginx-security \
  -e BACKEND=http://your-app:3000 \
  -e NGINX_ALWAYS_TLS_REDIRECT=on \
  -v /path/to/fullchain.pem:/etc/nginx/certs/fullchain.pem:ro \
  -v /path/to/privkey.pem:/etc/nginx/certs/privkey.pem:ro \
  -p 80:8080 -p 443:8443 \
  viktorpalchynskyi/nginx-security
```

If your backend is on HTTPS, add:

```bash
  -e BACKEND=https://your-app:8443 \
  -e PROXY_SSL=on \
```

## 3. Add Monitoring with Grafana (optional)

Starts Loki + Promtail + Grafana + nginx-exporter + CrowdSec alongside the nginx-security container.

**With make:**

```bash
make start-monitoring
```

**With docker compose:**

```bash
docker compose -f docker-compose.monitoring.yml --profile standalone --profile grafana up -d
docker network connect nginx-security-monitoring nginx-security
```

After startup:

1. Open Grafana at `http://localhost:3000` (login: `admin` / `admin`)
2. Go to **Dashboards** → **Import** → upload [`monitoring/dashboards/nginx-security.json`](monitoring/dashboards/nginx-security.json)
3. Select **Prometheus** and **Loki** data sources when prompted

Check health:

```bash
make health-monitoring
```

Stop:

```bash
make stop-monitoring
```

### Connect to an Existing Grafana

If you already have Grafana, Prometheus, and Loki — use external mode. Only Promtail, nginx-exporter, and CrowdSec are started.

**With make:**

```bash
# Set your Loki URL in .env or export it
export LOKI_URL=https://your-loki:3100/loki/api/v1/push

make start-monitoring-external
```

**With docker compose:**

```bash
export LOKI_URL=https://your-loki:3100/loki/api/v1/push

docker compose -f docker-compose.monitoring.yml up -d nginx-exporter crowdsec promtail
docker network connect nginx-security-monitoring nginx-security
```

Then add scrape targets to your Prometheus (see [`monitoring/prometheus-scrape-config.yml`](monitoring/prometheus-scrape-config.yml)):

```yaml
scrape_configs:
  - job_name: 'nginx-waf'
    static_configs:
      - targets: ['<nginx-security-host>:9113']
  - job_name: 'crowdsec'
    static_configs:
      - targets: ['<nginx-security-host>:6060']
```

Import the dashboard [`monitoring/dashboards/nginx-security.json`](monitoring/dashboards/nginx-security.json) into your Grafana.

### Useful Loki Queries

```
{job="nginx", type="access"} |= "403"    # Blocked by WAF
{job="nginx", type="access"} |= "429"    # Rate limited
{job="modsecurity"}                       # WAF audit events
```

## Reference

### Environment Variables

All variables have sensible defaults. You only need to set `BACKEND`.

| Variable | Default | Description |
|----------|---------|-------------|
| **Core** | | |
| `BACKEND` | `http://localhost:80` | **Required.** Backend URL to proxy to |
| `PORT` | `8080` | HTTP listen port |
| `SSL_PORT` | `8443` | HTTPS listen port |
| `SERVER_NAME` | `_` | Nginx server_name |
| `PROXY_TIMEOUT` | `60` | Backend proxy timeout (seconds) |
| `SERVER_TOKENS` | `off` | Show nginx version in headers (`on`/`off`) |
| **WAF** | | |
| `MODSEC_RULE_ENGINE` | `On` | `On` = blocking, `DetectionOnly` = logging only, `Off` = disabled |
| `PARANOIA` | `1` | OWASP CRS paranoia level 1-4 (higher = stricter) |
| `ANOMALY_INBOUND` | `5` | Inbound anomaly score threshold |
| `ANOMALY_OUTBOUND` | `4` | Outbound anomaly score threshold |
| `MODSEC_AUDIT_LOG` | `/var/log/modsecurity/audit.log` | Path to WAF audit log |
| `MODSEC_AUDIT_LOG_FORMAT` | `JSON` | Audit log format (`JSON` or `Native`) |
| **HTTPS backend** | | |
| `PROXY_SSL` | `off` | Enable SSL to backend (`on`/`off`) |
| `PROXY_SSL_VERIFY` | `off` | Verify backend SSL certificate (`on`/`off`) |
| `PROXY_SSL_PROTOCOLS` | `TLSv1.2 TLSv1.3` | Allowed SSL protocols to backend |
| **Real IP** | | |
| `SET_REAL_IP_FROM` | — | Trusted proxy CIDR for LB/CDN (e.g. `10.0.0.0/8`) |
| `REAL_IP_HEADER` | `X-Forwarded-For` | Header containing real client IP |
| **SSL termination** | | |
| `SSL_CERT_FILE` | `/etc/nginx/certs/fullchain.pem` | Path to SSL certificate |
| `SSL_CERT_KEY_FILE` | `/etc/nginx/certs/privkey.pem` | Path to SSL private key |
| `SSL_PROTOCOLS` | `TLSv1.2 TLSv1.3` | Allowed TLS protocols |
| `SSL_CIPHERS` | *(base image default)* | Allowed SSL ciphers |
| `SSL_PREFER_CIPHERS` | `on` | Prefer server ciphers over client (`on`/`off`) |
| `SSL_DH_BITS` | `2048` | DH parameters size (`2048` or `4096`) |
| `SSL_OCSP_STAPLING` | `on` | OCSP stapling (`on`/`off`) |
| `SSL_VERIFY` | `off` | Verify client certificate (`on`/`off`) |
| `SSL_VERIFY_DEPTH` | `1` | Client certificate chain verification depth |
| `NGINX_ALWAYS_TLS_REDIRECT` | `off` | Redirect all HTTP to HTTPS (`on`/`off`) |

### Volumes

All optional. The image works out of the box.

| Container Path | What It Does |
|----------------|-------------|
| `/etc/nginx/certs/` | SSL certificates for HTTPS termination |
| `/var/log/nginx/` | Nginx access and error logs |
| `/var/log/modsecurity/` | WAF audit logs (JSON) |
| `/etc/nginx/templates/conf.d/default.conf.template` | Custom nginx config (override rate limits, locations) |
| `/etc/modsecurity.d/owasp-crs/rules/RESPONSE-999-CUSTOM.conf` | Custom WAF rules |
| `/etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf` | WAF rule exclusions (false positive fixes) |

### Ports

| Port | Description |
|------|-------------|
| 8080 | HTTP |
| 8443 | HTTPS |
| 9113 | nginx-exporter metrics (sidecar) |
| 6060 | CrowdSec metrics (sidecar) |
