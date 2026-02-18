# Grafana Dashboard — Nginx Security Stack

Pre-built Grafana dashboard for monitoring the Nginx Security Stack.

## Import Instructions

### Via Grafana UI

1. Open Grafana → **Dashboards** → **New** → **Import**
2. Click **Upload dashboard JSON file** and select `nginx-security.json`
3. Select your **Prometheus** and **Loki** data sources when prompted
4. Click **Import**

### Via Grafana API

```bash
curl -X POST http://admin:password@grafana-host:3000/api/dashboards/import \
  -H 'Content-Type: application/json' \
  -d @nginx-security.json
```

## Prerequisites

The dashboard requires two data sources configured in Grafana:

| Data Source | Type | Purpose |
|---|---|---|
| Prometheus | `prometheus` | nginx-exporter metrics (port 9113) + CrowdSec metrics (port 6060) |
| Loki | `loki` | Nginx access/error logs + ModSecurity audit logs |

Add scrape targets to Prometheus using `monitoring/prometheus-scrape-config.yml`.

## Dashboard Panels

### Status Row
- **Nginx Status** — UP/DOWN indicator
- **Active Connections** — current active connections
- **Request Rate** — requests per second (5m average)
- **CrowdSec Active Bans** — current active ban decisions
- **CrowdSec Alerts** — alerts in last 24h
- **Attack Rate** — CrowdSec scenario triggers per second

### Metrics Charts
- **Request Rate Over Time** — HTTP requests/s timeseries
- **Nginx Connections** — active, reading, writing, waiting connections
- **CrowdSec Active Decisions** — ban/captcha decisions by reason
- **CrowdSec Attack Rate** — scenario overflows and alerts rate

### Log Panels
- **Nginx Access Logs** — all access log entries
- **Nginx Error Logs** — error log entries
- **ModSecurity Audit Logs** — WAF audit events (JSON)
- **Blocked Requests (403)** — requests blocked by WAF
- **Rate Limited Requests (429)** — requests blocked by rate limiter
