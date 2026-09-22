// extract-event-details — staff paste a block of free text (an email, a press
// release, a partner's blurb) and get back a best-effort structured guess at
// the event's fields, via the Claude API. The person still reviews and saves
// the result themselves; nothing here writes to the database.
//
// Deliberately safe by construction, not by instruction: ticket price,
// capacity, and ticket types are business decisions, so they are simply not
// fields in the schema below — there is no way for the model to return one,
// however the source text is worded.

import Anthropic from "npm:@anthropic-ai/sdk@0.127.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@0.127.0/helpers/zod";
// v4, not v3: the SDK's zodOutputFormat() helper calls zod's own v4
// to-json-schema code internally, which only understands v4-shaped schema
// objects. A v3 schema (e.g. zod@3.25.76, used elsewhere in this repo)
// crashes it with "Cannot read properties of undefined (reading 'def')".
import { z } from "npm:zod@4.6.5";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

// Keeps cost and latency bounded — roughly 1,500 words.
const MAX_INPUT_CHARS = 8000;
const MIN_INPUT_CHARS = 20;

// Kept in sync by hand with kEventCategories in
// packages/flc_core/lib/src/events_admin/event_draft.dart.
const CATEGORIES = [
  "Panel discussion",
  "Book talk",
  "Screening + Q&A",
  "Online talk",
  "Workshop / training",
  "Members' social",
  "Exhibition",
  "Awards & fundraising",
  "Private hire",
] as const;

const LINK_KINDS = ["link", "book", "film", "article", "video", "donate"] as const;

const ExtractedEvent = z.object({
  title: z.string().nullable(),
  subtitle: z.string().nullable(),
  summary: z.string().nullable(),
  description_md: z.string().nullable(),
  category: z.enum(CATEGORIES).nullable(),
  tags: z.array(z.string()),
  starts_at: z.string().nullable(),
  ends_at: z.string().nullable(),
  doors_at: z.string().nullable(),
  venue_room: z.string().nullable(),
  venue_address: z.string().nullable(),
  is_online: z.boolean(),
  livestream_url: z.string().nullable(),
  speakers: z.array(
    z.object({ name: z.string(), role: z.string().nullable(), bio: z.string().nullable() }),
  ),
  links: z.array(z.object({ label: z.string(), url: z.string(), kind: z.enum(LINK_KINDS) })),
  perks: z.array(z.string()),
  notes: z.array(z.string()),
});

const bodySchema = z.object({ text: z.string().min(MIN_INPUT_CHARS).max(MAX_INPUT_CHARS) }).strict();

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  let body: z.infer<typeof bodySchema>;
  try {
    body = bodySchema.parse(await req.json());
  } catch (err) {
    if (err instanceof z.ZodError && err.issues.some((i) => i.code === "too_big")) {
      return errorResponse(
        `Paste something shorter — under about 1,500 words (${MAX_INPUT_CHARS} characters). Try splitting it into two events.`,
        400,
      );
    }
    return errorResponse("Paste some text first.", 400, err instanceof z.ZodError ? err.issues : String(err));
  }

  const caller = createCallerClient(req);
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return errorResponse("unauthenticated", 401);
  const userId = userData.user.id;

  const admin = createAdminClient();
  const { data: isStaff } = await admin.rpc("is_staff", { p_uid: userId });
  if (!isStaff) return errorResponse("forbidden — staff role required", 403);

  // Not set up yet? Say so before spending any of the hourly allowance below.
  let apiKey: string;
  try {
    apiKey = requireEnv("ANTHROPIC_API_KEY");
  } catch (err) {
    console.error("Claude API not configured:", err);
    return errorResponse("Auto-fill isn't set up on the server yet (see docs/AUTOFILL_SETUP.md).", 503);
  }

  // This calls a paid API per use, so it's capped tighter than a free action.
  if (!(await checkRateLimit(admin, `extract-event:${userId}`, 20, "1 hour"))) {
    return errorResponse("You've used this a lot in the last hour — try again a little later.", 429);
  }

  const todayLondon = new Date().toLocaleDateString("en-CA", { timeZone: "Europe/London" }); // YYYY-MM-DD

  const client = new Anthropic({ apiKey });
  try {
    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 4096,
      system: `You read one pasted block of text about a club event — an email, a press release, a partner's blurb — and extract what it tells you into the given fields. Today's date in London is ${todayLondon}; resolve relative dates ("next Tuesday", "this Thursday") against it, always choosing a date in the future.

Rules:
- Every date/time field ("starts_at", "ends_at", "doors_at") must be the LONDON LOCAL wall-clock time, as an ISO 8601 string with NO timezone offset (e.g. "2026-10-14T19:00:00"). If a time isn't stated, use null rather than guessing one.
- "description_md" is the event's full description, lightly reformatted as plain paragraphs separated by a blank line, with "- " for a bullet list and "**bold**" only where the source clearly emphasises something. Never write HTML or markdown headings.
- "category" must be exactly one of the given options, or null if none clearly fits — never invent a new category.
- Only set "venue_room" / "venue_address" if the text actually names a room or a different address; leave them null to mean "the club's usual venue".
- Only include a speaker, a link, or a perk if the text actually names one — never invent one to fill the field.
- Ticket prices, capacity, and ticket types are deliberately not fields you can fill in — that is always a decision for a person, never guess or imply one, even in "notes".
- "notes" is a short list of plain-English notes about anything you were not confident about and the person should check by hand (an uncertain date, a guessed category, an ambiguous venue). Leave it empty if there's nothing to flag.
- Never fabricate a fact that is not in the text.`,
      messages: [{ role: "user", content: body.text }],
      output_config: { format: zodOutputFormat(ExtractedEvent) },
    });

    if (!response.parsed_output) {
      return errorResponse("Couldn't make sense of that text — try pasting a shorter or clearer excerpt.", 502);
    }
    return jsonResponse({ fields: response.parsed_output });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) {
      return errorResponse("The auto-fill service is busy right now — try again in a minute.", 503);
    }
    if (err instanceof Anthropic.APIError) {
      console.error("Claude API error:", err.status, err.message);
      return errorResponse("The auto-fill service couldn't process that just now.", 502);
    }
    console.error("extract-event-details failed:", err);
    return errorResponse("internal error", 500);
  }
});
