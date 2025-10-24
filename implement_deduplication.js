// Deduplication Implementation for SessionEventController
// This code can be added to your sessionElastic.ts file to prevent duplicate processing

// Add this at the top of your SessionEventController class
class SessionEventController {
    // In-memory cache for recent filenames (with TTL)
    private recentFilenames = new Map<string, number>();
    private readonly DEDUP_TTL = 5 * 60 * 1000; // 5 minutes TTL

    // Method to check if filename was recently processed
    private isDuplicateFilename(filename: string): boolean {
        const now = Date.now();
        const lastProcessed = this.recentFilenames.get(filename);
        
        if (lastProcessed && (now - lastProcessed) < this.DEDUP_TTL) {
            return true;
        }
        
        // Update the timestamp
        this.recentFilenames.set(filename, now);
        
        // Clean up old entries
        this.cleanupOldEntries(now);
        
        return false;
    }

    // Clean up old entries from memory
    private cleanupOldEntries(now: number): void {
        for (const [filename, timestamp] of this.recentFilenames.entries()) {
            if (now - timestamp > this.DEDUP_TTL) {
                this.recentFilenames.delete(filename);
            }
        }
    }

    // Enhanced createSessionEvent method with deduplication
    public createSessionEvent = async (req: Request, res: Response) => {
        try {
            // Log every API call received
            console.log(`[API_CALL_RECEIVED] sessionReceived endpoint called at ${new Date().toISOString()}`);

            const {
                type,
                source_channel,
                source_number,
                queue,
                dest_channel,
                dest_number,
                date,
                duration,
                filename,
                uniqueid,
                level,
                time,
                pid,
                hostname,
                name,
                msg
            } = req.body;

            // Log the call details
            console.log(`[API_CALL_DETAILS] Type: ${type}, Filename: ${filename}, Date: ${date}, Source: ${source_number}, Dest: ${dest_number}, UniqueID: ${uniqueid || 'N/A'}`);

            // Validate required fields
            if (!type || !source_channel || !source_number || !queue || !dest_channel || !dest_number || !date || !duration || !filename) {
                console.log(`[API_CALL_REJECTED] Missing required fields for filename: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);
                return res.status(StatusCodes.BAD_REQUEST).json({
                    success: false,
                    message: "Missing required fields",
                    data: null,
                    statusCode: StatusCodes.BAD_REQUEST
                });
            }

            // DEDUPLICATION CHECK - Add this before processing
            if (this.isDuplicateFilename(filename)) {
                console.log(`[API_CALL_DUPLICATE] Duplicate filename detected: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);
                return res.status(StatusCodes.OK).json({
                    success: true,
                    message: "Duplicate call detected and skipped",
                    data: {
                        type,
                        filename,
                        processed: false,
                        reason: "duplicate"
                    },
                    statusCode: StatusCodes.OK
                });
            }

            // Check if the call is incoming, otherwise skip processing
            if (type !== 'incoming') {
                console.log(`[API_CALL_SKIPPED] Non-incoming call type: ${type}, filename: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);
                return res.status(StatusCodes.OK).json({
                    success: true,
                    message: "Non-incoming call received. No processing performed.",
                    data: {
                        type,
                        processed: false
                    },
                    statusCode: StatusCodes.OK
                });
            }

            console.log(`[API_CALL_ACCEPTED] Processing incoming call, filename: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);

            // Rest of your existing processing logic...
            // ... (keep all your existing code here)

        } catch (error) {
            console.error(`[API_CALL_ERROR] Error processing session event:`, error);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                success: false,
                message: "Internal server error",
                data: null,
                statusCode: StatusCodes.INTERNAL_SERVER_ERROR
            });
        }
    }
}

// Alternative: Database-based deduplication (more robust for production)
// Add this method to check database for existing records
private async checkDatabaseDuplicate(filename: string): Promise<boolean> {
    try {
        const existingRecord = await sessionEventRepository.findByFilename(filename);
        return existingRecord !== null;
    } catch (error) {
        console.error('Error checking database duplicate:', error);
        return false; // If we can't check, allow processing
    }
}

// Usage in createSessionEvent method:
// Replace the in-memory deduplication with:
if (await this.checkDatabaseDuplicate(filename)) {
    console.log(`[API_CALL_DUPLICATE] Duplicate filename found in database: ${filename}`);
    return res.status(StatusCodes.OK).json({
        success: true,
        message: "Duplicate call detected and skipped",
        data: {
            type,
            filename,
            processed: false,
            reason: "duplicate_in_database"
        },
        statusCode: StatusCodes.OK
    });
}
