// Firebase Cloud Messaging (HTTP v1) without the Admin SDK: sign a short-lived
// JWT with the Firebase service account, swap it for an OAuth access token,
// then POST one message per device token. Only Web Crypto + fetch — nothing
// to install, nothing that can leak the service account anywhere but here.
//
// The service account JSON lives in the Edge Function secret
// FCM_SERVICE_ACCOUNT_JSON (supabase/.env.example, docs/PUSH_SETUP.md). It is
// never shipped to the app or the admin console.

import { requireEnv } from "./supabase-clients.ts";

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Extra key/values delivered with the notification. FCM requires string values. */
  data: Record<string, string>;
}

/** "ok" delivered; "unregistered" the token is dead and should be deleted; "error" try again later / bug. */
export type SendOutcome = "ok" | "unregistered" | "error";

/** Throws with a readable message if the secret is missing or malformed. */
export function loadServiceAccount(): ServiceAccount {
  const raw = requireEnv("FCM_SERVICE_ACCOUNT_JSON");
  let parsed: Partial<ServiceAccount>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON is not valid JSON");
  }
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON is missing client_email, private_key or project_id");
  }
  return parsed as ServiceAccount;
}

function base64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "") // a key pasted with literal "\n" sequences
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

let cachedToken: { value: string; expiresAtMs: number } | null = null;

/** An OAuth access token for the firebase.messaging scope, cached until shortly before it expires. */
export async function getAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAtMs - 60_000) return cachedToken.value;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const nowSec = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: tokenUri,
      iat: nowSec,
      exp: nowSec + 3600,
    }),
  );
  const signingInput = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput));
  const assertion = `${signingInput}.${base64url(signature)}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`Google token exchange failed (${res.status}): ${await res.text()}`);

  const json = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: json.access_token, expiresAtMs: Date.now() + json.expires_in * 1000 };
  return json.access_token;
}

export async function sendToToken(
  sa: ServiceAccount,
  accessToken: string,
  deviceToken: string,
  message: PushMessage,
): Promise<SendOutcome> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title: message.title, body: message.body },
        data: message.data,
        android: { priority: "HIGH" },
        apns: { payload: { aps: { sound: "default" } } },
      },
    }),
  });

  if (res.ok) return "ok";

  // A token that is no longer valid comes back as 404 / UNREGISTERED. Anything
  // else (quota, 5xx, a bad payload) must NOT delete the token.
  const text = await res.text();
  if (res.status === 404 || text.includes("UNREGISTERED")) return "unregistered";
  console.error(`FCM send failed (${res.status}):`, text);
  return "error";
}
