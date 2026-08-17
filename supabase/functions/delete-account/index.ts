// delete-account — briefing §9.10, a hard store requirement on both
// platforms. Immediate: anonymise PII, delete the membership photo,
// pseudonymise retained order records, then soft-delete via GoTrue (which
// disables sign-in and invalidates every session). The auth.users row
// itself is hard-purged after a 30-day grace window by
// purge-deleted-accounts, driven by pg_cron — see migration
// 20260817000014_account_deletion.sql.

import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";
import { writeAuditLog } from "../_shared/audit.ts";

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

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

  // Order/ticket records are retained for UK financial/charity
  // record-keeping (typically 6 years) but pseudonymised — the buyer's
  // identity goes, the transaction record doesn't.
  await admin
    .from("orders")
    .update({ buyer_email: "deleted-user@frontlineclub.local", buyer_name: null })
    .eq("user_id", userId);

  const { error: profileErr } = await admin
    .from("profiles")
    .update({
      full_name: null,
      display_name: null,
      phone: null,
      avatar_url: null,
      membership_photo_path: null,
      membership_pin: null,
      marketing_opt_in: false,
      push_opt_in: false,
      deleted_at: new Date().toISOString(),
    })
    .eq("id", userId);

  if (profileErr) {
    console.error("Failed to anonymise profile for account deletion:", profileErr);
    return errorResponse("Something went wrong deleting your account. Please contact the club.", 500);
  }

  if (profile?.membership_photo_path) {
    await admin.storage.from("membership-photos").remove([profile.membership_photo_path]);
  }

  // shouldSoftDelete=true: disables sign-in and invalidates all sessions
  // immediately, without dropping the auth.users row yet — that's
  // purge-deleted-accounts' job once the grace window passes.
  const { error: deleteErr } = await admin.auth.admin.deleteUser(userId, true);
  if (deleteErr) {
    console.error("Failed to soft-delete auth user:", deleteErr);
    return errorResponse("Something went wrong deleting your account. Please contact the club.", 500);
  }

  await writeAuditLog(admin, {
    actorId: userId,
    action: "account.delete_requested",
    entity: "profiles",
    entityId: userId,
  });

  return jsonResponse({ deleted: true });
});
