-include .env
export

.PHONY: help build run run-ssl stop-standalone health-standalone start stop restart test test-security test-false-pos logs logs-audit status bans unban-all health clean start-monitoring stop-monitoring health-monitoring start-monitoring-external health-monitoring-external

IMAGE_NAME ?= neolab/nginx-security
IMAGE_TAG ?= latest
CONTAINER_NAME ?= nginx-security

# Default target
help:
	@echo "Nginx Security Stack - Available Commands"
	@echo ""
	@echo "  Docker Image (Production):"
	@echo "  make build                - Build the Docker image"
	@echo "  make run                  - Run standalone container (HTTP)"
	@echo "  make run-ssl              - Run standalone container (HTTP + HTTPS)"
	@echo "  make stop-standalone      - Stop standalone container"
	@echo "  make health-standalone    - Check standalone container health"
	@echo ""
	@echo "  Development (docker compose with httpbin):"
	@echo "  make start                - Start all core services"
	@echo "  make stop                 - Stop all services"
	@echo "  make restart              - Restart all services"
	@echo ""
	@echo "  Monitoring (optional add-on):"
	@echo "  make start-monitoring          - Start full monitoring stack (standalone)"
	@echo "  make start-monitoring-external - Start monitoring (external Loki/Prometheus)"
	@echo "  make stop-monitoring           - Stop monitoring stack"
	@echo "  make health-monitoring         - Check monitoring health (standalone)"
	@echo "  make health-monitoring-external - Check monitoring health (external)"
	@echo ""
	@echo "  Testing:"
	@echo "  make test                 - Run all tests"
	@echo "  make test-security        - Run security tests only"
	@echo "  make test-false-pos       - Run false positive tests only"
	@echo ""
	@echo "  Logs & Status:"
	@echo "  make logs                 - View nginx-waf logs"
	@echo "  make logs-audit           - View ModSecurity audit logs"
	@echo "  make status               - Show service status"
	@echo "  make health               - Check health endpoints"
	@echo ""
	@echo "  CrowdSec:"
	@echo "  make bans                 - List CrowdSec bans"
	@echo "  make unban-all            - Remove all CrowdSec bans"
	@echo ""
	@echo "  Cleanup:"
	@echo "  make clean                - Stop services and remove volumes"

# ===========================================
# Docker Image Build & Run
# ===========================================

build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p 8080:8080 \
		-v ./logs/nginx:/var/log/nginx \
		-v ./logs/modsecurity:/var/log/modsecurity \
		$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Waiting for container to start..."
	@sleep 10
	@$(MAKE) health-standalone

run-ssl:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p 8080:8080 \
		-p 8443:8443 \
		-v ./certs/fullchain.pem:/etc/nginx/certs/fullchain.pem:ro \
		-v ./certs/privkey.pem:/etc/nginx/certs/privkey.pem:ro \
		-v ./logs/nginx:/var/log/nginx \
		-v ./logs/modsecurity:/var/log/modsecurity \
		$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Waiting for container to start..."
	@sleep 10
	@$(MAKE) health-standalone

stop-standalone:
	docker stop $(CONTAINER_NAME) 2>/dev/null || true
	docker rm $(CONTAINER_NAME) 2>/dev/null || true

health-standalone:
	@echo "Checking standalone container health..."
	@curl -sf http://localhost:8080/healthz > /dev/null 2>&1 && echo "nginx-security: OK" || echo "nginx-security: FAIL"

# ===========================================
# Development (docker compose)
# ===========================================

start:
	docker compose up -d nginx-waf crowdsec nginx-exporter httpbin
	@echo "Waiting for services to start..."
	@sleep 15
	@$(MAKE) health

stop:
	docker compose down

restart:
	docker compose restart nginx-waf crowdsec nginx-exporter

# ===========================================
# Monitoring Stack
# ===========================================

start-monitoring:
	docker compose -f docker-compose.monitoring.yml --profile standalone up -d
	@echo "Connecting nginx-security to monitoring network..."
	@docker network connect nginx-security-monitoring $(CONTAINER_NAME) 2>/dev/null || true
	@echo "Waiting for monitoring services to start..."
	@sleep 15
	@$(MAKE) health-monitoring

start-monitoring-external:
	@if [ -z "$(LOKI_URL)" ]; then \
		echo "ERROR: LOKI_URL is not set."; \
		echo "Set it in .env or export it: export LOKI_URL=https://loki.provider.com/loki/api/v1/push"; \
		exit 1; \
	fi
	@echo "Starting external monitoring mode..."
	@echo "  Loki URL: $$(echo '$(LOKI_URL)' | sed -E 's|://[^@]*@|://***@|')"
	docker compose -f docker-compose.monitoring.yml up -d nginx-exporter crowdsec promtail
	@echo "Connecting nginx-security to monitoring network..."
	@docker network connect nginx-security-monitoring $(CONTAINER_NAME) 2>/dev/null || true
	@echo "Waiting for monitoring services to start..."
	@sleep 15
	@$(MAKE) health-monitoring-external

stop-monitoring:
	docker compose -f docker-compose.monitoring.yml --profile standalone down
	docker compose -f docker-compose.monitoring.yml down

health-monitoring:
	@echo "Checking monitoring health (standalone)..."
	@curl -sf http://localhost:9113/metrics > /dev/null 2>&1 && echo "nginx-exporter: OK" || echo "nginx-exporter: FAIL"
	@curl -sf http://localhost:6060/metrics > /dev/null 2>&1 && echo "crowdsec: OK" || echo "crowdsec: FAIL"
	@curl -sf http://localhost:3100/ready > /dev/null 2>&1 && echo "loki: OK" || echo "loki: FAIL"

health-monitoring-external:
	@echo "Checking monitoring health (external)..."
	@curl -sf http://localhost:9113/metrics > /dev/null 2>&1 && echo "nginx-exporter: OK" || echo "nginx-exporter: FAIL"
	@curl -sf http://localhost:6060/metrics > /dev/null 2>&1 && echo "crowdsec: OK" || echo "crowdsec: FAIL"
	@docker ps --format '{{.Names}}' | grep -q promtail && echo "promtail: RUNNING" || echo "promtail: NOT RUNNING"
	@docker ps --format '{{.Names}}' | grep -q loki && echo "WARNING: loki is running (should not be in external mode)" || echo "loki: NOT RUNNING (expected)"

# ===========================================
# Testing
# ===========================================

test: test-security test-false-pos
	@echo "All tests completed"

test-security:
	@./scripts/test-security.sh localhost:8080 http

test-false-pos:
	@./scripts/test-false-positives.sh localhost:8080 http

# ===========================================
# Logs and monitoring
# ===========================================

logs:
	docker compose logs -f nginx-waf

logs-audit:
	@docker exec nginx-waf tail -f /var/log/modsecurity/audit.log 2>/dev/null | jq . || \
		docker exec nginx-waf tail -f /var/log/modsecurity/audit.log

status:
	docker compose ps

# ===========================================
# CrowdSec operations
# ===========================================

bans:
	docker exec crowdsec cscli decisions list

unban-all:
	docker exec crowdsec cscli decisions delete --all

# ===========================================
# Health checks (docker compose mode)
# ===========================================

health:
	@echo "Checking health endpoints..."
	@curl -sf http://localhost:8080/healthz > /dev/null 2>&1 && echo "nginx-waf: OK" || echo "nginx-waf: FAIL"
	@curl -sf http://localhost:9113/metrics > /dev/null 2>&1 && echo "nginx-exporter: OK" || echo "nginx-exporter: FAIL"
	@curl -sf http://localhost:6060/metrics > /dev/null 2>&1 && echo "crowdsec: OK" || echo "crowdsec: FAIL"

# ===========================================
# Cleanup
# ===========================================

clean:
	docker compose down -v
	rm -rf logs/nginx/* logs/modsecurity/*
