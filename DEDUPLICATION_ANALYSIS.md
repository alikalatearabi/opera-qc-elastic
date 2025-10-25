# Duplication Root Cause Analysis & Improvement Plan

## Executive Summary

**Problem:** Each filename appears exactly **6 times** in Elasticsearch, indicating a systematic duplication issue.

**Root Cause:** The deduplication logic was added AFTER the duplicates were created. The external API is likely sending the same calls multiple times, possibly due to:
1. Their retry/error recovery mechanism
2. Network timeouts
3. Their own internal queue retries

## Root Cause Analysis

### 1. **External API Behavior**
- External API sends POST requests to `/api/event/sessionReceived`
- **No rate limiting** on this endpoint (line 39 of `rateLimiter.ts` explicitly skips it)
- If our API is slow to respond or times out, the external API likely retries
- No deduplication existed before recent code changes

### 2. **Current Deduplication Logic** (Added Recently)
Located in `src/api/session/sessionElastic.ts` lines 80-99:

```typescript
// DEDUPLICATION CHECK: Check if this filename was already processed
try {
    const existingRecord = await sessionEventRepository.findByFilename(filename, 24);
    if (existingRecord) {
        console.log(`[API_CALL_DUPLICATE] Duplicate filename detected: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);
        return res.status(StatusCodes.OK).json({
            success: true,
            message: "Duplicate call detected and skipped",
            // ...
        });
    }
} catch (dedupError) {
    // Log error but don't block processing if deduplication check fails
    console.error(`[DEDUP_ERROR] Error checking for duplicates: ${dedupError}`);
}
```

**Problem:** This checks the database AFTER the request is received. If the external API sends 6 requests rapidly (within milliseconds), all 6 might pass the check simultaneously before any are written to the database.

### 3. **Race Condition**
Timeline of events when external API sends 6 identical requests:

```
Time 0ms:  Request 1 arrives → Check database (empty) → Allow
Time 1ms:  Request 2 arrives → Check database (empty) → Allow
Time 2ms:  Request 3 arrives → Check database (empty) → Allow
Time 3ms:  Request 4 arrives → Check database (empty) → Allow
Time 4ms:  Request 5 arrives → Check database (empty) → Allow
Time 5ms:  Request 6 arrives → Check database (empty) → Allow
...
Time 100ms: All 6 queries write to database
```

**Result:** All 6 create duplicate records because the check happened before any writes completed.

### 4. **Why Exactly 6 Times?**
Possible explanations:
- External API retries on 5xx errors (5 retries + 1 original = 6)
- External API has a retry queue with 5 workers (6 total instances)
- Network proxy/router retries exactly 5 times
- Load balancer retry configuration

## Improvement Plan

### ✅ Phase 1: Remove Existing Duplicates (DONE)
- Script: `remove-duplicates.py`
- Keeps oldest record for each filename
- Deletes all duplicates

### ✅ Phase 2: Add Database Check (DONE)
- Current implementation in `sessionElastic.ts`
- Uses `findByFilename()` with 24-hour window

### 🔄 Phase 3: Fix Race Condition (RECOMMENDED)

#### Option A: Database-Level Uniqueness Constraint (Best)
**Elasticsearch doesn't support unique constraints directly.** We need to:

1. **Add application-level lock using Redis:**
```typescript
async function acquireLock(filename: string): Promise<boolean> {
    const lockKey = `process_lock:${filename}`;
    const result = await redis.set(lockKey, '1', 'EX', 5, 'NX');
    return result === 'OK';
}

// In createSessionEvent:
if (!await acquireLock(filename)) {
    console.log(`[LOCK_FAILED] Another process is handling this filename: ${filename}`);
    return res.status(StatusCodes.CONFLICT).json({
        success: false,
        message: "Processing already in progress",
        reason: "duplicate_request"
    });
}

try {
    // Process the request
} finally {
    await redis.del(`process_lock:${filename}`);
}
```

#### Option B: Idempotency Key Pattern
```typescript
// Client sends an idempotency key
const idempotencyKey = req.headers['idempotency-key'] || filename;

// Store processed keys in Redis with TTL
const processed = await redis.get(`idempotent:${idempotencyKey}`);
if (processed) {
    return res.json({ success: true, message: "Already processed", cached: true });
}

// Mark as processed before actual processing
await redis.set(`idempotent:${idempotencyKey}`, '1', 'EX', 3600);
```

#### Option C: Optimistic Locking
```typescript
// Use Elasticsearch's `if_seq_no` and `if_primary_term` for optimistic locking
const response = await elasticsearchClient.index({
    index: this.indexName,
    body: document,
    op_type: 'create', // Fail if document already exists
    id: filename // Use filename as document ID
});

// If document with this ID already exists, Elasticsearch returns 409 Conflict
```

### 📊 Phase 4: Monitoring & Alerts

Add metrics to track:
1. Duplicate detection rate
2. Lock acquisition failures
3. External API retry patterns

```typescript
// Track metrics
console.log(`[METRICS] Duplicate rate: ${duplicates}/${total} (${rate}%)`);
```

### 🔍 Phase 5: External API Investigation

Contact external API team to understand:
1. Why they retry exactly 5 times
2. Can they add idempotency headers?
3. What triggers their retries?
4. Can we configure a longer timeout?

## Recommended Immediate Actions

1. **Implement Redis lock** (Option A) - Most robust
2. **Remove existing duplicates** using `remove-duplicates.py`
3. **Monitor logs** for `[API_CALL_DUPLICATE]` messages
4. **Contact external API team** to discuss their retry logic

## Code Quality Improvements

### 1. Error Handling
```typescript
// Better error handling in deduplication
try {
    const existingRecord = await sessionEventRepository.findByFilename(filename, 24);
    if (existingRecord) {
        // Log with more context
        logger.warn('Duplicate detected', {
            filename,
            existingId: existingRecord.id,
            existingDate: existingRecord.date,
            newRequestDate: date
        });
        return duplicateResponse;
    }
} catch (dedupError) {
    // Fail-safe: Allow processing if check fails
    logger.error('Dedup check failed', { error: dedupError, filename });
    // Continue processing - better to have duplicates than miss calls
}
```

### 2. Logging Improvements
```typescript
// Add structured logging
console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    event: 'API_CALL_RECEIVED',
    filename,
    uniqueid,
    ip: req.ip,
    userAgent: req.get('user-agent')
}));
```

### 3. Database Optimization
- Add index on `filename` field in Elasticsearch (already exists as `keyword`)
- Consider using filename as document `_id` for guaranteed uniqueness

## Conclusion

**The problem is a combination of:**
1. External API sending duplicate requests (likely retries)
2. Race condition in deduplication check
3. No database-level uniqueness constraint

**The solution requires:**
1. Application-level locking (Redis)
2. Better idempotency handling
3. Cooperation with external API team

The current deduplication logic is a good start but insufficient for concurrent requests. The Redis lock pattern will solve this definitively.
