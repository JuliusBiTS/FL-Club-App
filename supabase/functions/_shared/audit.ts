import { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface AuditEntry {
  actorId: string | null;
  action: string; // 'membership.activate', 'order.refund', 'role.grant', ...
  entity: string;
  entityId?: string | null;
  before?: unknown;
  after?: unknown;
  ip?: string | null;
  userAgent?: string | null;
}

/** audit_log is append-only (enforced at the DB level too) — this is the
 *  only way any privileged mutation should be recorded. Call it from
 *  service_role after the mutation succeeds, in the same function
 *  invocation, so the audit trail can never lag behind reality. */
export async function writeAuditLog(admin: SupabaseClient, entry: AuditEntry): Promise<void> {
  const { error } = await admin.from("audit_log").insert({
    actor_id: entry.actorId,
    action: entry.action,
    entity: entry.entity,
    entity_id: entry.entityId ?? null,
    before: entry.before ?? null,
    after: entry.after ?? null,
    ip: entry.ip ?? null,
    user_agent: entry.userAgent ?? null,
  });
  if (error) {
    // Never let a logging failure silently swallow the fact that a
    // privileged action happened without a trail — surface it loudly.
    console.error("FAILED TO WRITE AUDIT LOG for", entry.action, entry.entity, entry.entityId, error);
  }
}
