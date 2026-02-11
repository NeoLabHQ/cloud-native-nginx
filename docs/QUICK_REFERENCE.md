# Quick Reference

Common commands for managing the Nginx Security Stack.

## Service Management

| Command | Description |
|---------|-------------|
| `make start` | Start core services (nginx-waf, crowdsec, nginx-exporter, httpbin) |
| `make start-monitoring` | Start with monitoring stack (Loki, Promtail, Grafana) |
| `make stop` | Stop all services |
| `make restart` | Restart core services |
| `make status` | Show service status |
| `make health` | Check health endpoints |
| `make clean` | Stop services and remove volumes |

## Testing

| Command | Description |
|---------|-------------|
| `make test` | Run all tests (security + false positives) |
| `make test-security` | Run security tests only |
| `make test-false-pos` | Run false positive tests only |

## Logs

| Command | Description |
|---------|-------------|
| `make logs` | View nginx-waf logs (follow mode) |
| `make logs-audit` | View ModSecurity audit logs (JSON) |
| `docker-compose logs -f crowdsec` | View CrowdSec logs |
| `docker-compose logs -f nginx-exporter` | View exporter logs |

### Manual Log Commands

```bash
# View last 100 lines of access log
docker exec nginx-waf tail -100 /var/log/nginx/access.log

# View last 100 lines of error log
docker exec nginx-waf tail -100 /var/log/nginx/error.log

# View blocked requests (403)
docker exec nginx-waf grep " 403 " /var/log/nginx/access.log | tail -50

# View ModSecurity blocks with rule IDs
docker exec nginx-waf tail -100 /var/log/modsecurity/audit.log | jq -r '.transaction.messages[]?.message'
```

## CrowdSec Ban Management

| Command | Description |
|---------|-------------|
| `make bans` | List all current bans |
| `make unban-all` | Remove all bans |

### Manual CrowdSec Commands

```bash
# List bans
docker exec crowdsec cscli decisions list

# Unban specific IP
docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# Unban by decision ID
docker exec crowdsec cscli decisions delete --id 12345

# View alerts
docker exec crowdsec cscli alerts list

# View installed collections
docker exec crowdsec cscli collections list

# View bouncers
docker exec crowdsec cscli bouncers list
```

## Configuration Updates

### ModSecurity Rules

```bash
# Edit custom rules
vim config/modsecurity/custom-rules.conf

# Edit exclusions
vim config/modsecurity/exclusions.conf

# Restart to apply
docker-compose restart nginx-waf
```

### Nginx Configuration

```bash
# Edit nginx config
vim config/nginx/default.conf.template

# Validate config before restart
docker exec nginx-waf nginx -t

# Restart to apply
docker-compose restart nginx-waf
```

### Environment Variables

```bash
# Edit environment
vim .env

# Restart affected services
docker-compose restart nginx-waf crowdsec
```

## Health Checks

```bash
# Check nginx-waf health
curl -s http://localhost:8080/healthz

# Check nginx-exporter metrics
curl -s http://localhost:9113/metrics | head -20

# Check CrowdSec metrics
curl -s http://localhost:6060/metrics | head -20

# Check stub_status
curl -s http://localhost:8080/stub_status
```

## Debugging

### Test Specific Attack Pattern

```bash
# SQL Injection
curl "http://localhost:8080/?id=1' OR '1'='1"

# XSS
curl "http://localhost:8080/?q=<script>alert(1)</script>"

# SSRF
curl "http://localhost:8080/?url=http://169.254.169.254/latest/meta-data"

# Path Traversal
curl "http://localhost:8080/?file=../../../etc/passwd"
```

### Check Resource Usage

```bash
# View container stats
docker stats --no-stream

# View specific container
docker stats nginx-waf --no-stream
```

## Ports Reference

| Service | Port | Purpose |
|---------|------|---------|
| nginx-waf | 8080 | HTTP traffic |
| nginx-waf | 8443 | HTTPS traffic |
| nginx-exporter | 9113 | Prometheus metrics |
| crowdsec | 6060 | Metrics |
| loki | 3100 | Log aggregation |
| grafana | 3000 | Visualization |

## File Locations

| File | Purpose |
|------|---------|
| `config/nginx/default.conf.template` | Nginx configuration |
| `config/modsecurity/custom-rules.conf` | Custom WAF rules |
| `config/modsecurity/exclusions.conf` | Rule exclusions |
| `config/crowdsec/` | CrowdSec configuration |
| `logs/nginx/` | Nginx logs |
| `logs/modsecurity/` | ModSecurity audit logs |
| `.env` | Environment variables |
