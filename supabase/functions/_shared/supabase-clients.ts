import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

/** service_role client — bypasses RLS entirely. This is the only client
 *  that ever creates orders/tickets/loyalty entries or reads member photos.
 *  The key backing it lives only in this function's environment; it is
 *  never shipped to the Flutter app or the admin console front-end. */
export function createAdminClient(): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Anon-key client scoped to the caller's own JWT (forwarded from the
 *  incoming request). Use this to resolve "who is calling" via
 *  supabase.auth.getUser() and RLS-respecting reads — never to perform a
 *  privileged write, which must go through createAdminClient(). */
export function createCallerClient(req: Request): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const anonKey = requireEnv("SUPABASE_ANON_KEY");
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function getCallerUserId(req: Request): Promise<string | null> {
  const caller = createCallerClient(req);
  const { data, error } = await caller.auth.getUser();
  if (error || !data?.user) return null;
  return data.user.id;
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing required env var: ${name}`);
  return value;
}
