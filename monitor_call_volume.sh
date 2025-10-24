#!/bin/bash

# Real-time Call Volume Monitor for Production Server
# Run this on your production server: 31.184.134.153

echo "========================================="
echo "    REAL-TIME CALL VOLUME MONITOR"
echo "========================================="
echo "Server: 31.184.134.153"
echo "Started at: $(date)"
echo "Press Ctrl+C to stop monitoring"
echo ""

# Find app container
APP_CONTAINER=$(docker ps --format "table {{.Names}}" | grep -E "(app|opera)" | head -1)

if [ -z "$APP_CONTAINER" ]; then
    echo "❌ No app container found"
    exit 1
fi

echo "✅ Monitoring container: $APP_CONTAINER"
echo ""

# Initialize counters
TOTAL_CALLS=0
INCOMING_CALLS=0
OUTGOING_CALLS=0
ERRORS=0
START_TIME=$(date +%s)

# Function to display current stats
show_stats() {
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    
    # Calculate rates
    if [ $ELAPSED -gt 0 ]; then
        CALLS_PER_MINUTE=$(( (TOTAL_CALLS * 60) / ELAPSED ))
    else
        CALLS_PER_MINUTE=0
    fi
    
    clear
    echo "========================================="
    echo "    REAL-TIME CALL VOLUME MONITOR"
    echo "========================================="
    echo "Server: 31.184.134.153"
    echo "Monitoring: $APP_CONTAINER"
    echo "Elapsed: ${MINUTES}m ${SECONDS}s"
    echo ""
    echo "📊 CURRENT STATISTICS:"
    echo "----------------------"
    echo "Total calls received:     $TOTAL_CALLS"
    echo "Incoming calls:           $INCOMING_CALLS"
    echo "Outgoing calls:           $OUTGOING_CALLS"
    echo "Errors:                   $ERRORS"
    echo "Calls per minute:         $CALLS_PER_MINUTE"
    echo ""
    
    # Show recent calls (last 10)
    echo "📞 RECENT CALLS:"
    echo "----------------"
    docker logs --tail 10 $APP_CONTAINER 2>&1 | grep "\[API_CALL_DETAILS\]" | tail -5 | while read line; do
        FILENAME=$(echo "$line" | grep -o "Filename: [^,]*" | cut -d' ' -f2)
        TYPE=$(echo "$line" | grep -o "Type: [^,]*" | cut -d' ' -f2)
        TIME=$(echo "$line" | grep -o "2025-[0-9-]*T[0-9:]*\.[0-9]*Z" | head -1)
        printf "  %s | %s | %s\n" "$TIME" "$TYPE" "$FILENAME"
    done
    
    echo ""
    echo "Press Ctrl+C to stop monitoring"
}

# Function to check for duplicate filenames in recent calls
check_duplicates() {
    RECENT_FILENAMES=$(docker logs --tail 100 $APP_CONTAINER 2>&1 | grep "\[API_CALL_DETAILS\]" | grep -o "Filename: [^,]*" | cut -d' ' -f2 | sort | uniq -c | sort -nr | head -5)
    
    if [ ! -z "$RECENT_FILENAMES" ]; then
        echo ""
        echo "🔍 RECENT FILENAME FREQUENCY:"
        echo "-----------------------------"
        echo "$RECENT_FILENAMES" | while read count filename; do
            if [ $count -gt 1 ]; then
                printf "  ⚠️  %s: %d times (DUPLICATE!)\n" "$filename" "$count"
            else
                printf "  ✅ %s: %d time\n" "$filename" "$count"
            fi
        done
    fi
}

# Function to check queue status
check_queue_status() {
    REDIS_CONTAINER=$(docker ps --format "table {{.Names}}" | grep redis | head -1)
    if [ ! -z "$REDIS_CONTAINER" ]; then
        WAITING_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:waiting 2>/dev/null || echo "0")
        ACTIVE_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:active 2>/dev/null || echo "0")
        FAILED_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:failed 2>/dev/null || echo "0")
        
        echo ""
        echo "📊 QUEUE STATUS:"
        echo "----------------"
        echo "Waiting jobs:    $WAITING_JOBS"
        echo "Active jobs:     $ACTIVE_JOBS"
        echo "Failed jobs:     $FAILED_JOBS"
    fi
}

# Main monitoring loop
while true; do
    # Get current log count
    CURRENT_TOTAL=$(docker logs $APP_CONTAINER 2>&1 | grep "\[API_CALL_RECEIVED\]" | wc -l)
    CURRENT_INCOMING=$(docker logs $APP_CONTAINER 2>&1 | grep "\[API_CALL_ACCEPTED\]" | wc -l)
    CURRENT_OUTGOING=$(docker logs $APP_CONTAINER 2>&1 | grep "\[API_CALL_SKIPPED\]" | wc -l)
    CURRENT_ERRORS=$(docker logs $APP_CONTAINER 2>&1 | grep "\[API_CALL_ERROR\]" | wc -l)
    
    # Update counters
    TOTAL_CALLS=$CURRENT_TOTAL
    INCOMING_CALLS=$CURRENT_INCOMING
    OUTGOING_CALLS=$CURRENT_OUTGOING
    ERRORS=$CURRENT_ERRORS
    
    # Display stats
    show_stats
    
    # Check for duplicates every 30 seconds
    if [ $(( $(date +%s) % 30 )) -eq 0 ]; then
        check_duplicates
    fi
    
    # Check queue status every 60 seconds
    if [ $(( $(date +%s) % 60 )) -eq 0 ]; then
        check_queue_status
    fi
    
    # Wait 5 seconds before next update
    sleep 5
done
