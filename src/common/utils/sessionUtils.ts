import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import path from "node:path";
import fs from "node:fs";
import { downloadAndSaveAudio } from "@/common/utils/downloadFileStream";
import FormData from "form-data";
import axios from "axios";
import { env } from "@/common/utils/envConfig";

// Fix MinIO endpoint configuration - add protocol if missing
const getMinioEndpoint = () => {
    const endpoint = env.MINIO_ENDPOINT_UTL;
    // envConfig.ts ensures protocol is present
    return endpoint;
};

const s3Client = new S3Client({
    region: "us-east-1",
    endpoint: getMinioEndpoint(),
    credentials: {
        accessKeyId: env.MINIO_ACCESS_KEY,
        secretAccessKey: env.MINIO_SECRET_KEY,
    },
    forcePathStyle: true,
    tls: false,
});

const BUCKET_NAME = process.env.MINIO_BUCKET_NAME || "audio-files";

// Export the functions that will be used by the queue workers
export const sendAudioRequests = async (fileName: string, type: "incoming" | "outgoing", filePath: string) => {
    const username = "Tipax";
    const password = "Goz@r!SimotelTip@x!1404";
    const auth = {
        username,
        password,
    };

    try {
        const dir = path.dirname(filePath);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        await downloadAndSaveAudio(`${fileName}`, filePath, auth);

    } catch (error) {
        console.error("Error sending audio requests:", error);
    }
};

export const uploadToMinIO = async (filePath: string, objectName: string) => {
    try {
        if (!fs.existsSync(filePath)) {
            console.error(`File not found: ${filePath}`);
            return null;
        }

        const fileStream = fs.createReadStream(filePath);
        const stats = fs.statSync(filePath);

        const command = new PutObjectCommand({
            Bucket: BUCKET_NAME,
            Key: objectName,
            Body: fileStream,
            ContentType: "audio/wav",
            ContentLength: stats.size
        });

        await s3Client.send(command);

        // Return MinIO URL
        return `/${BUCKET_NAME}/${objectName}`;
    } catch (error) {
        console.error("Error uploading to MinIO:", error);
        return null;
    }
};

export const sendFilesToTranscriptionAPI = async (filePathIn: string, filePathOut: string) => {
    try {
        if (!fs.existsSync(filePathIn) || !fs.existsSync(filePathOut)) {
            console.error(`One or both files not found: ${filePathIn}, ${filePathOut}`);
            return null;
        }

        const form = new FormData();

        // Get file stats (size) to help FormData handle streams
        const fileStatIn = fs.statSync(filePathIn);
        const fileStatOut = fs.statSync(filePathOut);

        form.append("customer", fs.createReadStream(filePathIn));
        form.append("agent", fs.createReadStream(filePathOut));

        // Updated endpoint URL
        const response = await axios.post("http://31.184.134.153:8003/transcription/", form, {
            headers: {
                ...form.getHeaders(),
                "accept": "application/json"
            },
        });

        return response.data;
    } catch (error: any) {
        console.error("Error sending files to transcription API:", error.response?.data || error.message);
        return null;
    }
};

export const sendToAnalysisAPI = async (transcriptionData: any) => {
    try {
        if (!transcriptionData) {
            console.error("No transcription data provided");
            return null;
        }

        // Call the public analysis endpoint with JSON payload
        const response = await axios.post(
            "http://31.184.134.153:8003/analyze/",
            transcriptionData,
            {
                headers: {
                    "accept": "application/json",
                    "Content-Type": "application/json"
                }
            }
        );
        return response.data;
    } catch (error: any) {
        console.error("Error in analysis processing:", error.response?.data || error.message);
        return null;
    }
};
