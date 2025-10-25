#!/bin/bash

# List Files by Date in Elasticsearch
# Groups files by date and shows counts

echo "=== Files Grouped by Date ==="
echo "Time: $(date)"
echo ""

# Check if Elasticsearch is running
if ! curl -s http://localhost:9200 >/dev/null 2>&1; then
    echo "❌ Elasticsearch is not running"
    exit 1
fi

echo "✅ Elasticsearch is accessible"
echo ""

# Query files grouped by date
echo "=== Files by Date (Current Month) ==="

QUERY='{
  "query": {
    "range": {
      "date": {
        "gte": "now-30d"
      }
    }
  },
  "aggs": {
    "by_date": {
      "date_histogram": {
        "field": "date",
        "calendar_interval": "day",
        "format": "yyyy-MM-dd"
      },
      "aggs": {
        "unique_files": {
          "cardinality": {
            "field": "filename.keyword"
          }
        }
      }
    }
  },
  "size": 0
}'

# Execute query and parse response
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$QUERY" | grep -A 2 '"key_as_string"' | while read -r line; do
    if echo "$line" | grep -q '"key_as_string"'; then
        DATE=$(echo "$line" | sed 's/.*"key_as_string":"\([^"]*\)".*/\1/')
        READ_LINE=$DATE
    fi
    if echo "$line" | grep -q '"doc_count"'; then
        COUNT=$(echo "$line" | sed 's/.*"doc_count":\([0-9]*\).*/\1/')
        UNIQUE_LINE=""
    fi
    if echo "$line" | grep -q '"value"'; then
        UNIQUE=$(echo "$line" | grep '"value"' | sed 's/.*"value":\([0-9]*\).*/\1/')
        if [ -n "$DATE" ] && [ -n "$COUNT" ] && [ -n "$UNIQUE" ]; then
            DUPLICATES=$((COUNT - UNIQUE))
            printf "%s: Total=%d, Unique=%d, Duplicates=%d\n" "$DATE" "$COUNT" "$UNIQUE" "$DUPLICATES"
        fi
    fi
done

echo ""

# Get overall statistics
echo "=== Overall Statistics ==="

TOTAL_COUNT=$(curl -s -X GET "localhost:9200/opera-qc-session-events/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' || echo "0")

UNIQUE_FILES_QUERY='{
  "aggs": {
    "unique": {
      "cardinality": {
        "field": "filename.keyword"
      }
    }
  },
  "size": 0
}'

UNIQUE_COUNT=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$UNIQUE_FILES_QUERY" | grep -o '"value":[0-9]*' | grep -o '[0-9]*' || echo "0")

DUPLICATE_COUNT=$((TOTAL_COUNT - UNIQUE_COUNT))

echo "Total records: $TOTAL_COUNT"
echo "Unique filenames: $UNIQUE_COUNT"
echo "Potential duplicates: $DUPLICATE_COUNT"

if [ "$TOTAL_COUNT" -gt 0 ]; then
    PERCENTAGE=$(echo "scale=2; $DUPLICATE_COUNT * 100 / $TOTAL_COUNT" | bc 2>/dev/null || echo "0")
    echo "Duplicate percentage: ${PERCENTAGE}%"
fi

echo ""
echo "Done"
