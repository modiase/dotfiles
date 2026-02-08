import { Storage } from "@google-cloud/storage";
import { PubSub } from "@google-cloud/pubsub";
import type { Request, Response } from "@google-cloud/functions-framework";
import { pipe } from "fp-ts/function";
import * as E from "fp-ts/Either";
import * as TE from "fp-ts/TaskEither";

const storage = new Storage();
const pubsub = new PubSub();

interface AlertConfig {
  topic: string;
  priority: string;
  title: string;
  message: string;
}

interface CheckBackupRequest {
  bucket: string;
  object: string;
  max_age_hours: number;
  alert: AlertConfig;
}

const getEnv = (name: string): E.Either<Error, string> =>
  pipe(
    process.env[name]?.trim(),
    E.fromNullable(new Error(`Missing env var: ${name}`)),
    E.filterOrElse(
      (v) => v.length > 0,
      () => new Error(`Empty env var: ${name}`),
    ),
  );

const validateRequest = (body: unknown): E.Either<Error, CheckBackupRequest> =>
  pipe(
    body as CheckBackupRequest,
    E.fromPredicate(
      (b) => !!(b?.bucket && b?.object && b?.max_age_hours && b?.alert),
      () => new Error("Missing required fields"),
    ),
  );

export const checkBackup = async (req: Request, res: Response): Promise<void> =>
  pipe(
    E.Do,
    E.bind("request", () => validateRequest(req.body)),
    E.bind("ntfyTopicId", () => getEnv("NTFY_TOPIC_ID")),
    TE.fromEither,
    TE.flatMap(({ request, ntfyTopicId }) =>
      TE.tryCatch(
        async () => {
          const [metadata] = await storage
            .bucket(request.bucket)
            .file(request.object)
            .getMetadata();
          const updated = new Date(metadata.updated as string);
          const ageHours = (Date.now() - updated.getTime()) / (1000 * 60 * 60);

          if (ageHours > request.max_age_hours) {
            await pubsub.topic(ntfyTopicId).publishMessage({
              data: Buffer.from(request.alert.message),
              attributes: {
                topic: request.alert.topic,
                priority: request.alert.priority,
                title: request.alert.title,
              },
            });
            console.log(
              `Alert sent: backup ${request.bucket}/${request.object} is ${ageHours.toFixed(1)}h old`,
            );
            return { status: "alert_sent" as const, age_hours: ageHours };
          }
          console.log(
            `Backup OK: ${request.bucket}/${request.object} is ${ageHours.toFixed(1)}h old`,
          );
          return { status: "ok" as const, age_hours: ageHours };
        },
        (err) => err as Error,
      ),
    ),
    TE.match(
      (err) => {
        console.error("Error checking backup:", err);
        res.status(err.message === "Missing required fields" ? 400 : 500).json({
          error: err.message,
        });
      },
      (result) => res.json(result),
    ),
  )();
