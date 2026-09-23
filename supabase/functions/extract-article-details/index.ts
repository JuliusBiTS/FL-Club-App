// extract-article-details — staff paste a whole draft (a Word doc, an email, a
// blurb from a contributor) and get back a best-effort split into the
// article's fields via the Claude API: title, summary, body, type, author,
// date and original link. Nothing is written to the database; the person
// reviews the result in the editor and publishes it themselves.
// The model NEVER writes article text. It only points at passages of the pasted
// text (verbatim quotes, verified by substring match) and classifies; the body
// is the original text with the title/byline/email wrapper cut out, by code.


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

// The model never writes any text that ends up in the article. It only POINTS
// at passages of the pasted text (verbatim quotes) and classifies. Every quote
// is then checked against the original with a plain substring test, and the
// article body is built by CODE: the original text with the title / byline /
// email wrapper cut out. If the model invents or alters a quote it simply
// doesn't match and is ignored. That is what makes "never rewrite, never
// generate" a property of the program rather than a request to the model.
const Pointers = z.object({
  title_quote: z.string().nullable(),
  excerpt_quote: z.string().nullable(),
  author_quote: z.string().nullable(),
  date_quote: z.string().nullable(),
  published_on: z.string().nullable(),
  link_quote: z.string().nullable(),
  kind: z.enum(["Story", "Blog"]).nullable(),
  remove_quotes: z.array(z.string()),
  notes: z.array(z.string()),
});

function found(text: string, quote: string | null): string | null {
  if (!quote) return null;
  const q = quote.trim();
  return q.length > 0 && text.includes(q) ? q : null;
}

function buildFields(text: string, p: z.infer<typeof Pointers>) {
  const title = found(text, p.title_quote);
  if (title && (title.length > 200 || title.includes("\n"))) return buildFields(text, { ...p, title_quote: null });
  const excerpt = found(text, p.excerpt_quote);
  const author = found(text, p.author_quote);
  const link = found(text, p.link_quote);
  const dateQuote = found(text, p.date_quote);
  const publishedOn = dateQuote && p.published_on && /^\d{4}-\d{2}-\d{2}$/.test(p.published_on) ? p.published_on : null;

  // Body = the original text minus the pieces the model pointed at. Nothing is
  // reworded; only whole, verified passages are cut, and never more than 40%.
  let body = text.replace(/\r\n/g, "\n");
  const cuts = [title, ...p.remove_quotes.map((q) => found(text, q))].filter((q): q is string => !!q && q.length <= 1500);
  const original = body.length;
  for (const c of cuts) {
    const next = body.replace(c, "");
    if (original - next.length <= original * 0.4) body = next;
  }
  body = body.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();

  return {
    title,
    excerpt,
    body: body.length > 0 ? body : null,
    kind: p.kind,
    author_name: author,
    published_on: publishedOn,
    link_url: link,
    notes: p.notes,
  };
}

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
      max_tokens: 4096,
      system: `You are a filing assistant for a journalism club. You read one pasted block of text — a draft article, story or blog post, possibly wrapped in an email — and POINT AT parts of it. You never write, rewrite, summarise, shorten, correct or improve any text. Today's date in London is ${todayLondon}.

Every "…_quote" field must be copied CHARACTER FOR CHARACTER from the pasted text, exactly as it appears, including its punctuation and spelling. If you cannot copy something exactly, use null. Anything you paraphrase will be thrown away.

Fields:
- "title_quote": the piece's own headline line, only if it has one; else null. Never invent a headline.
- "excerpt_quote": one or two consecutive sentences copied from the piece's own opening or standfirst, to show under the title. Copy only; do not summarise. Null if unsure.
- "author_quote": the author's name as written in a byline or sign-off; null if the text doesn't name them.
- "date_quote": a date exactly as written in the text (e.g. "12 September 2026") if the text says when the piece was written or published; else null. "published_on": that same date as YYYY-MM-DD (null if date_quote is null).
- "link_quote": a URL copied exactly, only if the text gives one for the original publication.
- "kind": "Story" for a reported/feature/narrative piece, "Blog" for opinion, commentary or club news; null if unclear.
- "remove_quotes": passages that are NOT part of the article and should be cut, each copied exactly: email headers, greetings ("Hi Martin,"), sign-offs, the byline line, the date line. Never list any sentence of the article itself.
- "notes": short plain notes for the editor about anything to check by hand (no headline found, unclear author, text that looks unfinished). Notes are shown to the editor only and are never published.`,
      messages: [{ role: "user", content: body.text }],
      output_config: { format: zodOutputFormat(Pointers) },
    });

    if (!response.parsed_output) {
      return errorResponse("Couldn't make sense of that text — try pasting a clearer excerpt.", 502);
    }
    return jsonResponse({ fields: buildFields(body.text, response.parsed_output) });
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
