# 🧪 Manual Testing Guide for Elasticsearch Migration

This guide provides step-by-step instructions to manually test your new Elasticsearch-powered Opera QC Backend.

## 🚀 Quick Start Testing

### 1. Start All Services

```bash
# Start all services
docker-compose up -d

# Check if all containers are running
docker-compose ps
```

You should see these services running:
- ✅ `elasticsearch` (port 9200)
- ✅ `kibana` (port 5601)  
- ✅ `redis` (port 6379)
- ✅ `minio` (ports 9005, 9006)
- ✅ `app` (port 8081)

### 2. Run Automated Test Suite

```bash
# Run the comprehensive test script
./test-elasticsearch-migration.sh
```

This will test all components automatically and provide a detailed report.

## 🔍 Manual Testing Steps

### Step 1: Verify Elasticsearch is Running

```bash
# Check cluster health
curl http://localhost:9200/_cluster/health

# Expected response: {"cluster_name":"docker-cluster","status":"green"...}
```

### Step 2: Check Application Health

```bash
# Test application endpoint
curl http://localhost:8081/api/docs

# Should return Swagger UI HTML
```

### Step 3: Test User Registration

```bash
# Register a new user
curl -X POST http://localhost:8081/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123",
    "name": "Test User"
  }'

# Expected response: {"success":true,"message":"Success"...}
```

### Step 4: Test User Login

```bash
# Login to get JWT token
curl -X POST http://localhost:8081/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com", 
    "password": "testpassword123"
  }'

# Expected response with JWT token
# Copy the token from response for next steps
```

### Step 5: Test Session Events API

```bash
# Replace YOUR_JWT_TOKEN with actual token from login
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8081/api/event?page=1&limit=10

# Expected: JSON response with session events data
```

### Step 6: Test Webhook Endpoint (Call Simulation)

```bash
# Simulate incoming call webhook
curl -X POST http://localhost:8081/api/event/sessionReceived \
  -H "Content-Type: application/json" \
  -u "User1:hyQ39c8E873MVv5e22E3T355n3bYV5nf" \
  -d '{
    "type": "incoming",
    "source_channel": "SIP/test",
    "source_number": "09123456789",
    "queue": "test-queue",
    "dest_channel": "SIP/agent",
    "dest_number": "101",
    "date": "2024-01-15 14:30:22",
    "duration": "00:02:45",
    "filename": "test-call-12345",
    "level": 30,
    "time": 1705320622000,
    "pid": 1234,
    "hostname": "test-server",
    "name": "test-session",
    "msg": "Test call session"
  }'

# Expected: {"success":true,"message":"Session event processing started"...}
```

### Step 7: Test Search Functionality

```bash
# Test full-text search
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  "http://localhost:8081/api/event?searchText=test&page=1&limit=5"

# Test filtering
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  "http://localhost:8081/api/event?type=incoming&page=1&limit=5"

# Test multiple filters
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  "http://localhost:8081/api/event?emotion=happy&category=support&page=1&limit=5"
```

### Step 8: Test Analytics Endpoints

```bash
# Get session statistics
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8081/api/event/stats

# Get dashboard data
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8081/api/event/dashboard

# Get categories
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8081/api/event/categories

# Get topics
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8081/api/event/topics
```

## 🔍 Elasticsearch Direct Testing

### Check Indices

```bash
# List all indices
curl http://localhost:9200/_cat/indices?v

# Check specific index
curl http://localhost:9200/opera-qc-session-events/_search?size=5&pretty

# Get index mapping
curl http://localhost:9200/opera-qc-session-events/_mapping?pretty
```

### Test Search Queries

```bash
# Search for specific terms
curl -X POST http://localhost:9200/opera-qc-session-events/_search \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match": {
        "searchText": "test"
      }
    },
    "size": 5
  }' | jq

# Complex search with filters
curl -X POST http://localhost:9200/opera-qc-session-events/_search \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"type": "incoming"}},
          {"exists": {"field": "transcription"}}
        ]
      }
    },
    "size": 5
  }' | jq
```

## 📊 Kibana Testing

1. **Open Kibana**: http://localhost:5601

2. **Explore Data**:
   - Go to "Discover" tab
   - Select your index pattern (opera-qc-*)
   - Explore your session events data

3. **Create Visualizations**:
   - Go to "Visualizations"
   - Create charts for emotions, categories, call volumes
   - Build a dashboard for real-time monitoring

## 🚨 Troubleshooting

### Common Issues and Solutions

1. **Elasticsearch not starting**:
   ```bash
   # Check logs
   docker logs elasticsearch
   
   # Restart with more memory
   docker-compose down
   docker-compose up -d
   ```

2. **Application can't connect to Elasticsearch**:
   ```bash
   # Check network connectivity
   docker exec app curl http://elasticsearch:9200/_cluster/health
   
   # Check environment variables
   docker exec app env | grep ELASTICSEARCH
   ```

3. **No data in Elasticsearch**:
   ```bash
   # Check if indices exist
   curl http://localhost:9200/_cat/indices
   
   # Run migration if needed
   npm run migrate-to-elasticsearch
   ```

4. **Authentication failing**:
   ```bash
   # Check if user exists in Elasticsearch
   curl http://localhost:9200/opera-qc-users/_search?pretty
   
   # Create a user manually via API
   curl -X POST http://localhost:8081/api/auth/register \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@test.com","password":"admin123","name":"Admin"}'
   ```

## 📈 Performance Testing

### Load Testing with Sample Data

```bash
# Create multiple test calls
for i in {1..10}; do
  curl -X POST http://localhost:8081/api/event/sessionReceived \
    -H "Content-Type: application/json" \
    -u "User1:hyQ39c8E873MVv5e22E3T355n3bYV5nf" \
    -d "{
      \"type\": \"incoming\",
      \"source_number\": \"0912345678$i\",
      \"dest_number\": \"10$i\",
      \"filename\": \"test-call-$i\",
      \"date\": \"2024-01-15 14:30:22\",
      \"duration\": \"00:02:45\",
      \"source_channel\": \"SIP/test$i\",
      \"dest_channel\": \"SIP/agent$i\",
      \"queue\": \"queue$i\"
    }"
  sleep 1
done
```

### Monitor Performance

```bash
# Check Elasticsearch performance
curl http://localhost:9200/_nodes/stats/indices/search?pretty

# Monitor application logs
docker logs -f app

# Check Redis queue status
docker exec opera-qc-redis redis-cli info replication
```

## ✅ Success Criteria

Your migration is successful if:

- ✅ All services start without errors
- ✅ User registration and login work
- ✅ Webhook endpoint accepts calls and queues jobs
- ✅ Session events API returns data
- ✅ Search functionality works with filters
- ✅ Analytics endpoints return statistics
- ✅ Kibana shows your data
- ✅ Performance is noticeably improved

## 🎯 Next Steps

After successful testing:

1. **Import existing data**: Run `npm run migrate-to-elasticsearch`
2. **Set up monitoring**: Configure alerts in Kibana
3. **Optimize performance**: Tune Elasticsearch settings
4. **Update frontend**: Modify frontend to use new search capabilities
5. **Deploy to production**: Update production environment

## 📞 Support

If you encounter issues:

1. Check the logs: `docker-compose logs app`
2. Verify Elasticsearch health: `curl http://localhost:9200/_cluster/health`
3. Review the migration guide: `ELASTICSEARCH_MIGRATION.md`
4. Run the automated test script: `./test-elasticsearch-migration.sh`

---

**Happy testing! 🚀**
