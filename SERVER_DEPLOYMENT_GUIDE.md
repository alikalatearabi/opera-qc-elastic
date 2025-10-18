# 🚀 Server Deployment Guide: Internal Docker Network for Transcription Services

## Overview
This guide helps you migrate your transcription services from external network calls to internal Docker networking on your production server (31.184.134.153).

## 🎯 What This Migration Does

### Before (Current Setup)
```
┌─────────────┐    External Network    ┌──────────────────┐
│     App     │ ──── 31.184.134.153:8003 ──→ │ Transcription API │
│ Container   │                        │   (Separate)     │
└─────────────┘                        └──────────────────┘
```

### After (New Setup)
```
┌─────────────┐    Docker Network     ┌──────────────────┐
│     App     │ ──── opera-tipax:8003 ──→ │ Transcription API │
│ Container   │      (Internal)       │   (Same Network) │
└─────────────┘                       └──────────────────┘
```

## 📋 Prerequisites

1. SSH access to your production server (31.184.134.153)
2. Your current transcription services running separately
3. Updated code from this repository

## 🚀 Step-by-Step Migration

### 1. Upload Files to Server

First, upload your updated files to the server:

```bash
# From your local machine
scp -r /home/ali/Documents/work-projects/Gashtasb/Opera-qc-back-elastic/ user@31.184.134.153:/home/user/
```

### 2. SSH to Server

```bash
ssh user@31.184.134.153
cd /path/to/Opera-qc-back-elastic
```

### 3. Run Migration Script

```bash
chmod +x server-migration.sh
./server-migration.sh
```

### 4. Manual Migration Steps (Alternative)

If you prefer to do it manually:

```bash
# Stop existing transcription services
cd ~/Desktop/tipax  # or wherever your transcription docker-compose is
docker-compose down

# Go to main app directory
cd /path/to/Opera-qc-back-elastic

# Build and start all services
docker-compose build app
docker-compose up -d

# Check status
docker-compose ps
```

## 🔧 Configuration Changes Made

### 1. Docker Compose (docker-compose.yml)
Added transcription services to the main compose file:

```yaml
services:
  # ... existing services ...

  # Transcription Services
  vllm-api:
    image: vllm:v1.0
    container_name: vllm-api
    # ... GPU configuration ...
    networks:
      - app-network

  operaasr-general:
    image: faster_asr:v1.3
    container_name: operaasr_general
    # ... GPU configuration ...
    networks:
      - app-network

  opera-tipax:
    image: opera_tipax:v2.3
    container_name: opera_tipax
    ports:
      - "8003:8003"
    networks:
      - app-network
```

### 2. Environment Configuration
Added transcription API URL variable:

```env
TRANSCRIPTION_API_URL=http://opera-tipax:8003
```

### 3. Application Code
Updated API calls to use internal hostname:

```typescript
// Before: http://31.184.134.153:8003/transcription/
// After:  http://opera-tipax:8003/transcription/
const response = await axios.post(`${env.TRANSCRIPTION_API_URL}/transcription/`, form);
```

## 🔍 Verification

After migration, verify everything is working:

### 1. Check All Containers
```bash
docker-compose ps
```

Expected output:
```
     Name                   Command               State           Ports
-------------------------------------------------------------------------
app                     docker-entrypoint.sh npm ...   Up      5555/tcp, 0.0.0.0:8081->8081/tcp
elasticsearch           /bin/tini -- /usr/local/b...   Up      0.0.0.0:9200->9200/tcp, 0.0.0.0:9300->9300/tcp
kibana                  /bin/tini -- /usr/local/b...   Up      0.0.0.0:5601->5601/tcp
minio                   /usr/bin/docker-entrypoint...   Up      0.0.0.0:9005->9000/tcp, 0.0.0.0:9006->9006/tcp
opera-qc-redis          docker-entrypoint.sh redis...   Up      0.0.0.0:6379->6379/tcp
opera_tipax             uvicorn main:app --host 0....   Up      0.0.0.0:8003->8003/tcp
operaasr_general        uvicorn main:app --host 0....   Up      0.0.0.0:8001->8001/tcp
vllm-api                bash -c python3 -m vllm.e...   Up      0.0.0.0:8000->8000/tcp
```

### 2. Test Internal Connectivity
```bash
# From inside the app container
docker exec app wget -q --spider http://opera-tipax:8003/docs
echo $?  # Should return 0 if successful
```

### 3. Test External Access
```bash
# From your local machine or browser
curl http://31.184.134.153:8003/docs
curl http://31.184.134.153:8081/health
```

### 4. Monitor Queue Processing
```bash
# Check if transcription jobs are being processed
docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:waiting
docker exec opera-qc-redis redis-cli LLEN bull:transcription-processing:failed
```

## 📊 Benefits of This Migration

### ✅ Performance Improvements
- **Faster communication**: Internal Docker network vs external network calls
- **Lower latency**: No network routing overhead
- **Better reliability**: No dependency on external network stability

### ✅ Security Improvements
- **Network isolation**: Services communicate internally
- **Reduced attack surface**: Less exposure to external network
- **Better container security**: All services in same trusted network

### ✅ Operational Improvements
- **Simplified deployment**: Single docker-compose file
- **Better monitoring**: All services in one place
- **Easier scaling**: Services can reference each other by name

## 🚨 Troubleshooting

### Issue: Transcription Service Not Starting
```bash
# Check logs
docker-compose logs opera-tipax

# Common issues:
# 1. GPU allocation conflicts
# 2. Port conflicts
# 3. Image not found
```

### Issue: Internal Network Not Working
```bash
# Check network configuration
docker network ls
docker network inspect opera-qc-back-elastic_app-network

# Test connectivity
docker exec app ping opera-tipax
```

### Issue: GPU Memory Issues
```bash
# Check GPU usage
nvidia-smi

# May need to adjust GPU memory allocation in docker-compose.yml
```

## 🔄 Rollback Plan

If you need to rollback:

```bash
# Stop new setup
docker-compose down

# Start old transcription services
cd ~/Desktop/tipax
docker-compose up -d

# Update environment variables back to external URLs
# TRANSCRIPTION_API_URL=http://31.184.134.153:8003
```

## 📞 Support

If you encounter issues:
1. Check the service logs: `docker-compose logs [service-name]`
2. Verify network connectivity between containers
3. Ensure GPU resources are properly allocated
4. Check port conflicts with existing services