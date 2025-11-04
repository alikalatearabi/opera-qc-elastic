import { z } from "zod";

export const commonValidations = {
  id: z
    .string()
    .refine((data) => !Number.isNaN(Number(data)), "ID must be a numeric value")
    .transform(Number)
    .refine((num) => num > 0, "ID must be a positive number"),
  // ... other common validations
};

export interface SessionEventInput {
  type: string;
  source_channel: string;
  source_number: string;
  queue: string;
  dest_channel: string;
  dest_number: string;
  date: string;
  duration: string;
  filename: string;
  uniqueid?: string;
  level?: number;
  time?: number;
  pid?: number;
  hostname?: string;
  name?: string;
  msg?: string;
}

export const validateSessionEventInput = (reqBody: any): { isValid: boolean; data?: SessionEventInput; missingFields?: string[] } => {
  const requiredFields = ['type', 'source_channel', 'source_number', 'queue', 'dest_channel', 'dest_number', 'date', 'duration', 'filename'];
  const missingFields: string[] = [];

  for (const field of requiredFields) {
    if (!reqBody[field]) {
      missingFields.push(field);
    }
  }

  if (missingFields.length > 0) {
    return {
      isValid: false,
      missingFields
    };
  }

  return {
    isValid: true,
    data: {
      type: reqBody.type,
      source_channel: reqBody.source_channel,
      source_number: reqBody.source_number,
      queue: reqBody.queue,
      dest_channel: reqBody.dest_channel,
      dest_number: reqBody.dest_number,
      date: reqBody.date,
      duration: reqBody.duration,
      filename: reqBody.filename,
      uniqueid: reqBody.uniqueid,
      level: reqBody.level,
      time: reqBody.time,
      pid: reqBody.pid,
      hostname: reqBody.hostname,
      name: reqBody.name,
      msg: reqBody.msg
    }
  };
};