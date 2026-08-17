// Every Edge Function is called directly from the Flutter app and the
// Flutter Web admin console, never browsed to from arbitrary origins, but
// the admin console (a browser context) still needs permissive CORS to
// call these from its own origin during local dev and once deployed.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Call first in every handler; returns a Response for OPTIONS preflight, null otherwise. */
export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}
