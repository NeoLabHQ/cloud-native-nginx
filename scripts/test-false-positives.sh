#!/bin/bash

# ===========================================
# Nginx Security Stack - False Positive Tests
# ===========================================
# Tests that legitimate requests are NOT blocked

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

echo "===== NGINX SECURITY STACK - FALSE POSITIVE TESTS ====="
echo ""
echo "Target: ${BASE_URL}"
echo "Date: $(date)"
echo ""
echo "These tests verify that legitimate requests are NOT blocked."
echo ""

PASSED=0
FAILED=0

# Helper function to test that request passes
test_pass() {
    local name="$1"
    local url="$2"
    local method="${3:-GET}"
    local data="${4:-}"

    if [ "$method" == "POST" ] && [ -n "$data" ]; then
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" -d "$data" -H "Content-Type: application/json" -k 2>/dev/null)
    elif [ "$method" == "POST" ]; then
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" -k 2>/dev/null)
    else
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" "$url" -k 2>/dev/null)
    fi

    # Should NOT be 403 (blocked)
    if [ "$RESULT" != "403" ]; then
        echo -e "${GREEN}[PASS]${NC} $name - Got $RESULT (not blocked)"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name - Got 403 (FALSE POSITIVE - should not be blocked!)"
        ((FAILED++))
    fi
}

echo "--- 1. Phone Numbers with Parentheses ---"
echo "Testing that phone numbers with parentheses are allowed..."
test_pass "US phone format" "${BASE_URL}/api/users?phone=(123)456-7890"
test_pass "International format" "${BASE_URL}/api/users?phone=+1(555)123-4567"
test_pass "Indian format" "${BASE_URL}/api/users?phone=(91)9876543210"
echo ""

echo "--- 2. Wildcard Search Queries ---"
echo "Testing that wildcard searches are allowed..."
test_pass "Wildcard search (*)" "${BASE_URL}/api/search?q=test*"
test_pass "Wildcard in middle" "${BASE_URL}/api/search?q=user*name"
test_pass "Multiple wildcards" "${BASE_URL}/api/search?q=*admin*"
echo ""

echo "--- 3. Mathematical Expressions ---"
echo "Testing that math expressions are allowed..."
test_pass "Multiplication" "${BASE_URL}/api/calc?expr=2*3"
test_pass "Parentheses" "${BASE_URL}/api/calc?expr=2*(3+4)"
test_pass "Complex expression" "${BASE_URL}/api/calc?expr=(10+5)*2"
echo ""

echo "--- 4. URLs with Query Parameters ---"
echo "Testing that URLs with query strings are allowed..."
test_pass "Redirect URL" "${BASE_URL}/api/redirect?url=https://example.com?foo=bar"
test_pass "Callback URL" "${BASE_URL}/api/callback?return_url=https://app.com/done?status=success"
echo ""

echo "--- 5. JSON Payloads ---"
echo "Testing that JSON payloads are allowed..."
test_pass "Simple JSON" "${BASE_URL}/api/data" "POST" '{"name":"John","age":30}'
test_pass "Nested JSON" "${BASE_URL}/api/data" "POST" '{"user":{"name":"John","email":"john@example.com"}}'
test_pass "Array in JSON" "${BASE_URL}/api/data" "POST" '{"items":[1,2,3],"tags":["a","b"]}'
echo ""

echo "--- 6. Base64 Data ---"
echo "Testing that base64-encoded data is allowed..."
test_pass "Base64 string" "${BASE_URL}/api/decode?data=SGVsbG8gV29ybGQ="
test_pass "Base64 with padding" "${BASE_URL}/api/decode?data=dGVzdA=="
echo ""

echo "--- 7. GraphQL Queries ---"
echo "Testing that GraphQL queries are allowed..."
test_pass "GraphQL query" "${BASE_URL}/graphql" "POST" '{"query":"query { users { id name } }"}'
test_pass "GraphQL mutation" "${BASE_URL}/graphql" "POST" '{"query":"mutation { createUser(name: \"John\") { id } }"}'
test_pass "GraphQL with variables" "${BASE_URL}/graphql" "POST" '{"query":"query GetUser($id: ID!) { user(id: $id) { name } }","variables":{"id":"123"}}'
echo ""

echo "--- 8. Common API Patterns ---"
echo "Testing common legitimate API patterns..."
test_pass "Pagination" "${BASE_URL}/api/items?page=1&limit=10&sort=name:asc"
test_pass "Filtering" "${BASE_URL}/api/items?status=active&type=premium"
test_pass "Date range" "${BASE_URL}/api/reports?from=2024-01-01&to=2024-12-31"
test_pass "UUID path" "${BASE_URL}/api/users/550e8400-e29b-41d4-a716-446655440000"
echo ""

echo "--- 9. File Uploads (content-type check) ---"
echo "Testing that file upload content types are allowed..."
# Note: These are just content-type checks, not actual file uploads
RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/upload" -H "Content-Type: multipart/form-data" -k 2>/dev/null)
if [ "$RESULT" != "403" ]; then
    echo -e "${GREEN}[PASS]${NC} Multipart form-data - Got $RESULT (not blocked)"
    ((PASSED++))
else
    echo -e "${RED}[FAIL]${NC} Multipart form-data - Got 403 (FALSE POSITIVE)"
    ((FAILED++))
fi
echo ""

echo "--- 10. Special Characters in Names ---"
echo "Testing names with special characters..."
test_pass "Irish name (O'Brien)" "${BASE_URL}/api/users?name=O'Brien"
test_pass "Hyphenated name" "${BASE_URL}/api/users?name=Mary-Jane"
test_pass "Accented name" "${BASE_URL}/api/users?name=José"
echo ""

echo "===== TEST SUMMARY ====="
echo -e "Passed:   ${GREEN}$PASSED${NC}"
echo -e "Failed:   ${RED}$FAILED${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some legitimate requests were blocked (FALSE POSITIVES)!${NC}"
    echo ""
    echo "To fix false positives:"
    echo "1. Check ModSecurity audit log:"
    echo "   docker exec nginx-waf cat /var/log/modsecurity/audit.log | jq '.transaction.messages'"
    echo ""
    echo "2. Add rule exclusion in config/modsecurity/exclusions.conf:"
    echo "   SecRuleRemoveById <RULE_ID>"
    echo ""
    echo "3. Restart nginx-waf:"
    echo "   docker-compose restart nginx-waf"
    exit 1
else
    echo -e "${GREEN}No false positives detected! All legitimate requests passed.${NC}"
    exit 0
fi
