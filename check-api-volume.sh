#!/bin/bash

# API Call Volume Analyzer
# Analyzes how many calls the external API sent to your system

echo "=== API Call Volume Analyzer ==="
echo "Time: $(date)"
echo ""

# Get app container
APP_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "^app$" | head -1)

# If 'app' not found, try other patterns
if [ -z "$APP_CONTAINER" ]; then
    APP_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "(backend|api)" | head -1)
fi

if [ -z "$APP_CONTAINER" ]; then
    echo "❌ No app container found"
    exit 1
fi

echo "App container: $APP_CONTAINER"
echo ""

# Get logs from last 24 hours
echo "=== Analyzing API Calls (Last 24 Hours) ==="

# Count different types of calls
TOTAL_RECEIVED=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_RECEIVED\]" || echo "0")
TOTAL_ACCEPTED=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_ACCEPTED\]" || echo "0")
TOTAL_SKIPPED=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_SKIPPED\]" || echo "0")
TOTAL_REJECTED=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_REJECTED\]" || echo "0")
TOTAL_QUEUED=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_QUEUED\]" || echo "0")
TOTAL_ERRORS=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep -c "\[API_CALL_ERROR\]" || echo "0")

echo "📊 API Call Statistics:"
echo "  Total received from external API:    $TOTAL_RECEIVED"
echo "  Incoming calls accepted:             $TOTAL_ACCEPTED"
echo "  Outgoing calls skipped:              $TOTAL_SKIPPED"
echo "  Calls rejected (bad data):           $TOTAL_REJECTED"
echo "  Calls queued successfully:           $TOTAL_QUEUED"
echo "  API processing errors:               $TOTAL_ERRORS"
echo ""

# Breakdown by hour
echo "=== Hourly Breakdown (Last 24 Hours) ==="

HOURS=()
for i in {0..23}; do
    HOURS+=($i)
done

for hour in "${HOURS[@]}"; do
    COUNT=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep "\[API_CALL_RECEIVED\]" | grep -E "$(date -d "-$hour hours" '+%Y-%m-%dT%H:' 2>/dev/null || date -v-"${hour}H" '+%Y-%m-%dT%H:' 2>/dev/null)" | wc -l)
    printf "  Hour %02d:00 - %02d:59: %4d calls\n" "$hour" "$hour" "$COUNT"
done

echo ""

# Top call sources
echo "=== Top Call Sources (Last 100 calls) ==="

TOP_SOURCES=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep "\[API_CALL_DETAILS\]" | tail -100 | grep -o "Source: [^,]*" | cut -d' ' -f2 | sort | uniq -c | sort -nr | head -10)

if [ ! -z "$TOP_SOURCES" ]; then
    echo "$TOP_SOURCES" | while read count number; do
        printf "  %s: %s calls\n" "$number" "$count"
    done
else
    echo "No source data found"
fi

echo ""

# Call frequency analysis
echo "=== Call Frequency Analysis ==="

# Get timestamps of all calls
TIMESTAMPS=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep "\[API_CALL_RECEIVED\]" | grep -o "2025-[0-9-]*T[0-9:]*\.[0-9]*Z" | sort)

if [ ! -z "$TIMESTAMPS" ]; then
    TOTAL_CALLS=$(echo "$TIMESTAMPS" | wc -l)
    
    # Calculate average time between calls
    if [ $TOTAL_CALLS -gt 1 ]; then
        FIRST_CALL=$(echo "$TIMESTAMPS" | head -1)
        LAST_CALL=$(echo "$TIMESTAMPS" | tail -1)
        
        FIRST_EPOCH=$(date -d "$FIRST_CALL" +%s 2>/dev/null || echo "0")
        LAST_EPOCH=$(date -d "$LAST_CALL" +%s 2>/dev/null || echo "0")
        
        if [ $FIRST_EPOCH -gt 0 ] && [ $LAST_EPOCH -gt 0 ]; then
            TIME_SPAN=$((LAST_EPOCH - FIRST_EPOCH))
            AVG_INTERVAL=$((TIME_SPAN / TOTAL_CALLS))
            
            echo "  Average time between calls: $AVG_INTERVAL seconds"
            echo "  Calls per hour (average): ~$((TOTAL_CALLS * 3600 / (TIME_SPAN + 1)))"
        fi
    fi
fi

echo ""

echo "Done"
