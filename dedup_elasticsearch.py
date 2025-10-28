#!/usr/bin/env python3
"""
Remove duplicate documents from Elasticsearch
Keeps the oldest record for each filename
"""

import json
import subprocess
import sys
from collections import defaultdict

def curl_post(url, data):
    """Execute curl POST request"""
    cmd = [
        'curl', '-s', '-X', 'POST',
        url,
        '-H', 'Content-Type: application/json',
        '-d', json.dumps(data)
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout)

def curl_get(url):
    """Execute curl GET request"""
    cmd = ['curl', '-s', '-X', 'GET', url]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout)

def delete_doc(doc_id):
    """Delete a document by ID"""
    url = f"localhost:9200/opera-qc-session-events/_doc/{doc_id}"
    cmd = ['curl', '-s', '-X', 'DELETE', url]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout)

def main():
    print("=== Removing Duplicates from Elasticsearch ===\n")
    
    # Get all duplicates
    print("Finding duplicates...")
    query = {
        "aggs": {
            "duplicates": {
                "terms": {
                    "field": "filename",
                    "min_doc_count": 2,
                    "size": 1000
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
    }
    
    result = curl_post("localhost:9200/opera-qc-session-events/_search", query)
    buckets = result.get('aggregations', {}).get('duplicates', {}).get('buckets', [])
    
    print(f"Found {len(buckets)} filenames with duplicates\n")
    
    if len(buckets) == 0:
        print("No duplicates found!")
        return
    
    # Count total duplicates to delete
    total_to_delete = 0
    for bucket in buckets:
        count = bucket['doc_count']
        # Keep 1, delete (count - 1)
        total_to_delete += (count - 1)
    
    print(f"Total duplicate records to delete: {total_to_delete}")
    print(f"Approximate records to keep: {len(buckets)}")
    print()
    
    response = input("Continue with deletion? (y/N): ")
    if response.lower() != 'y':
        print("Cancelled.")
        return
    
    print("\nDeleting duplicates...")
    
    deleted = 0
    for bucket in buckets:
        filename = bucket['key']
        count = bucket['doc_count']
        docs = bucket['docs']['hits']['hits']
        
        # Keep the first (oldest), delete the rest
        for doc in docs[1:]:  # Skip first doc
            doc_id = doc['_id']
            delete_doc(doc_id)
            deleted += 1
            
            if deleted % 100 == 0:
                print(f"Deleted {deleted} duplicate records...")
    
    print(f"\nDone! Deleted {deleted} duplicate records")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled by user")
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
