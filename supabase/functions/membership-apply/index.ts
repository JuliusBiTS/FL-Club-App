// membership-apply — briefing §9.7. The app never sells membership; this
// just gives the club a real queue (instead of only a mailbox) and, if the
// caller is signed in, flips their member_status to 'applied' so the "You"
// tab can show progress. The device's mailto: launch happens entirely
// client-side — this function only needs to persist the application.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

const bodySchema = z
  .object({
    full_name: z.string().min(1).max(200).optional(),
    email: z.string().email().optional(), // required only for guests, see below
    occupation: z.string().max(200).optional(),
    message: z.string().max(4000).optional(),
  })
  .strict();

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

  const admin = createAdminClient();

  // Membership can be applied for without an account (§4 — guests see the
  // "Become a member" handle too), but if the caller does have a session we
  // use it as the source of truth for identity rather than trusting the body.
  const authHeader = req.headers.get("Authorization");
  let userId: string | null = null;
  let email = body.email ?? null;
  let fullName = body.full_name ?? null;

  if (authHeader && authHeader !== "Bearer") {
    const caller = createCallerClient(req);
    const { data: userData } = await caller.auth.getUser();
    if (userData?.user) {
      userId = userData.user.id;
      email = userData.user.email ?? email;
      const { data: profile } = await admin.from("profiles").select("full_name").eq("id", userId).maybeSingle();
      fullName = profile?.full_name ?? fullName;
    }
  }

  if (!email) {
    return errorResponse("An email address is required.", 400);
  }

  const rateLimitKey = userId ? `membership-apply:${userId}` : `membership-apply:${email.toLowerCase()}`;
  const allowed = await checkRateLimit(admin, rateLimitKey, 3, "1 hour");
  if (!allowed) {
    return errorResponse("You've already submitted an application recently — the club will be in touch.", 429);
  }

  const { data: application, error: insertErr } = await admin
    .from("membership_applications")
    .insert({
      user_id: userId,
      email,
      full_name: fullName,
      occupation: body.occupation ?? null,
      message: body.message ?? null,
      source: "app",
    })
    .select("id")
    .single();

  if (insertErr) {
    console.error("membership_applications insert failed:", insertErr);
    return errorResponse("Something went wrong submitting your application. Please try again.", 500);
  }

  if (userId) {
    // Only move 'none' -> 'applied'. Never downgrade an existing active/
    // lapsed/suspended member who is, say, re-applying after a lapse for
    // clarity — that transition is an admin decision (§4 hard rule).
    await admin
      .from("profiles")
      .update({ member_status: "applied" })
      .eq("id", userId)
      .eq("member_status", "none");
  }

  return jsonResponse({ application_id: application.id, status: "submitted" });
});
