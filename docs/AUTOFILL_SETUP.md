# Switching on "Paste details to auto-fill"

In the event editor, staff can paste a block of text — an email, a press release, a
partner's blurb — and click **Auto-fill**. It fills in whatever blank fields it can
(title, date/time, venue, description, speakers, links, tags) using the Claude API.

It never touches price, capacity, or ticket types — those aren't fields the server is
even allowed to return, so there's no way for it to guess one. It also never overwrites
anything already typed in by hand; it only fills blanks, and always shows a summary of
what it filled in, what it left alone, and anything it wasn't confident about.

Cost: this calls a paid API, per use — roughly **2-3 US cents per paste** (see
"What it costs" below). Everything else in this app runs on free tiers; this is the one
part that isn't. Without the key below, the button simply says the feature isn't set up
yet — nothing else in the app is affected.

## 1. Get an API key

You mentioned you already have Claude API access loaded up — use that:

1. Sign in at [console.anthropic.com](https://console.anthropic.com) with the account
   that has it.
2. **Settings → API keys → Create key.**
3. Copy it — it's shown once. Treat it like a password: never paste it into chat, git,
   or anywhere else it could leak.

(If you ever need to do this again on a different account — say, if the club wants its
own separate one later — same steps, just sign up fresh first.)

## 2. Store it as a Supabase secret

From the `supabase/` folder, run this yourself in your own terminal (so the real key
never passes through this chat):

```bash
supabase secrets set ANTHROPIC_API_KEY="sk-ant-...your key..."
```

## 3. Deploy the function

```bash
supabase functions deploy extract-event-details
```

## 4. Try it

In the event editor (console or app), open **New event**, click **Paste details**, and
paste in something like a real (or made-up, for testing) event announcement — a few
sentences with a date, a venue, and a speaker or two. Click **Auto-fill** and check the
summary it shows afterwards.

## What it costs

Uses `claude-opus-5` — Anthropic's guidance is not to downgrade to a cheaper model just
to save money without you deciding that; it's your call, not an automatic one. For a
typical paste (a few hundred words in, a small set of fields back out):

| | Tokens | Cost |
|---|---|---|
| Input (your text + instructions) | ~2,500 | ~$0.0125 |
| Output (the extracted fields) | ~500 | ~$0.0125 |
| **Per use** | | **~2-3 US cents** |

At, say, 50 uses a month that's roughly $1-1.50 — small next to the project's
£0-25/month target, but genuinely not free, unlike everything else in this app.

**To cut the cost further:** ask me to switch the model in
`supabase/functions/extract-event-details/index.ts` to `claude-haiku-4-5`, which is
about 5x cheaper per call. It's a one-line change; quality may be slightly less precise
on messier or more oddly-formatted text, but for a clearly-written paste it should still
do a good job.

## Troubleshooting

- **"This API key is not scoped to a workspace..."** — the key was created at the
  account's general level rather than inside one specific workspace. Fix: in the
  Console, open a **Workspace** (sidebar) → that workspace's own **API Keys** tab →
  **Create Key** there instead, and replace the secret with the new value.
- Anything else: check **Supabase dashboard → Edge Functions → extract-event-details →
  Logs** — the real error is logged there even though the app only shows a generic
  message.

## Limits

- Best on a well-written source (an email, a press release). Very short or vague text
  just comes back mostly empty — the field summary says so, and nothing is guessed.
- Dates are resolved against today's date in London — check them, especially for
  anything phrased as "next Tuesday" or similar.
- Rate-limited to 20 uses per staff member per hour, since each use costs money.
- If the key above is ever rotated or removed, the button keeps working for everything
  else in the app — it just goes back to saying auto-fill isn't set up.
