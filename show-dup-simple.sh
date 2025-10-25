#!/bin/bash

echo "Finding duplicates..."

# Get all filenames and count them
curl -s -X POST "localhost:9200/opera-qc-session-events/_search?size=0" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "all_filenames": {
      "terms": {
        "field": "filename",
        "size": 50
      }
    }
  }
}' > /tmp/result.json

# Just show the JSON so we can see what we get
echo "Raw response:"
cat /tmp/result.json
