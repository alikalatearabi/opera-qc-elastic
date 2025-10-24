#!/bin/bash

# Duplicate Call Analysis Script for Production Server
# This script helps identify if external API is sending duplicate calls

echo "========================================="
echo "    DUPLICATE CALL ANALYSIS"
echo "========================================="
echo "Server: 31.184.134.153"
echo "Generated at: $(date)"
echo ""

# Find app container
APP_CONTAINER=$(docker ps --format "table {{.Names}}" | grep -E "(app|opera)" | head -1)

if [ -z "$APP_CONTAINER" ]; then
    echo "❌ No app container found"
    exit 1
fi

echo "✅ Analyzing container: $APP_CONTAINER"
echo ""

# Get logs from last 24 hours
echo "📊 ANALYZING CALLS FROM LAST 24 HOURS:"
echo "--------------------------------------"

# Get all API call details from last 24 hours
CALL_DETAILS=$(docker logs --since 24h $APP_CONTAINER 2>&1 | grep "\[API_CALL_DETAILS\]")

if [ -z "$CALL_DETAILS" ]; then
    echo "❌ No API call details found in last 24 hours"
    exit 1
fi

TOTAL_CALLS=$(echo "$CALL_DETAILS" | wc -l)
echo "Total calls in last 24 hours: $TOTAL_CALLS"

# Extract filenames and analyze duplicates
echo ""
echo "🔍 FILENAME DUPLICATE ANALYSIS:"
echo "-------------------------------"

# Create a temporary file to store filename analysis
TEMP_FILE="/tmp/filename_analysis_$$.txt"

# Extract filenames with timestamps
echo "$CALL_DETAILS" | while read line; do
    FILENAME=$(echo "$line" | grep -o "Filename: [^,]*" | cut -d' ' -f2)
    TIMESTAMP=$(echo "$line" | grep -o "2025-[0-9-]*T[0-9:]*\.[0-9]*Z" | head -1)
    TYPE=$(echo "$line" | grep -o "Type: [^,]*" | cut -d' ' -f2)
    if [ ! -z "$FILENAME" ] && [ ! -z "$TIMESTAMP" ]; then
        echo "$TIMESTAMP|$TYPE|$FILENAME" >> "$TEMP_FILE"
    fi
done

# Analyze duplicates
if [ -f "$TEMP_FILE" ]; then
    # Count duplicates by filename
    DUPLICATES=$(cut -d'|' -f3 "$TEMP_FILE" | sort | uniq -c | sort -nr | head -20)
    
    echo "Top filenames by frequency:"
    echo "$DUPLICATES" | while read count filename; do
        if [ $count -gt 1 ]; then
            printf "  ⚠️  %s: %d times (DUPLICATE!)\n" "$filename" "$count"
            
            # Show timestamps for duplicates
            echo "    Timestamps:"
            grep "|$filename$" "$TEMP_FILE" | cut -d'|' -f1 | while read timestamp; do
                echo "      - $timestamp"
            done
            echo ""
        else
            printf "  ✅ %s: %d time\n" "$filename" "$count"
        fi
    done
    
    # Clean up temp file
    rm -f "$TEMP_FILE"
fi

echo ""
echo "📈 CALL PATTERN ANALYSIS:"
echo "-------------------------"

# Analyze call patterns by hour
echo "Calls per hour (last 24 hours):"
HOURLY_PATTERN=$(echo "$CALL_DETAILS" | grep -o "2025-[0-9-]*T[0-9][0-9]:" | cut -d'T' -f2 | cut -d':' -f1 | sort | uniq -c | sort -k2 -n)

if [ ! -z "$HOURLY_PATTERN" ]; then
    echo "$HOURLY_PATTERN" | while read count hour; do
        printf "  Hour %02d:00 - %02d:59: %4d calls\n" "$hour" "$hour" "$count"
    done
fi

echo ""
echo "🕐 TIME-BASED DUPLICATE ANALYSIS:"
echo "--------------------------------"

# Check for calls with same filename within short time windows
echo "Checking for rapid duplicates (same filename within 5 minutes):"

# Create detailed analysis file
DETAILED_FILE="/tmp/detailed_analysis_$$.txt"
echo "$CALL_DETAILS" | while read line; do
    FILENAME=$(echo "$line" | grep -o "Filename: [^,]*" | cut -d' ' -f2)
    TIMESTAMP=$(echo "$line" | grep -o "2025-[0-9-]*T[0-9:]*\.[0-9]*Z" | head -1)
    if [ ! -z "$FILENAME" ] && [ ! -z "$TIMESTAMP" ]; then
        # Convert timestamp to epoch for comparison
        EPOCH=$(date -d "$TIMESTAMP" +%s 2>/dev/null || echo "0")
        echo "$EPOCH|$TIMESTAMP|$FILENAME" >> "$DETAILED_FILE"
    fi
done

if [ -f "$DETAILED_FILE" ]; then
    # Sort by filename and timestamp
    sort -t'|' -k3,3 -k1,1n "$DETAILED_FILE" > "${DETAILED_FILE}.sorted"
    
    # Find rapid duplicates
    RAPID_DUPLICATES=0
    CURRENT_FILENAME=""
    CURRENT_TIMESTAMP=0
    
    while IFS='|' read -r epoch timestamp filename; do
        if [ "$filename" = "$CURRENT_FILENAME" ]; then
            TIME_DIFF=$((epoch - CURRENT_TIMESTAMP))
            if [ $TIME_DIFF -lt 300 ]; then  # Less than 5 minutes
                RAPID_DUPLICATES=$((RAPID_DUPLICATES + 1))
                echo "  ⚠️  Rapid duplicate: $filename"
                echo "      First:  $CURRENT_TIMESTAMP_STR"
                echo "      Second: $timestamp"
                echo "      Gap:    ${TIME_DIFF}s"
                echo ""
            fi
        fi
        CURRENT_FILENAME="$filename"
        CURRENT_TIMESTAMP="$epoch"
        CURRENT_TIMESTAMP_STR="$timestamp"
    done < "${DETAILED_FILE}.sorted"
    
    if [ $RAPID_DUPLICATES -eq 0 ]; then
        echo "  ✅ No rapid duplicates found"
    else
        echo "  🚨 Found $RAPID_DUPLICATES rapid duplicate pairs"
    fi
    
    # Clean up
    rm -f "$DETAILED_FILE" "${DETAILED_FILE}.sorted"
fi

echo ""
echo "🔍 EXTERNAL API BEHAVIOR ANALYSIS:"
echo "----------------------------------"

# Analyze if external API is sending calls in bursts
echo "Analyzing call burst patterns..."

# Get call timestamps and analyze gaps
TIMESTAMPS=$(echo "$CALL_DETAILS" | grep -o "2025-[0-9-]*T[0-9:]*\.[0-9]*Z" | sort)

if [ ! -z "$TIMESTAMPS" ]; then
    # Calculate time gaps between calls
    PREVIOUS_EPOCH=0
    GAPS_FILE="/tmp/gaps_$$.txt"
    
    echo "$TIMESTAMPS" | while read timestamp; do
        CURRENT_EPOCH=$(date -d "$timestamp" +%s 2>/dev/null || echo "0")
        if [ $PREVIOUS_EPOCH -gt 0 ]; then
            GAP=$((CURRENT_EPOCH - PREVIOUS_EPOCH))
            echo "$GAP" >> "$GAPS_FILE"
        fi
        PREVIOUS_EPOCH=$CURRENT_EPOCH
    done
    
    if [ -f "$GAPS_FILE" ]; then
        # Analyze gap patterns
        SMALL_GAPS=$(awk '$1 < 10 {count++} END {print count+0}' "$GAPS_FILE")
        MEDIUM_GAPS=$(awk '$1 >= 10 && $1 < 60 {count++} END {print count+0}' "$GAPS_FILE")
        LARGE_GAPS=$(awk '$1 >= 60 {count++} END {print count+0}' "$GAPS_FILE")
        
        echo "Call gap analysis:"
        echo "  Small gaps (<10s):    $SMALL_GAPS"
        echo "  Medium gaps (10-60s): $MEDIUM_GAPS"
        echo "  Large gaps (>60s):    $LARGE_GAPS"
        
        if [ $SMALL_GAPS -gt 50 ]; then
            echo "  ⚠️  High number of small gaps - possible burst sending"
        fi
        
        rm -f "$GAPS_FILE"
    fi
fi

echo ""
echo "📋 RECOMMENDATIONS:"
echo "------------------"

# Provide recommendations based on analysis
if [ $TOTAL_CALLS -gt 5000 ]; then
    echo "1. 🚨 HIGH VOLUME: $TOTAL_CALLS calls in 24h - check if this is expected"
fi

echo "2. 🔍 Check external API configuration:"
echo "   - Verify webhook retry settings"
echo "   - Check if multiple instances are sending calls"
echo "   - Review API rate limiting"

echo "3. 📊 Monitor for patterns:"
echo "   - Run this script regularly to track trends"
echo "   - Set up alerts for unusual call volumes"
echo "   - Log external API behavior"

echo "4. 🛠️  Implementation suggestions:"
echo "   - Add filename-based deduplication in your API"
echo "   - Implement call rate monitoring"
echo "   - Add external API health checks"

echo ""
echo "========================================="
echo "Analysis completed at: $(date)"
echo "========================================="
