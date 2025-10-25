# Deduplication Plan for Call Processing

## Current Situation

**External API sends calls with:**
- `filename` - Primary identifier (e.g., `14040803-103456-09358907000-1200`)
- `uniqueid` - Optional unique identifier
- `type` - "incoming" or "outgoing" (only incoming are processed)
- Other fields: source_number, dest_number, date, duration, etc.

**Current Problem:**
- No deduplication checks exist
- External API may retry/send duplicates
- Same call can be processed multiple times

## Deduplication Strategy

### Option 1: Filename-Based Deduplication (Recommended)
**Most reliable** because filename is unique per call.

**Implementation:**
1. Check Elasticsearch for existing filename
2. If exists within last 24 hours → Skip
3. If not exists → Process normally

**Pros:**
- Simple and reliable
- Filename is the most stable identifier
- Fast Elasticsearch lookup

**Cons:**
- Requires Elasticsearch query (adds ~10-50ms)

### Option 2: Compound Key Deduplication
Use combination of: `source_number` + `dest_number` + `date` + `duration`

**Pros:**
- Works even if filename changes

**Cons:**
- More complex
- Slower (more fields to check)
- Date/duration must match exactly

### Option 3: In-Memory Cache (Quick Fix)
Keep recent filenames in memory with TTL (e.g., 5 minutes)

**Pros:**
- Very fast (< 1ms)
- No external queries

**Cons:**
- Not persistent (lost on restart)
- Memory limited
- Doesn't work across multiple server instances

## Recommended Implementation

### Phase 1: Elasticsearch-Based Deduplication (Primary)

Add check in `src/api/session/sessionElastic.ts`:

```typescript
// Before processing, check if filename exists in Elasticsearch
const existingRecord = await sessionEventRepository.findByFilename(filename);

if (existingRecord && isRecentRecord(existingRecord, 24)) { // Last 24 hours
    console.log(`[API_CALL_DUPLICATE] Duplicate filename: ${filename}`);
    return res.status(200).json({
        success: true,
        message: "Duplicate call detected and skipped",
        data: { type, filename, processed: false, reason: "duplicate" },
        statusCode: 200
    });
}
```

### Phase 2: Add Repository Method

Add to `src/common/utils/elasticsearchRepository.ts`:

```typescript
async findByFilename(filename: string, hoursWindow: number = 24): Promise<SessionEventDocument | null> {
    const cutoffDate = new Date();
    cutoffDate.setHours(cutoffDate.getHours() - hoursWindow);
    
    const response = await elasticsearchClient.search({
        index: this.indexName,
        body: {
            query: {
                bool: {
                    must: [
                        { term: { "filename.keyword": filename } },
                        { range: { date: { gte: cutoffDate.toISOString() } } }
                    ]
                }
            }
        },
        size: 1
    });
    
    if (response.hits.hits.length > 0) {
        return { id: response.hits.hits[0]._id, ...response.hits.hits[0]._source };
    }
    return null;
}
```

### Phase 3: Add In-Memory Cache (Optional, for extra speed)

Add Redis-based cache for super-fast lookups:

```typescript
// Check Redis cache first (very fast)
const cacheKey = `call:${filename}`;
const cached = await redisClient.get(cacheKey);
if (cached) {
    return duplicate_response;
}

// Then check Elasticsearch
const existing = await sessionEventRepository.findByFilename(filename);

if (existing) {
    // Cache for 5 minutes
    await redisClient.setex(cacheKey, 300, '1');
    return duplicate_response;
}
```

## Testing Plan

1. **Unit Test:** Check deduplication logic
2. **Integration Test:** Send same call twice, verify second is skipped
3. **Load Test:** Ensure deduplication doesn't slow down high-volume processing
4. **Edge Cases:** 
   - Calls older than 24 hours should be allowed
   - Missing fields should be handled gracefully

## Monitoring

Add metrics:
- `duplicates_detected_total` - Counter for duplicates
- `dedup_check_duration_ms` - Time taken for dedup checks

## Rollout Plan

1. **Week 1:** Add Elasticsearch-based deduplication (Phase 1)
2. **Week 2:** Monitor performance and accuracy
3. **Week 3:** Add Redis cache if needed (Phase 3)
4. **Week 4:** Document and optimize

## Alternative: Upstream Fix

**Best Solution:** Fix at the source - Configure external API to not retry/resend duplicates.

But this deduplication is a good safety net regardless.
