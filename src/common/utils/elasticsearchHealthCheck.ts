import { elasticsearchClient } from './elasticsearchClient';
import { pino } from 'pino';

const logger = pino({ name: 'elasticsearch-health' });

export interface ElasticsearchHealthStatus {
    isHealthy: boolean;
    cluster: {
        status: string;
        name: string;
        numberOfNodes: number;
        activeShards: number;
    };
    indices: {
        sessionEvents: {
            exists: boolean;
            documentCount?: number;
            sizeInBytes?: number;
        };
        users: {
            exists: boolean;
            documentCount?: number;
            sizeInBytes?: number;
        };
    };
    error?: string;
}

export const checkElasticsearchHealth = async (): Promise<ElasticsearchHealthStatus> => {
    try {
        // Check cluster health
        const clusterHealth = await elasticsearchClient.cluster.health();

        // Check indices stats
        const sessionEventsIndex = `${process.env.ELASTICSEARCH_INDEX_PREFIX || 'opera-qc'}-session-events`;
        const usersIndex = `${process.env.ELASTICSEARCH_INDEX_PREFIX || 'opera-qc'}-users`;

        // Check if indices exist and get stats
        const [sessionEventsExists, usersExists] = await Promise.all([
            elasticsearchClient.indices.exists({ index: sessionEventsIndex }),
            elasticsearchClient.indices.exists({ index: usersIndex })
        ]);

        const result: ElasticsearchHealthStatus = {
            isHealthy: clusterHealth.status !== 'red',
            cluster: {
                status: clusterHealth.status || 'unknown',
                name: clusterHealth.cluster_name || 'unknown',
                numberOfNodes: clusterHealth.number_of_nodes || 0,
                activeShards: clusterHealth.active_shards || 0
            },
            indices: {
                sessionEvents: {
                    exists: sessionEventsExists
                },
                users: {
                    exists: usersExists
                }
            }
        };

        // Get document counts if indices exist
        if (sessionEventsExists) {
            try {
                const sessionEventsCount = await elasticsearchClient.count({
                    index: sessionEventsIndex
                });
                result.indices.sessionEvents.documentCount = sessionEventsCount.count;
            } catch (error) {
                logger.warn('Could not get session events count:', error);
            }
        }

        if (usersExists) {
            try {
                const usersCount = await elasticsearchClient.count({
                    index: usersIndex
                });
                result.indices.users.documentCount = usersCount.count;
            } catch (error) {
                logger.warn('Could not get users count:', error);
            }
        }

        // Get index sizes if indices exist
        try {
            const indicesStats = await elasticsearchClient.indices.stats({
                index: [sessionEventsIndex, usersIndex].filter(index =>
                    index === sessionEventsIndex ? sessionEventsExists : usersExists
                )
            });

            if (indicesStats.indices) {
                if (indicesStats.indices[sessionEventsIndex]) {
                    result.indices.sessionEvents.sizeInBytes =
                        indicesStats.indices[sessionEventsIndex].total?.store?.size_in_bytes;
                }
                if (indicesStats.indices[usersIndex]) {
                    result.indices.users.sizeInBytes =
                        indicesStats.indices[usersIndex].total?.store?.size_in_bytes;
                }
            }
        } catch (error) {
            logger.warn('Could not get indices stats:', error);
        }

        return result;

    } catch (error: any) {
        logger.error('Elasticsearch health check failed:', error);
        return {
            isHealthy: false,
            cluster: {
                status: 'red',
                name: 'unknown',
                numberOfNodes: 0,
                activeShards: 0
            },
            indices: {
                sessionEvents: { exists: false },
                users: { exists: false }
            },
            error: error.message || 'Unknown error'
        };
    }
};

export const initializeElasticsearchHealth = async (): Promise<boolean> => {
    try {
        const health = await checkElasticsearchHealth();

        if (health.isHealthy) {
            logger.info('Elasticsearch health check passed', {
                clusterStatus: health.cluster.status,
                clusterName: health.cluster.name,
                numberOfNodes: health.cluster.numberOfNodes,
                sessionEventsExists: health.indices.sessionEvents.exists,
                usersExists: health.indices.users.exists
            });
            return true;
        } else {
            logger.error('Elasticsearch health check failed', health);
            return false;
        }
    } catch (error) {
        logger.error('Failed to initialize Elasticsearch health check:', error);
        return false;
    }
};

// Format bytes for human readable output
export const formatBytes = (bytes?: number): string => {
    if (!bytes) return '0 B';

    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));

    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
};

// CLI utility for health checks
export const printHealthStatus = async (): Promise<void> => {
    const health = await checkElasticsearchHealth();

    console.log('\n=== ELASTICSEARCH HEALTH STATUS ===');
    console.log(`Overall Health: ${health.isHealthy ? '✅ HEALTHY' : '❌ UNHEALTHY'}`);

    console.log('\nCluster Information:');
    console.log(`  Status: ${health.cluster.status}`);
    console.log(`  Name: ${health.cluster.name}`);
    console.log(`  Nodes: ${health.cluster.numberOfNodes}`);
    console.log(`  Active Shards: ${health.cluster.activeShards}`);

    console.log('\nIndices Status:');
    console.log(`  Session Events:`);
    console.log(`    Exists: ${health.indices.sessionEvents.exists ? '✅' : '❌'}`);
    if (health.indices.sessionEvents.documentCount !== undefined) {
        console.log(`    Documents: ${health.indices.sessionEvents.documentCount.toLocaleString()}`);
    }
    if (health.indices.sessionEvents.sizeInBytes) {
        console.log(`    Size: ${formatBytes(health.indices.sessionEvents.sizeInBytes)}`);
    }

    console.log(`  Users:`);
    console.log(`    Exists: ${health.indices.users.exists ? '✅' : '❌'}`);
    if (health.indices.users.documentCount !== undefined) {
        console.log(`    Documents: ${health.indices.users.documentCount.toLocaleString()}`);
    }
    if (health.indices.users.sizeInBytes) {
        console.log(`    Size: ${formatBytes(health.indices.users.sizeInBytes)}`);
    }

    if (health.error) {
        console.log(`\nError: ${health.error}`);
    }

    console.log('=====================================\n');
};

// Export for use in monitoring scripts
export default {
    checkElasticsearchHealth,
    initializeElasticsearchHealth,
    printHealthStatus,
    formatBytes
};
