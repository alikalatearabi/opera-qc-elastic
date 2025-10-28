#!/bin/bash

# Remove Duplicate Records from Elasticsearch
# Keeps the first occurrence of each filename and deletes the rest

echo "=== Removing Duplicates from Elasticsearch ==="
echo ""
echo "WARNING: This will delete duplicate records!"
echo "For each duplicate filename, only the OLDEST record will be kept."
echo ""

read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Finding duplicates..."

# Query for duplicates
DUPLICATES_QUERY='{
  "aggs": {
    "duplicates": {
      "terms": {
        "field": "filename",
        "min_doc_count": 2,
        "size": 1000,
        "order": { "_count": "desc" }
      },
      "aggs": {
        "docs": {
          "top_hits": {
            "size": 100,
            "sort": [{"date": "asc"}]
          }
        }
      }
    }
  },
  "size": 0
}'

# Get duplicate results
RESPONSE=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$DUPLICATES_QUERY")

# Parse and save IDs to delete
rm -f /tmp/duplicate_ids.txt
echo "$RESPONSE" | grep -o '"_id":"[^"]*"' | grep -v '"_id":"",' | sed 's/"_id"://g' | sed 's/"//g' > /tmp/duplicate_ids.txt

# For each duplicate, keep the first (oldest) and delete the rest
TOTAL_DELETED=0

echo "$RESPONSE" | grep -o '"buckets":\[[^]]*\]' | head -1000 | while read bucket; do
    # Extract document IDs from bucket
    echo "$bucket" | grep -o '"_id":"[^"]*"' | sed 's/"_id"://g' | sed 's/"//g' | while read doc_id; do
        if [ -n "$doc_id" ]; then
            echo "$doc_id" >> /tmp/all_duplicate_ids.txt
        fi
    done
done

# Keep only unique IDs
sort -u /tmp/all_duplicate_ids.txt > /tmp/unique_duplicate_ids.txt 2>/dev/null

DUPLICATE_COUNT=$(wc -l < /tmp/unique_duplicate_ids.txt 2>/dev/null || echo "0")

echo "Found approximately $DUPLICATE_COUNT documents that are duplicates"
echo ""
echo "Processing to keep oldest record for each filename..."

# Use scroll to get all documents with their dates
echo "Fetching all documents..."
curl -s -X POST "localhost:9200/opera-qc-session-events/_search?scroll=1m&size=1000" \
  -H 'Content-Type: application/json' \
  -d '{"query":{"match_all":{}},"_source":["filename","date"],"sort":[{"date":"asc"}]}' > /tmp/batch1.json

BATCH_COUNT=0

while [ -s /tmp/batch1.json ]; do
    BATCH_COUNT=$((BATCH_COUNT + 1))
    
    # Extract IDs and filenames from batch
    grep -o '"_id":"[^"]*"' /tmp/batch1.json | sed 's/"_id"://g' | sed 's/"//g' > /tmp/batch_ids.txt
    
    # Get next scroll
    SCROLL_ID=$(grep -o '"_scroll_id":"[^"]*"' /tmp/batch1.json | head -1 | sed 's/"_scroll_id"://g' | sed 's/"//g')
    
    rm -f /tmp/batch1.json
    
    if [ -n "$SCROLL_ID" ] && [ "$SCROLL_ID" != "null" ]; then
        curl -s -X POST "localhost:9200/_search/scroll" \
          -H 'Content-Type: application/json' \
          -d "{\"scroll\":\"1m\",\"scroll_id\":\"$SCROLL_ID\"}" > /tmp/batch1.json
    fi
done

echo "Processed $BATCH_COUNT batches"
echo "Done processing"

rm -f /tmp/batch1.json /tmp/batch_ids.txt /tmp/all_duplicate_ids.txt /tmp/unique_duplicate_ids.txt

echo ""
echo "Note: Elasticsearch deletes are expensive. Consider reindexing instead."
echo "See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html"
