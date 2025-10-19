# Audio Files Cleanup Scripts

This directory contains scripts to automatically remove old audio files from both local filesystem and MinIO storage to free up disk space.

## Available Scripts

### 1. Node.js Version (`cleanup-old-audio-files.js`)
**Recommended for integration with the existing Node.js application**

- Uses the same environment variables as the main application
- Better error handling and logging
- Calculates and reports freed disk space
- Supports both local filesystem and MinIO cleanup

### 2. Bash Version (`cleanup-old-audio-files.sh`)
**Recommended for system-level cron jobs**

- Standalone script with minimal dependencies
- Downloads MinIO client automatically if needed
- Works well in containerized environments
- Colored output for better readability

## Usage

### Quick Start

```bash
# Test what would be deleted (dry run)
npm run cleanup-audio-dry

# Actually delete files older than 2 days
npm run cleanup-audio

# Custom number of days (e.g., 7 days)
node cleanup-old-audio-files.js --days 7

# Bash version with custom days
./cleanup-old-audio-files.sh --days 7 --dry-run
```

### Command Line Options

Both scripts support the following options:

- `--dry-run`: Show what would be deleted without actually deleting
- `--days N`: Number of days old (default: 2)
- `--help`: Show help message

### Environment Variables

The Node.js script uses these environment variables:

```bash
AUDIO_DIR=/app/conversations              # Local audio directory
MINIO_ENDPOINT_UTL=http://localhost:9005  # MinIO endpoint
MINIO_ACCESS_KEY=minioaccesskey           # MinIO access key
MINIO_SECRET_KEY=miniosecretkey           # MinIO secret key
MINIO_BUCKET_NAME=audio-files             # MinIO bucket name
```

## Automated Cleanup with Cron

### Setup Automated Cleanup

Run the setup script to configure automatic cleanup:

```bash
./setup-audio-cleanup-cron.sh
```

This will guide you through:
1. Choosing a schedule (daily, every 12 hours, etc.)
2. Selecting script type (Bash or Node.js)
3. Setting up the cron job

### Manual Cron Setup

#### Option 1: Daily at 2:00 AM
```bash
# Add to crontab
0 2 * * * cd /path/to/project && ./cleanup-old-audio-files.sh >> /var/log/audio-cleanup.log 2>&1
```

#### Option 2: Every 12 hours
```bash
# Add to crontab  
0 */12 * * * cd /path/to/project && node cleanup-old-audio-files.js >> /var/log/audio-cleanup.log 2>&1
```

#### Docker Environment
For Docker deployments, add the cron job inside the container or use a separate cron container:

```dockerfile
# Add to Dockerfile
RUN echo "0 2 * * * cd /usr/src/app && node cleanup-old-audio-files.js >> /var/log/audio-cleanup.log 2>&1" | crontab -
```

## What Gets Cleaned Up

### File Types
- `.wav` - Wave audio files
- `.mp3` - MP3 audio files  
- `.m4a` - M4A audio files
- `.flac` - FLAC audio files
- `.aac` - AAC audio files
- `.ogg` - OGG audio files

### Locations
1. **Local Filesystem**: Files in the configured audio directory
2. **MinIO Storage**: Files in the configured MinIO bucket
3. **Empty Directories**: Removes empty directories after cleanup

### Age Calculation
Files are considered "old" based on their modification time (mtime):
- Default: 2 days old
- Configurable via `--days` parameter
- Uses the file's last modified date, not creation date

## Examples

### Basic Usage
```bash
# See what would be deleted
npm run cleanup-audio-dry

# Delete files older than 2 days (default)
npm run cleanup-audio

# Delete files older than 7 days
node cleanup-old-audio-files.js --days 7
```

### Advanced Usage
```bash
# Custom environment for testing
AUDIO_DIR=./test-audio MINIO_BUCKET_NAME=test-bucket npm run cleanup-audio-dry

# Bash version with custom settings
MINIO_ENDPOINT=http://192.168.1.100:9000 ./cleanup-old-audio-files.sh --days 1 --dry-run
```

### Docker Usage
```bash
# Run cleanup inside Docker container
docker exec -it app node cleanup-old-audio-files.js --dry-run

# Run with custom environment
docker exec -e AUDIO_DIR=/custom/path -it app npm run cleanup-audio-dry
```

## Monitoring and Logs

### View Cleanup Logs
```bash
# View recent cleanup activity
tail -f /var/log/audio-cleanup.log

# View logs with timestamps
tail -f /var/log/audio-cleanup.log | while read line; do echo "$(date): $line"; done
```

### Check Disk Space
```bash
# Check disk usage before/after cleanup
df -h

# Check specific directory usage
du -sh /app/conversations
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x cleanup-old-audio-files.sh
   chmod +x setup-audio-cleanup-cron.sh
   ```

2. **MinIO Connection Failed**
   - Check MinIO endpoint URL
   - Verify access credentials
   - Ensure MinIO service is running

3. **Node.js Module Errors**
   ```bash
   npm install  # Reinstall dependencies
   ```

4. **Cron Job Not Running**
   ```bash
   # Check cron service
   sudo systemctl status cron
   
   # Check cron logs
   grep CRON /var/log/syslog
   
   # List current cron jobs
   crontab -l
   ```

### Debug Mode

For detailed debugging, run scripts with verbose output:

```bash
# Node.js version
DEBUG=* node cleanup-old-audio-files.js --dry-run

# Bash version with verbose output
bash -x cleanup-old-audio-files.sh --dry-run
```

## Safety Features

- **Dry Run Mode**: Always test with `--dry-run` first
- **File Type Filtering**: Only removes audio files, not other file types
- **Age Verification**: Double-checks file modification times
- **Error Handling**: Continues processing even if individual files fail
- **Logging**: Comprehensive logging of all operations
- **Rollback**: No rollback needed as files are permanently deleted (use dry-run for safety)

## Integration with Application

The cleanup scripts are designed to work alongside the main Opera QC application:

- Uses same environment configuration
- Respects same file paths and storage locations
- Can be called from application code if needed
- Logs are compatible with application logging format

## Performance Considerations

- **Batch Processing**: Processes files in batches to avoid memory issues
- **Concurrent Safety**: Safe to run while application is processing new files
- **Resource Usage**: Minimal CPU and memory footprint
- **Network Efficiency**: Optimized MinIO operations

## Security Considerations

- **File Permissions**: Respects file system permissions
- **Access Control**: Uses configured MinIO credentials
- **Audit Trail**: All operations are logged
- **Safe Defaults**: Conservative default settings (2 days retention)

---

**Note**: Always test cleanup scripts in a development environment before deploying to production. Use `--dry-run` mode to verify what will be deleted before running the actual cleanup.
