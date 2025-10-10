import { Client } from '@elastic/elasticsearch';
import { env } from '@/common/utils/envConfig';
import { pino } from 'pino';

const logger = pino({ name: 'elasticsearch-client' });

// Create Elasticsearch client
export const elasticsearchClient = new Client({
    node: env.ELASTICSEARCH_URL,
    // Add authentication if needed in production
    // auth: {
    //     username: 'elastic',
    //     password: 'your-password'
    // },
    // Add SSL configuration if needed
    // tls: {
    //     ca: fs.readFileSync('./ca.crt'),
    //     rejectUnauthorized: false
    // }
});

// Test connection and log status
export const initializeElasticsearch = async () => {
    try {
        // Check if Elasticsearch is available
        const health = await elasticsearchClient.cluster.health();
        logger.info(`Elasticsearch cluster health: ${health.status}`);

        // Check if our indices exist, create them if they don't
        await ensureIndicesExist();

        logger.info("Elasticsearch connection initialized successfully");
        return true;
    } catch (error) {
        logger.error("Failed to initialize Elasticsearch connection:", error);
        throw error;
    }
};

// Ensure all required indices exist
export const ensureIndicesExist = async () => {
    const sessionEventIndex = `${env.ELASTICSEARCH_INDEX_PREFIX}-session-events`;
    const userIndex = `${env.ELASTICSEARCH_INDEX_PREFIX}-users`;

    try {
        // Check and create session events index
        const sessionEventExists = await elasticsearchClient.indices.exists({
            index: sessionEventIndex
        });

        if (!sessionEventExists) {
            await createSessionEventIndex();
            logger.info(`Created index: ${sessionEventIndex}`);
        }

        // Check and create users index
        const userExists = await elasticsearchClient.indices.exists({
            index: userIndex
        });

        if (!userExists) {
            await createUserIndex();
            logger.info(`Created index: ${userIndex}`);
        }

    } catch (error) {
        logger.error("Error ensuring indices exist:", error);
        throw error;
    }
};

// Create session events index with optimized mapping
export const createSessionEventIndex = async () => {
    const indexName = `${env.ELASTICSEARCH_INDEX_PREFIX}-session-events`;

    await elasticsearchClient.indices.create({
        index: indexName,
        body: {
            settings: {
                number_of_shards: 1,
                number_of_replicas: 0,
                analysis: {
                    analyzer: {
                        persian_analyzer: {
                            tokenizer: "standard",
                            filter: ["lowercase", "persian_normalization"]
                        }
                    },
                    filter: {
                        persian_normalization: {
                            type: "persian_normalization"
                        }
                    }
                }
            },
            mappings: {
                properties: {
                    // Basic call information
                    id: { type: "keyword" },
                    level: { type: "integer" },
                    time: { type: "date" },
                    pid: { type: "integer" },
                    hostname: { type: "keyword" },
                    name: { type: "keyword" },
                    msg: { type: "text", analyzer: "persian_analyzer" },

                    // Call metadata
                    type: { type: "keyword" }, // incoming/outgoing
                    sourceChannel: { type: "keyword" },
                    sourceNumber: { type: "keyword" },
                    queue: { type: "keyword" },
                    destChannel: { type: "keyword" },
                    destNumber: { type: "keyword" },
                    date: { type: "date" },
                    duration: { type: "keyword" },
                    filename: { type: "keyword" },

                    // File URLs
                    incommingfileUrl: { type: "keyword", index: false },
                    outgoingfileUrl: { type: "keyword", index: false },

                    // AI Analysis Results - Optimized for search and aggregation
                    transcription: {
                        type: "object",
                        properties: {
                            Agent: {
                                type: "text",
                                analyzer: "persian_analyzer",
                                fields: {
                                    keyword: { type: "keyword", ignore_above: 256 }
                                }
                            },
                            Customer: {
                                type: "text",
                                analyzer: "persian_analyzer",
                                fields: {
                                    keyword: { type: "keyword", ignore_above: 256 }
                                }
                            }
                        }
                    },

                    // Analysis fields with both text and keyword mappings
                    explanation: {
                        type: "text",
                        analyzer: "persian_analyzer",
                        fields: {
                            keyword: { type: "keyword", ignore_above: 512 }
                        }
                    },
                    category: {
                        type: "keyword",
                        fields: {
                            text: { type: "text", analyzer: "persian_analyzer" }
                        }
                    },
                    topic: {
                        type: "keyword" // Array of topic keywords
                    },
                    emotion: {
                        type: "keyword",
                        fields: {
                            text: { type: "text", analyzer: "persian_analyzer" }
                        }
                    },
                    keyWords: {
                        type: "keyword" // Array of keywords
                    },
                    routinCheckStart: { type: "keyword" },
                    routinCheckEnd: { type: "keyword" },
                    forbiddenWords: {
                        type: "object",
                        dynamic: true // Allow dynamic fields for forbidden word counts
                    },

                    // Timestamps for tracking
                    createdAt: { type: "date" },
                    updatedAt: { type: "date" },

                    // Full-text search field combining all searchable content
                    searchText: {
                        type: "text",
                        analyzer: "persian_analyzer"
                    }
                }
            }
        }
    });
};

// Create users index
export const createUserIndex = async () => {
    const indexName = `${env.ELASTICSEARCH_INDEX_PREFIX}-users`;

    await elasticsearchClient.indices.create({
        index: indexName,
        body: {
            settings: {
                number_of_shards: 1,
                number_of_replicas: 0
            },
            mappings: {
                properties: {
                    id: { type: "keyword" },
                    email: { type: "keyword" },
                    name: { type: "text" },
                    password: { type: "keyword", index: false }, // Don't index passwords
                    isVerified: { type: "boolean" },
                    createdAt: { type: "date" },
                    updatedAt: { type: "date" }
                }
            }
        }
    });
};

// Helper function to get index names
export const getIndexNames = () => ({
    sessionEvents: `${env.ELASTICSEARCH_INDEX_PREFIX}-session-events`,
    users: `${env.ELASTICSEARCH_INDEX_PREFIX}-users`
});

export default elasticsearchClient;
