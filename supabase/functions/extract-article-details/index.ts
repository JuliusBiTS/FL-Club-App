// extract-article-details — staff paste a whole draft (a Word doc, an email, a
// blurb from a contributor) and get back a best-effort split into the
// article's fields via the Claude API: title, summary, body, type, author,
// date and original link. Nothing is written to the database; the person
// reviews the result in the editor and publishes it themselves.
//
// The model is told to keep the author's own words. It sorts and tidies; it
// does not rewrite, shorten or add facts.

import Anthropic from "npm:@anthropic-ai/sdk@0.127.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@0.127.0/helpers/zod";
// v4 on purpose — see extract-event-details for why.
import { z } from "npm:zod@4.6.5";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

const MAX_INPUT_CHARS = 30000; // a long feature piece
const MIN_INPUT_CHARS = 20;

const ExtractedArticle = z.object({
  title: z.string().nullable(),
  excerpt: z.string().nullable(),
  body: z.string().nullable(),
  kind: z.enum(["Story", "Blog"]).nullable(),
  author_name: z.string().nullable(),
  published_on: z.string().nullable(),
  link_url: z.string().nullable(),
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
      return errorResponse("That's very long — paste up to about 5,000 words at a time.", 400);
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

  let apiKey: string;
  try {
    apiKey = requireEnv("ANTHROPIC_API_KEY");
  } catch (err) {
    console.error("Claude API not configured:", err);
    return errorResponse("Auto-fill isn't set up on the server yet (see docs/AUTOFILL_SETUP.md).", 503);
  }

  if (!(await checkRateLimit(admin, `extract-article:${userId}`, 20, "1 hour"))) {
    return errorResponse("You've used this a lot in the last hour — try again a little later.", 429);
  }

  const todayLondon = new Date().toLocaleDateString("en-CA", { timeZone: "Europe/London" });

  const client = new Anthropic({ apiKey });
  try {
    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 16000,
      system: `You read one pasted block of text — a draft article, story, blog post, or an email containing one — and sort it into the given fields. Today's date in London is ${todayLondon}.

Rules:
- Keep the author's own words. Do not rewrite, shorten, summarise or add anything to "body"; only tidy it: remove email headers/signatures/"Dear…" wrappers that are not part of the piece, fix obvious line-break damage, and separate paragraphs with a blank line. Never write HTML or markdown headings; "- " for a real bullet list is fine.
- "title": the piece's own headline if it has one; otherwise null (do not invent a headline).
- "excerpt": one or two sentences to show under the title. Use the piece's own standfirst/intro if it has one; otherwise you may write a short neutral summary using only facts in the text.
- "kind": "Story" for a reported/feature/narrative piece, "Blog" for an opinion, commentary or club-news post; null if unclear.
- "author_name": only if the text names the author (a byline or sign-off). Never guess.
- "published_on": a date as YYYY-MM-DD only if the text states when it was written or published; else null.
- "link_url": only if the text gives a URL for the original publication; else null.
- "notes": short plain-English notes on anything the person should check by hand (missing headline, unclear author, text that looked like boilerplate you removed). Empty if nothing to flag.
- Never fabricate a fact that is not in the text.`,
      messages: [{ role: "user", content: body.text }],
      output_config: { format: zodOutputFormat(ExtractedArticle) },
    });

    if (!response.parsed_output) {
      return errorResponse("Couldn't make sense of that text — try pasting a clearer excerpt.", 502);
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
    console.error("extract-article-details failed:", err);
    return errorResponse("internal error", 500);
  }
});
