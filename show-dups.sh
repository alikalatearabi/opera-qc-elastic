#!/bin/bash

echo "=== Duplicate Filenames in Elasticsearch ==="
echo ""

# Query and parse
curl -s -X POST "localhost:9200/opera-qc-session-events/_search?size=0" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "filenames": {
      "terms": {
        "field": "filename",
        "size": 100,
        "order": { "_count": "desc" }
      }
    }
  }
}' | grep -o '"key":"[^"]*","doc_count":[0-9]*' | sed 's/"key":"//g' | sed 's/","doc_count":/ /g' | sed 's/"//g' | while read filename count; do
    printf "%-70s - %3d times\n" "$filename" "$count"
done | head -100

echo ""
echo "Summary shown above"
echo ""
echo "Note: sum_other_doc_count shows there are more than 100 unique filenames"
echo "Current response shows top 100 most frequent filenames"
