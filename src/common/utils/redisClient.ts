import Redis from "ioredis";

import { env } from "@/common/utils/envConfig";

export const redisClient = new Redis({
    host: env.REDIS_HOST,
    port: Number(env.REDIS_PORT),
});

redisClient.on("error", (error) => {
    console.error("Redis connection error:", error);
});

redisClient.on("connect", () => {
    console.log("Redis client connected");
});

export const disconnectRedis = async () => {
    if (redisClient.status !== "end") {
        await redisClient.quit();
    }
};

