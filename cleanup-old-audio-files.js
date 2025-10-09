#!/usr/bin/env node

/**
 * Audio Files Cleanup Script (Node.js Version)
 * Removes audio files older than specified days from both local filesystem and MinIO storage
 * 
 * Usage:
 *   node cleanup-old-audio-files.js [--dry-run] [--days N]
 *   npm run cleanup-audio [-- --dry-run] [-- --days N]
 */

import fs from 'fs';
import path from 'path';
import { promisify } from 'util';
import { S3Client, ListObjectsV2Command, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { config } from 'dotenv';

// Load environment variables
config();

const stat = promisify(fs.stat);
const readdir = promisify(fs.readdir);
const unlink = promisify(fs.unlink);
const rmdir = promisify(fs.rmdir);

// Configuration from environment variables with defaults
const DEFAULT_DAYS_OLD = 2;
const AUDIO_EXTENSIONS = ['.wav', '.mp3', '.m4a', '.flac', '.aac', '.ogg'];
const LOCAL_AUDIO_DIR = process.env.AUDIO_DIR || '/app/conversations';
const MINIO_BUCKET = process.env.MINIO_BUCKET_NAME || 'audio-files';
const MINIO_ENDPOINT = process.env.MINIO_ENDPOINT_UTL || 'http://localhost:9005';
const MINIO_ACCESS_KEY = process.env.MINIO_ACCESS_KEY || 'minioaccesskey';
const MINIO_SECRET_KEY = process.env.MINIO_SECRET_KEY || 'miniosecretkey';

// Parse command line arguments
const args = process.argv.slice(2);
let daysOld = DEFAULT_DAYS_OLD;
let dryRun = false;

for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
        case '--dry-run':
            dryRun = true;
            break;
        case '--days':
            daysOld = parseInt(args[i + 1]);
            if (isNaN(daysOld) || daysOld < 0) {
                console.error('Error: --days must be a positive number');
                process.exit(1);
            }
            i++; // Skip next argument
            break;
        case '--help':
        case '-h':
            console.log('Usage: node cleanup-old-audio-files.js [--dry-run] [--days N]');
            console.log('  --dry-run    Show what would be deleted without actually deleting');
            console.log('  --days N     Number of days old (default: 2)');
            console.log('  --help       Show this help message');
            process.exit(0);
        default:
            console.error(`Unknown option: ${args[i]}`);
            process.exit(1);
    }
}

// Logging functions
const log = (message) => {
    console.log(`[${new Date().toISOString()}] ${message}`);
};

const logSuccess = (message) => {
    console.log(`✅ ${message}`);
};

const logWarning = (message) => {
    console.log(`⚠️  ${message}`);
};

const logError = (message) => {
    console.error(`❌ ${message}`);
};

// MinIO S3 Client setup
const s3Client = new S3Client({
    region: "us-east-1",
    endpoint: MINIO_ENDPOINT,
    credentials: {
        accessKeyId: MINIO_ACCESS_KEY,
        secretAccessKey: MINIO_SECRET_KEY,
    },
    forcePathStyle: true,
    tls: false,
});

/**
 * Check if a file is an audio file based on its extension
 */
function isAudioFile(filename) {
    const ext = path.extname(filename).toLowerCase();
    return AUDIO_EXTENSIONS.includes(ext);
}

/**
 * Check if a file is older than the specified number of days
 */
function isFileOlderThan(fileStat, days) {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);
    return fileStat.mtime < cutoffDate;
}

/**
 * Recursively find all audio files in a directory
 */
async function findAudioFiles(directory, olderThanDays) {
    const audioFiles = [];
    
    try {
        const items = await readdir(directory);
        
        for (const item of items) {
            const fullPath = path.join(directory, item);
            
            try {
                const itemStat = await stat(fullPath);
                
                if (itemStat.isDirectory()) {
                    // Recursively search subdirectories
                    const subFiles = await findAudioFiles(fullPath, olderThanDays);
                    audioFiles.push(...subFiles);
                } else if (itemStat.isFile() && isAudioFile(item) && isFileOlderThan(itemStat, olderThanDays)) {
                    audioFiles.push({
                        path: fullPath,
                        size: itemStat.size,
                        mtime: itemStat.mtime
                    });
                }
            } catch (error) {
                logWarning(`Cannot access ${fullPath}: ${error.message}`);
            }
        }
    } catch (error) {
        logError(`Cannot read directory ${directory}: ${error.message}`);
    }
    
    return audioFiles;
}

/**
 * Clean up local audio files
 */
async function cleanupLocalFiles() {
    log(`Cleaning up local audio files older than ${daysOld} days...`);
    
    if (!fs.existsSync(LOCAL_AUDIO_DIR)) {
        logWarning(`Local audio directory ${LOCAL_AUDIO_DIR} does not exist`);
        return { deleted: 0, errors: 0 };
    }
    
    const audioFiles = await findAudioFiles(LOCAL_AUDIO_DIR, daysOld);
    
    if (audioFiles.length === 0) {
        log(`No local audio files older than ${daysOld} days found`);
        return { deleted: 0, errors: 0 };
    }
    
    log(`Found ${audioFiles.length} local audio files older than ${daysOld} days`);
    
    // Calculate total size
    const totalSize = audioFiles.reduce((sum, file) => sum + file.size, 0);
    const totalSizeMB = (totalSize / (1024 * 1024)).toFixed(2);
    log(`Total size to be freed: ${totalSizeMB} MB`);
    
    if (dryRun) {
        logWarning('DRY RUN - Would delete the following local files:');
        audioFiles.forEach(file => {
            const sizeMB = (file.size / (1024 * 1024)).toFixed(2);
            console.log(`  - ${file.path} (${sizeMB} MB, modified: ${file.mtime.toISOString()})`);
        });
        return { deleted: 0, errors: 0 };
    }
    
    let deleted = 0;
    let errors = 0;
    
    for (const file of audioFiles) {
        try {
            await unlink(file.path);
            console.log(`Deleted: ${file.path}`);
            deleted++;
        } catch (error) {
            logError(`Failed to delete ${file.path}: ${error.message}`);
            errors++;
        }
    }
    
    logSuccess(`Deleted ${deleted} local audio files (${totalSizeMB} MB freed)`);
    if (errors > 0) {
        logWarning(`${errors} files could not be deleted`);
    }
    
    return { deleted, errors };
}

/**
 * Clean up MinIO audio files
 */
async function cleanupMinIOFiles() {
    log(`Cleaning up MinIO audio files older than ${daysOld} days...`);
    
    try {
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - daysOld);
        
        // List all objects in the bucket
        const listCommand = new ListObjectsV2Command({
            Bucket: MINIO_BUCKET,
        });
        
        const response = await s3Client.send(listCommand);
        
        if (!response.Contents || response.Contents.length === 0) {
            log(`No files found in MinIO bucket ${MINIO_BUCKET}`);
            return { deleted: 0, errors: 0 };
        }
        
        // Filter audio files older than cutoff date
        const oldAudioFiles = response.Contents.filter(obj => {
            if (!obj.Key || !obj.LastModified) return false;
            
            const isAudio = isAudioFile(obj.Key);
            const isOld = obj.LastModified < cutoffDate;
            
            return isAudio && isOld;
        });
        
        if (oldAudioFiles.length === 0) {
            log(`No MinIO audio files older than ${daysOld} days found`);
            return { deleted: 0, errors: 0 };
        }
        
        log(`Found ${oldAudioFiles.length} MinIO audio files older than ${daysOld} days`);
        
        // Calculate total size
        const totalSize = oldAudioFiles.reduce((sum, file) => sum + (file.Size || 0), 0);
        const totalSizeMB = (totalSize / (1024 * 1024)).toFixed(2);
        log(`Total size to be freed: ${totalSizeMB} MB`);
        
        if (dryRun) {
            logWarning('DRY RUN - Would delete the following MinIO files:');
            oldAudioFiles.forEach(file => {
                const sizeMB = ((file.Size || 0) / (1024 * 1024)).toFixed(2);
                console.log(`  - ${file.Key} (${sizeMB} MB, modified: ${file.LastModified?.toISOString()})`);
            });
            return { deleted: 0, errors: 0 };
        }
        
        let deleted = 0;
        let errors = 0;
        
        // Delete files one by one (could be optimized with batch delete for large numbers)
        for (const file of oldAudioFiles) {
            try {
                const deleteCommand = new DeleteObjectCommand({
                    Bucket: MINIO_BUCKET,
                    Key: file.Key,
                });
                
                await s3Client.send(deleteCommand);
                console.log(`Deleted: ${file.Key}`);
                deleted++;
            } catch (error) {
                logError(`Failed to delete ${file.Key}: ${error.message}`);
                errors++;
            }
        }
        
        logSuccess(`Deleted ${deleted} MinIO audio files (${totalSizeMB} MB freed)`);
        if (errors > 0) {
            logWarning(`${errors} files could not be deleted`);
        }
        
        return { deleted, errors };
        
    } catch (error) {
        logError(`Error accessing MinIO bucket: ${error.message}`);
        return { deleted: 0, errors: 1 };
    }
}

/**
 * Clean up empty directories
 */
async function cleanupEmptyDirectories(directory = LOCAL_AUDIO_DIR) {
    if (!fs.existsSync(directory)) {
        return 0;
    }
    
    let removedCount = 0;
    
    try {
        const items = await readdir(directory);
        
        // First, recursively clean subdirectories
        for (const item of items) {
            const fullPath = path.join(directory, item);
            
            try {
                const itemStat = await stat(fullPath);
                if (itemStat.isDirectory()) {
                    removedCount += await cleanupEmptyDirectories(fullPath);
                }
            } catch (error) {
                // Ignore errors for individual items
            }
        }
        
        // Then check if current directory is now empty
        const remainingItems = await readdir(directory);
        if (remainingItems.length === 0 && directory !== LOCAL_AUDIO_DIR) {
            if (dryRun) {
                console.log(`Would remove empty directory: ${directory}`);
            } else {
                try {
                    await rmdir(directory);
                    console.log(`Removed empty directory: ${directory}`);
                    removedCount++;
                } catch (error) {
                    // Ignore errors when removing directories
                }
            }
        }
        
    } catch (error) {
        // Ignore errors
    }
    
    return removedCount;
}

/**
 * Main execution function
 */
async function main() {
    log('Starting audio files cleanup script');
    log(`Configuration:`);
    log(`  - Days old: ${daysOld}`);
    log(`  - Dry run: ${dryRun}`);
    log(`  - Local directory: ${LOCAL_AUDIO_DIR}`);
    log(`  - MinIO bucket: ${MINIO_BUCKET}`);
    log(`  - MinIO endpoint: ${MINIO_ENDPOINT}`);
    
    console.log('');
    
    try {
        // Clean up local files
        const localResults = await cleanupLocalFiles();
        console.log('');
        
        // Clean up MinIO files
        const minioResults = await cleanupMinIOFiles();
        console.log('');
        
        // Clean up empty directories
        log('Cleaning up empty directories...');
        const emptyDirsRemoved = await cleanupEmptyDirectories();
        if (emptyDirsRemoved > 0) {
            logSuccess(`Removed ${emptyDirsRemoved} empty directories`);
        } else {
            log('No empty directories found');
        }
        console.log('');
        
        // Summary
        const totalDeleted = localResults.deleted + minioResults.deleted;
        const totalErrors = localResults.errors + minioResults.errors;
        
        if (dryRun) {
            logWarning('DRY RUN completed - no files were actually deleted');
        } else {
            logSuccess(`Cleanup completed successfully`);
            log(`Summary: ${totalDeleted} files deleted, ${totalErrors} errors`);
        }
        
        process.exit(totalErrors > 0 ? 1 : 0);
        
    } catch (error) {
        logError(`Cleanup failed: ${error.message}`);
        process.exit(1);
    }
}

// Run the script
main();
