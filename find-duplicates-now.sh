#!/bin/bash

# Find Existing Duplicates
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

# Query for duplicates in last 24 hours
echo "=== Checking for Duplicates (Last 24 Hours) ==="

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
        "size": 50,
        "order": { "_count": "desc" }
      },
      "aggs": {
        "duplicate_docs": {
          "top_hits": {
            "size": 5,
            "_source": ["id", "date", "sourceNumber", "destNumber"]
          }
        }
      }
    }
  },
  "size": 0
}'

RESPONSE=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$QUERY")

# Parse the response
DUPLICATE_COUNT=$(echo "$RESPONSE" | jq '.aggregations.duplicate_filenames.buckets | length')

if [ "$DUPLICATE_COUNT" = "0" ]; then
    echo "✅ No duplicates found in last 24 hours"
else
    echo "⚠️  Found $DUPLICATE_COUNT filenames with duplicates"
    echo ""
    
    # Show details of each duplicate
    echo "$RESPONSE" | jq -r '.aggregations.duplicate_filenames.buckets[] | 
        "Filename: \(.key)
        Times: \(.doc_count)
        Document IDs:
        \(.duplicate_docs.hits.hits[] | "  - ID: \(._id), Date: \(._source.date), Source: \(._source.sourceNumber), Dest: \(._source.destNumber)")
        ---"'
fi

echo ""

# Check all time duplicates
echo "=== Checking for Duplicates (All Time) ==="

ALL_TIME_QUERY='{
  "aggs": {
    "duplicate_filenames": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 50,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}'

ALL_TIME_RESPONSE=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$ALL_TIME_QUERY")

ALL_DUPLICATE_COUNT=$(echo "$ALL_TIME_RESPONSE" | jq '.aggregations.duplicate_filenames.buckets | length')

if [ "$ALL_DUPLICATE_COUNT" = "0" ]; then
    echo "✅ No duplicates found in entire history"
else
    echo "⚠️  Found $ALL_DUPLICATE_COUNT filenames with duplicates in entire history"
    echo ""
    
    # Show top duplicates
    echo "Top 20 most duplicated filenames:"
    echo "$ALL_TIME_RESPONSE" | jq -r '.aggregations.duplicate_filenames.buckets[0:20][] | 
        "\(.doc_count)x - \(.key)"'
fi

echo ""

# Get statistics
echo "=== Statistics ==="

TOTAL_RESPONSE=$(curl -s -X GET "localhost:9200/opera-qc-session-events/_count")
TOTAL_COUNT=$(echo "$TOTAL_RESPONSE" | jq '.count')

UNIQUE_FILENAMES=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{"aggs":{"unique_filenames":{"cardinality":{"field":"filename.keyword"}}},"size":0}' | jq '.aggregations.unique_filenames.value')

echo "Total records: $TOTAL_COUNT"
echo "Unique filenames: $UNIQUE_FILENAMES"
if [ "$ALL_DUPLICATE_COUNT" != "0" ]; then
    DUPLICATE_RECORDS=$((TOTAL_COUNT - UNIQUE_FILENAMES))
    echo "Duplicate records: $DUPLICATE_RECORDS"
    PERCENTAGE=$(echo "scale=2; $DUPLICATE_RECORDS * 100 / $TOTAL_COUNT" | bc)
    echo "Percentage: ${PERCENTAGE}%"
fi

echo ""
echo "Done"
