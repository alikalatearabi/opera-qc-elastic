# Scripts for Production Server

## Where to Run These Scripts

**All these scripts should be run on your production server at `31.184.134.153`, NOT on your local machine.**

## Files Already on Server

All these files are in: `~/opera-qc-elastic/` on the server

## How to Run

SSH into your server first:
```bash
ssh rahpoo@31.184.134.153
cd ~/opera-qc-elastic
git pull  # Get latest scripts
```

## Available Scripts

### 1. Check for Duplicates
```bash
./find-dups-final.sh
```
Shows duplicate filenames (if any exist)

### 2. Check MinIO Volume (for cleanup)
```bash
sudo ./inspect-minio-volume.sh   # Just look at what's there
sudo ./cleanup-minio-volume.sh 2 # Delete files older than 2 days
```

### 3. Check API Call Volume
```bash
./check-api-volume.sh
```
Shows how many calls the external API is sending

### 4. Check Elasticsearch Stats
```bash
./check-es-duplicates.sh
./list-files-by-date.sh
```

## Important Notes

- Scripts connect to Elasticsearch at `localhost:9200` because they run ON the server
- MinIO cleanup scripts require `sudo` because they access Docker volumes
- All git changes should be pushed first, then pulled on server

## Quick Test Commands

Check if Elasticsearch has data:
```bash
curl -s "localhost:9200/_cat/indices"
curl -s "localhost:9200/opera-qc-session-events/_count"
```

Check recent API calls:
```bash
docker logs --tail 100 app | grep "\[API_CALL"
```
