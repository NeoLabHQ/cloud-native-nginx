.PHONY: help start stop restart test test-security test-false-pos logs logs-audit status bans unban-all health clean start-monitoring

# Default target
help:
	@echo "Nginx Security Stack - Available Commands"
	@echo ""
	@echo "  make start              - Start all core services"
	@echo "  make start-monitoring   - Start with monitoring stack (Loki, Promtail, Grafana)"
	@echo "  make stop               - Stop all services"
	@echo "  make restart            - Restart all services"
	@echo "  make test               - Run all tests"
	@echo "  make test-security      - Run security tests only"
	@echo "  make test-false-pos     - Run false positive tests only"
	@echo "  make logs               - View nginx-waf logs"
	@echo "  make logs-audit         - View ModSecurity audit logs"
	@echo "  make status             - Show service status"
	@echo "  make bans               - List CrowdSec bans"
	@echo "  make unban-all          - Remove all CrowdSec bans"
	@echo "  make health             - Check health endpoints"
	@echo "  make clean              - Stop services and remove volumes"

# Service management
start:
	docker-compose up -d nginx-waf crowdsec nginx-exporter httpbin
	@echo "Waiting for services to start..."
	@sleep 15
	@$(MAKE) health

start-monitoring:
	docker-compose --profile monitoring up -d
	@echo "Waiting for services to start..."
	@sleep 20
	@$(MAKE) health

stop:
	docker-compose down

restart:
	docker-compose restart nginx-waf crowdsec nginx-exporter

# Testing
test: test-security test-false-pos
	@echo "All tests completed"

test-security:
	@./scripts/test-security.sh localhost:8080 http

test-false-pos:
	@./scripts/test-false-positives.sh localhost:8080 http

# Logs and monitoring
logs:
	docker-compose logs -f nginx-waf

logs-audit:
	@docker exec nginx-waf tail -f /var/log/modsecurity/audit.log 2>/dev/null | jq . || \
		docker exec nginx-waf tail -f /var/log/modsecurity/audit.log

status:
	docker-compose ps

# CrowdSec operations
bans:
	docker exec crowdsec cscli decisions list

unban-all:
	docker exec crowdsec cscli decisions delete --all

# Health checks
health:
	@echo "Checking health endpoints..."
	@curl -sf http://localhost:8080/healthz > /dev/null 2>&1 && echo "nginx-waf: OK" || echo "nginx-waf: FAIL"
	@curl -sf http://localhost:9113/metrics > /dev/null 2>&1 && echo "nginx-exporter: OK" || echo "nginx-exporter: FAIL"
	@curl -sf http://localhost:6060/metrics > /dev/null 2>&1 && echo "crowdsec: OK" || echo "crowdsec: FAIL"

# Cleanup
clean:
	docker-compose down -v
	rm -rf logs/nginx/* logs/modsecurity/*
