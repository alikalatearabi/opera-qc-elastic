#!/bin/bash

echo "=== Debugging Elasticsearch Query ==="
echo ""

# Try the query and show raw output
echo "Querying Elasticsearch..."
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "dups": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 5,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}' > /tmp/elastic_response.json

echo "Response saved to /tmp/elastic_response.json"
echo ""
echo "First 50 lines of response:"
head -50 /tmp/elastic_response.json

echo ""
echo "Checking for buckets..."
grep -i "buckets" /tmp/elastic_response.json | head -5

echo ""
echo "Checking for key and doc_count..."
grep -E "key|doc_count" /tmp/elastic_response.json | head -20
