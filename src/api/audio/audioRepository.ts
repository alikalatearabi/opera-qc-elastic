import { sessionEventRepository, type SessionEventDocument } from "@/common/utils/elasticsearchRepository";

export class AudioRepository {
    /**
     * Gets all session events from Elasticsearch with only essential fields
     */
    public static async getAllSessionEvents() {
        const result = await sessionEventRepository.search({}, { page: 1, limit: 10000 });
        return result.data.map(event => ({
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
     * Gets session events with ID greater than the provided lastId with only essential fields
     * @param lastId The ID to start from (exclusive)
     */
    public static async getSessionEventsAfterLastId(lastId: string) {
        // For Elasticsearch, we'll use a different approach since IDs are strings
        // We'll use the _source.createdAt field for ordering
        const result = await sessionEventRepository.search({}, { page: 1, limit: 10000 });
        return result.data
            .filter(event => event.id && event.id > lastId)
            .map(event => ({
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
     * @param lastId Optional ID to start from (exclusive)
     * @param batchSize Number of records to fetch per batch
     */
    public static async *streamSessionEvents(lastId: string | undefined = undefined, batchSize = 1000) {
        let currentPage = 1;
        let hasMoreRecords = true;

        while (hasMoreRecords) {
            const result = await sessionEventRepository.search({}, {
                page: currentPage,
                limit: batchSize
            });

            if (result.data.length === 0) {
                hasMoreRecords = false;
            } else {
                // Filter by lastId if provided
                let batch = result.data;
                if (lastId !== undefined) {
                    batch = batch.filter(event => event.id && event.id > lastId);
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

                // Check if we've reached the end
                if (result.data.length < batchSize) {
                    hasMoreRecords = false;
                } else {
                    currentPage++;
                }
            }
        }
    }
} 