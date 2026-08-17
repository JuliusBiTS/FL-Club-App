// purge-deleted-accounts — briefing §9.10: "Hard-purge of the auth.users
// row after a 30-day grace window, via a scheduled job." Runs daily via
// pg_cron (migration 20260817000014_account_deletion.sql). Hard-deleting
// the auth.users row cascades to profiles (on delete cascade) — everything
// that was going to be deleted already was, at request time, in
// delete-account; this just removes the row itself.

import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient } from "../_shared/supabase-clients.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const admin = createAdminClient();

  const { data: pending, error } = await admin.rpc("find_accounts_pending_purge", { p_grace_days: 30 });
  if (error) {
    console.error("find_accounts_pending_purge failed:", error);
    return errorResponse("internal error", 500);
  }

  let purged = 0;
  for (const row of (pending ?? []) as Array<{ user_id: string }>) {
    const { error: deleteErr } = await admin.auth.admin.deleteUser(row.user_id, false);
    if (deleteErr) {
      console.error(`Failed to hard-purge user ${row.user_id}:`, deleteErr);
      continue;
    }
    purged++;
  }

  return jsonResponse({ purged });
});
