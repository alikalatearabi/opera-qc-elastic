#!/bin/bash

# Show Duplicate Filenames
# Lists filenames that appear multiple times

echo "=== Finding Duplicate Filenames ==="
echo "Time: $(date)"
echo ""

# Query for duplicate filenames
QUERY='{
  "aggs": {
    "duplicates": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 100,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}'

echo "Getting duplicate filenames from Elasticsearch..."
echo ""

# Get response and save to temp file
TEMP_FILE="/tmp/elastic_duplicates_$$.json"
curl -s -X POST "localhost:9200/opera-qc-session-events/_search" \
  -H 'Content-Type: application/json' \
  -d "$QUERY" > "$TEMP_FILE"

# Parse and display results
echo "=== Top 50 Most Duplicated Filenames ==="
echo ""

# Extract duplicates using grep and awk
grep -o '"key":"[^"]*"' "$TEMP_FILE" | sed 's/"key":"//g' | sed 's/"//g' | while read -r filename; do
    # Count occurrences by searching for this filename in the response
    COUNT=$(grep -o "\"key\":\"$filename\"" "$TEMP_FILE" | wc -l)
    # Get the actual count from the doc_count field after this key
    grep -A 3 "\"key\":\"$filename\"" "$TEMP_FILE" | grep "doc_count" | grep -o '[0-9]*' | head -1
done | paste - - 2>/dev/null | while read count filename; do
    if [ -n "$count" ] && [ -n "$filename" ]; then
        echo "$count times: $filename"
    fi
done | head -50

rm -f "$TEMP_FILE"

echo ""
echo "Done"
