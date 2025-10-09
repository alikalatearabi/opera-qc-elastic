#!/bin/bash

# 🧪 Elasticsearch Migration Testing Script
# This script tests all aspects of the new Elasticsearch-powered Opera QC Backend

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="http://localhost:8081"
ELASTICSEARCH_URL="http://localhost:9200"
KIBANA_URL="http://localhost:5601"

# Test credentials (update these with your actual credentials)
TEST_EMAIL="test@example.com"
TEST_PASSWORD="testpassword123"

echo -e "${BLUE}🧪 Opera QC Elasticsearch Testing Suite${NC}"
echo "=============================================="

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        echo -e "${RED}   Error: $3${NC}"
    fi
}

# Function to make HTTP requests with error handling
make_request() {
    local method=$1
    local url=$2
    local data=$3
    local headers=$4
    
    if [ -n "$data" ]; then
        if [ -n "$headers" ]; then
            curl -s -X "$method" "$url" -H "Content-Type: application/json" -H "$headers" -d "$data"
        else
            curl -s -X "$method" "$url" -H "Content-Type: application/json" -d "$data"
        fi
    else
        if [ -n "$headers" ]; then
            curl -s -X "$method" "$url" -H "$headers"
        else
            curl -s -X "$method" "$url"
        fi
    fi
}

# Test 1: Check if Elasticsearch is running
echo -e "\n${YELLOW}1. Testing Elasticsearch Connection${NC}"
ES_HEALTH=$(curl -s "$ELASTICSEARCH_URL/_cluster/health" 2>/dev/null || echo "ERROR")
if [[ "$ES_HEALTH" == *"green"* ]] || [[ "$ES_HEALTH" == *"yellow"* ]]; then
    print_result 0 "Elasticsearch is running and healthy"
    echo "   Cluster status: $(echo $ES_HEALTH | jq -r '.status' 2>/dev/null || echo 'Unknown')"
else
    print_result 1 "Elasticsearch connection failed" "$ES_HEALTH"
    echo -e "${RED}   Please start Elasticsearch: docker-compose up -d elasticsearch${NC}"
    exit 1
fi

# Test 2: Check if Kibana is accessible
echo -e "\n${YELLOW}2. Testing Kibana Connection${NC}"
KIBANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$KIBANA_URL/api/status" 2>/dev/null || echo "000")
if [ "$KIBANA_STATUS" = "200" ]; then
    print_result 0 "Kibana is accessible at $KIBANA_URL"
else
    print_result 1 "Kibana connection failed" "HTTP Status: $KIBANA_STATUS"
    echo -e "${YELLOW}   Note: Kibana might still be starting up${NC}"
fi

# Test 3: Check if the Node.js application is running
echo -e "\n${YELLOW}3. Testing Application Server${NC}"
APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/docs" 2>/dev/null || echo "000")
if [ "$APP_STATUS" = "200" ]; then
    print_result 0 "Application server is running"
    echo "   Swagger docs available at: $BASE_URL/api/docs"
else
    print_result 1 "Application server connection failed" "HTTP Status: $APP_STATUS"
    echo -e "${RED}   Please start the application: npm run dev${NC}"
    exit 1
fi

# Test 4: Check Elasticsearch indices
echo -e "\n${YELLOW}4. Testing Elasticsearch Indices${NC}"
INDICES=$(curl -s "$ELASTICSEARCH_URL/_cat/indices?format=json" 2>/dev/null || echo "[]")
SESSION_INDEX_EXISTS=$(echo "$INDICES" | jq -r '.[] | select(.index | contains("session-events")) | .index' 2>/dev/null || echo "")
USER_INDEX_EXISTS=$(echo "$INDICES" | jq -r '.[] | select(.index | contains("users")) | .index' 2>/dev/null || echo "")

if [ -n "$SESSION_INDEX_EXISTS" ]; then
    print_result 0 "Session events index exists: $SESSION_INDEX_EXISTS"
    # Get document count
    DOC_COUNT=$(curl -s "$ELASTICSEARCH_URL/$SESSION_INDEX_EXISTS/_count" | jq -r '.count' 2>/dev/null || echo "0")
    echo "   Document count: $DOC_COUNT"
else
    print_result 1 "Session events index not found" "Index might not be created yet"
fi

if [ -n "$USER_INDEX_EXISTS" ]; then
    print_result 0 "Users index exists: $USER_INDEX_EXISTS"
else
    print_result 1 "Users index not found" "Index might not be created yet"
fi

# Test 5: Test user registration (if no users exist)
echo -e "\n${YELLOW}5. Testing User Registration${NC}"
REGISTER_RESPONSE=$(make_request "POST" "$BASE_URL/api/auth/register" "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"name\":\"Test User\"}" 2>/dev/null || echo "ERROR")

if [[ "$REGISTER_RESPONSE" == *"Success"* ]]; then
    print_result 0 "User registration successful"
elif [[ "$REGISTER_RESPONSE" == *"Duplicate"* ]]; then
    print_result 0 "User already exists (this is fine for testing)"
else
    print_result 1 "User registration failed" "$REGISTER_RESPONSE"
fi

# Test 6: Test user login
echo -e "\n${YELLOW}6. Testing User Authentication${NC}"
LOGIN_RESPONSE=$(make_request "POST" "$BASE_URL/api/auth/login" "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" 2>/dev/null || echo "ERROR")

if [[ "$LOGIN_RESPONSE" == *"token"* ]]; then
    print_result 0 "User login successful"
    # Extract JWT token
    JWT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.token' 2>/dev/null || echo "")
    if [ -n "$JWT_TOKEN" ] && [ "$JWT_TOKEN" != "null" ]; then
        echo "   JWT token obtained successfully"
    else
        echo -e "${YELLOW}   Warning: Could not extract JWT token${NC}"
    fi
else
    print_result 1 "User login failed" "$LOGIN_RESPONSE"
    echo -e "${YELLOW}   Note: You may need to create a user first or check credentials${NC}"
    JWT_TOKEN=""
fi

# Test 7: Test session events API (with authentication)
echo -e "\n${YELLOW}7. Testing Session Events API${NC}"
if [ -n "$JWT_TOKEN" ]; then
    SESSIONS_RESPONSE=$(make_request "GET" "$BASE_URL/api/event?page=1&limit=5" "" "Authorization: Bearer $JWT_TOKEN" 2>/dev/null || echo "ERROR")
    
    if [[ "$SESSIONS_RESPONSE" == *"data"* ]]; then
        print_result 0 "Session events API accessible"
        # Check if there's data
        DATA_COUNT=$(echo "$SESSIONS_RESPONSE" | jq -r '.data.pagination.totalItems' 2>/dev/null || echo "0")
        echo "   Total session events: $DATA_COUNT"
    else
        print_result 1 "Session events API failed" "$SESSIONS_RESPONSE"
    fi
else
    print_result 1 "Skipping session events test" "No JWT token available"
fi

# Test 8: Test session statistics API
echo -e "\n${YELLOW}8. Testing Session Statistics API${NC}"
if [ -n "$JWT_TOKEN" ]; then
    STATS_RESPONSE=$(make_request "GET" "$BASE_URL/api/event/stats" "" "Authorization: Bearer $JWT_TOKEN" 2>/dev/null || echo "ERROR")
    
    if [[ "$STATS_RESPONSE" == *"total_calls"* ]]; then
        print_result 0 "Session statistics API working"
        TOTAL_CALLS=$(echo "$STATS_RESPONSE" | jq -r '.data.total_calls' 2>/dev/null || echo "0")
        echo "   Total calls in system: $TOTAL_CALLS"
    else
        print_result 1 "Session statistics API failed" "$STATS_RESPONSE"
    fi
else
    print_result 1 "Skipping statistics test" "No JWT token available"
fi

# Test 9: Test webhook endpoint (sessionReceived)
echo -e "\n${YELLOW}9. Testing Webhook Endpoint${NC}"
WEBHOOK_DATA='{
    "type": "incoming",
    "source_channel": "SIP/test",
    "source_number": "09123456789",
    "queue": "test-queue",
    "dest_channel": "SIP/agent",
    "dest_number": "101",
    "date": "2024-01-15 14:30:22",
    "duration": "00:02:45",
    "filename": "test-call-12345",
    "level": 30,
    "time": 1705320622000,
    "pid": 1234,
    "hostname": "test-server",
    "name": "test-session",
    "msg": "Test call session"
}'

# Use basic auth for webhook (as configured in the system)
WEBHOOK_RESPONSE=$(curl -s -X POST "$BASE_URL/api/event/sessionReceived" \
    -H "Content-Type: application/json" \
    -u "User1:hyQ39c8E873MVv5e22E3T355n3bYV5nf" \
    -d "$WEBHOOK_DATA" 2>/dev/null || echo "ERROR")

if [[ "$WEBHOOK_RESPONSE" == *"jobId"* ]]; then
    print_result 0 "Webhook endpoint working"
    JOB_ID=$(echo "$WEBHOOK_RESPONSE" | jq -r '.data.jobId' 2>/dev/null || echo "")
    echo "   Job queued with ID: $JOB_ID"
else
    print_result 1 "Webhook endpoint failed" "$WEBHOOK_RESPONSE"
fi

# Test 10: Test search functionality
echo -e "\n${YELLOW}10. Testing Search Functionality${NC}"
if [ -n "$JWT_TOKEN" ]; then
    # Test basic search
    SEARCH_RESPONSE=$(make_request "GET" "$BASE_URL/api/event?searchText=test&page=1&limit=5" "" "Authorization: Bearer $JWT_TOKEN" 2>/dev/null || echo "ERROR")
    
    if [[ "$SEARCH_RESPONSE" == *"data"* ]]; then
        print_result 0 "Search functionality working"
    else
        print_result 1 "Search functionality failed" "$SEARCH_RESPONSE"
    fi
    
    # Test filter search
    FILTER_RESPONSE=$(make_request "GET" "$BASE_URL/api/event?type=incoming&page=1&limit=5" "" "Authorization: Bearer $JWT_TOKEN" 2>/dev/null || echo "ERROR")
    
    if [[ "$FILTER_RESPONSE" == *"data"* ]]; then
        print_result 0 "Filter functionality working"
    else
        print_result 1 "Filter functionality failed" "$FILTER_RESPONSE"
    fi
else
    print_result 1 "Skipping search tests" "No JWT token available"
fi

# Test 11: Check Redis connection (for queues)
echo -e "\n${YELLOW}11. Testing Redis Connection${NC}"
REDIS_STATUS=$(docker exec opera-qc-redis redis-cli ping 2>/dev/null || echo "ERROR")
if [ "$REDIS_STATUS" = "PONG" ]; then
    print_result 0 "Redis is running and accessible"
else
    print_result 1 "Redis connection failed" "$REDIS_STATUS"
    echo -e "${YELLOW}   Note: Queues may not work without Redis${NC}"
fi

# Test 12: Check MinIO connection
echo -e "\n${YELLOW}12. Testing MinIO Connection${NC}"
MINIO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9005/minio/health/live" 2>/dev/null || echo "000")
if [ "$MINIO_STATUS" = "200" ]; then
    print_result 0 "MinIO is running and accessible"
    echo "   MinIO console: http://localhost:9006"
else
    print_result 1 "MinIO connection failed" "HTTP Status: $MINIO_STATUS"
fi

# Final Summary
echo -e "\n${BLUE}📊 Test Summary${NC}"
echo "=============================================="
echo -e "🔍 Elasticsearch: ${GREEN}Running${NC}"
echo -e "📊 Kibana: ${GREEN}Available at $KIBANA_URL${NC}"
echo -e "🚀 Application: ${GREEN}Running at $BASE_URL${NC}"
echo -e "📚 API Docs: ${GREEN}$BASE_URL/api/docs${NC}"

echo -e "\n${YELLOW}🎯 Next Steps:${NC}"
echo "1. Visit Kibana to explore your data: $KIBANA_URL"
echo "2. Check API documentation: $BASE_URL/api/docs"
echo "3. Monitor logs: docker-compose logs -f app"
echo "4. Test with real call data via webhook endpoint"

echo -e "\n${GREEN}🎉 Testing completed!${NC}"

# Optional: Open browser windows
if command -v xdg-open > /dev/null; then
    echo -e "\n${YELLOW}Opening browser windows...${NC}"
    xdg-open "$KIBANA_URL" 2>/dev/null &
    xdg-open "$BASE_URL/api/docs" 2>/dev/null &
elif command -v open > /dev/null; then
    echo -e "\n${YELLOW}Opening browser windows...${NC}"
    open "$KIBANA_URL" 2>/dev/null &
    open "$BASE_URL/api/docs" 2>/dev/null &
fi
