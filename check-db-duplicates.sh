#!/bin/bash

# Database Duplicate Checker
# Checks for duplicate filenames in the database

echo "=== Database Duplicate Checker ==="
echo "Time: $(date)"
echo ""

# Get PostgreSQL container
POSTGRES_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i postgres | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ No PostgreSQL container found"
    exit 1
fi

echo "PostgreSQL container: $POSTGRES_CONTAINER"
echo ""

# Check for duplicate filenames in the last 24 hours
echo "=== Checking for Duplicate Filenames (Last 24 Hours) ==="

DUPLICATES=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "
SELECT filename, COUNT(*) as count 
FROM \"SessionEvent\" 
WHERE date >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY filename 
HAVING COUNT(*) > 1 
ORDER BY count DESC 
LIMIT 20;" 2>/dev/null)

if [ ! -z "$DUPLICATES" ]; then
    echo "⚠️  DUPLICATES FOUND:"
    echo ""
    echo "$DUPLICATES" | while read line; do
        if [ ! -z "$line" ]; then
            echo "  $line"
        fi
    done
else
    echo "✅ No duplicates found in last 24 hours"
fi

echo ""

# Get total count and stats
echo "=== Database Statistics ==="

TODAY_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\" WHERE date >= CURRENT_DATE;" 2>/dev/null | tr -d ' ' || echo "0")

YESTERDAY_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\" WHERE date >= CURRENT_DATE - INTERVAL '1 day' AND date < CURRENT_DATE;" 2>/dev/null | tr -d ' ' || echo "0")

TOTAL_COUNT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "SELECT COUNT(*) FROM \"SessionEvent\";" 2>/dev/null | tr -d ' ' || echo "0")

echo "Total today: $TODAY_COUNT"
echo "Total yesterday: $YESTERDAY_COUNT"
echo "Total records: $TOTAL_COUNT"

echo ""
echo "=== Recent Records (Last 10) ==="

RECENT=$(docker exec -e PGPASSWORD='StrongP@ssw0rd123' $POSTGRES_CONTAINER psql -U postgres -d opera_qc -t -c "
SELECT 
    DATE_TRUNC('hour', date) as hour,
    filename,
    type,
    source_number,
    dest_number
FROM \"SessionEvent\"
ORDER BY date DESC
LIMIT 10;" 2>/dev/null)

if [ ! -z "$RECENT" ]; then
    echo "$RECENT"
else
    echo "No recent records found"
fi

echo ""
echo "Done"
