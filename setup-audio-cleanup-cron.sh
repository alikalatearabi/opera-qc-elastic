#!/bin/bash

# Setup script for automated audio cleanup
# This script sets up a cron job to run the audio cleanup automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup-old-audio-files.sh"
CLEANUP_JS_SCRIPT="$SCRIPT_DIR/cleanup-old-audio-files.js"
CRON_LOG="/var/log/audio-cleanup.log"

echo "Audio Cleanup Cron Job Setup"
echo "============================="

# Check if running as root for system-wide cron
if [ "$EUID" -eq 0 ]; then
    echo "Running as root - setting up system-wide cron job"
    CRON_USER="root"
else
    echo "Running as user - setting up user cron job"
    CRON_USER=$(whoami)
fi

# Function to setup cron job
setup_cron() {
    local schedule="$1"
    local script_to_use="$2"
    
    echo "Setting up cron job with schedule: $schedule"
    echo "Using script: $script_to_use"
    
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "$CRON_LOG")"
    sudo touch "$CRON_LOG"
    sudo chmod 666 "$CRON_LOG"
    
    # Add cron job
    local cron_entry="$schedule cd $SCRIPT_DIR && $script_to_use >> $CRON_LOG 2>&1"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "cleanup-old-audio-files"; then
        echo "Existing audio cleanup cron job found. Removing..."
        crontab -l 2>/dev/null | grep -v "cleanup-old-audio-files" | crontab -
    fi
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    echo "✅ Cron job added successfully!"
    echo "📄 Logs will be written to: $CRON_LOG"
}

# Menu for user selection
echo ""
echo "Choose cleanup schedule:"
echo "1) Daily at 2:00 AM"
echo "2) Every 12 hours"
echo "3) Every 6 hours"
echo "4) Custom schedule"
echo "5) Remove existing cron job"
echo ""

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        schedule="0 2 * * *"
        ;;
    2)
        schedule="0 */12 * * *"
        ;;
    3)
        schedule="0 */6 * * *"
        ;;
    4)
        echo "Enter cron schedule (e.g., '0 2 * * *' for daily at 2 AM):"
        read -p "Schedule: " schedule
        ;;
    5)
        echo "Removing existing audio cleanup cron job..."
        if crontab -l 2>/dev/null | grep -q "cleanup-old-audio-files"; then
            crontab -l 2>/dev/null | grep -v "cleanup-old-audio-files" | crontab -
            echo "✅ Cron job removed successfully!"
        else
            echo "ℹ️  No existing audio cleanup cron job found."
        fi
        exit 0
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Choose script type
echo ""
echo "Choose script type:"
echo "1) Bash script (recommended for system cron)"
echo "2) Node.js script (requires Node.js environment)"
echo ""

read -p "Enter your choice (1-2): " script_choice

case $script_choice in
    1)
        if [ ! -f "$CLEANUP_SCRIPT" ]; then
            echo "❌ Bash cleanup script not found: $CLEANUP_SCRIPT"
            exit 1
        fi
        script_to_use="$CLEANUP_SCRIPT"
        ;;
    2)
        if [ ! -f "$CLEANUP_JS_SCRIPT" ]; then
            echo "❌ Node.js cleanup script not found: $CLEANUP_JS_SCRIPT"
            exit 1
        fi
        # Check if node is available
        if ! command -v node &> /dev/null; then
            echo "❌ Node.js not found. Please install Node.js or choose the bash script."
            exit 1
        fi
        script_to_use="node $CLEANUP_JS_SCRIPT"
        ;;
    *)
        echo "Invalid choice. Using bash script as default."
        script_to_use="$CLEANUP_SCRIPT"
        ;;
esac

# Setup the cron job
setup_cron "$schedule" "$script_to_use"

echo ""
echo "📋 Current cron jobs:"
crontab -l

echo ""
echo "🔧 To manually run the cleanup script:"
echo "   Bash version: $CLEANUP_SCRIPT"
echo "   Node.js version: node $CLEANUP_JS_SCRIPT"
echo ""
echo "🔍 To view cleanup logs:"
echo "   tail -f $CRON_LOG"
echo ""
echo "⚠️  Note: Make sure the environment variables are properly set for the cron job"
echo "   You may need to add environment variables to the cron job or use a wrapper script"
