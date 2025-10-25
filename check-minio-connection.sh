#!/bin/bash

# MinIO Connection Checker
# Checks if MinIO is accessible on production server 31.184.134.153
# Usage: ./check-minio-connection.sh

set -e

# MinIO configuration for production server
SERVER_HOST="31.184.134.153"
MINIO_PORTS=(9005 9000 9001)  # Common MinIO ports
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if port is open
check_port() {
    local host="$1"
    local port="$2"
    
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to test MinIO endpoint
test_minio_endpoint() {
    local endpoint="$1"
    
    log "Testing MinIO endpoint: $endpoint"
    
    # Try to connect with curl
    if curl -s --connect-timeout 5 "$endpoint" &>/dev/null; then
        log_success "Endpoint $endpoint is accessible"
        return 0
    else
        log_warning "Endpoint $endpoint is not accessible"
        return 1
    fi
}

# Function to check MinIO with mc client
test_minio_with_mc() {
    local endpoint="$1"
    
    # Install mc if not available
    MC_CMD=""
    if command -v mc &> /dev/null; then
        MC_CMD="mc"
    else
        log "Installing MinIO client for testing..."
        INSTALL_DIR="/tmp/minio-test-$$"
        mkdir -p "$INSTALL_DIR"
        
        if command -v wget &> /dev/null; then
            wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O "$INSTALL_DIR/mc"
        elif command -v curl &> /dev/null; then
            curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$INSTALL_DIR/mc"
        else
            log_error "Cannot install MinIO client"
            return 1
        fi
        
        chmod +x "$INSTALL_DIR/mc"
        MC_CMD="$INSTALL_DIR/mc"
    fi
    
    # Test connection
    local alias_name="test_minio"
    if $MC_CMD alias set "$alias_name" "$endpoint" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null; then
        if $MC_CMD ls "$alias_name" &>/dev/null; then
            log_success "MinIO connection successful with mc client"
            
            # Show buckets
            log "Available buckets:"
            $MC_CMD ls "$alias_name" | while read -r line; do
                if [ -n "$line" ]; then
                    echo "  - $line"
                fi
            done
            
            # Cleanup
            if [[ "$MC_CMD" == "/tmp/minio-test-"* ]]; then
                rm -rf "$(dirname "$MC_CMD")"
            fi
            
            return 0
        else
            log_error "MinIO connection failed with mc client"
        fi
    else
        log_error "Failed to configure MinIO client"
    fi
    
    # Cleanup
    if [[ "$MC_CMD" == "/tmp/minio-test-"* ]]; then
        rm -rf "$(dirname "$MC_CMD")"
    fi
    
    return 1
}

# Main execution
main() {
    log "Checking MinIO connection to production server $SERVER_HOST"
    echo ""
    
    # Check basic connectivity
    log "Checking basic connectivity to server..."
    if ping -c 1 -W 5 "$SERVER_HOST" &>/dev/null; then
        log_success "Server $SERVER_HOST is reachable"
    else
        log_error "Server $SERVER_HOST is not reachable"
        exit 1
    fi
    
    echo ""
    
    # Check MinIO ports
    log "Checking MinIO ports..."
    local accessible_ports=()
    
    for port in "${MINIO_PORTS[@]}"; do
        if check_port "$SERVER_HOST" "$port"; then
            log_success "Port $port is open"
            accessible_ports+=("$port")
        else
            log_warning "Port $port is closed or filtered"
        fi
    done
    
    if [ ${#accessible_ports[@]} -eq 0 ]; then
        log_error "No MinIO ports are accessible"
        log "Please check:"
        log "  1. MinIO container is running on the server"
        log "  2. Port mapping is correct in docker-compose.yml"
        log "  3. Firewall allows connections to MinIO ports"
        exit 1
    fi
    
    echo ""
    
    # Test MinIO endpoints
    log "Testing MinIO endpoints..."
    local working_endpoints=()
    
    for port in "${accessible_ports[@]}"; do
        local endpoint="http://$SERVER_HOST:$port"
        if test_minio_endpoint "$endpoint"; then
            working_endpoints+=("$endpoint")
        fi
    done
    
    if [ ${#working_endpoints[@]} -eq 0 ]; then
        log_error "No MinIO endpoints are responding"
        exit 1
    fi
    
    echo ""
    
    # Test with MinIO client
    log "Testing MinIO client connection..."
    local working_mc_endpoint=""
    
    for endpoint in "${working_endpoints[@]}"; do
        if test_minio_with_mc "$endpoint"; then
            working_mc_endpoint="$endpoint"
            break
        fi
    done
    
    echo ""
    
    # Summary
    log "=== CONNECTION SUMMARY ==="
    log "Server: $SERVER_HOST"
    log "Accessible ports: ${accessible_ports[*]}"
    log "Working endpoints: ${working_endpoints[*]}"
    
    if [ -n "$working_mc_endpoint" ]; then
        log_success "MinIO is fully accessible at: $working_mc_endpoint"
        log ""
        log "You can use this endpoint in your cleanup script:"
        log "  MINIO_ENDPOINT=\"$working_mc_endpoint\""
    else
        log_warning "MinIO endpoints are accessible but client connection failed"
        log "This might be due to:"
        log "  1. Incorrect credentials"
        log "  2. MinIO not fully initialized"
        log "  3. Network issues"
    fi
    
    echo ""
    log "=== RECOMMENDED CLEANUP COMMAND ==="
    if [ -n "$working_mc_endpoint" ]; then
        echo "To run cleanup with the working endpoint:"
        echo "  sed -i 's|MINIO_ENDPOINT=.*|MINIO_ENDPOINT=\"$working_mc_endpoint\"|' cleanup-minio-direct.sh"
        echo "  ./cleanup-minio-direct.sh --dry-run"
    else
        echo "Fix the MinIO connection issues first, then run:"
        echo "  ./cleanup-minio-direct.sh --dry-run"
    fi
}

# Run main function
main "$@"
