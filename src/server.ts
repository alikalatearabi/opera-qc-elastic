import cors from "cors";
import express, { type Express } from "express";
import helmet from "helmet";
import { pino } from "pino";

import { openAPIRouter } from "@/api-docs/openAPIRouter";
import { userRouter } from "@/api/user/userRouter";
import errorHandler from "@/common/middleware/errorHandler";
import rateLimiter from "@/common/middleware/rateLimiter";
import requestLogger from "@/common/middleware/requestLogger";
import { env } from "@/common/utils/envConfig";
import { initializeElasticsearch } from "@/common/utils/elasticsearchClient";
import passport from "passport";
import { authRouter } from "./api/auth/authRouter";
import { passportConfig } from "./auth";
import { sessionEventRouter } from "@/api/session/sessionRouter";
import expressBasicAuth from "express-basic-auth";
import { sessionWorker } from '@/queue/sessionQueue';
import { sequentialWorker } from '@/queue/sequentialQueue';
import { transcriptionWorker } from '@/queue/transcriptionQueue';
import { sequentialRouter } from "@/api/sequential/sequentialRouter";
import { audioRouter } from "./api/audio/audioRouter";

const logger = pino({ name: "server start" });
const app: Express = express();
console.log("Swagger URL:", env.SWAGGER_URL);

// Initialize Elasticsearch connection
initializeElasticsearch()
    .then(() => {
        logger.info("Elasticsearch connection initialized");
    })
    .catch((error) => {
        logger.error("Failed to initialize Elasticsearch connection:", error);
    });

// Set the application to trust the reverse proxy
app.set("trust proxy", true);

// Setting up authentication handler
app.use(passport.initialize());
passport.use(passportConfig);

// Middlewares
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
// Configure CORS to allow all origins
app.use(cors({
    origin: function (origin, callback) {
        // Allow requests with no origin (like mobile apps, curl requests)
        if (!origin) return callback(null, true);

        const allowedOrigins = env.CORS_ORIGIN.split(',');
        if (allowedOrigins.indexOf(origin) !== -1 || allowedOrigins.includes('*')) {
            return callback(null, true);
        } else {
            return callback(null, true); // Allow all origins during development
            // For production: return callback(new Error('Not allowed by CORS'), false);
        }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true
}));
app.use(rateLimiter);

// Request logging
app.use(requestLogger);

// Routes
app.use("/api/auth", authRouter);
app.use("/api/users", passport.authenticate("jwt", { session: false }), userRouter);
// app.use("/api/sessions", passport.authenticate("jwt", { session: false }), sessionEventRouter);
app.use("/api/event", sessionEventRouter);
app.use("/api/sequential", sequentialRouter);
app.use("/api/audio", audioRouter); // Basic auth is handled within the router
// Swagger UI
app.use("/api/docs", openAPIRouter);
app.use(helmet());

// Error handlers
app.use(errorHandler());

// Initialize queue worker
sessionWorker.on('completed', (job: any) => {
    console.log(`Job ${job.id} completed successfully`);
});

sessionWorker.on('failed', (job: any, err: any) => {
    console.error(`Job ${job?.id} failed with error:`, err);
});

// No need to set up event handlers for sequential worker here
// as they are already defined in the sequentialQueue.ts file

// Initialize transcription worker
transcriptionWorker.on('completed', (job: any) => {
    console.log(`Transcription job ${job.id} completed successfully`);
});

transcriptionWorker.on('failed', (job: any, err: any) => {
    console.error(`Transcription job ${job?.id} failed with error:`, err);
});

export { app, logger };
