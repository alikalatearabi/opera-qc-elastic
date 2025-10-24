#!/bin/bash

# High Call Volume Investigation Script for Production Server
# Run this on your production server: 31.184.134.153

echo "========================================="
echo "    HIGH CALL VOLUME INVESTIGATION"
echo "========================================="
echo "Server: 31.184.134.153"
echo "Generated at: $(date)"
echo ""

# Check if Docker is running
if ! docker ps >/dev/null 2>&1; then
    echo "❌ Docker is not running or not accessible"
    exit 1
fi

# Get container logs
echo "📊 ANALYZING CALL PATTERNS:"
echo "---------------------------"

# Check if app container exists and get its name
APP_CONTAINER=$(docker ps -a --format "table {{.Names}}" | grep -E "(app|opera)" | head -1)

if [ -z "$APP_CONTAINER" ]; then
    echo "❌ No app container found. Available containers:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

echo "✅ Found app container: $APP_CONTAINER"
echo ""

# Get recent logs (last 1000 lines)
LOGS=$(docker logs --tail 1000 $APP_CONTAINER 2>&1)

echo "📞 RECENT API CALL STATISTICS (Last 1000 log entries):"
echo "-----------------------------------------------------"

# Count different types of API calls
TOTAL_RECEIVED=$(echo "$LOGS" | grep "\[API_CALL_RECEIVED\]" | wc -l)
ACCEPTED=$(echo "$LOGS" | grep "\[API_CALL_ACCEPTED\]" | wc -l)
SKIPPED=$(echo "$LOGS" | grep "\[API_CALL_SKIPPED\]" | wc -l)
QUEUED=$(echo "$LOGS" | grep "\[API_CALL_QUEUED\]" | wc -l)
REJECTED=$(echo "$LOGS" | grep "\[API_CALL_REJECTED\]" | wc -l)
ERRORS=$(echo "$LOGS" | grep "\[API_CALL_ERROR\]" | wc -l)

echo "Total API calls received:     $TOTAL_RECEIVED"
echo "Incoming calls accepted:      $ACCEPTED"
echo "Outgoing calls skipped:       $SKIPPED"
echo "Jobs successfully queued:     $QUEUED"
echo "Calls rejected (bad data):    $REJECTED"
echo "API processing errors:        $ERRORS"

echo ""
echo "📈 CALL VOLUME BY HOUR (Last 24 hours):"
echo "---------------------------------------"

# Extract hourly call patterns
HOURLY_CALLS=$(echo "$LOGS" | grep "\[API_CALL_RECEIVED\]" | grep -o "2025-[0-9-]*T[0-9][0-9]:" | cut -d'T' -f2 | cut -d':' -f1 | sort | uniq -c | sort -k2 -n)

if [ ! -z "$HOURLY_CALLS" ]; then
    echo "$HOURLY_CALLS" | while read count hour; do
        printf "Hour %02d:00 - %02d:59: %4d calls\n" "$hour" "$hour" "$count"
    done
else
    echo "No recent API calls found in logs"
fi

echo ""
echo "🔍 DUPLICATE CALL ANALYSIS:"
echo "---------------------------"

# Check for duplicate filenames in recent calls
echo "Checking for duplicate filenames in last 100 calls..."
RECENT_FILENAMES=$(echo "$LOGS" | grep "\[API_CALL_DETAILS\]" | tail -100 | grep -o "Filename: [^,]*" | cut -d' ' -f2 | sort | uniq -c | sort -nr | head -10)

if [ ! -z "$RECENT_FILENAMES" ]; then
    echo "Top filenames by frequency:"
    echo "$RECENT_FILENAMES" | while read count filename; do
        if [ $count -gt 1 ]; then
            printf "  ⚠️  %s: %d times (POTENTIAL DUPLICATE)\n" "$filename" "$count"
        else
            printf "  ✅ %s: %d time\n" "$filename" "$count"
        fi
    done
else
    echo "No filename data found in recent logs"
fi

echo ""
echo "📊 QUEUE STATUS:"
echo "----------------"

# Check Redis queue status
if docker ps | grep -q redis; then
    REDIS_CONTAINER=$(docker ps --format "table {{.Names}}" | grep redis | head -1)
    echo "✅ Redis container found: $REDIS_CONTAINER"
    
    # Check queue lengths
    WAITING_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:waiting 2>/dev/null || echo "0")
    ACTIVE_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:active 2>/dev/null || echo "0")
    COMPLETED_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:completed 2>/dev/null || echo "0")
    FAILED_JOBS=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:failed 2>/dev/null || echo "0")
    
    echo "Sequential Queue Status:"
    echo "  Waiting jobs:    $WAITING_JOBS"
    echo "  Active jobs:     $ACTIVE_JOBS"
    echo "  Completed jobs:  $COMPLETED_JOBS"
    echo "  Failed jobs:     $FAILED_JOBS"
    
    # Check transcription queue
    TRANS_WAITING=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:transcription-processing:waiting 2>/dev/null || echo "0")
    TRANS_ACTIVE=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:transcription-processing:active 2>/dev/null || echo "0")
    TRANS_FAILED=$(docker exec $REDIS_CONTAINER redis-cli LLEN bull:transcription-processing:failed 2>/dev/null || echo "0")
    
    echo "Transcription Queue Status:"
    echo "  Waiting jobs:    $TRANS_WAITING"
    echo "  Active jobs:     $TRANS_ACTIVE"
    echo "  Failed jobs:     $TRANS_FAILED"
else
    echo "❌ Redis container not found"
fi

echo ""
echo "🗄️  DATABASE STATUS:"
echo "-------------------"

# Check database status
if docker ps | grep -q postgres; then
    POSTGRES_CONTAINER=$(docker ps --format "table {{.Names}}" | grep postgres | head -1)
    echo "✅ PostgreSQL container found: $POSTGRES_CONTAINER"
    
    # Get recent session counts
    TODAY_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\" WHERE DATE(date) = CURRENT_DATE;" 2>/dev/null | tr -d ' ' || echo "0")
    YESTERDAY_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\" WHERE DATE(date) = CURRENT_DATE - INTERVAL '1 day';" 2>/dev/null | tr -d ' ' || echo "0")
    TOTAL_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\";" 2>/dev/null | tr -d ' ' || echo "0")
    
    echo "Session counts:"
    echo "  Today:          $TODAY_COUNT"
    echo "  Yesterday:      $YESTERDAY_COUNT"
    echo "  Total:          $TOTAL_COUNT"
    
    # Check for recent duplicates in database
    echo ""
    echo "Checking for duplicate filenames in database (last 24 hours)..."
    DUPLICATES=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "
    SELECT filename, COUNT(*) as count 
    FROM \"SessionEvent\" 
    WHERE date >= CURRENT_DATE - INTERVAL '1 day'
    GROUP BY filename 
    HAVING COUNT(*) > 1 
    ORDER BY count DESC 
    LIMIT 10;" 2>/dev/null)
    
    if [ ! -z "$DUPLICATES" ] && [ "$DUPLICATES" != " " ]; then
        echo "⚠️  DUPLICATE FILENAMES FOUND:"
        echo "$DUPLICATES" | while read filename count; do
            if [ -n "$filename" ] && [ "$filename" != " " ]; then
                printf "  %s: %s times\n" "$filename" "$count"
            fi
        done
    else
        echo "✅ No duplicate filenames found in database"
    fi
else
    echo "❌ PostgreSQL container not found"
fi

echo ""
echo "🚨 POTENTIAL ISSUES IDENTIFIED:"
echo "-------------------------------"

# Analyze for potential issues
ISSUES_FOUND=0

# Check for high call volume
if [ $TOTAL_RECEIVED -gt 1000 ]; then
    echo "⚠️  HIGH CALL VOLUME: $TOTAL_RECEIVED calls in recent logs"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check for high error rate
if [ $TOTAL_RECEIVED -gt 0 ]; then
    ERROR_RATE=$(( (ERRORS * 100) / TOTAL_RECEIVED ))
    if [ $ERROR_RATE -gt 5 ]; then
        echo "⚠️  HIGH ERROR RATE: $ERROR_RATE% ($ERRORS errors out of $TOTAL_RECEIVED calls)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi

# Check for queue backlog
if [ $WAITING_JOBS -gt 100 ]; then
    echo "⚠️  QUEUE BACKLOG: $WAITING_JOBS jobs waiting in queue"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check for failed jobs
if [ $FAILED_JOBS -gt 50 ]; then
    echo "⚠️  HIGH FAILURE RATE: $FAILED_JOBS failed jobs"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ $ISSUES_FOUND -eq 0 ]; then
    echo "✅ No major issues detected"
fi

echo ""
echo "🔧 RECOMMENDED ACTIONS:"
echo "----------------------"

if [ $TOTAL_RECEIVED -gt 1000 ]; then
    echo "1. 📊 Monitor external API sending calls - check if they're sending duplicates"
    echo "2. 🔍 Check if the same filename is being sent multiple times"
    echo "3. 📈 Consider implementing rate limiting on the external API side"
fi

if [ $WAITING_JOBS -gt 100 ]; then
    echo "4. ⚡ Queue is backlogged - consider increasing worker concurrency"
    echo "5. 🔄 Check if transcription service is responding properly"
fi

if [ $FAILED_JOBS -gt 50 ]; then
    echo "6. 🚨 High failure rate - check error logs for specific failure reasons"
    echo "7. 🔧 Review file server connectivity and audio file availability"
fi

echo ""
echo "📋 MONITORING COMMANDS:"
echo "----------------------"
echo "# Real-time log monitoring:"
echo "docker logs -f $APP_CONTAINER | grep '\[API_CALL'"
echo ""
echo "# Check queue status every 10 seconds:"
echo "watch -n 10 'docker exec $REDIS_CONTAINER redis-cli LLEN bull:analyseCalls:waiting'"
echo ""
echo "# Monitor recent calls:"
echo "docker logs --tail 50 $APP_CONTAINER | grep '\[API_CALL_DETAILS\]'"
echo ""
echo "# Check for specific filename duplicates:"
echo "docker logs $APP_CONTAINER 2>&1 | grep 'FILENAME_TO_CHECK' | wc -l"

echo ""
echo "========================================="
echo "Investigation completed at: $(date)"
echo "========================================="
