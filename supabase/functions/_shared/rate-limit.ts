import { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Backed by the check_rate_limit() Postgres function (migration
 *  20260817000007) — a single atomic upsert, safe under concurrent
 *  requests for the same key. Limits per briefing §13.7:
 *    create-order        10 / min  / user
 *    membership-apply     3 / hour / user
 *    password reset        5 / hour / email   (handled by Supabase Auth, not here)
 *    scan verification    60 / min  / device
 */
export async function checkRateLimit(
  admin: SupabaseClient,
  key: string,
  max: number,
  windowIso8601: string, // e.g. '1 minute', '1 hour' — passed straight to Postgres interval literal
): Promise<boolean> {
  const { data, error } = await admin.rpc("check_rate_limit", {
    p_key: key,
    p_max: max,
    p_window: windowIso8601,
  });
  if (error) {
    // Fail closed on infrastructure errors for anything payment- or
    // membership-adjacent would be too aggressive for a launch-stage app;
    // fail OPEN but log loudly so it shows up in Sentry/function logs.
    console.error("check_rate_limit failed, allowing call through:", error);
    return true;
  }
  return Boolean(data);
}
