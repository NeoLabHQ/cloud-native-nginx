# Nginx Security Stack

Docker-based security stack: WAF (ModSecurity + OWASP CRS), CrowdSec, Rate Limiting.

## Quick Start

```bash
cp .env.example .env
make start
make test
```

Works out of the box with test backend (httpbin).

For your own backend, edit `BACKEND` in `.env`:
```bash
BACKEND=http://your-app:3000
```

## Commands

```bash
make help               # Show all commands
make start              # Start core services
make start-monitoring   # Start with monitoring (Loki, Grafana)
make stop               # Stop all services
make restart            # Restart services
make test               # Run all tests
make test-security      # Security tests only
make test-false-pos     # False positive tests only
make logs               # View nginx-waf logs
make logs-audit         # View ModSecurity audit logs
make status             # Show service status
make health             # Check health endpoints
make bans               # List CrowdSec bans
make unban-all          # Remove all bans
make clean              # Stop and remove volumes
```

## Ports

| Service | Port |
|---------|------|
| nginx-waf HTTP | 8080 |
| nginx-waf HTTPS | 8443 |
| nginx-exporter | 9113 |
| crowdsec | 6060 |

## Docs

- [Quick Reference](docs/QUICK_REFERENCE.md)
- [Emergency Procedures](docs/EMERGENCY.md)
