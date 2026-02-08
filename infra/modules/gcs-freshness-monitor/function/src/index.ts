import { Storage } from "@google-cloud/storage";
import { PubSub } from "@google-cloud/pubsub";
import type { Request, Response } from "@google-cloud/functions-framework";
import { pipe } from "fp-ts/function";
import * as E from "fp-ts/Either";
import * as TE from "fp-ts/TaskEither";
import * as t from "io-ts";
import { PathReporter } from "io-ts/PathReporter";

const storage = new Storage();
const pubsub = new PubSub();

const AlertConfig = t.strict({
  topic: t.string,
  priority: t.string,
  title: t.string,
  message: t.string,
});

const FreshnessCheckRequest = t.strict({
  bucket: t.string,
  object: t.string,
  max_age_hours: t.number,
  alert: AlertConfig,
});

type FreshnessCheckRequest = t.TypeOf<typeof FreshnessCheckRequest>;

const getEnv = (name: string): E.Either<Error, string> =>
  pipe(
    process.env[name]?.trim(),
    E.fromNullable(new Error(`Missing env var: ${name}`)),
    E.filterOrElse(
      (v) => v.length > 0,
      () => new Error(`Empty env var: ${name}`),
    ),
  );

const decodeRequest = (body: unknown): E.Either<Error, FreshnessCheckRequest> =>
  pipe(
    FreshnessCheckRequest.decode(body),
    E.mapLeft((errors) => new Error(PathReporter.report(E.left(errors)).join(", "))),
  );

export const checkFreshness = async (req: Request, res: Response): Promise<void> =>
  pipe(
    E.Do,
    E.bind("request", () => decodeRequest(req.body)),
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
              `Alert sent: ${request.bucket}/${request.object} is ${ageHours.toFixed(1)}h old (threshold: ${request.max_age_hours}h)`,
            );
            return { status: "alert_sent" as const, age_hours: ageHours };
          }
          console.log(
            `OK: ${request.bucket}/${request.object} is ${ageHours.toFixed(1)}h old`,
          );
          return { status: "ok" as const, age_hours: ageHours };
        },
        (err) => err as Error,
      ),
    ),
    TE.match(
      (err) => {
        console.error("Error checking freshness:", err);
        res.status(err.message.startsWith("Invalid value") ? 400 : 500).json({
          error: err.message,
        });
      },
      (result) => res.json(result),
    ),
  )();
