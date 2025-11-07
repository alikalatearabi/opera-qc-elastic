import express from "express";
import { SequentialJobController } from "./sequentialController";

export const sequentialRouter = express.Router();
const sequentialJobController = new SequentialJobController();

sequentialRouter.post("/jobs", sequentialJobController.addJob);
sequentialRouter.get("/jobs/:jobId/status", sequentialJobController.getJobStatus);
sequentialRouter.get("/jobs", sequentialJobController.getAllJobs); 