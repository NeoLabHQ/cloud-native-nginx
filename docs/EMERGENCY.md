# Emergency Procedures

Quick reference for emergency situations when the WAF is blocking legitimate traffic or causing issues.

## 1. Quick WAF Disable (Detection Only Mode)

Switch ModSecurity to detection-only mode (logs attacks but doesn't block):

```bash
# Edit .env or docker-compose.yml
MODSEC_RULE_ENGINE=DetectionOnly

# Restart nginx-waf
docker-compose restart nginx-waf
```

Or completely disable ModSecurity:

```bash
MODSEC_RULE_ENGINE=Off
docker-compose restart nginx-waf
```

## 2. Disable Rate Limiting

Comment out rate limiting in nginx config:

```bash
# Edit config/nginx/default.conf.template
# Comment out these lines:
# limit_req zone=general burst=50 nodelay;
# limit_req zone=auth burst=3 nodelay;
# limit_req zone=api burst=100 nodelay;

# Restart nginx-waf
docker-compose restart nginx-waf
```

## 3. Remove All CrowdSec Bans

```bash
# Remove all current bans
docker exec crowdsec cscli decisions delete --all

# Verify bans are cleared
docker exec crowdsec cscli decisions list
```

## 4. Unban Specific IP

```bash
# List current bans to find the decision ID
docker exec crowdsec cscli decisions list

# Delete specific ban by ID
docker exec crowdsec cscli decisions delete --id <decision_id>

# Or unban by IP
docker exec crowdsec cscli decisions delete --ip <ip_address>
```

## 5. Rollback Configuration via Git

```bash
# Discard all local changes
git checkout -- config/

# Restart services
docker-compose restart nginx-waf crowdsec
```

## 6. Full WAF Bypass (Emergency Nginx)

For critical situations, bypass the WAF entirely by pointing directly to backend:

```bash
# Stop nginx-waf
docker-compose stop nginx-waf

# Run emergency nginx without WAF (example)
docker run -d --name emergency-nginx \
  -p 8080:80 \
  --network cloud-native-nginx_security-net \
  nginx:alpine

# Update emergency nginx to proxy to backend
docker exec -it emergency-nginx sh -c 'cat > /etc/nginx/conf.d/default.conf << EOF
server {
    listen 80;
    location / {
        proxy_pass http://httpbin:80;
    }
}
EOF'

docker exec emergency-nginx nginx -s reload
```

To restore:

```bash
docker stop emergency-nginx && docker rm emergency-nginx
docker-compose start nginx-waf
```

## 7. Increase Anomaly Threshold (Less Strict)

If too many false positives, increase the anomaly threshold:

```bash
# Edit .env
ANOMALY_INBOUND=10  # Default is 5, higher = less strict
PARANOIA=1          # Keep at 1 for production

docker-compose restart nginx-waf
```

## 8. Disable Specific Rule

If a specific rule is causing issues:

```bash
# Edit config/modsecurity/exclusions.conf
# Add rule exclusion:
SecRuleRemoveById 9900013  # Disable SSRF rule

docker-compose restart nginx-waf
```

## 9. Check What's Blocking

```bash
# View recent ModSecurity blocks
docker exec nginx-waf tail -100 /var/log/modsecurity/audit.log | jq -r '.transaction.messages[]?.message' | sort | uniq -c | sort -rn

# View nginx access logs for 403s
docker exec nginx-waf grep " 403 " /var/log/nginx/access.log | tail -50
```

## 10. Complete Service Restart

```bash
# Stop everything
docker-compose down

# Clear logs if needed
rm -rf logs/nginx/* logs/modsecurity/*

# Start fresh
docker-compose up -d nginx-waf crowdsec nginx-exporter httpbin
```

## Escalation Contacts

| Role | Contact | When to escalate |
|------|---------|------------------|
| DevOps Lead | [TBD] | Service down > 5 min |
| Security Team | [TBD] | Suspected real attack |
| CloudBankin Support | [TBD] | Infrastructure issues |

## Recovery Checklist

After emergency procedures, remember to:

- [ ] Restore WAF to `On` mode after investigation
- [ ] Re-enable rate limiting
- [ ] Review logs to understand what triggered the issue
- [ ] Add appropriate exclusions for legitimate traffic
- [ ] Document the incident
- [ ] Update rules if needed
