#!/bin/bash

# ===========================================
# Nginx Security Stack - False Positive Tests
# ===========================================
# Tests that legitimate requests are NOT blocked

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HOST="${1:-localhost:8080}"
PROTOCOL="${2:-http}"
BASE_URL="${PROTOCOL}://${HOST}"

echo "===== NGINX SECURITY STACK - FALSE POSITIVE TESTS ====="
echo ""
echo "Target: ${BASE_URL}"
echo "Date: $(date)"
echo ""
echo "These tests verify that legitimate requests are NOT blocked."
echo ""

PASSED=0
FAILED=0

# Helper function to test with URL-encoded payload
test_pass() {
    local name="$1"
    local path="$2"
    local param="$3"
    local value="$4"
    local method="${5:-GET}"
    local data="${6:-}"

    if [ -n "$param" ]; then
        # Use -G and --data-urlencode for proper URL encoding
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" -G --data-urlencode "${param}=${value}" "${BASE_URL}${path}" -k 2>/dev/null)
    elif [ "$method" == "POST" ] && [ -n "$data" ]; then
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}${path}" -d "$data" -H "Content-Type: application/json" -k 2>/dev/null)
    else
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}${path}" -k 2>/dev/null)
    fi

    # Should NOT be 403 (blocked by WAF)
    if [ "$RESULT" != "403" ]; then
        echo -e "${GREEN}[PASS]${NC} $name - Got $RESULT (not blocked)"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name - Got 403 (FALSE POSITIVE!)"
        ((FAILED++))
    fi
}

echo "--- 1. Phone Numbers with Parentheses ---"
test_pass "US phone format" "/api/users" "phone" "(123)456-7890"
test_pass "International format" "/api/users" "phone" "+1(555)123-4567"
test_pass "Indian format" "/api/users" "phone" "(91)9876543210"
echo ""

echo "--- 2. Wildcard Search Queries ---"
test_pass "Wildcard search (*)" "/api/search" "q" "test*"
test_pass "Wildcard in middle" "/api/search" "q" "user*name"
test_pass "Multiple wildcards" "/api/search" "q" "*admin*"
echo ""

echo "--- 3. Mathematical Expressions ---"
test_pass "Multiplication" "/api/calc" "expr" "2*3"
test_pass "Parentheses" "/api/calc" "expr" "2*(3+4)"
test_pass "Complex expression" "/api/calc" "expr" "(10+5)*2"
echo ""

echo "--- 4. URLs with Query Parameters ---"
test_pass "Redirect URL" "/api/redirect" "url" "https://example.com?foo=bar"
test_pass "Callback URL" "/api/callback" "return_url" "https://app.com/done?status=success"
echo ""

echo "--- 5. JSON Payloads ---"
test_pass "Simple JSON" "/api/data" "" "" "POST" '{"name":"John","age":30}'
test_pass "Nested JSON" "/api/data" "" "" "POST" '{"user":{"name":"John","email":"john@example.com"}}'
test_pass "Array in JSON" "/api/data" "" "" "POST" '{"items":[1,2,3],"tags":["a","b"]}'
echo ""

echo "--- 6. Base64 Data ---"
test_pass "Base64 string" "/api/decode" "data" "SGVsbG8gV29ybGQ="
test_pass "Base64 with padding" "/api/decode" "data" "dGVzdA=="
echo ""

echo "--- 7. GraphQL Queries ---"
test_pass "GraphQL query" "/graphql" "" "" "POST" '{"query":"query { users { id name } }"}'
test_pass "GraphQL mutation" "/graphql" "" "" "POST" '{"query":"mutation { createUser(name: \"John\") { id } }"}'
echo ""

echo "--- 8. Common API Patterns ---"
test_pass "Pagination" "/api/items" "page" "1"
test_pass "Filtering" "/api/items" "status" "active"
test_pass "Date range" "/api/reports" "from" "2024-01-01"
echo ""

echo "--- 9. Special Characters in Names ---"
test_pass "Irish name (O'Brien)" "/api/users" "name" "O'Brien"
test_pass "Hyphenated name" "/api/users" "name" "Mary-Jane"
echo ""

echo "===== TEST SUMMARY ====="
echo -e "Passed:   ${GREEN}$PASSED${NC}"
echo -e "Failed:   ${RED}$FAILED${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some legitimate requests were blocked (FALSE POSITIVES)!${NC}"
    echo ""
    echo "To fix false positives, check ModSecurity audit log:"
    echo "  docker exec nginx-waf cat /var/log/modsecurity/audit.log | jq '.transaction.messages'"
    exit 1
else
    echo -e "${GREEN}No false positives detected!${NC}"
    exit 0
fi
