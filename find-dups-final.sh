#!/bin/bash

echo "=== Finding Duplicate Filenames ==="
echo ""

# Query and parse duplicates
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "dups": {
      "terms": {
        "field": "filename",
        "min_doc_count": 2,
        "size": 50,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}' | awk -F'"' '
/"key":/ { filename = $4; next }
/"doc_count":/ { count = $3; if (filename) print count "x - " filename; filename = "" }
'
