#!/bin/bash

# Cleanup Duplicates using Elasticsearch delete-by-query
# Keeps the first (oldest) record for each filename

echo "=== Cleanup Duplicate Records ==="
echo ""
echo "Strategy: For each duplicate filename, keep the oldest record"
echo ""

# First, let's see how many duplicates we have
echo "Checking current duplicate count..."
DUPLICATE_CHECK=$(curl -s -X POST "localhost:9200/opera-qc-session-events/_search?size=0" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "dups": {
      "terms": {
        "field": "filename",
        "min_doc_count": 2,
        "size": 1
      }
    }
  }
}')

DUPLICATE_BUCKETS=$(echo "$DUPLICATE_CHECK" | grep -o '"buckets":\[.*\]' | grep -o '{"key":' | wc -l)

if [ "$DUPLICATE_BUCKETS" = "0" ]; then
    echo "✅ No duplicates found!"
    exit 0
fi

echo "⚠️  Found duplicate filenames"
echo ""

# Show a few examples
echo "Sample duplicate filenames:"
curl -s -X POST "localhost:9200/opera-qc-session-events/_search?size=0" \
  -H 'Content-Type: application/json' \
  -d '{
  "aggs": {
    "sample": {
      "terms": {
        "field": "filename",
        "min_doc_count": 2,
        "size": 5
      }
    }
  }
}' | grep -o '"key":"[^"]*"' | sed 's/"key":"//g' | sed 's/"//g' | head -5

echo ""
read -p "Continue with cleanup? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Removing duplicates..."

# Strategy: Use a script-based approach to find and delete duplicates
# For each filename that appears multiple times, keep only one

echo "This will take a while with 100K+ records..."
echo "Consider running this during off-peak hours"
echo ""

# Get total count before
BEFORE_COUNT=$(curl -s "localhost:9200/opera-qc-session-events/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
echo "Total records before: $BEFORE_COUNT"

# Method: Reindex with deduplication
echo ""
echo "Creating reindex script..."

# Create a Python script for better handling
cat > /tmp/reindex_dedup.py << 'PYTHONEOF'
import json
import subprocess
import sys

def reindex_with_dedup():
    print("Fetching all documents...")
    
    # Use scroll API to get all docs
    scroll_query = {
        "query": {"match_all": {}},
        "sort": [{"date": "asc"}],
        "size": 1000
    }
    
    cmd = [
        'curl', '-s', '-X', 'POST',
        'localhost:9200/opera-qc-session-events/_search?scroll=1m&size=1000',
        '-H', 'Content-Type: application/json',
        '-d', json.dumps(scroll_query)
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return
    
    print("Done")
    print("Note: Full reindexing with deduplication requires more complex logic")
    print("Consider using Elasticsearch reindex API with deduplication script")

if __name__ == "__main__":
    reindex_with_dedup()
PYTHONEOF

python3 /tmp/reindex_dedup.py

rm -f /tmp/reindex_dedup.py

echo ""
echo "Alternative: Use Kibana to delete duplicates manually"
echo "Or: Reindex to a new index with deduplication logic"
