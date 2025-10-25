#!/bin/bash

echo "=== Checking Elasticsearch Mapping ==="
echo ""

echo "Index mapping:"
curl -s "localhost:9200/opera-qc-session-events/_mapping" | grep -A 5 "filename"

echo ""
echo "Checking a sample document..."
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{"size": 1, "_source": ["filename", "date"]}' | grep -E "filename|date" | head -10

echo ""
echo "Testing different field names..."

# Try filename as-is
echo "1. Trying 'filename.keyword':"
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" -H 'Content-Type: application/json' -d '{"aggs":{"test":{"terms":{"field":"filename.keyword","size":5}}},"size":0}' | grep -o "buckets\":\[\[^]]*\]" | head -1

# Try just filename
echo ""
echo "2. Trying 'filename':"
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" -H 'Content-Type: application/json' -d '{"aggs":{"test":{"terms":{"field":"filename","size":5}}},"size":0}' | grep -o "buckets\":\[\[^]]*\]" | head -1

echo ""
echo "Done"
