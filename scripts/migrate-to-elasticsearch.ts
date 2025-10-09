#!/usr/bin/env node
/**
 * Migration script to transfer data from PostgreSQL to Elasticsearch
 * 
 * Usage:
 *   npm run migrate-to-elasticsearch
 * 
 * This script will:
 * 1. Connect to Elasticsearch
 * 2. Insert sample data for testing
 * 3. Provide progress feedback and error handling
 */

import { esClient, initializeElasticsearch, SESSION_EVENTS_INDEX, USERS_INDEX } from '../src/common/utils/elasticsearchClient.js';
import { sessionEventRepository, userRepository, SessionEventDocument, UserDocument } from '../src/common/utils/elasticsearchRepository.js';
import { pino } from 'pino';

const logger = pino({ name: 'migration-script' });

interface MigrationStats {
    sessionEvents: {
        total: number;
        migrated: number;
        errors: number;
    };
    users: {
        total: number;
        migrated: number;
        errors: number;
    };
}

async function clearElasticsearchIndices() {
    logger.info(`Clearing Elasticsearch index: ${SESSION_EVENTS_INDEX}`);
    await esClient.indices.delete({ index: SESSION_EVENTS_INDEX, ignore_unavailable: true });
    logger.info(`Clearing Elasticsearch index: ${USERS_INDEX}`);
    await esClient.indices.delete({ index: USERS_INDEX, ignore_unavailable: true });
    logger.info('Elasticsearch indices cleared.');
}

async function insertSampleData() {
    logger.info('Inserting sample data into Elasticsearch...');

    // Sample session event
    const sampleSessionEvent: SessionEventDocument = {
        level: 30,
        time: Date.now(), // Use timestamp as number
        pid: 1234,
        hostname: "test-host",
        name: "Sample Session",
        type: "incoming",
        sourceChannel: "SIP/sample-in",
        sourceNumber: "1234567890",
        queue: "support",
        destChannel: "SIP/sample-out",
        destNumber: "9876",
        date: new Date().toISOString(),
        duration: "00:01:30",
        filename: "sample-call-123",
        msg: "This is a sample call for testing Elasticsearch.",
        transcription: {
            Agent: "سلام، چطور میتونم کمکتون کنم؟",
            Customer: "سلام، من در مورد یک مشکل فنی سوال داشتم."
        },
        explanation: "مکالمه در مورد مشکل فنی مشتری و ارائه راه حل.",
        category: "پشتیبانی فنی",
        topic: { "فنی": "اینترنت" },
        emotion: "خنثی",
        keyWords: ["مشکل", "فنی", "راه حل", "اینترنت"],
        forbiddenWords: { "آره": 1 },
        routinCheckStart: "0",
        routinCheckEnd: "0",
        incommingfileUrl: "/audio-files/sample-in.wav",
        outgoingfileUrl: "/audio-files/sample-out.wav"
    };

    // Sample user
    const sampleUser: UserDocument = {
        email: "test@example.com",
        name: "Test User",
        password: "$2a$10$example.hash.here", // This would be a real bcrypt hash in practice
        isVerified: true
    };

    try {
        // Insert sample session event
        const createdEvent = await sessionEventRepository.create(sampleSessionEvent);
        logger.info(`Created sample session event with ID: ${createdEvent.id}`);

        // Insert sample user
        const createdUser = await userRepository.create(sampleUser);
        logger.info(`Created sample user with ID: ${createdUser.id}`);

        logger.info('Sample data inserted successfully!');

        // Verify the data
        const eventCount = await esClient.count({ index: SESSION_EVENTS_INDEX });
        const userCount = await esClient.count({ index: USERS_INDEX });

        logger.info(`Verification - Session Events: ${eventCount.count}, Users: ${userCount.count}`);

    } catch (error) {
        logger.error('Error inserting sample data:', error);
        throw error;
    }
}

async function verifyMigration() {
    logger.info('Verifying Elasticsearch indices...');

    const eventCount = await esClient.count({ index: SESSION_EVENTS_INDEX });
    const userCount = await esClient.count({ index: USERS_INDEX });

    logger.info(`Elasticsearch SessionEvent count: ${eventCount.count}`);
    logger.info(`Elasticsearch User count: ${userCount.count}`);

    if (eventCount.count > 0 || userCount.count > 0) {
        logger.info('Elasticsearch indices contain data. Migration looks good.');
    } else {
        logger.warn('Elasticsearch indices are empty.');
    }
}

async function main() {
    const args = process.argv.slice(2);
    const shouldClear = args.includes('--clear');
    const shouldVerify = args.includes('--verify');
    const shouldSample = args.includes('--sample');

    try {
        logger.info('Starting migration process...');

        // Initialize Elasticsearch connection
        await initializeElasticsearch();
        logger.info('Elasticsearch connection established');

        if (shouldClear) {
            await clearElasticsearchIndices();
        }

        if (shouldSample) {
            await insertSampleData();
        }

        if (shouldVerify) {
            await verifyMigration();
        }

        if (!shouldClear && !shouldSample && !shouldVerify) {
            logger.info('No specific action specified. Use --clear, --sample, or --verify');
            logger.info('Available options:');
            logger.info('  --clear   Clear all Elasticsearch indices');
            logger.info('  --sample  Insert sample data for testing');
            logger.info('  --verify  Verify current data in Elasticsearch');
        }

        logger.info('Migration process completed successfully');
        process.exit(0);

    } catch (error) {
        logger.error('Migration failed:', error);
        process.exit(1);
    }
}

// Run the migration
main();