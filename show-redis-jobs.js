#!/usr/bin/env node

/**
 * Redis Jobs Inspector for Opera QC Backend
 *
 * This script connects to Redis and displays the current state of all BullMQ queues
 * used in the Opera QC Backend application.
 *
 * Usage:
 *   node show-redis-jobs.js [redis-host] [redis-port]
 *
 * Default: localhost 6379
 */

const Redis = require('ioredis');
const { Queue } = require('bullmq');

// Queue names from the application
const QUEUES = [
    'sequential-processing',
    'transcription-processing',
    'llm-processing'
];

// Redis connection configuration
const REDIS_HOST = process.argv[2] || 'localhost';
const REDIS_PORT = parseInt(process.argv[3]) || 6379;

async function inspectQueue(queueName) {
    console.log(`\n🔍 Inspecting queue: ${queueName}`);
    console.log('='.repeat(50));

    const queue = new Queue(queueName, {
        connection: {
            host: REDIS_HOST,
            port: REDIS_PORT,
        }
    });

    try {
        // Get queue statistics
        const waiting = await queue.getWaiting();
        const active = await queue.getActive();
        const completed = await queue.getCompleted();
        const failed = await queue.getFailed();
        const delayed = await queue.getDelayed();

        console.log(`📊 Queue Statistics:`);
        console.log(`   Waiting: ${waiting.length}`);
        console.log(`   Active: ${active.length}`);
        console.log(`   Completed: ${completed.length}`);
        console.log(`   Failed: ${failed.length}`);
        console.log(`   Delayed: ${delayed.length}`);

        // Show waiting jobs
        if (waiting.length > 0) {
            console.log(`\n⏳ Waiting Jobs (${waiting.length}):`);
            for (const job of waiting.slice(0, 5)) { // Show first 5
                const data = job.data;
                console.log(`   Job ${job.id}: ${data.type || 'unknown'} - ${data.filename || data.sessionEventId || 'no filename'}`);
            }
            if (waiting.length > 5) {
                console.log(`   ... and ${waiting.length - 5} more`);
            }
        }

        // Show active jobs
        if (active.length > 0) {
            console.log(`\n⚡ Active Jobs (${active.length}):`);
            for (const job of active) {
                const data = job.data;
                const progress = job.progress || 0;
                console.log(`   Job ${job.id}: ${data.type || 'unknown'} - ${data.filename || data.sessionEventId || 'no filename'} (${progress}%)`);
            }
        }

        // Show recent completed jobs
        if (completed.length > 0) {
            console.log(`\n✅ Recent Completed Jobs (${Math.min(completed.length, 3)}):`);
            for (const job of completed.slice(0, 3)) {
                const data = job.data;
                const finishedOn = job.finishedOn ? new Date(job.finishedOn).toLocaleString() : 'unknown';
                console.log(`   Job ${job.id}: ${data.type || 'unknown'} - ${data.filename || data.sessionEventId || 'no filename'} (${finishedOn})`);
            }
            if (completed.length > 3) {
                console.log(`   ... and ${completed.length - 3} more completed jobs`);
            }
        }

        // Show recent failed jobs
        if (failed.length > 0) {
            console.log(`\n❌ Recent Failed Jobs (${Math.min(failed.length, 3)}):`);
            for (const job of failed.slice(0, 3)) {
                const data = job.data;
                const failedReason = job.failedReason ? job.failedReason.substring(0, 100) : 'unknown';
                console.log(`   Job ${job.id}: ${data.type || 'unknown'} - ${data.filename || data.sessionEventId || 'no filename'}`);
                console.log(`      Reason: ${failedReason}${failedReason.length > 100 ? '...' : ''}`);
            }
            if (failed.length > 3) {
                console.log(`   ... and ${failed.length - 3} more failed jobs`);
            }
        }

        // Show delayed jobs
        if (delayed.length > 0) {
            console.log(`\n⏰ Delayed Jobs (${delayed.length}):`);
            for (const job of delayed.slice(0, 3)) {
                const data = job.data;
                const delay = job.opts.delay || 0;
                const delayedUntil = new Date(Date.now() + delay).toLocaleString();
                console.log(`   Job ${job.id}: ${data.type || 'unknown'} - ${data.filename || data.sessionEventId || 'no filename'} (delayed until ${delayedUntil})`);
            }
            if (delayed.length > 3) {
                console.log(`   ... and ${delayed.length - 3} more delayed jobs`);
            }
        }

    } catch (error) {
        console.error(`❌ Error inspecting queue ${queueName}:`, error.message);
    } finally {
        await queue.close();
    }
}

async function showRedisInfo() {
    console.log('🔗 Connecting to Redis...');

    const redis = new Redis({
        host: REDIS_HOST,
        port: REDIS_PORT,
    });

    try {
        const info = await redis.info();
        console.log('✅ Connected to Redis');
        console.log(`📍 Host: ${REDIS_HOST}:${REDIS_PORT}`);

        // Extract some basic info
        const version = info.match(/redis_version:([^\r\n]+)/)?.[1];
        const uptime = info.match(/uptime_in_seconds:([^\r\n]+)/)?.[1];
        const connected_clients = info.match(/connected_clients:([^\r\n]+)/)?.[1];
        const used_memory = info.match(/used_memory_human:([^\r\n]+)/)?.[1];

        console.log(`📊 Redis Info:`);
        console.log(`   Version: ${version}`);
        console.log(`   Uptime: ${Math.floor(parseInt(uptime) / 86400)} days`);
        console.log(`   Connected Clients: ${connected_clients}`);
        console.log(`   Used Memory: ${used_memory}`);

    } catch (error) {
        console.error('❌ Failed to connect to Redis:', error.message);
        console.log('\n💡 Make sure Redis is running and accessible.');
        console.log('   For local development: redis-server');
        console.log('   For Docker: docker-compose up -d redis');
        process.exit(1);
    } finally {
        await redis.disconnect();
    }
}

async function main() {
    console.log('🚀 Opera QC Backend - Redis Jobs Inspector');
    console.log('=' .repeat(55));

    // Show Redis connection info
    await showRedisInfo();

    // Inspect each queue
    for (const queueName of QUEUES) {
        await inspectQueue(queueName);
    }

    console.log('\n🎯 Summary:');
    console.log('=' .repeat(20));
    console.log('✅ Inspection completed');
    console.log('💡 Use this script to monitor queue health and job processing');
    console.log('🔄 Run periodically to track system performance');

    process.exit(0);
}

// Handle errors
process.on('unhandledRejection', (error) => {
    console.error('❌ Unhandled error:', error);
    process.exit(1);
});

process.on('SIGINT', () => {
    console.log('\n👋 Shutting down gracefully...');
    process.exit(0);
});

// Run the script
main().catch((error) => {
    console.error('❌ Script failed:', error);
    process.exit(1);
});
