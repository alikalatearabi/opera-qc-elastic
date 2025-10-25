#!/usr/bin/env python3

import subprocess
import json
import sys

print("=== Finding Duplicate Filenames ===")
print("")

# Query Elasticsearch
query = """{
  "aggs": {
    "duplicates": {
      "terms": {
        "field": "filename.keyword",
        "min_doc_count": 2,
        "size": 50,
        "order": { "_count": "desc" }
      }
    }
  },
  "size": 0
}"""

try:
    result = subprocess.run(
        ['curl', '-s', '-X', 'POST', 'localhost:9200/opera-qc-session-events/_search',
         '-H', 'Content-Type: application/json',
         '-d', query],
        capture_output=True,
        text=True
    )
    
    data = json.loads(result.stdout)
    
    buckets = data.get('aggregations', {}).get('duplicates', {}).get('buckets', [])
    
    if buckets:
        print(f"Found {len(buckets)} duplicate filenames:")
        print("")
        for bucket in buckets:
            filename = bucket['key']
            count = bucket['doc_count']
            print(f"{count:4d}x - {filename}")
    else:
        print("No duplicates found")
        
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
