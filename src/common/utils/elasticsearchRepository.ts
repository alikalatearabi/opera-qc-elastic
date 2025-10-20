import { elasticsearchClient, getIndexNames } from '@/common/utils/elasticsearchClient';
import { pino } from 'pino';

const logger = pino({ name: 'elasticsearch-repository' });

export interface SessionEventDocument {
    id?: string;
    level: number;
    time: number | string;
    pid: number;
    hostname: string;
    name: string;
    msg: string;
    type: 'incoming' | 'outgoing';
    sourceChannel?: string;
    sourceNumber?: string;
    queue?: string;
    destChannel?: string;
    destNumber?: string;
    date: Date | string;
    duration: string;
    filename: string;
    incommingfileUrl?: string;
    outgoingfileUrl?: string;
    transcription?: {
        Agent: string;
        Customer: string;
    };
    explanation?: string;
    category?: string;
    topic?: string[];
    emotion?: string;
    keyWords?: string[];
    routinCheckStart?: string;
    routinCheckEnd?: string;
    forbiddenWords?: Record<string, number>;
    createdAt?: Date | string;
    updatedAt?: Date | string;
    searchText?: string;
}

export interface UserDocument {
    id?: string;
    email: string;
    name?: string;
    password: string;
    isVerified: boolean;
    createdAt?: Date | string;
    updatedAt?: Date | string;
}

export interface SearchFilters {
    emotion?: string;
    category?: string;
    topic?: string;
    destNumber?: string;
    type?: 'incoming' | 'outgoing';
    dateFrom?: Date;
    dateTo?: Date;
    persianDate?: string; // For exact Persian date matching
    searchText?: string;
}

export interface SortOption {
    field: string;
    order: 'asc' | 'desc';
}

export interface PaginationOptions {
    page: number;
    limit: number;
    sort?: SortOption[];
    useScroll?: boolean; // Whether to use scroll API for large result sets
    scrollTTL?: string; // Time to keep scroll context alive (e.g. '1m')
}

export interface SearchResult<T> {
    data: T[];
    total: number;
    page: number;
    limit: number;
    scrollId?: string; // For scroll API pagination
    totalPages: number;
}

export class SessionEventRepository {
    private readonly indexName = getIndexNames().sessionEvents;

    // Create a new session event
    async create(sessionEvent: Omit<SessionEventDocument, 'id' | 'createdAt' | 'updatedAt'>): Promise<SessionEventDocument> {
        try {
            const now = new Date();
            const document: SessionEventDocument = {
                ...sessionEvent,
                createdAt: now,
                updatedAt: now,
                searchText: this.buildSearchText(sessionEvent)
            };

            const response = await elasticsearchClient.index({
                index: this.indexName,
                body: document,
                refresh: 'wait_for' // Ensure document is immediately searchable
            });

            return {
                ...document,
                id: response._id
            };
        } catch (error) {
            logger.error('Error creating session event:', error);
            throw error;
        }
    }

    // Find session event by ID
    async findById(id: string): Promise<SessionEventDocument | null> {
        try {
            const response = await elasticsearchClient.get({
                index: this.indexName,
                id
            });

            if (response.found) {
                return {
                    id: response._id,
                    ...response._source as SessionEventDocument
                };
            }
            return null;
        } catch (error: any) {
            if (error.statusCode === 404) {
                return null;
            }
            logger.error('Error finding session event by ID:', error);
            throw error;
        }
    }

    // Update session event
    async update(id: string, updates: Partial<SessionEventDocument>): Promise<SessionEventDocument | null> {
        try {
            const updateDoc = {
                ...updates,
                updatedAt: new Date()
            };

            // Add search text if transcription or other searchable fields are updated
            if (updates.transcription || updates.explanation || updates.category) {
                const current = await this.findById(id);
                if (current) {
                    updateDoc.searchText = this.buildSearchText({ ...current, ...updates });
                }
            }

            const response = await elasticsearchClient.update({
                index: this.indexName,
                id,
                body: {
                    doc: updateDoc
                },
                refresh: 'wait_for'
            });

            // Return updated document
            return await this.findById(id);
        } catch (error: any) {
            if (error.statusCode === 404) {
                return null;
            }
            logger.error('Error updating session event:', error);
            throw error;
        }
    }

    // Search session events with filters and pagination
    async search(filters: SearchFilters = {}, pagination: PaginationOptions, includeUnprocessed: boolean = false): Promise<SearchResult<SessionEventDocument>> {
        try {
            const { page, limit, useScroll, scrollTTL = '1m' } = pagination;

            // Build query
            const query = this.buildSearchQuery(filters, includeUnprocessed);

            // Build sort options
            let sortOptions = [{ date: { order: 'desc' } }]; // Default sort

            // If custom sort is provided, use it instead
            if (pagination.sort && pagination.sort.length > 0) {
                sortOptions = pagination.sort.map(sortOpt => {
                    return { [sortOpt.field]: { order: sortOpt.order } };
                });
            }

            // Use scroll API for large result sets
            if (useScroll) {
                const response = await elasticsearchClient.search({
                    index: this.indexName,
                    scroll: scrollTTL,
                    body: {
                        query,
                        sort: sortOptions,
                        size: limit
                    }
                });

                // Process the scroll response
                const data = response.hits.hits.map(hit => ({
                    id: hit._id,
                    ...hit._source as SessionEventDocument
                }));

                const total = typeof response.hits.total === 'number'
                    ? response.hits.total
                    : response.hits.total?.value || 0;

                return {
                    data,
                    total,
                    page: 1,
                    limit,
                    scrollId: response._scroll_id,
                    totalPages: Math.ceil(total / limit)
                };
            }

            // Use regular search for normal pagination
            const from = (page - 1) * limit;

            // Ensure we don't exceed Elasticsearch's max window size (10,000)
            if (from + limit > 10000) {
                throw new Error(`Result window is too large. Use scroll API by setting useScroll: true in pagination options.`);
            }

            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    query,
                    sort: sortOptions,
                    from,
                    size: limit
                }
            });

            // Process the response
            return this.processResponse(response, page, limit);
        } catch (error) {
            logger.error('Error searching session events:', error);
            throw error;
        }
    }

    // Process regular search response
    private processResponse(response: any, page: number, limit: number): SearchResult<SessionEventDocument> {
        const data = response.hits.hits.map(hit => ({
            id: hit._id,
            ...hit._source as SessionEventDocument
        }));

        const total = typeof response.hits.total === 'number'
            ? response.hits.total
            : response.hits.total?.value || 0;

        return {
            data,
            total,
            page,
            limit,
            totalPages: Math.ceil(total / limit)
        };
    }

    // Continue a scroll search using a scroll ID
    async scroll(scrollId: string, scrollTTL: string = '1m'): Promise<SearchResult<SessionEventDocument>> {
        try {
            const response = await elasticsearchClient.scroll({
                scroll_id: scrollId,
                scroll: scrollTTL
            });

            const data = response.hits.hits.map(hit => ({
                id: hit._id,
                ...hit._source as SessionEventDocument
            }));

            const total = typeof response.hits.total === 'number'
                ? response.hits.total
                : response.hits.total?.value || 0;

            // Calculate the next "page" (just for consistency in the API)
            const nextPage = 1; // Scroll doesn't have pages in the traditional sense

            return {
                data,
                total,
                page: nextPage,
                limit: data.length,
                scrollId: response._scroll_id,
                totalPages: Math.ceil(total / data.length)
            };
        } catch (error) {
            logger.error('Error scrolling session events:', error);
            throw error;
        }
    }

    // Clear a scroll context to free resources
    async clearScroll(scrollId: string): Promise<boolean> {
        try {
            await elasticsearchClient.clearScroll({
                scroll_id: scrollId
            });
            return true;
        } catch (error) {
            logger.error('Error clearing scroll:', error);
            return false;
        }
    }

    // Get distinct categories
    async getDistinctCategories(): Promise<string[]> {
        try {
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    size: 0,
                    aggs: {
                        categories: {
                            terms: {
                                field: 'category',
                                size: 1000
                            }
                        }
                    }
                }
            });

            return response.aggregations?.categories.buckets.map((bucket: any) => bucket.key) || [];
        } catch (error) {
            logger.error('Error getting distinct categories:', error);
            throw error;
        }
    }

    // Get distinct topics (from topic object values)
    async getDistinctTopics(): Promise<string[]> {
        try {
            // This is more complex with Elasticsearch as we need to extract values from topic object
            // We'll use a script aggregation
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    size: 0,
                    aggs: {
                        topic_values: {
                            terms: {
                                script: {
                                    source: `
                                        if (params._source.topic != null) {
                                            List values = new ArrayList();
                                            for (entry in params._source.topic.entrySet()) {
                                                values.add(entry.getValue().toString());
                                            }
                                            return values;
                                        }
                                        return [];
                                    `
                                },
                                size: 1000
                            }
                        }
                    }
                }
            });

            return response.aggregations?.topic_values.buckets.map((bucket: any) => bucket.key) || [];
        } catch (error) {
            logger.error('Error getting distinct topics:', error);
            // Fallback: get all documents and extract topics client-side
            return this.getDistinctTopicsFallback();
        }
    }

    // Fallback method for getting distinct topics
    private async getDistinctTopicsFallback(): Promise<string[]> {
        const response = await elasticsearchClient.search({
            index: this.indexName,
            body: {
                query: {
                    exists: { field: 'topic' }
                },
                _source: ['topic'],
                size: 1000
            }
        });

        const topics = new Set<string>();
        response.hits.hits.forEach((hit: any) => {
            const topicObj = hit._source?.topic;
            if (topicObj && typeof topicObj === 'object') {
                Object.values(topicObj).forEach(value => {
                    if (typeof value === 'string') {
                        topics.add(value);
                    }
                });
            }
        });

        return Array.from(topics);
    }

    // Get distinct destination numbers for incoming calls
    async getDistinctDestNumbers(): Promise<string[]> {
        try {
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    size: 0,
                    query: {
                        term: { type: 'incoming' }
                    },
                    aggs: {
                        dest_numbers: {
                            terms: {
                                field: 'destNumber',
                                size: 1000
                            }
                        }
                    }
                }
            });

            return response.aggregations?.dest_numbers.buckets.map((bucket: any) => bucket.key) || [];
        } catch (error) {
            logger.error('Error getting distinct destination numbers:', error);
            throw error;
        }
    }

    // Get session statistics
    async getStats(): Promise<{
        total_calls: number;
        total_agents: number;
        top_emotion: string | null;
        top_emotion_count: number;
        distinct_categories: number;
        distinct_topics: number;
    }> {
        try {
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    size: 0,
                    aggs: {
                        total_calls: {
                            value_count: { field: 'id' }
                        },
                        total_agents: {
                            cardinality: {
                                field: 'destNumber',
                                script: {
                                    source: "params._source.type == 'incoming' ? params._source.destNumber : null"
                                }
                            }
                        },
                        top_emotion: {
                            terms: {
                                field: 'emotion',
                                size: 1
                            }
                        },
                        distinct_categories: {
                            cardinality: { field: 'category' }
                        }
                    }
                }
            });

            const aggs = response.aggregations;
            const topEmotionBucket = aggs?.top_emotion.buckets[0];

            return {
                total_calls: aggs?.total_calls.value || 0,
                total_agents: aggs?.total_agents.value || 0,
                top_emotion: topEmotionBucket?.key || null,
                top_emotion_count: topEmotionBucket?.doc_count || 0,
                distinct_categories: aggs?.distinct_categories.value || 0,
                distinct_topics: (await this.getDistinctTopics()).length
            };
        } catch (error) {
            logger.error('Error getting session statistics:', error);
            throw error;
        }
    }

    // Get dashboard analytics data
    async getDashboardData(): Promise<any> {
        try {
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    size: 0,
                    aggs: {
                        emotion_pie_chart: {
                            terms: {
                                field: 'emotion',
                                size: 10
                            }
                        },
                        emotion_line_chart: {
                            date_histogram: {
                                field: 'date',
                                calendar_interval: 'day'
                            },
                            aggs: {
                                emotions: {
                                    terms: {
                                        field: 'emotion',
                                        size: 10
                                    }
                                }
                            }
                        },
                        top_destinations: {
                            terms: {
                                field: 'destNumber',
                                size: 10
                            }
                        },
                        forbidden_words_table: {
                            nested: {
                                path: 'forbiddenWords'
                            },
                            aggs: {
                                words: {
                                    terms: {
                                        script: {
                                            source: `
                                                if (params._source.forbiddenWords != null) {
                                                    List words = new ArrayList();
                                                    for (entry in params._source.forbiddenWords.entrySet()) {
                                                        words.add(entry.getKey());
                                                    }
                                                    return words;
                                                }
                                                return [];
                                            `
                                        }
                                    }
                                }
                            }
                        },
                        key_words_table: {
                            terms: {
                                field: 'keyWords',
                                size: 20
                            }
                        },
                        topic_pie_chart: {
                            terms: {
                                script: {
                                    source: `
                                        if (params._source.topic != null) {
                                            List keys = new ArrayList();
                                            for (entry in params._source.topic.entrySet()) {
                                                keys.add(entry.getKey());
                                            }
                                            return keys;
                                        }
                                        return [];
                                    `
                                }
                            }
                        }
                    }
                }
            });

            return this.formatDashboardResponse(response.aggregations);
        } catch (error) {
            logger.error('Error getting dashboard data:', error);
            throw error;
        }
    }

    // Build search query based on filters
    private buildSearchQuery(filters: SearchFilters, includeUnprocessed: boolean = false) {
        const must: any[] = [];
        const filter: any[] = [];

        // Only show calls with transcription data (processed calls) unless includeUnprocessed is true
        if (!includeUnprocessed) {
            must.push({
                exists: { field: 'transcription' }
            });
        }

        if (filters.emotion) {
            filter.push({ term: { emotion: filters.emotion } });
        }

        if (filters.category) {
            filter.push({ term: { category: filters.category } });
        }

        if (filters.topic) {
            filter.push({
                script: {
                    script: {
                        source: `
                            if (params._source.topic != null) {
                                for (entry in params._source.topic.entrySet()) {
                                    if (entry.getValue().toString() == params.topic) {
                                        return true;
                                    }
                                }
                            }
                            return false;
                        `,
                        params: { topic: filters.topic }
                    }
                }
            });
        }

        if (filters.destNumber) {
            filter.push({ term: { destNumber: filters.destNumber } });
        }

        if (filters.type) {
            filter.push({ term: { type: filters.type } });
        }

        if (filters.dateFrom || filters.dateTo) {
            const range: any = {};
            if (filters.dateFrom) range.gte = filters.dateFrom;
            if (filters.dateTo) range.lte = filters.dateTo;
            filter.push({ range: { date: range } });
        }

        if (filters.persianDate) {
            // Search for dates that start with the Persian date (YYYY-MM-DD format)
            filter.push({
                prefix: { date: filters.persianDate }
            });
        }

        if (filters.searchText) {
            must.push({
                multi_match: {
                    query: filters.searchText,
                    fields: [
                        'searchText^2',
                        'transcription.Agent',
                        'transcription.Customer',
                        'explanation',
                        'category',
                        'keyWords'
                    ],
                    type: 'best_fields',
                    fuzziness: 'AUTO'
                }
            });
        }

        return {
            bool: {
                must,
                filter
            }
        };
    }

    // Build search text for full-text search
    private buildSearchText(sessionEvent: Partial<SessionEventDocument>): string {
        const parts: string[] = [];

        if (sessionEvent.transcription?.Agent) {
            parts.push(sessionEvent.transcription.Agent);
        }
        if (sessionEvent.transcription?.Customer) {
            parts.push(sessionEvent.transcription.Customer);
        }
        if (sessionEvent.explanation) {
            parts.push(sessionEvent.explanation);
        }
        if (sessionEvent.category) {
            parts.push(sessionEvent.category);
        }
        if (sessionEvent.keyWords) {
            parts.push(...sessionEvent.keyWords);
        }

        return parts.join(' ');
    }

    // Format dashboard response
    private formatDashboardResponse(aggs: any) {
        return {
            emotion_pie_chart: aggs?.emotion_pie_chart?.buckets?.map((bucket: any) => ({
                emotion: bucket.key,
                count: bucket.doc_count
            })) || [],
            emotion_line_chart: this.formatLineChart(aggs?.emotion_line_chart?.buckets || [], 'emotions'),
            topic_line_chart: {}, // Would need similar processing
            top_destinations: aggs?.top_destinations?.buckets?.map((bucket: any) => ({
                dest_number: bucket.key,
                count: bucket.doc_count
            })) || [],
            forbidden_words_table: aggs?.forbidden_words_table?.words?.buckets?.map((bucket: any) => ({
                forbidden_word: bucket.key,
                count: bucket.doc_count
            })) || [],
            key_words_table: aggs?.key_words_table?.buckets?.map((bucket: any) => ({
                key_words: bucket.key,
                count: bucket.doc_count
            })) || [],
            topic_pie_chart: aggs?.topic_pie_chart?.buckets?.map((bucket: any) => ({
                topic: bucket.key,
                count: bucket.doc_count
            })) || []
        };
    }

    // Format line chart data
    private formatLineChart(buckets: any[], subField: string) {
        const result: Record<string, Record<string, number>> = {};

        buckets.forEach((bucket: any) => {
            const date = bucket.key_as_string || bucket.key;
            result[date] = {};

            if (bucket[subField]?.buckets) {
                bucket[subField].buckets.forEach((subBucket: any) => {
                    result[date][subBucket.key] = subBucket.doc_count;
                });
            }
        });

        return result;
    }
}

export class UserRepository {
    private readonly indexName = getIndexNames().users;

    async create(user: Omit<UserDocument, 'id' | 'createdAt' | 'updatedAt'>): Promise<UserDocument> {
        try {
            const now = new Date();
            const document: UserDocument = {
                ...user,
                createdAt: now,
                updatedAt: now
            };

            const response = await elasticsearchClient.index({
                index: this.indexName,
                body: document,
                refresh: 'wait_for'
            });

            return {
                ...document,
                id: response._id
            };
        } catch (error) {
            logger.error('Error creating user:', error);
            throw error;
        }
    }

    async findByEmail(email: string): Promise<UserDocument | null> {
        try {
            const response = await elasticsearchClient.search({
                index: this.indexName,
                body: {
                    query: {
                        term: { email }
                    }
                }
            });

            if (response.hits.hits.length > 0) {
                const hit = response.hits.hits[0];
                return {
                    id: hit._id,
                    ...hit._source as UserDocument
                };
            }
            return null;
        } catch (error) {
            logger.error('Error finding user by email:', error);
            throw error;
        }
    }

    async findById(id: string): Promise<UserDocument | null> {
        try {
            const response = await elasticsearchClient.get({
                index: this.indexName,
                id
            });

            if (response.found) {
                return {
                    id: response._id,
                    ...response._source as UserDocument
                };
            }
            return null;
        } catch (error: any) {
            if (error.statusCode === 404) {
                return null;
            }
            logger.error('Error finding user by ID:', error);
            throw error;
        }
    }
}

// Export repository instances
export const sessionEventRepository = new SessionEventRepository();
export const userRepository = new UserRepository();
