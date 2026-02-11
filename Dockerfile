FROM owasp/modsecurity-crs:4-nginx-alpine-202601060501

# Custom nginx config with rate limiting zones
# $binary_remote_addr is used for per-IP rate limiting (4-byte binary IP representation)
COPY config/nginx/default.conf.template /etc/nginx/templates/conf.d/default.conf.template

# Custom WAF rules (15 rules: SQLi, XSS, SSRF, path traversal, scanner detection)
COPY config/modsecurity/custom-rules.conf /etc/modsecurity.d/owasp-crs/rules/RESPONSE-999-CUSTOM.conf

# Rule exclusions for false positive prevention
COPY config/modsecurity/exclusions.conf /etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf

# Environment variable defaults
ENV BACKEND=http://localhost:80 \
    PORT=8080 \
    SSL_PORT=8443 \
    SERVER_NAME=_ \
    MODSEC_RULE_ENGINE=On \
    MODSEC_AUDIT_LOG=/var/log/modsecurity/audit.log \
    MODSEC_AUDIT_LOG_FORMAT=JSON \
    PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    PROXY_TIMEOUT=60 \
    PROXY_SSL=off

EXPOSE 8080 8443

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=15s \
    CMD curl -f http://localhost:8080/healthz || exit 1
