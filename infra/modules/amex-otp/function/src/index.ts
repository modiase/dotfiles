import type { HttpFunction } from "@google-cloud/functions-framework";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";

const PROJECT_ID = process.env.GCP_PROJECT!;
const GMAIL_QUERY = process.env.GMAIL_QUERY!;
const POLL_INTERVAL_MS = 5_000;
const POLL_TIMEOUT_MS = 120_000;
const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";
const OTP_PATTERN = /One-Time Verification Code:<\/p>[\s\S]*?<p[^>]*>(\d{4,8})<\/p>/;

interface Credentials {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}

interface MessageRef {
  id: string;
}

interface ListResponse {
  messages?: MessageRef[];
}

interface MessagePart {
  mimeType?: string;
  body?: { data?: string };
  parts?: MessagePart[];
}

interface Message {
  id: string;
  payload?: MessagePart;
}

const secretManager = new SecretManagerServiceClient();
let cachedCredentials: Credentials | null = null;

async function getCredentials(): Promise<Credentials> {
  if (cachedCredentials) return cachedCredentials;

  const [version] = await secretManager.accessSecretVersion({
    name: `projects/${PROJECT_ID}/secrets/amex-otp-gmail-credentials/versions/latest`,
  });
  const raw = version.payload?.data?.toString() ?? "";
  const parsed = JSON.parse(raw) as {
    client_id: string;
    client_secret: string;
    refresh_token: string;
  };

  cachedCredentials = {
    clientId: parsed.client_id,
    clientSecret: parsed.client_secret,
    refreshToken: parsed.refresh_token,
  };
  return cachedCredentials;
}

async function getAccessToken(creds: Credentials): Promise<string> {
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: creds.clientId,
      client_secret: creds.clientSecret,
      refresh_token: creds.refreshToken,
      grant_type: "refresh_token",
    }),
  });

  const data = (await resp.json()) as { access_token?: string };
  if (!data.access_token) {
    throw new Error(`Token exchange failed: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

function findPartData(part: MessagePart, mimeType: string): string | undefined {
  if (part.mimeType === mimeType && part.body?.data) return part.body.data;
  for (const child of part.parts ?? []) {
    const found = findPartData(child, mimeType);
    if (found) return found;
  }
  return undefined;
}

function extractCode(message: Message): string | null {
  const payload = message.payload;
  if (!payload) return null;

  const htmlData = findPartData(payload, "text/html");
  if (!htmlData) return null;

  const html = Buffer.from(htmlData, "base64url").toString("utf-8");
  const match = html.match(OTP_PATTERN);
  return match?.[1] ?? null;
}

function log(severity: string, message: string, extra?: Record<string, unknown>): void {
  console.log(JSON.stringify({ severity, message, ...extra }));
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export const getOtp: HttpFunction = async (_req, res) => {
  try {
    const creds = await getCredentials();
    const accessToken = await getAccessToken(creds);
    const headers = { Authorization: `Bearer ${accessToken}` };
    const deadline = Date.now() + POLL_TIMEOUT_MS;

    while (Date.now() < deadline) {
      const listResp = await fetch(
        `${GMAIL_API}/messages?q=${encodeURIComponent(GMAIL_QUERY)}&maxResults=1`,
        { headers },
      );
      const listData = (await listResp.json()) as ListResponse;

      if (listData.messages?.length) {
        const msgId = listData.messages[0].id;
        log("INFO", "Found matching email", { messageId: msgId });

        const msgResp = await fetch(`${GMAIL_API}/messages/${msgId}?format=full`, { headers });
        const msgData = (await msgResp.json()) as Message;
        const code = extractCode(msgData);

        await fetch(`${GMAIL_API}/messages/${msgId}`, { method: "DELETE", headers });
        log("INFO", "Deleted email", { messageId: msgId });

        if (code) {
          res.json({ success: true, code });
        } else {
          log("WARNING", "Email matched but no OTP code found in body");
          res.json({ success: false, code: null });
        }
        return;
      }

      await sleep(POLL_INTERVAL_MS);
    }

    log("WARNING", "No matching email found within timeout");
    res.json({ success: false, code: null });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log("ERROR", "Failed to retrieve OTP email", { error: message });
    res.status(500).json({ error: message });
  }
};
