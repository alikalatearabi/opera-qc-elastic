import type { Request, RequestHandler, Response } from "express";
import { ServiceResponse } from "@/common/models/serviceResponse";
import { handleServiceResponse } from "@/common/utils/httpHandlers";
import { StatusCodes } from "http-status-codes";
import moment from 'moment-jalaali';
import { Queue } from "bullmq";
import { env } from "@/common/utils/envConfig";
import { sessionEventRepository, type SearchFilters } from "@/common/utils/elasticsearchRepository";
import { addSequentialJob } from "@/queue/sequentialQueue";
import os from "node:os";
import fs from "node:fs";
import path from "node:path";

const sessionQueue = new Queue(env.BULL_QUEUE, {
    connection: {
        host: env.REDIS_HOST,
        port: Number(env.REDIS_PORT),
    }
});

export class SessionEventController {

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

            // Convert Persian date to Gregorian date
            // Handle different input formats: "YYYY-MM-DD HH:mm:ss" or ISO string
            const moment = require('moment-jalaali');
            let gregorianDate: Date;

            if (date.includes('T') && date.includes('Z')) {
                // ISO format like "1404-07-22T10:00:00.000Z" - treat as Persian date
                const dateOnly = date.split('T')[0]; // Extract YYYY-MM-DD part
                const [year, month, day] = dateOnly.split('-').map(Number);
                const persianMoment = moment(`${year}-${month}-${day}`, 'jYYYY-jM-jD');
                gregorianDate = persianMoment.toDate();
                console.log(`Converted Persian ISO date ${date} to Gregorian: ${gregorianDate.toISOString()}`);
            } else {
                // Original format: Persian YYYY-MM-DD HH:mm:ss
                const [persianDatePart, timePart] = date.split(' ');
                const [year, month, day] = persianDatePart.split('-').map(Number);
                const persianMoment = moment(`${year}-${month}-${day} ${timePart}`, 'jYYYY-jM-jD HH:mm:ss');
                gregorianDate = persianMoment.toDate();
                console.log(`Converted Persian date ${date} to Gregorian: ${gregorianDate.toISOString()}`);
            }

            // Add job to sequential queue instead of the regular queue
            const job = await addSequentialJob('process-session', {
                type,
                sourceChannel: source_channel,
                sourceNumber: source_number,
                queue,
                destChannel: dest_channel,
                destNumber: dest_number,
                date: gregorianDate,
                duration,
                filename,
                uniqueid,
                // Add these fields from the request if provided
                level: level || 30,
                time: time || new Date().getTime(),
                pid: pid || process.pid,
                hostname: hostname || os.hostname(),
                name: name || "session",
                msg: msg || "New call session"
            });

            console.log(`[API_CALL_QUEUED] Job queued successfully with ID: ${job.id}, filename: ${filename}, uniqueid: ${uniqueid || 'N/A'}`);

            return res.status(StatusCodes.OK).json({
                success: true,
                message: "Session event processing started (sequential processing)",
                data: {
                    jobId: job.id,
                    status: "waiting",
                    type
                },
                statusCode: StatusCodes.OK
            });
        } catch (error) {
            console.log(`[API_CALL_ERROR] Error creating session event: ${error}`);
            console.error('Error creating session event:', error);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                success: false,
                message: "Error processing session event",
                data: null,
                statusCode: StatusCodes.INTERNAL_SERVER_ERROR
            });
        }
    };

    public getSessionEventById: RequestHandler = async (req: Request, res: Response) => {
        const { id } = req.params;

        try {
            const sessionEvent = await sessionEventRepository.findById(id);

            if (!sessionEvent) {
                return handleServiceResponse(ServiceResponse.failure("Session event not found", {}, StatusCodes.NOT_FOUND), res);
            }

            // Format the response with only the requested fields
            const formattedEvent = {
                id: sessionEvent.id,
                destNumber: sessionEvent.destNumber,
                searchText: sessionEvent.searchText || "",
                transcription: sessionEvent.transcription,
                explanation: sessionEvent.explanation,
                topic: sessionEvent.topic,
                sourceNumber: sessionEvent.sourceNumber,
                date: sessionEvent.date
            };

            const serviceResponse = ServiceResponse.success("Session event retrieved successfully", formattedEvent);
            return handleServiceResponse(serviceResponse, res);
        } catch (error) {
            console.log(error);
            return handleServiceResponse(ServiceResponse.failure("Error fetching session event", error, StatusCodes.INTERNAL_SERVER_ERROR), res);
        }
    };

    public getSessions: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching sessions with pagination and filters...");

            // Extract pagination parameters from query
            const page = parseInt(req.query.page as string) || 1;
            const limit = parseInt(req.query.limit as string) || 10;

            // Extract filters from query
            const filters: SearchFilters = {};

            if (req.query.emotion) filters.emotion = req.query.emotion as string;
            if (req.query.category) filters.category = req.query.category as string;
            if (req.query.topic) filters.topic = req.query.topic as string;
            if (req.query.destNumber) filters.destNumber = req.query.destNumber as string;
            if (req.query.type) filters.type = req.query.type as 'incoming' | 'outgoing';
            if (req.query.searchText) filters.searchText = req.query.searchText as string;

            console.log("Pagination and filter params:", { page, limit, filters });

            // Search using Elasticsearch
            const result = await sessionEventRepository.search(filters, { page, limit });

            // Format sessions with only the requested fields
            const formattedSessions = result.data.map(event => ({
                id: event.id,
                destNumber: event.destNumber,
                searchText: event.searchText || "",
                transcription: event.transcription,
                explanation: event.explanation,
                topic: event.topic,
                sourceNumber: event.sourceNumber,
                date: event.date
            }));

            console.log("Fetched Sessions:", formattedSessions.length);

            // Add an additional check for empty results
            if (formattedSessions.length === 0) {
                return handleServiceResponse(
                    ServiceResponse.success(
                        "No processed session events found",
                        {
                            data: [],
                            pagination: {
                                currentPage: 1,
                                totalPages: 0,
                                totalItems: 0,
                                limit,
                                hasNextPage: false,
                                hasPrevPage: false,
                                appliedFilters: {
                                    emotion: filters.emotion || null,
                                    category: filters.category || null,
                                    topic: filters.topic || null,
                                    destNumber: filters.destNumber || null
                                }
                            }
                        }
                    ),
                    res
                );
            }

            // Create pagination metadata
            const pagination = {
                currentPage: result.page,
                totalPages: result.totalPages,
                totalItems: result.total,
                limit: result.limit,
                hasNextPage: result.page < result.totalPages,
                hasPrevPage: result.page > 1,
                appliedFilters: {
                    emotion: filters.emotion || null,
                    category: filters.category || null,
                    topic: filters.topic || null,
                    destNumber: filters.destNumber || null
                }
            };

            return handleServiceResponse(
                ServiceResponse.success(
                    "Session events retrieved successfully",
                    {
                        data: formattedSessions,
                        pagination
                    }
                ),
                res
            );

        } catch (error) {
            console.error("Error fetching session events:", error);
            return handleServiceResponse(
                ServiceResponse.failure("Error fetching session events", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getSessionsByFilter: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching dashboard data...");

            const responseData = await sessionEventRepository.getDashboardData();

            const serviceResponse = ServiceResponse.success("Session events retrieved successfully", responseData);
            return handleServiceResponse(serviceResponse, res);
        } catch (error) {
            console.error("Error in getSessionsByFilter:", error);
            return handleServiceResponse(ServiceResponse.failure("Error fetching session events", error, StatusCodes.INTERNAL_SERVER_ERROR), res);
        }
    };

    public getJobStatus = async (req: Request, res: Response) => {
        try {
            const { jobId } = req.params;

            if (!jobId) {
                return res.status(StatusCodes.BAD_REQUEST).json({
                    success: false,
                    message: "Job ID is required",
                    data: null,
                    statusCode: StatusCodes.BAD_REQUEST
                });
            }

            // First try to get job from the original queue
            let job = await sessionQueue.getJob(jobId);
            let queueType = "standard";

            // If not found, try the sequential queue
            if (!job) {
                const { sequentialQueue } = await import('@/queue/sequentialQueue');
                job = await sequentialQueue.getJob(jobId);
                queueType = "sequential";
            }

            if (!job) {
                return res.status(StatusCodes.NOT_FOUND).json({
                    success: false,
                    message: "Job not found in any queue",
                    data: null,
                    statusCode: StatusCodes.NOT_FOUND
                });
            }

            const state = await job.getState();
            const progress = job.progress;
            const result = job.returnvalue;
            const failedReason = job.failedReason;

            return res.status(StatusCodes.OK).json({
                success: true,
                message: "Job status retrieved successfully",
                data: {
                    jobId: job.id,
                    queueType,
                    state,
                    progress,
                    result,
                    failedReason
                },
                statusCode: StatusCodes.OK
            });
        } catch (error) {
            console.error('Error getting job status:', error);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                success: false,
                message: "Error retrieving job status",
                data: null,
                statusCode: StatusCodes.INTERNAL_SERVER_ERROR
            });
        }
    };

    public getDistinctCategories: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching distinct categories...");

            const categories = await sessionEventRepository.getDistinctCategories();

            console.log(`Found ${categories.length} distinct categories`);

            return handleServiceResponse(
                ServiceResponse.success(
                    "Categories retrieved successfully",
                    categories
                ),
                res
            );
        } catch (error) {
            console.error("Error fetching distinct categories:", error);
            return handleServiceResponse(
                ServiceResponse.failure("Error fetching categories", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getDistinctTopics: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching distinct topics (subtopics)...");

            const topics = await sessionEventRepository.getDistinctTopics();

            console.log(`Found ${topics.length} distinct topics`);

            return handleServiceResponse(
                ServiceResponse.success(
                    "Topics retrieved successfully",
                    topics
                ),
                res
            );
        } catch (error) {
            console.error("Error fetching distinct topics:", error);
            return handleServiceResponse(
                ServiceResponse.failure("Error fetching topics", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getDistinctDestNumbers: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching distinct destination numbers for incoming calls...");

            const destNumbers = await sessionEventRepository.getDistinctDestNumbers();

            console.log(`Found ${destNumbers.length} distinct destination numbers for incoming calls`);

            return handleServiceResponse(
                ServiceResponse.success(
                    "Destination numbers for incoming calls retrieved successfully",
                    destNumbers
                ),
                res
            );
        } catch (error) {
            console.error("Error fetching distinct destination numbers:", error);
            return handleServiceResponse(
                ServiceResponse.failure("Error fetching destination numbers", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getSessionStats: RequestHandler = async (req: Request, res: Response) => {
        try {
            console.log("Fetching session statistics...");

            const stats = await sessionEventRepository.getStats();

            console.log("Statistics fetched successfully:", stats);

            return handleServiceResponse(
                ServiceResponse.success("Session statistics retrieved successfully", stats),
                res
            );
        } catch (error) {
            console.error("Error fetching session statistics:", error);
            return handleServiceResponse(
                ServiceResponse.failure("Error fetching session statistics", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getSessionsByPersianDate: RequestHandler = async (req: Request, res: Response) => {
        try {
            const { date } = req.params;
            console.log(`Fetching sessions for Persian date: ${date}`);

            // Extract pagination parameters from query
            const page = parseInt(req.query.page as string) || 1;
            const limit = parseInt(req.query.limit as string) || 10;
            const includeUnprocessed = req.query.includeUnprocessed === 'true'; // Debug parameter

            // Validate Persian date format (DD-MM-YYYY)
            const dateRegex = /^\d{1,2}-\d{1,2}-\d{4}$/;
            if (!dateRegex.test(date)) {
                return handleServiceResponse(
                    ServiceResponse.failure("Invalid date format. Use DD-MM-YYYY format (e.g., 22-7-1404)", {}, StatusCodes.BAD_REQUEST),
                    res
                );
            }

            // Parse Persian date components and create date string for exact match
            const [day, month, year] = date.split('-').map(Number);
            const persianDateString = `${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;

            console.log(`Searching for exact Persian date match: ${persianDateString}`);

            // Extract additional filters from query (same as getSessions)
            const filters: SearchFilters = {
                persianDate: persianDateString // Use exact Persian date match instead of Gregorian range
            };

            if (req.query.emotion) filters.emotion = req.query.emotion as string;
            if (req.query.category) filters.category = req.query.category as string;
            if (req.query.topic) filters.topic = req.query.topic as string;
            if (req.query.destNumber) filters.destNumber = req.query.destNumber as string;
            if (req.query.type) filters.type = req.query.type as 'incoming' | 'outgoing';
            if (req.query.searchText) filters.searchText = req.query.searchText as string;

            console.log("Date filter and additional params:", { date, persianDateString, page, limit, filters, includeUnprocessed });

            // Search using Elasticsearch - conditionally include transcription requirement
            const result = await sessionEventRepository.search(filters, { page, limit }, includeUnprocessed);

            // Format sessions with only the requested fields (same as getSessions)
            const formattedSessions = result.data.map(event => ({
                id: event.id,
                destNumber: event.destNumber,
                searchText: event.searchText || "",
                transcription: event.transcription,
                explanation: event.explanation,
                topic: event.topic,
                sourceNumber: event.sourceNumber,
                date: event.date,
                type: event.type,
                filename: event.filename,
                hasTranscription: !!event.transcription
            }));

            console.log(`Fetched ${formattedSessions.length} sessions for Persian date ${date} (includeUnprocessed: ${includeUnprocessed})`);

            // Handle empty results
            if (formattedSessions.length === 0) {
                const message = includeUnprocessed
                    ? `No session events found for Persian date ${date} (including unprocessed)`
                    : `No processed session events found for Persian date ${date}`;
                return handleServiceResponse(
                    ServiceResponse.success(
                        message,
                        {
                            data: [],
                            pagination: {
                                currentPage: 1,
                                totalPages: 0,
                                totalItems: 0,
                                limit,
                                hasNextPage: false,
                                hasPrevPage: false,
                                appliedFilters: {
                                    persianDate: date,
                                    emotion: filters.emotion || null,
                                    category: filters.category || null,
                                    topic: filters.topic || null,
                                    destNumber: filters.destNumber || null,
                                    includeUnprocessed
                                }
                            }
                        }
                    ),
                    res
                );
            }

            // Create pagination metadata
            const pagination = {
                currentPage: result.page,
                totalPages: result.totalPages,
                totalItems: result.total,
                limit: result.limit,
                hasNextPage: result.page < result.totalPages,
                hasPrevPage: result.page > 1,
                appliedFilters: {
                    persianDate: date,
                    emotion: filters.emotion || null,
                    category: filters.category || null,
                    topic: filters.topic || null,
                    destNumber: filters.destNumber || null,
                    includeUnprocessed
                }
            };

            const message = includeUnprocessed
                ? `Session events for Persian date ${date} retrieved successfully (including unprocessed)`
                : `Session events for Persian date ${date} retrieved successfully`;

            return handleServiceResponse(
                ServiceResponse.success(
                    message,
                    {
                        data: formattedSessions,
                        pagination
                    }
                ),
                res
            );

        } catch (error) {
            console.error(`Error fetching sessions for Persian date ${req.params.date}:`, error);
            return handleServiceResponse(
                ServiceResponse.failure(`Error fetching session events for date ${req.params.date}`, error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public getAudioFile: RequestHandler = async (req: Request, res: Response) => {
        try {
            const filename = req.params.filename;

            // Validate the filename to prevent directory traversal attacks
            if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
                return handleServiceResponse(
                    ServiceResponse.failure("Invalid filename", {}, StatusCodes.BAD_REQUEST),
                    res
                );
            }

            // Directory where audio files are stored (configure via AUDIO_DIR env or default to ./conversations)
            const audioDirectory = process.env.AUDIO_DIR || path.join(process.cwd(), 'conversations');
            let filePath = path.join(audioDirectory, filename);

            console.log(`Attempting to access audio file: ${filePath}`);

            // Check if directory exists
            if (!fs.existsSync(audioDirectory)) {
                console.error(`Audio directory does not exist: ${audioDirectory}`);
                return handleServiceResponse(
                    ServiceResponse.failure("Audio directory not found", {}, StatusCodes.NOT_FOUND),
                    res
                );
            }

            // List files in the directory to help with debugging
            try {
                const files = fs.readdirSync(audioDirectory);
                console.log(`Files in ${audioDirectory}:`, files.slice(0, 10)); // Show first 10 files
                console.log(`Total files in directory: ${files.length}`);

                // Check if the file exists with case-insensitive search
                const fileExists = files.some(file => file.toLowerCase() === filename.toLowerCase());
                if (fileExists) {
                    console.log(`File exists with different case sensitivity`);
                    // Find the actual filename with correct case
                    const actualFilename = files.find(file => file.toLowerCase() === filename.toLowerCase());
                    if (actualFilename) {
                        console.log(`Using actual filename: ${actualFilename}`);
                        // Update the file path with the correct case
                        filePath = path.join(audioDirectory, actualFilename);
                    }
                }
            } catch (err) {
                console.error(`Error reading directory: ${audioDirectory}`, err);
            }

            // Check if the file exists
            if (!fs.existsSync(filePath)) {
                console.error(`Audio file not found: ${filePath}`);
                return handleServiceResponse(
                    ServiceResponse.failure(`Audio file not found: ${filename}`, {}, StatusCodes.NOT_FOUND),
                    res
                );
            }

            console.log(`File found, preparing to stream: ${filePath}`);

            // Set the appropriate headers
            res.setHeader('Content-Type', 'audio/wav');
            res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

            // Create a read stream and pipe it to the response
            const fileStream = fs.createReadStream(filePath);
            fileStream.pipe(res);

            // Handle errors on the stream
            fileStream.on('error', (error) => {
                console.error(`Error streaming audio file ${filename}:`, error);
                if (!res.headersSent) {
                    handleServiceResponse(
                        ServiceResponse.failure("Error streaming audio file", error, StatusCodes.INTERNAL_SERVER_ERROR),
                        res
                    );
                }
            });
        } catch (error) {
            console.error(`Error serving audio file:`, error);
            return handleServiceResponse(
                ServiceResponse.failure("Error serving audio file", error, StatusCodes.INTERNAL_SERVER_ERROR),
                res
            );
        }
    };

    public checkAudioFile: RequestHandler = async (req: Request, res: Response) => {
        try {
            const filename = req.params.filename;

            // Validate the filename
            if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
                return res.json({
                    status: 'error',
                    message: 'Invalid filename',
                    details: {
                        filename,
                        validation: 'failed'
                    }
                });
            }

            const audioDirectory = '/home/afeai/conversations';
            const filePath = path.join(audioDirectory, filename);

            // Check directory
            const dirExists = fs.existsSync(audioDirectory);
            let dirStats: fs.Stats | null = null;
            let dirPermissions: string | null = null;
            let directoryFiles: string[] = [];

            if (dirExists) {
                try {
                    dirStats = fs.statSync(audioDirectory);
                    dirPermissions = '0' + (dirStats.mode & parseInt('777', 8)).toString(8);

                    // List files that match similar pattern to help debugging
                    const allFiles = fs.readdirSync(audioDirectory);
                    // Get first 20 files and any that are similar to the requested filename
                    directoryFiles = allFiles
                        .filter(file => file.includes(filename.split('-')[0]) || directoryFiles.length < 20)
                        .slice(0, 20);
                } catch (error) {
                    console.error('Error getting directory info:', error);
                }
            }

            // Check file existence
            const fileExists = fs.existsSync(filePath);
            let fileStats: fs.Stats | null = null;
            let filePermissions: string | null = null;
            let fileContent: string | null = null;

            if (fileExists) {
                try {
                    fileStats = fs.statSync(filePath);
                    filePermissions = '0' + (fileStats.mode & parseInt('777', 8)).toString(8);

                    // Try to access file
                    try {
                        // Read just the first 100 bytes to check if we can access the file
                        const fd = fs.openSync(filePath, 'r');
                        const buffer = Buffer.alloc(100);
                        fs.readSync(fd, buffer, 0, 100, 0);
                        fs.closeSync(fd);
                        fileContent = 'First 100 bytes readable';
                    } catch (readError: any) {
                        fileContent = `Error reading file: ${readError.message}`;
                    }
                } catch (error) {
                    console.error('Error getting file info:', error);
                }
            }

            // Check for similar files (case insensitive)
            let similarFile: { name: string; exactMatch: boolean; caseDifference: boolean } | null = null;
            if (dirExists && !fileExists) {
                try {
                    const files = fs.readdirSync(audioDirectory);
                    const match = files.find(file => file.toLowerCase() === filename.toLowerCase());
                    if (match) {
                        similarFile = {
                            name: match,
                            exactMatch: match === filename,
                            caseDifference: match !== filename
                        };
                    }
                } catch (error) {
                    console.error('Error looking for similar files:', error);
                }
            }

            // Check process permissions
            const processInfo = {
                uid: process.getuid ? process.getuid() : 'Not available',
                gid: process.getgid ? process.getgid() : 'Not available',
                cwd: process.cwd(),
                execPath: process.execPath
            };

            // Check directory readability
            let dirReadable = false;
            try {
                fs.accessSync(audioDirectory, fs.constants.R_OK);
                dirReadable = true;
            } catch (err) {
                dirReadable = false;
            }

            return res.json({
                status: 'success',
                diagnostics: {
                    requestedFile: {
                        filename,
                        fullPath: filePath
                    },
                    directory: {
                        path: audioDirectory,
                        exists: dirExists,
                        stats: dirStats,
                        permissions: dirPermissions,
                        readable: dirReadable,
                        sampleFiles: directoryFiles
                    },
                    file: {
                        exists: fileExists,
                        stats: fileStats,
                        permissions: filePermissions,
                        sizeBytes: fileExists && fileStats ? fileStats.size : null,
                        readable: fileContent !== null,
                        content: fileContent
                    },
                    similarFile,
                    process: processInfo
                }
            });
        } catch (error: any) {
            console.error('Error in checkAudioFile:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Server error checking audio file',
                error: {
                    message: error.message,
                    stack: error.stack
                }
            });
        }
    };
}

export const sessionEventController = new SessionEventController();
