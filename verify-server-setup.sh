#!/bin/bash

# Quick Server Verification Script
# Run this on your server after deployment to verify internal networking

set -e

echo "🔍 Quick Server Verification - Internal Docker Network"
echo "====================================================="
echo "Server: $(hostname)"
echo "Time: $(date)"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# 1. Check if containers are running
echo "1. Checking Container Status:"
echo "=============================="
required_containers=("app" "opera_tipax" "opera-qc-redis" "minio" "elasticsearch")
all_running=true

for container in "${required_containers[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        success "$container is running"
    else
        error "$container is NOT running"
        all_running=false
    fi
done

echo ""

# 2. Check internal network connectivity
echo "2. Testing Internal Network Connectivity:"
echo "========================================"

# Test app -> transcription service
if docker exec app sh -c "wget -q --timeout=5 --spider http://opera-tipax:8003/docs" 2>/dev/null; then
    success "App can reach transcription service internally (opera-tipax:8003)"
else
    error "App cannot reach transcription service internally"
fi

# Test app -> redis
if docker exec app sh -c "nc -z redis 6379" 2>/dev/null; then
    success "App can reach Redis internally (redis:6379)"
else
    error "App cannot reach Redis internally"
fi

# Test app -> minio
if docker exec app sh -c "nc -z minio 9000" 2>/dev/null; then
    success "App can reach MinIO internally (minio:9000)"
else
    error "App cannot reach MinIO internally"
fi

echo ""

# 3. Check external accessibility
echo "3. Testing External Access:"
echo "=========================="

services=(
    "8081:Main App"
    "8003:Transcription API"
    "9005:MinIO API"
    "9006:MinIO Console"
    "5601:Kibana"
)

for service in "${services[@]}"; do
    port="${service%%:*}"
    name="${service#*:}"
    
    if curl -s --max-time 3 "http://localhost:${port}" > /dev/null 2>&1; then
        success "$name accessible on port $port"
    elif curl -s --max-time 3 "http://localhost:${port}/health" > /dev/null 2>&1; then
        success "$name accessible on port $port (health endpoint)"
    elif curl -s --max-time 3 "http://localhost:${port}/docs" > /dev/null 2>&1; then
        success "$name accessible on port $port (docs endpoint)"
    else
        warning "$name not responding on port $port (may still be starting)"
    fi
done

echo ""

# 4. Check environment variables
echo "4. Verifying Environment Configuration:"
echo "======================================"

# Check if TRANSCRIPTION_API_URL is set correctly
transcription_url=$(docker exec app printenv TRANSCRIPTION_API_URL 2>/dev/null || echo "not_set")
if [ "$transcription_url" = "http://opera-tipax:8003" ]; then
    success "TRANSCRIPTION_API_URL correctly set to internal URL"
else
    error "TRANSCRIPTION_API_URL is '$transcription_url' (should be 'http://opera-tipax:8003')"
fi

# Check Redis host
redis_host=$(docker exec app printenv REDIS_HOST 2>/dev/null || echo "not_set")
if [ "$redis_host" = "redis" ]; then
    success "REDIS_HOST correctly set to internal hostname"
else
    error "REDIS_HOST is '$redis_host' (should be 'redis')"
fi

echo ""

# 5. Test a sample transcription API call (if possible)
echo "5. Testing Transcription API Integration:"
echo "======================================="

# Check if transcription endpoint responds
if curl -s --max-time 5 "http://localhost:8003/docs" > /dev/null 2>&1; then
    success "Transcription API is responding externally"
    
    # Test internal call from app container
    if docker exec app sh -c "curl -s --max-time 5 http://opera-tipax:8003/docs" > /dev/null 2>&1; then
        success "Transcription API reachable internally from app container"
    else
        error "Transcription API not reachable internally from app container"
    fi
else
    warning "Transcription API not responding (may still be loading model)"
fi

echo ""

# 6. Check Redis queue
echo "6. Checking Redis Queue Status:"
echo "=============================="

waiting_jobs=$(docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:waiting 2>/dev/null || echo "ERROR")
failed_jobs=$(docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:failed 2>/dev/null || echo "ERROR")
completed_jobs=$(docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:completed 2>/dev/null || echo "ERROR")

if [ "$waiting_jobs" != "ERROR" ]; then
    echo "Waiting jobs: $waiting_jobs"
    echo "Failed jobs: $failed_jobs"
    echo "Completed jobs: $completed_jobs"
    success "Redis queue is accessible"
else
    error "Cannot access Redis queue"
fi

echo ""

# Summary
echo "📊 VERIFICATION SUMMARY"
echo "======================"

if $all_running; then
    success "All required containers are running"
else
    error "Some containers are missing - check with: docker-compose ps"
fi

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
echo "1. If all checks passed: Your migration is successful! 🎉"
echo "2. If some checks failed: "
echo "   - Wait a few minutes for services to fully start"
echo "   - Check logs: docker-compose logs -f [service-name]"
echo "   - Restart problematic service: docker-compose restart [service-name]"
echo ""
echo "3. Monitor your application:"
echo "   - Watch logs: docker-compose logs -f app"
echo "   - Check queue: watch 'docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:waiting'"
echo "   - Test transcription: Submit a test session through your app"
echo ""
echo "4. External URLs:"
echo "   - App: http://31.184.134.153:8081"
echo "   - Transcription API: http://31.184.134.153:8003/docs"
echo "   - MinIO Console: http://31.184.134.153:9006"
echo "   - Kibana: http://31.184.134.153:5601"