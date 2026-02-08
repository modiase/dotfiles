import * as https from "https";
import { pipe } from "fp-ts/function";
import * as E from "fp-ts/Either";
import * as TE from "fp-ts/TaskEither";

// Actual Eventarc Pub/Sub format (SDK types are wrong)
interface PubSubMessage {
  attributes?: Record<string, string>;
  data: string;
  message_id: string;
  publish_time: string;
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

export const handlePubSub = async (
  cloudEvent: PubSubMessage,
): Promise<{ success: boolean; statusCode: number }> =>
  pipe(
    E.Do,
    E.bind("ntfyUrl", () => getEnv("NTFY_URL")),
    E.bind("ntfyUser", () => getEnv("NTFY_USER")),
    E.bind("ntfyPassword", () => getEnv("NTFY_PASSWORD")),
    E.let("attributes", () => cloudEvent.attributes ?? {}),
    E.let("body", () => Buffer.from(cloudEvent.data, "base64").toString("utf-8")),
    E.let("topic", ({ attributes }) => attributes.topic ?? "general"),
    TE.fromEither,
    TE.flatMap(({ ntfyUrl, ntfyUser, ntfyPassword, attributes, body, topic }): (() => Promise<E.Either<Error, number>>) => () =>
      new Promise((resolve) => {
        const req = https.request(
          new URL(`${ntfyUrl}/${topic}`),
          {
            method: "POST",
            headers: {
              Authorization: `Basic ${Buffer.from(`${ntfyUser}:${ntfyPassword}`).toString("base64")}`,
              Priority: attributes.priority ?? "3",
              ...(attributes.title && { Title: attributes.title }),
              ...(attributes.tags && { Tags: attributes.tags }),
            },
          },
          (res) => {
            let data = "";
            res.on("data", (chunk: Buffer) => (data += chunk.toString()));
            res.on("end", () => {
              const statusCode = res.statusCode ?? 500;
              if (statusCode >= 200 && statusCode < 300) {
                console.log(`Sent to ntfy/${topic}: ${body.substring(0, 100)}`);
                resolve(E.right(statusCode));
              } else {
                resolve(E.left(new Error(`ntfy returned ${statusCode}: ${data}`)));
              }
            });
          },
        );
        req.on("error", (err) => resolve(E.left(err)));
        req.write(body);
        req.end();
      }),
    ),
    TE.match(
      (err) => {
        throw err;
      },
      (statusCode) => ({ success: true, statusCode }),
    ),
  )();
