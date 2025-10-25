#!/bin/bash

# Upload cleanup script to production server
# Usage: ./upload-cleanup-to-server.sh

set -e

SERVER_USER="rahpoo"
SERVER_HOST="31.184.134.153"
REMOTE_DIR="~/opera-qc-elastic"
CLEANUP_SCRIPT="server-minio-cleanup.sh"

echo "Uploading cleanup script to production server..."
echo "Server: ${SERVER_USER}@${SERVER_HOST}"
echo "Remote directory: ${REMOTE_DIR}"
echo ""

# Check if script exists
if [ ! -f "$CLEANUP_SCRIPT" ]; then
    echo "Error: Cleanup script not found: $CLEANUP_SCRIPT"
    exit 1
fi

# Upload script
echo "Uploading $CLEANUP_SCRIPT..."
scp "$CLEANUP_SCRIPT" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_DIR}/"

# Make it executable on remote server
echo "Making script executable on remote server..."
ssh "${SERVER_USER}@${SERVER_HOST}" "chmod +x ${REMOTE_DIR}/${CLEANUP_SCRIPT}"

echo ""
echo "Upload complete!"
echo ""
echo "Now you can run the script on the server:"
echo "  ssh ${SERVER_USER}@${SERVER_HOST}"
echo "  cd ${REMOTE_DIR}"
echo "  ./${CLEANUP_SCRIPT} 7"
echo ""
echo "Or run it directly:"
echo "  ssh ${SERVER_USER}@${SERVER_HOST} 'cd ${REMOTE_DIR} && ./${CLEANUP_SCRIPT} 7'"
echo ""
echo "The '7' parameter means it will delete files older than 7 days."
