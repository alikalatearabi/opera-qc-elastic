#!/bin/bash

# Quick Duplicate Call Checker
# Run this on the production server to check for duplicate calls

echo "=== Duplicate Call Checker ==="
echo "Time: $(date)"
echo ""

# Get app container
APP_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "(app|opera|backend)" | head -1)

if [ -z "$APP_CONTAINER" ]; then
    echo "❌ No app container found"
    exit 1
fi

echo "Container: $APP_CONTAINER"
echo ""

# Check recent API calls for duplicates
echo "=== Recent API Calls (Last 50) ==="
RECENT_LOGS=$(docker logs --tail 1000 $APP_CONTAINER 2>&1 | grep "\[API_CALL_DETAILS\]" | tail -50)

if [ -z "$RECENT_LOGS" ]; then
    echo "No recent API calls found"
else
    echo "Recent calls:"
    echo "$RECENT_LOGS" | head -10
fi

echo ""

# Extract filenames and check for duplicates
echo "=== Filename Duplicates ==="
FILENAMES=$(echo "$RECENT_LOGS" | grep -o "Filename: [^,]*" | cut -d' ' -f2 | sort | uniq -c | sort -nr)

if [ ! -z "$FILENAMES" ]; then
    DUPLICATES=$(echo "$FILENAMES" | awk '$1 > 1')
    
    if [ ! -z "$DUPLICATES" ]; then
        echo "⚠️  DUPLICATES FOUND:"
        echo "$DUPLICATES"
    else
        echo "✅ No duplicates found in recent calls"
    fi
else
    echo "No filenames found"
fi

echo ""

# Check API call statistics
echo "=== API Call Statistics (Last Hour) ==="
LOGS_HOUR=$(docker logs --since 1h $APP_CONTAINER 2>&1)

TOTAL_RECEIVED=$(echo "$LOGS_HOUR" | grep "\[API_CALL_RECEIVED\]" | wc -l)
TOTAL_ACCEPTED=$(echo "$LOGS_HOUR" | grep "\[API_CALL_ACCEPTED\]" | wc -l)
TOTAL_SKIPPED=$(echo "$LOGS_HOUR" | grep "\[API_CALL_SKIPPED\]" | wc -l)

echo "Total received: $TOTAL_RECEIVED"
echo "Accepted:       $TOTAL_ACCEPTED"
echo "Skipped:        $TOTAL_SKIPPED"

echo ""
echo "Done"
