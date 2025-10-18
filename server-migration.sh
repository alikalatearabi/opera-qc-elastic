#!/bin/bash

# Server Migration Script: Move Transcription Services to Internal Docker Network
# Run this script on your production server (31.184.134.153)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

echo "🚀 Server Transcription Services Migration"
echo "========================================="
echo "Server: $(hostname)"
echo "Date: $(date)"
echo ""

# Check if we're on the right server
SERVER_IP=$(hostname -I | awk '{print $1}' || echo "unknown")
log "Current server IP: $SERVER_IP"
echo ""

# Step 0: Backup current setup
log "Step 0: Creating backup..."
BACKUP_DIR="/tmp/transcription-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current docker-compose.yml if it exists
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml.backup"
    log_success "Backed up docker-compose.yml to $BACKUP_DIR"
fi

# Step 1: Stop current transcription services (if running separately)
log "Step 1: Stopping existing separate transcription services..."
if [ -d "~/Desktop/tipax" ]; then
    cd ~/Desktop/tipax
    if docker-compose ps | grep -q "tipax\|vllm\|operaasr"; then
        log "Found existing transcription services, stopping them..."
        docker-compose down || log_warning "Failed to stop some services"
        log_success "Existing transcription services stopped"
    else
        log "No separate transcription services found running"
    fi
fi

# Return to main app directory
cd /home/ali/Documents/work-projects/Gashtasb/Opera-qc-back-elastic || {
    log_error "Main application directory not found!"
    exit 1
}

# Step 2: Show current running containers
log "Step 2: Current running containers..."
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Step 3: Build and deploy updated services
log "Step 3: Building updated application..."
if ! docker-compose build app; then
    log_error "Failed to build application"
    exit 1
fi

log "Step 4: Starting all services with transcription integration..."
if ! docker-compose up -d; then
    log_error "Failed to start services"
    echo ""
    echo "Check logs with: docker-compose logs"
    exit 1
fi

# Step 5: Wait for services to initialize
log "Step 5: Waiting for services to initialize..."
sleep 45

# Step 6: Health checks
log "Step 6: Performing health checks..."
echo ""

# Check main app
log "Checking main application..."
APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/health" 2>/dev/null || echo "000")
if [ "$APP_STATUS" = "200" ]; then
    log_success "✅ Main app is running"
else
    log_warning "⚠️ Main app health check: HTTP $APP_STATUS (might still be starting)"
fi

# Check transcription API
log "Checking transcription API..."
TRANS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8003/docs" 2>/dev/null || echo "000")
if [ "$TRANS_STATUS" = "200" ]; then
    log_success "✅ Transcription API is running"
else
    log_warning "⚠️ Transcription API health check: HTTP $TRANS_STATUS (might still be starting)"
fi

# Check Redis
log "Checking Redis..."
REDIS_STATUS=$(docker exec opera-qc-redis redis-cli ping 2>/dev/null || echo "ERROR")
if [ "$REDIS_STATUS" = "PONG" ]; then
    log_success "✅ Redis is running"
else
    log_error "❌ Redis health check failed"
fi

# Check MinIO
log "Checking MinIO..."
MINIO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9005/minio/health/live" 2>/dev/null || echo "000")
if [ "$MINIO_STATUS" = "200" ]; then
    log_success "✅ MinIO is running"
else
    log_error "❌ MinIO health check failed: HTTP $MINIO_STATUS"
fi

# Check Elasticsearch
log "Checking Elasticsearch..."
ES_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/_cluster/health" 2>/dev/null || echo "000")
if [ "$ES_STATUS" = "200" ]; then
    log_success "✅ Elasticsearch is running"
else
    log_warning "⚠️ Elasticsearch health check: HTTP $ES_STATUS"
fi

echo ""
log "Step 7: Testing internal network connectivity..."

# Wait a bit more for transcription service to be ready
sleep 15

# Test internal connectivity from app container
log "Testing internal Docker network connectivity..."
INTERNAL_TEST=$(docker exec app sh -c "wget -q --spider http://opera-tipax:8003/docs" 2>/dev/null && echo "SUCCESS" || echo "FAILED")
if [ "$INTERNAL_TEST" = "SUCCESS" ]; then
    log_success "✅ Internal Docker network connectivity working"
else
    log_warning "⚠️ Internal network test failed - checking service status..."
    
    # Check if transcription container is running
    if docker ps | grep -q "opera_tipax"; then
        log "Transcription container is running, checking logs..."
        docker logs opera_tipax --tail 10
    else
        log_error "Transcription container not found!"
    fi
fi

echo ""
echo "📊 SERVICE STATUS SUMMARY"
echo "========================"
echo "Main App (8081): $([ "$APP_STATUS" = "200" ] && echo "✅ Running" || echo "⚠️ HTTP $APP_STATUS")"
echo "Transcription (8003): $([ "$TRANS_STATUS" = "200" ] && echo "✅ Running" || echo "⚠️ HTTP $TRANS_STATUS")"
echo "Redis (6379): $([ "$REDIS_STATUS" = "PONG" ] && echo "✅ Running" || echo "❌ Failed")"
echo "MinIO (9005): $([ "$MINIO_STATUS" = "200" ] && echo "✅ Running" || echo "❌ Failed")"
echo "Elasticsearch (9200): $([ "$ES_STATUS" = "200" ] && echo "✅ Running" || echo "⚠️ HTTP $ES_STATUS")"
echo "Internal Network: $([ "$INTERNAL_TEST" = "SUCCESS" ] && echo "✅ Working" || echo "⚠️ Check needed")"

echo ""
echo "🔧 MONITORING COMMANDS"
echo "====================="
echo "# View all containers:"
echo "docker-compose ps"
echo ""
echo "# Check application logs:"
echo "docker-compose logs -f app"
echo ""
echo "# Check transcription service logs:"
echo "docker-compose logs -f opera-tipax"
echo ""
echo "# Monitor Redis queue:"
echo "docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:waiting"
echo ""
echo "# Test transcription endpoint:"
echo "curl -X GET http://31.184.134.153:8003/docs"
echo ""

echo "🌐 EXTERNAL ACCESS URLs"
echo "======================"
echo "Main Application: http://31.184.134.153:8081"
echo "Transcription API: http://31.184.134.153:8003/docs"
echo "MinIO Console: http://31.184.134.153:9006"
echo "Kibana: http://31.184.134.153:5601"
echo "Swagger UI: http://31.184.134.153:8084"
echo ""

if [ "$APP_STATUS" = "200" ] && [ "$TRANS_STATUS" = "200" ] && [ "$INTERNAL_TEST" = "SUCCESS" ]; then
    log_success "🎉 Migration completed successfully!"
    echo ""
    echo "✅ All services are now using internal Docker networking."
    echo "✅ Transcription calls will use internal hostname 'opera-tipax:8003'"
    echo "✅ No more external network calls for transcription services."
else
    log_warning "⚠️ Migration completed but some services may need attention."
    echo ""
    echo "📋 TROUBLESHOOTING:"
    echo "- If services are still starting, wait 2-3 minutes and rerun health checks"
    echo "- Check individual service logs: docker-compose logs [service-name]"
    echo "- Restart specific service: docker-compose restart [service-name]"
fi

echo ""
echo "💾 Backup location: $BACKUP_DIR"