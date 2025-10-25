#!/bin/bash

echo "=== Finding Duplicates ==="
echo ""

# Query and save to file
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "dups": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 50,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}' > /tmp/dups.json

# Parse with awk
awk -F'"' '
/"key":/ { filename = $4; next }
/"doc_count":/ { count = $3; print count "x - " filename }
' /tmp/dups.json

rm -f /tmp/dups.json
