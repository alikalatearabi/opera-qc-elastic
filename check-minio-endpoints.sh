#!/bin/bash

# Check different MinIO endpoints to find where the files actually are

set -e

MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"

echo "=== Checking Different MinIO Endpoints ==="
echo ""

# Possible endpoints to check
ENDPOINTS=(
    "http://31.184.134.153:9005"
    "http://31.184.134.153:9000"
    "http://31.184.134.153:9001"
    "http://localhost:9005"
    "http://localhost:9000"
    "http://localhost:9001"
    "http://127.0.0.1:9005"
    "http://127.0.0.1:9000"
    "http://127.0.0.1:9001"
)

for endpoint in "${ENDPOINTS[@]}"; do
    echo "Checking: $endpoint"
    
    # Create test alias
    TEST_ALIAS="test_$$"
    
    if mc alias set "$TEST_ALIAS" "$endpoint" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>/dev/null; then
        echo "  ✓ Connection successful"
        
        # List buckets
        if buckets=$(mc ls "$TEST_ALIAS/" 2>/dev/null); then
            echo "  Buckets found:"
            echo "$buckets" | sed 's/^/    /'
            
            # Check if audio-files exists and has files
            if mc ls "$TEST_ALIAS/audio-files" &>/dev/null; then
                file_count=$(mc ls --recursive "$TEST_ALIAS/audio-files/" 2>/dev/null | wc -l)
                bucket_size=$(mc du "$TEST_ALIAS/audio-files" 2>/dev/null | tail -1 || echo "unknown")
                echo "    -> audio-files bucket: $file_count files, size: $bucket_size"
                
                if [ $file_count -gt 0 ]; then
                    echo ""
                    echo "*** FOUND FILES AT: $endpoint ***"
                    echo ""
                fi
            fi
        else
            echo "  ✗ Cannot list buckets"
        fi
        
        # Cleanup
        mc alias remove "$TEST_ALIAS" 2>/dev/null || true
    else
        echo "  ✗ Cannot connect"
    fi
    
    echo ""
done

echo "Done checking endpoints"
