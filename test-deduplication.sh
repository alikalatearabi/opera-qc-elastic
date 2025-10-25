#!/bin/bash

# Test Deduplication
# Sends the same call twice to verify deduplication works

echo "=== Testing Deduplication ==="
echo "Time: $(date)"
echo ""

# Get app container
APP_CONTAINER="app"

# Test data
TEST_FILENAME="test-dedup-$(date +%s)"
TEST_DATE="1404-08-03 10:34:56"

# Function to send test call
send_test_call() {
    local attempt=$1
    echo "Attempt $attempt: Sending test call with filename: $TEST_FILENAME"
    
    curl -s -X POST http://localhost:8081/api/event/sessionReceived \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $(echo -n 'tipax:opera-qc-2024' | base64)" \
        -d '{
            "type": "incoming",
            "source_channel": "SIP/test-123",
            "source_number": "09123456789",
            "queue": "test-queue",
            "dest_channel": "SIP/agent-456",
            "dest_number": "BB09938900865",
            "date": "'"$TEST_DATE"'",
            "duration": "00:02:45",
            "filename": "'"$TEST_FILENAME"'",
            "level": 30,
            "time": '$(date +%s)000',
            "pid": 1234,
            "hostname": "test-server",
            "name": "test-dedup-session",
            "msg": "Test deduplication call"
        }' | jq .
    
    echo ""
    sleep 2
}

echo "Step 1: Send first call (should be processed)"
echo "-----------------------------------------------"
send_test_call "1"

echo ""
echo "Waiting 3 seconds..."
sleep 3

echo ""
echo "Step 2: Send same call again (should be detected as duplicate)"
echo "---------------------------------------------------------------"
send_test_call "2"

echo ""
echo "=== Checking Application Logs ==="
echo ""

# Check for duplicate detection in logs
echo "Recent API call logs:"
docker logs --tail 50 $APP_CONTAINER 2>&1 | grep -E "\[API_CALL_(RECEIVED|DUPLICATE|ACCEPTED)\]" | tail -10

echo ""
echo "=== Test Complete ==="
echo ""
echo "Expected behavior:"
echo "  1. First call: [API_CALL_ACCEPTED] - call processed"
echo "  2. Second call: [API_CALL_DUPLICATE] - call skipped"
echo ""
echo "If you see [API_CALL_DUPLICATE] in the logs for attempt 2, deduplication is working!"
