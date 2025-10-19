#!/bin/bash

# Migration Script: Move Transcription Services to Internal Docker Network
# This script helps you migrate from external transcription API calls to internal Docker networking

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

echo "🚀 Transcription Services Migration Script"
echo "=========================================="
echo ""

# Step 1: Stop current transcription services
log "Step 1: Stopping existing transcription services..."
cd ~/Desktop/tipax
if docker-compose ps | grep -q "tipax"; then
    log "Stopping transcription services in ~/Desktop/tipax..."
    docker-compose down
    log_success "Transcription services stopped"
else
    log_warning "No running transcription services found in ~/Desktop/tipax"
fi

# Step 2: Build and start integrated services
log "Step 2: Starting integrated services..."
cd /home/ali/Documents/work-projects/Gashtasb/Opera-qc-back-elastic

# Build the app if needed
log "Building application..."
if ! docker-compose build app; then
    log_error "Failed to build application"
    exit 1
fi

# Start all services including transcription
log "Starting all services (including transcription)..."
if ! docker-compose up -d; then
    log_error "Failed to start services"
    exit 1
fi

# Step 3: Wait for services to be ready
log "Step 3: Waiting for services to be ready..."
sleep 30

# Step 4: Health checks
log "Step 4: Performing health checks..."
echo ""

# Check app
APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/health" 2>/dev/null || echo "000")
if [ "$APP_STATUS" = "200" ]; then
    log_success "✅ Main app is running (http://localhost:8081)"
else
    log_error "❌ Main app health check failed (HTTP: $APP_STATUS)"
fi

# Check transcription API
TRANS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8003/docs" 2>/dev/null || echo "000")
if [ "$TRANS_STATUS" = "200" ]; then
    log_success "✅ Transcription API is running (http://localhost:8003)"
else
    log_error "❌ Transcription API health check failed (HTTP: $TRANS_STATUS)"
fi

# Check Redis
REDIS_STATUS=$(docker exec opera-qc-redis redis-cli ping 2>/dev/null || echo "ERROR")
if [ "$REDIS_STATUS" = "PONG" ]; then
    log_success "✅ Redis is running"
else
    log_error "❌ Redis health check failed"
fi

# Check MinIO
MINIO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9005/minio/health/live" 2>/dev/null || echo "000")
if [ "$MINIO_STATUS" = "200" ]; then
    log_success "✅ MinIO is running (http://localhost:9005)"
else
    log_error "❌ MinIO health check failed (HTTP: $MINIO_STATUS)"
fi

echo ""
log "Step 5: Verifying internal network connectivity..."

# Test internal network connectivity from app container
log "Testing transcription API connectivity from app container..."
INTERNAL_TEST=$(docker exec app wget -q --spider http://opera-tipax:8003/docs 2>/dev/null && echo "SUCCESS" || echo "FAILED")
if [ "$INTERNAL_TEST" = "SUCCESS" ]; then
    log_success "✅ Internal Docker network connectivity working"
else
    log_error "❌ Internal Docker network connectivity failed"
    echo "   This might indicate the transcription service is not ready yet."
    echo "   Check with: docker-compose logs opera-tipax"
fi

echo ""
echo "📋 MIGRATION STATUS SUMMARY"
echo "=========================="
echo "Main App: $([ "$APP_STATUS" = "200" ] && echo "✅ Running" || echo "❌ Failed")"
echo "Transcription API: $([ "$TRANS_STATUS" = "200" ] && echo "✅ Running" || echo "❌ Failed")"
echo "Redis: $([ "$REDIS_STATUS" = "PONG" ] && echo "✅ Running" || echo "❌ Failed")"
echo "MinIO: $([ "$MINIO_STATUS" = "200" ] && echo "✅ Running" || echo "❌ Failed")"
echo "Internal Network: $([ "$INTERNAL_TEST" = "SUCCESS" ] && echo "✅ Working" || echo "❌ Failed")"

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
echo "1. Monitor logs: docker-compose logs -f app"
echo "2. Test transcription: Check your application for successful transcription jobs"
echo "3. Monitor queue: docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:waiting"
echo "4. Access services:"
echo "   - Main App: http://localhost:8081"
echo "   - Transcription API: http://localhost:8003/docs"
echo "   - MinIO Console: http://localhost:9006"
echo "   - Kibana: http://localhost:5601"
echo ""

if [ "$APP_STATUS" = "200" ] && [ "$TRANS_STATUS" = "200" ] && [ "$INTERNAL_TEST" = "SUCCESS" ]; then
    log_success "🎉 Migration completed successfully!"
    echo "Your transcription services are now using internal Docker networking."
else
    log_warning "⚠️ Migration completed with some issues."
    echo "Please check the logs and fix any issues before proceeding."
fi