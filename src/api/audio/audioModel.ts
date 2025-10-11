import { extendZodWithOpenApi } from "@asteasolutions/zod-to-openapi";
import { z } from "zod";

extendZodWithOpenApi(z);

// Schema for session event data with only essential fields
export const SessionEventSchema = z.object({
    id: z.string(),
    destNumber: z.string(),
    searchText: z.string(),
    transcription: z.any().nullable().optional(),
    explanation: z.string().nullable().optional(),
    topic: z.any().nullable().optional(),
    sourceNumber: z.string(),
    date: z.string().datetime(),
});

// Query parameter schema for lastId parameter
export const AudioQueryParamSchema = z.object({
    lastId: z.string().optional(), // Keep as string for Elasticsearch IDs
    batchSize: z.string().optional().transform((val) => (val ? parseInt(val, 10) : 1000)),
});

// Response schema for multiple session events
export const SessionEventsResponseSchema = z.object({
    data: z.array(SessionEventSchema),
}); 