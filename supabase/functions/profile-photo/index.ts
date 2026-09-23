// profile-photo — the signed-in user's own account / membership-card picture.
//
// Security model (briefing §13.6): photos live in the PRIVATE
// `membership-photos` bucket, which has no client read/write policy at all.
// This function is the only door: it acts as the caller (JWT verified), only
// ever touches `<caller-id>/…`, checks the file really is a JPEG or PNG by
// its magic bytes (not its claimed type), caps the size, and hands back only
// short-lived signed URLs. Staff see the same photo when scanning a member
// (verify-scan signs it for 15 minutes).

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { writeAuditLog } from "../_shared/audit.ts";

const BUCKET = "membership-photos";
const MAX_BYTES = 1_500_000; // the app sends a ~512px re-encoded JPEG, well under this

const bodySchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("get") }),
  z.object({ action: z.literal("remove") }),
  z.object({ action: z.literal("set"), image_base64: z.string().min(20).max(2_200_000) }),
]);

function detectType(bytes: Uint8Array): { ext: string; mime: string } | null {
  if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { ext: "jpg", mime: "image/jpeg" };
  }
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length > 8 && png.every((b, i) => bytes[i] === b)) return { ext: "png", mime: "image/png" };
  return null;
}

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  let body: z.infer<typeof bodySchema>;
  try {
    body = bodySchema.parse(await req.json());
  } catch (err) {
    return errorResponse("invalid request body", 400, err instanceof z.ZodError ? err.issues : String(err));
  }

  const caller = createCallerClient(req);
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return errorResponse("unauthenticated", 401);
  const userId = userData.user.id;

  const admin = createAdminClient();
  const { data: profile } = await admin
    .from("profiles")
    .select("membership_photo_path")
    .eq("id", userId)
    .maybeSingle();
  if (!profile) return errorResponse("profile not found", 404);
  const oldPath: string | null = profile.membership_photo_path;

  const sign = async (path: string | null) => {
    if (!path) return null;
    const { data } = await admin.storage.from(BUCKET).createSignedUrl(path, 600);
    return data?.signedUrl ?? null;
  };

  if (body.action === "get") {
    return jsonResponse({ photo_signed_url: await sign(oldPath) });
  }

  if (body.action === "remove") {
    if (oldPath) {
      await admin.storage.from(BUCKET).remove([oldPath]);
      await admin.from("profiles").update({ membership_photo_path: null }).eq("id", userId);
      await writeAuditLog(admin, { actorId: userId, action: "profile.photo_remove", entity: "profile", entityId: userId });
    }
    return jsonResponse({ photo_signed_url: null });
  }

  // set
  const allowed = await checkRateLimit(admin, `photo:${userId}`, 10, "1 hour");
  if (!allowed) return errorResponse("Too many photo changes — try again later.", 429);

  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(body.image_base64), (c) => c.charCodeAt(0));
  } catch {
    return errorResponse("That doesn't look like a valid image.", 400);
  }
  if (bytes.length > MAX_BYTES) return errorResponse("That picture is too large.", 413);
  const type = detectType(bytes);
  if (!type) return errorResponse("Please use a JPEG or PNG picture.", 415);

  // A fresh name each time so a replaced photo can't be served from a stale
  // cache, and the previous file is removed afterwards.
  const path = `${userId}/${Date.now()}.${type.ext}`;
  const { error: upErr } = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: type.mime, upsert: false });
  if (upErr) {
    console.error("profile-photo upload failed:", upErr);
    return errorResponse("Couldn't save your picture. Please try again.", 500);
  }

  const { error: updErr } = await admin.from("profiles").update({ membership_photo_path: path }).eq("id", userId);
  if (updErr) {
    await admin.storage.from(BUCKET).remove([path]);
    console.error("profile-photo profile update failed:", updErr);
    return errorResponse("Couldn't save your picture. Please try again.", 500);
  }
  if (oldPath && oldPath !== path) await admin.storage.from(BUCKET).remove([oldPath]);
  await writeAuditLog(admin, { actorId: userId, action: "profile.photo_set", entity: "profile", entityId: userId });

  return jsonResponse({ photo_signed_url: await sign(path) });
});
