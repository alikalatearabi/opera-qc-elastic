import { sessionEventRepository, type SessionEventDocument } from "@/common/utils/elasticsearchRepository";

export class AudioRepository {
    /**
     * Gets all session events from Elasticsearch with only essential fields
     * Uses scroll API for large result sets
     * @param sortField Field to sort by (default: 'date')
     * @param sortOrder Sort order ('asc' or 'desc', default: 'desc')
     */
    public static async getAllSessionEvents(
        sortField = 'date',
        sortOrder: 'asc' | 'desc' = 'desc'
    ) {
        // Use scroll API to avoid result window limits
        const result = await sessionEventRepository.search({}, { 
            page: 1, 
            limit: 5000,
            sort: [{ field: sortField, order: sortOrder }],
            useScroll: true,
            scrollTTL: '1m'
        });
        
        // Map results to the expected format
        const mappedResults = result.data.map(event => ({
            id: event.id,
            destNumber: event.destNumber,
            searchText: event.searchText || "",
            transcription: event.transcription,
            explanation: event.explanation,
            topic: event.topic,
            sourceNumber: event.sourceNumber,
            date: event.date
        }));
        
        // Clean up scroll context if we have a scrollId
        if (result.scrollId) {
            try {
                await sessionEventRepository.clearScroll(result.scrollId);
            } catch (error) {
                console.error("Error clearing scroll context:", error);
            }
        }
        
        return mappedResults;
    }

    /**
     * Gets session events with ID greater than the provided lastId with only essential fields
     * Uses scroll API for large result sets
     * @param lastId The ID to start from (exclusive)
     * @param sortField Field to sort by (default: 'date')
     * @param sortOrder Sort order ('asc' or 'desc', default: 'desc')
     */
    public static async getSessionEventsAfterLastId(
        lastId: string,
        sortField = 'date',
        sortOrder: 'asc' | 'desc' = 'desc'
    ) {
        // For Elasticsearch, we'll use createdAt timestamp for reliable ordering
        const lastEvent = await sessionEventRepository.findById(lastId);
        
        // Use scroll API to avoid result window limits
        const result = await sessionEventRepository.search({}, { 
            page: 1, 
            limit: 5000,
            sort: [{ field: sortField, order: sortOrder }],
            useScroll: true,
            scrollTTL: '1m'
        });
        
        let scrollId = result.scrollId;
        let allData: SessionEventDocument[] = [...result.data];
        let hasMoreData = true;
        
        // Continue scrolling to get all results
        try {
            while (hasMoreData && scrollId) {
                const scrollResult = await sessionEventRepository.scroll(scrollId);
                
                if (scrollResult.data.length === 0) {
                    hasMoreData = false;
                } else {
                    allData = [...allData, ...scrollResult.data];
                    scrollId = scrollResult.scrollId;
                }
            }
        } finally {
            // Clean up scroll context
            if (scrollId) {
                try {
                    await sessionEventRepository.clearScroll(scrollId);
                } catch (error) {
                    console.error("Error clearing scroll context:", error);
                }
            }
        }
        
        // Filter the data based on lastId
        let filteredData;
        if (lastEvent && lastEvent.createdAt) {
            // Filter events created after the lastId event
            filteredData = allData.filter(event => 
                event.id && 
                event.id !== lastId && 
                event.createdAt && 
                new Date(event.createdAt) > new Date(lastEvent.createdAt)
            );
        } else {
            // Fallback to string comparison if event not found
            filteredData = allData.filter(event => event.id && event.id > lastId);
        }
        
        // Map to the expected format
        return filteredData.map(event => ({
            id: event.id,
            destNumber: event.destNumber,
            searchText: event.searchText || "",
            transcription: event.transcription,
            explanation: event.explanation,
            topic: event.topic,
            sourceNumber: event.sourceNumber,
            date: event.date
        }));
    }

    /**
     * Streams session events in batches to avoid memory issues
     * Uses Elasticsearch scroll API for efficient pagination of large result sets
     * @param lastId Optional ID to start from (exclusive)
     * @param batchSize Number of records to fetch per batch
     * @param sortField Field to sort by (default: 'date')
     * @param sortOrder Sort order ('asc' or 'desc', default: 'desc')
     */
    public static async *streamSessionEvents(
        lastId: string | undefined = undefined, 
        batchSize = 1000,
        sortField = 'date',
        sortOrder: 'asc' | 'desc' = 'desc'
    ) {
        // Ensure batch size doesn't exceed Elasticsearch limits
        const safeBatchSize = Math.min(batchSize, 5000);
        let hasMoreRecords = true;
        let scrollId: string | undefined;

        try {
            // Initial search with scroll
            const result = await sessionEventRepository.search({}, {
                page: 1,
                limit: safeBatchSize,
                sort: [{ field: sortField, order: sortOrder }],
                useScroll: true,
                scrollTTL: '5m' // Keep scroll context alive for 5 minutes
            });

            // Store the scroll ID for subsequent requests
            scrollId = result.scrollId;
            
            if (result.data.length === 0) {
                hasMoreRecords = false;
            } else {
                // Process first batch
                yield* processAndYieldBatch(result.data, lastId);
            }
            
            // Continue scrolling until no more results
            while (hasMoreRecords && scrollId) {
                const scrollResult = await sessionEventRepository.scroll(scrollId);
                
                if (scrollResult.data.length === 0) {
                    hasMoreRecords = false;
                } else {
                    // Process next batch
                    yield* processAndYieldBatch(scrollResult.data, lastId);
                    
                    // Update scroll ID for next request
                    scrollId = scrollResult.scrollId;
                }
            }
        } catch (error) {
            console.error("Error in streamSessionEvents:", error);
            // Re-throw the error to be handled by the caller
            throw error;
        } finally {
            // Clean up scroll context if we have a scrollId
            if (scrollId) {
                try {
                    await sessionEventRepository.clearScroll(scrollId);
                } catch (clearError) {
                    console.error("Error clearing scroll context:", clearError);
                }
            }
        }
        
        // Helper function to process and yield batches
        async function* processAndYieldBatch(data: SessionEventDocument[], lastIdFilter?: string) {
            // Filter by lastId if provided
            let batch = data;
            if (lastIdFilter !== undefined) {
                // Use createdAt timestamp for reliable ordering
                const lastEvent = await sessionEventRepository.findById(lastIdFilter);
                if (lastEvent && lastEvent.createdAt) {
                    // Filter events created after the lastId event
                    batch = batch.filter(event => 
                        event.id && 
                        event.id !== lastIdFilter && 
                        event.createdAt && 
                        new Date(event.createdAt) > new Date(lastEvent.createdAt)
                    );
                } else {
                    // Fallback to string comparison if event not found
                    batch = batch.filter(event => event.id && event.id > lastIdFilter);
                }
            }

            // Filter fields to return only essential data
            const filteredBatch = batch.map(event => ({
                id: event.id,
                destNumber: event.destNumber,
                searchText: event.searchText || "",
                transcription: event.transcription,
                explanation: event.explanation,
                topic: event.topic,
                sourceNumber: event.sourceNumber,
                date: event.date
            }));

            if (filteredBatch.length > 0) {
                yield filteredBatch;
            }
        }
    }
} 