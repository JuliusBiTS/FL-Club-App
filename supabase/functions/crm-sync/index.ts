// crm-sync — keeps the app's idea of "who is a member" in step with the
// club's CRM (SHEEP). Admin only.
//
// Actions (POST { action, members? }):
//   sync     pull members from the CRM into the crm_members staging table,
//            then return a PREVIEW of what would change. Changes nothing.
//   import   same, but from rows the admin supplies (e.g. a parsed CSV
//            export) — works with no CRM API at all, and is how the whole
//            pipeline can be tested today.
//   preview  just show what would change from what's already staged.
//   apply    make the changes (crm_reconcile_apply). Always a separate,
//            deliberate step after previewing; audited per profile.
//
// Nothing here can create a member out of thin air: only a CRM record that
// says "active" can activate an existing account with the same email, and a
// person absent from the CRM is flagged, never changed.
//
// Secrets (set from your own terminal, never pasted into chat):
//   SHEEP_API_URL   the CRM's member-list endpoint
//   SHEEP_API_KEY   the API credential
// Until they're set, `sync` answers 503 with a plain-English message and
// `import` / `preview` / `apply` all still work.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";

type CrmStatus = "active" | "lapsed" | "cancelled" | "unknown";

interface CrmMember {
  external_id: string;
  email: string | null;
  full_name: string | null;
  status: CrmStatus;
  membership_kind: string | null;
  membership_number: string | null;
  started_at: string | null;
  expires_at: string | null;
  raw: unknown;
}

const importRow = z.object({
  external_id: z.string().min(1).max(100),
  email: z.string().email().nullish(),
  full_name: z.string().max(200).nullish(),
  status: z.enum(["active", "lapsed", "cancelled", "unknown"]),
  membership_kind: z.enum(["full", "honorary", "lifetime"]).nullish(),
  membership_number: z.string().max(50).nullish(),
  started_at: z.string().datetime().nullish(),
  expires_at: z.string().datetime().nullish(),
});

const bodySchema = z
  .object({
    action: z.enum(["sync", "import", "preview", "apply"]),
    members: z.array(importRow).max(20000).optional(),
  })
  .strict();

// ---------------------------------------------------------------------------
// The one CRM-specific part. UNVERIFIED: written without SHEEP's API docs or
// a sample response, so the field names below are educated guesses and the
// raw record is kept in crm_members.raw precisely so the mapping can be
// corrected from real data. Replace/extend `mapSheepRecord` once we have the
// docs; nothing outside this function needs to change.
// ---------------------------------------------------------------------------

function mapSheepRecord(r: Record<string, unknown>): CrmMember | null {
  const str = (...keys: string[]): string | null => {
    for (const k of keys) {
      const v = r[k];
      if (typeof v === "string" && v.trim()) return v.trim();
      if (typeof v === "number") return String(v);
    }
    return null;
  };

  const externalId = str("id", "member_id", "memberId", "contact_id", "uuid");
  if (!externalId) return null;

  const expires = str("expiry_date", "expires_at", "end_date", "renewal_date", "valid_to");
  const started = str("start_date", "started_at", "join_date", "joined");
  const statusText = (str("status", "membership_status", "state") ?? "").toLowerCase();

  let status: CrmStatus = "unknown";
  if (/(active|current|paid|live)/.test(statusText)) status = "active";
  else if (/(lapse|expire|overdue)/.test(statusText)) status = "lapsed";
  else if (/(cancel|resign|terminat|deceas)/.test(statusText)) status = "cancelled";
  // An "active" record whose own expiry is already in the past is lapsed.
  if (status === "active" && expires && new Date(expires) < new Date()) status = "lapsed";

  const joinedName = [str("first_name", "firstName", "forename"), str("last_name", "lastName", "surname")].filter(Boolean).join(" ");
  const name = str("full_name", "name") ?? (joinedName || null);

  const toIso = (s: string | null) => {
    if (!s) return null;
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  };

  const kindText = (str("membership_type", "type", "tier", "category") ?? "").toLowerCase();
  const kind = kindText.includes("life") ? "lifetime" : kindText.includes("honor") ? "honorary" : kindText ? "full" : null;

  return {
    external_id: externalId,
    email: str("email", "email_address", "emailAddress")?.toLowerCase() ?? null,
    full_name: name,
    status,
    membership_kind: kind,
    membership_number: str("membership_number", "membershipNumber", "number"),
    started_at: toIso(started),
    expires_at: toIso(expires),
    raw: r,
  };
}

async function fetchFromSheep(): Promise<CrmMember[]> {
  const url = Deno.env.get("SHEEP_API_URL");
  const key = Deno.env.get("SHEEP_API_KEY");
  if (!url || !key) throw new NotConfigured();

  const res = await fetch(url, { headers: { Authorization: `Bearer ${key}`, Accept: "application/json" } });
  if (!res.ok) throw new Error(`The CRM answered ${res.status}.`);
  const json = await res.json();
  const list: unknown[] = Array.isArray(json) ? json : Array.isArray(json?.members) ? json.members : Array.isArray(json?.data) ? json.data : [];
  return list
    .map((r) => (r && typeof r === "object" ? mapSheepRecord(r as Record<string, unknown>) : null))
    .filter((m): m is CrmMember => m !== null);
}

class NotConfigured extends Error {}

// ---------------------------------------------------------------------------

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
  const { data: isAdmin } = await admin.rpc("is_admin", { p_uid: userId });
  if (!isAdmin) return errorResponse("forbidden — admin role required", 403);

  if (body.action === "preview") return await previewResponse(admin);

  if (body.action === "apply") {
    const { data: changed, error } = await admin.rpc("crm_reconcile_apply");
    if (error) {
      console.error("crm_reconcile_apply failed:", error);
      return errorResponse("Couldn't apply the changes.", 500);
    }
    await admin.from("crm_sync_runs").insert({
      trigger: "manual", finished_at: new Date().toISOString(), status: "ok", applied: true,
      summary: { changed }, created_by: userId,
    });
    return jsonResponse({ applied: true, changed });
  }

  // sync / import: fill the staging table, then preview.
  const { data: run } = await admin
    .from("crm_sync_runs")
    .insert({ trigger: body.action === "import" ? "import" : "manual", created_by: userId })
    .select("id")
    .single();

  try {
    let members: CrmMember[];
    if (body.action === "import") {
      if (!body.members || body.members.length === 0) return errorResponse("No members supplied to import.", 400);
      members = body.members.map((m) => ({
        external_id: m.external_id,
        email: m.email?.toLowerCase() ?? null,
        full_name: m.full_name ?? null,
        status: m.status,
        membership_kind: m.membership_kind ?? null,
        membership_number: m.membership_number ?? null,
        started_at: m.started_at ?? null,
        expires_at: m.expires_at ?? null,
        raw: null,
      }));
    } else {
      members = await fetchFromSheep();
    }

    for (let i = 0; i < members.length; i += 500) {
      const chunk = members.slice(i, i + 500).map((m) => ({ ...m, source: "sheep", synced_at: new Date().toISOString() }));
      const { error } = await admin.from("crm_members").upsert(chunk, { onConflict: "source,external_id" });
      if (error) throw new Error(`Saving members failed: ${error.message}`);
    }

    if (run?.id) {
      await admin.from("crm_sync_runs").update({ finished_at: new Date().toISOString(), status: "ok", fetched: members.length }).eq("id", run.id);
    }
    return await previewResponse(admin, members.length);
  } catch (err) {
    const notConfigured = err instanceof NotConfigured;
    if (run?.id) {
      await admin.from("crm_sync_runs").update({ finished_at: new Date().toISOString(), status: "failed", error: String(err).slice(0, 500) }).eq("id", run.id);
    }
    if (notConfigured) {
      return errorResponse("The CRM connection isn't set up yet (SHEEP_API_URL / SHEEP_API_KEY). You can still import a member list by hand.", 503);
    }
    console.error("crm-sync failed:", err);
    return errorResponse("The CRM sync failed — see the sync history.", 502);
  }
});

async function previewResponse(admin: ReturnType<typeof createAdminClient>, fetched?: number) {
  const { data, error } = await admin.rpc("crm_reconcile_preview");
  if (error) {
    console.error("crm_reconcile_preview failed:", error);
    return errorResponse("Couldn't work out the preview.", 500);
  }
  const rows = (data ?? []) as Array<{ action: string }>;
  const counts: Record<string, number> = {};
  for (const r of rows) counts[r.action] = (counts[r.action] ?? 0) + 1;
  // Only the rows that need a decision go back in full; "none" is just a count.
  return jsonResponse({ fetched, counts, changes: rows.filter((r) => r.action !== "none") });
}
