#!/bin/bash

# Redis Jobs Inspector for Opera QC Backend
# Shell script version - no Node.js dependencies required
#
# Usage:
#   ./show-redis-jobs.sh [redis-host] [redis-port]
#
# Default: localhost 6379

# Configuration
REDIS_HOST=${1:-localhost}
REDIS_PORT=${2:-6379}
REDIS_URL="redis://$REDIS_HOST:$REDIS_PORT"

# Queue names from the application
QUEUES=("sequential-processing" "transcription-processing" "llm-processing")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

print_subheader() {
    echo -e "${CYAN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${MAGENTA}ℹ️  $1${NC}"
}

# Function to check if redis-cli is available
check_redis_cli() {
    if ! command -v redis-cli &> /dev/null; then
        print_error "redis-cli is not installed or not in PATH"
        echo "Please install Redis CLI tools:"
        echo "  Ubuntu/Debian: sudo apt-get install redis-tools"
        echo "  CentOS/RHEL: sudo yum install redis"
        echo "  macOS: brew install redis"
        exit 1
    fi
}

# Function to test Redis connection
test_redis_connection() {
    print_info "Testing Redis connection to $REDIS_HOST:$REDIS_PORT..."

    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping &> /dev/null; then
        print_success "Connected to Redis"
        return 0
    else
        print_error "Failed to connect to Redis at $REDIS_HOST:$REDIS_PORT"
        echo "Make sure Redis is running and accessible."
        echo "For local development: redis-server"
        echo "For Docker: docker-compose up -d redis"
        exit 1
    fi
}

# Function to get Redis info
get_redis_info() {
    print_subheader "📊 Redis Server Info:"

    # Get basic Redis info
    local redis_info
    redis_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" info server 2>/dev/null)

    if [ $? -eq 0 ]; then
        local redis_version
        redis_version=$(echo "$redis_info" | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
        local uptime_days
        uptime_days=$(echo "$redis_info" | grep "uptime_in_days:" | cut -d: -f2 | tr -d '\r')
        local connected_clients
        connected_clients=$(echo "$redis_info" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
        local used_memory_human
        used_memory_human=$(echo "$redis_info" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')

        echo "   Version: $redis_version"
        echo "   Uptime: $uptime_days days"
        echo "   Connected Clients: $connected_clients"
        echo "   Used Memory: $used_memory_human"
    else
        print_warning "Could not retrieve Redis server info"
    fi
}

# Function to get queue length
get_queue_length() {
    local queue_name=$1
    local queue_type=$2

    local length
    length=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LLEN "bull:$queue_name:$queue_type" 2>/dev/null)

    # Handle errors
    if [ $? -ne 0 ] || [ -z "$length" ]; then
        echo "0"
    else
        echo "$length"
    fi
}

# Function to get job details
get_job_details() {
    local queue_name=$1
    local queue_type=$2
    local max_jobs=${3:-5}

    local jobs
    jobs=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LRANGE "bull:$queue_name:$queue_type" 0 "$((max_jobs-1))" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$jobs" ]; then
        echo "$jobs"
    else
        echo ""
    fi
}

# Function to parse job data (simplified)
parse_job_data() {
    local job_data=$1

    # Extract basic job info from JSON-like structure
    # This is a simplified parser - real BullMQ jobs have complex JSON structure
    local job_id
    job_id=$(echo "$job_data" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$job_id" ]; then
        echo "unknown-job"
    else
        echo "$job_id"
    fi
}

# Function to inspect a queue
inspect_queue() {
    local queue_name=$1

    print_header "🔍 Inspecting queue: $queue_name"

    # Get queue statistics
    local waiting_count
    local active_count
    local completed_count
    local failed_count
    local delayed_count

    waiting_count=$(get_queue_length "$queue_name" "waiting")
    active_count=$(get_queue_length "$queue_name" "active")
    completed_count=$(get_queue_length "$queue_name" "completed")
    failed_count=$(get_queue_length "$queue_name" "failed")
    delayed_count=$(get_queue_length "$queue_name" "delayed")

    print_subheader "📊 Queue Statistics:"
    echo "   Waiting: $waiting_count"
    echo "   Active: $active_count"
    echo "   Completed: $completed_count"
    echo "   Failed: $failed_count"
    echo "   Delayed: $delayed_count"

    # Show waiting jobs
    if [ "$waiting_count" -gt 0 ]; then
        print_subheader "⏳ Waiting Jobs ($waiting_count):"
        local waiting_jobs
        waiting_jobs=$(get_job_details "$queue_name" "waiting" 5)

        if [ -n "$waiting_jobs" ]; then
            local count=1
            echo "$waiting_jobs" | while read -r job_data; do
                if [ $count -le 5 ]; then
                    local job_id
                    job_id=$(parse_job_data "$job_data")
                    echo "   Job $job_id"
                    ((count++))
                fi
            done
        fi

        if [ "$waiting_count" -gt 5 ]; then
            echo "   ... and $((waiting_count-5)) more"
        fi
    fi

    # Show active jobs
    if [ "$active_count" -gt 0 ]; then
        print_subheader "⚡ Active Jobs ($active_count):"
        local active_jobs
        active_jobs=$(get_job_details "$queue_name" "active")

        if [ -n "$active_jobs" ]; then
            echo "$active_jobs" | while read -r job_data; do
                local job_id
                job_id=$(parse_job_data "$job_data")
                echo "   Job $job_id"
            done
        fi
    fi

    # Show recent completed jobs
    if [ "$completed_count" -gt 0 ]; then
        print_subheader "✅ Recent Completed Jobs ($(min 3 "$completed_count")):"
        local completed_jobs
        completed_jobs=$(get_job_details "$queue_name" "completed" 3)

        if [ -n "$completed_jobs" ]; then
            local count=1
            echo "$completed_jobs" | while read -r job_data; do
                if [ $count -le 3 ]; then
                    local job_id
                    job_id=$(parse_job_data "$job_data")
                    echo "   Job $job_id"
                    ((count++))
                fi
            done
        fi

        if [ "$completed_count" -gt 3 ]; then
            echo "   ... and $((completed_count-3)) more completed jobs"
        fi
    fi

    # Show recent failed jobs
    if [ "$failed_count" -gt 0 ]; then
        print_subheader "❌ Recent Failed Jobs ($(min 3 "$failed_count")):"
        local failed_jobs
        failed_jobs=$(get_job_details "$queue_name" "failed" 3)

        if [ -n "$failed_jobs" ]; then
            local count=1
            echo "$failed_jobs" | while read -r job_data; do
                if [ $count -le 3 ]; then
                    local job_id
                    job_id=$(parse_job_data "$job_data")
                    echo "   Job $job_id"
                    ((count++))
                fi
            done
        fi

        if [ "$failed_count" -gt 3 ]; then
            echo "   ... and $((failed_count-3)) more failed jobs"
        fi
    fi

    # Show delayed jobs
    if [ "$delayed_count" -gt 0 ]; then
        print_subheader "⏰ Delayed Jobs ($delayed_count):"
        local delayed_jobs
        delayed_jobs=$(get_job_details "$queue_name" "delayed" 3)

        if [ -n "$delayed_jobs" ]; then
            local count=1
            echo "$delayed_jobs" | while read -r job_data; do
                if [ $count -le 3 ]; then
                    local job_id
                    job_id=$(parse_job_data "$job_data")
                    echo "   Job $job_id"
                    ((count++))
                fi
            done
        fi

        if [ "$delayed_count" -gt 3 ]; then
            echo "   ... and $((delayed_count-3)) more delayed jobs"
        fi
    fi
}

# Function to get minimum of two numbers
min() {
    if [ "$1" -lt "$2" ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

# Main script
main() {
    echo -e "${GREEN}🚀 Opera QC Backend - Redis Jobs Inspector${NC}"
    echo "==============================================="
    echo ""

    # Check dependencies
    check_redis_cli

    # Test connection
    test_redis_connection

    # Show Redis info
    get_redis_info
    echo ""

    # Inspect each queue
    for queue in "${QUEUES[@]}"; do
        inspect_queue "$queue"
        echo ""
    done

    # Summary
    print_header "🎯 Summary"
    print_success "Inspection completed"
    print_info "Use this script to monitor queue health and job processing"
    print_info "Run periodically to track system performance"
}

# Handle script interruption
trap 'echo -e "\n👋 Shutting down gracefully..."; exit 0' INT

# Run main function
main "$@"</content>
<parameter name="filePath">/home/ali/Documents/work-projects/Gashtasb/Opera-qc-back-elastic/show-redis-jobs.sh