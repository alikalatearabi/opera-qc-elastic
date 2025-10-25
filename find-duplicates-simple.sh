#!/bin/bash

# Find Existing Duplicates (No dependencies version)
# Analyzes current Elasticsearch data to find duplicate filenames

echo "=== Finding Existing Duplicates ==="
echo "Time: $(date)"
echo ""

# Check if Elasticsearch is running
if ! curl -s http://localhost:9200 >/dev/null 2>&1; then
    echo "❌ Elasticsearch is not running or not accessible"
    exit 1
fi

echo "✅ Elasticsearch is accessible"
echo ""

# Get duplicates for last 24 hours
echo "=== Checking for Duplicates (Last 24 Hours) ==="
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
  "query": {
    "range": {"date": {"gte": "now-24h"}}
  },
  "aggs": {
    "duplicates": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 50
      }
    }
  },
  "size": 0
}' | grep -o '"key":"[^"]*"' | head -20

echo ""

# Get all time duplicates
echo "=== Checking for Duplicates (All Time) ==="
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "duplicates": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 50
      }
    }
  },
  "size": 0
}' | grep -o '"key":"[^"]*"' | sed 's/"key":"//g' | sed 's/"//g' | head -20

echo ""

# Get total count
echo "=== Statistics ==="
TOTAL=$(curl -s -X GET "localhost:9200/opera-qc-session-events/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
echo "Total records: $TOTAL"

echo ""
echo "Done"
