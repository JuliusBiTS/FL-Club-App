// get-member-card — briefing §9.6. Called on sign-in and periodically
// thereafter (e.g. app foreground) so the card can be cached and rendered
// entirely offline. Hands the app member_secret for the CURRENT monthly
// period only — not the master key — so a suspended member's cached card
// stops verifying within a month even without connectivity (§13.4).

import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { base64urlEncode, currentMemberPeriod, deriveMemberScanKey, deriveMemberSecret } from "../_shared/ticket-crypto.ts";

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST" && req.method !== "GET") return errorResponse("method not allowed", 405);

  const caller = createCallerClient(req);
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return errorResponse("unauthenticated", 401);
  const userId = userData.user.id;

  const admin = createAdminClient();
  const { data: profile, error: profileErr } = await admin
    .from("profiles")
    .select("full_name, member_status, membership_kind, membership_number, membership_pin, membership_started_at, membership_expires_at, membership_photo_path")
    .eq("id", userId)
    .maybeSingle();

  if (profileErr || !profile) return errorResponse("profile not found", 404);
  if (profile.member_status !== "active") {
    return errorResponse("Not an active member.", 403);
  }
  if (profile.membership_expires_at && new Date(profile.membership_expires_at) < new Date()) {
    return errorResponse("Membership has expired.", 403);
  }

  const period = currentMemberPeriod();
  const memberScanKey = await deriveMemberScanKey(requireEnv("MASTER_MEMBER_KEY"), period);
  const memberSecret = await deriveMemberSecret(memberScanKey, userId);

  let photoSignedUrl: string | null = null;
  if (profile.membership_photo_path) {
    const { data: signed } = await admin.storage
      .from("membership-photos")
      .createSignedUrl(profile.membership_photo_path, 900); // 15 min TTL, re-requested well before card re-open
    photoSignedUrl = signed?.signedUrl ?? null;
  }

  return jsonResponse({
    full_name: profile.full_name,
    membership_kind: profile.membership_kind,
    membership_number: profile.membership_number,
    membership_pin: profile.membership_pin, // TODO: decrypt via pgsodium once wired — see migration 20260817000002
    member_since: profile.membership_started_at,
    valid_to: profile.membership_expires_at,
    photo_signed_url: photoSignedUrl,
    member_secret: base64urlEncode(memberSecret), // client regenerates rotating codes locally from this, no further network calls needed until it next syncs
    period, // the app should re-fetch a fresh secret once the local period rolls over
    server_time: new Date().toISOString(),
  });
});
