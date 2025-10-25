#!/bin/bash

# Elasticsearch Duplicate Checker
# Checks for duplicate filenames in Elasticsearch

echo "=== Elasticsearch Duplicate Checker ==="
echo "Time: $(date)"
echo ""

# Get Elasticsearch container
ES_CONTAINER="elasticsearch"

echo "Elasticsearch container: $ES_CONTAINER"
echo ""

# Check Elasticsearch is running
if ! docker ps | grep -q $ES_CONTAINER; then
    echo "❌ Elasticsearch container not running"
    exit 1
fi

echo "✅ Elasticsearch is running"
echo ""

# Query for duplicates from last 24 hours
echo "=== Checking for Duplicate Filenames (Last 24 Hours) ==="

# Create query to find duplicates
QUERY='{
  "query": {
    "range": {
      "date": {
        "gte": "now-24h"
      }
    }
  },
  "aggs": {
    "duplicate_filenames": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 20
      }
    }
  },
  "size": 0
}'

# Execute query
RESULT=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$QUERY")

# Extract duplicates
DUPLICATES=$(echo "$RESULT" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | sed 's/"key":"//g' | sed 's/","doc_count":/ /g')

if [ ! -z "$DUPLICATES" ]; then
    echo "⚠️  DUPLICATES FOUND:"
    echo ""
    echo "$DUPLICATES" | while read line; do
        if [ ! -z "$line" ]; then
            FILENAME=$(echo "$line" | cut -d'"' -f1)
            COUNT=$(echo "$line" | grep -o '[0-9]*$')
            echo "  $FILENAME: $COUNT times"
        fi
    done
else
    echo "✅ No duplicates found in last 24 hours"
fi

echo ""

# Get total stats
echo "=== Elasticsearch Statistics ==="

TOTAL_RESPONSE=$(curl -s -X GET "localhost:9200/opera-qc-session-events/_count")
TOTAL_COUNT=$(echo "$TOTAL_RESPONSE" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')

echo "Total records in index: $TOTAL_COUNT"

# Get last 24 hours count
LAST_24H_RESPONSE=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_count" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "date": {
          "gte": "now-24h"
        }
      }
    }
  }')
LAST_24H_COUNT=$(echo "$LAST_24H_RESPONSE" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')

echo "Records in last 24 hours: $LAST_24H_COUNT"

echo ""

# Get recent records
echo "=== Recent Records (Last 10) ==="

RECENT_RESPONSE=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 10,
    "sort": [{"date": "desc"}],
    "_source": ["filename", "type", "sourceNumber", "destNumber", "date"]
  }')

# Parse recent records
echo "$RECENT_RESPONSE" | grep -o '"filename":"[^"]*"' | sed 's/"filename":"//g' | sed 's/"//g' | head -10 | while read filename; do
    if [ ! -z "$filename" ]; then
        echo "  $filename"
    fi
done

echo ""
echo "Done"
