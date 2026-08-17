// podcast-sync — briefing §9.8. We consume the public RSS feed directly —
// no Spotify SDK, no auth, no branding requirements, keeps us independent
// of Spotify. Runs hourly via pg_cron. [CONFIRM] the canonical feed URL
// with the club — see docs/OPEN_QUESTIONS.md.

import { XMLParser } from "npm:fast-xml-parser@4.5.0";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, requireEnv } from "../_shared/supabase-clients.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const feedUrl = requireEnv("PODCAST_RSS_URL");
  const res = await fetch(feedUrl);
  if (!res.ok) return errorResponse(`could not fetch podcast feed: ${res.status}`, 502);
  const xml = await res.text();

  const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_" });
  const feed = parser.parse(xml);
  const items = feed?.rss?.channel?.item;
  const itemList = Array.isArray(items) ? items : items ? [items] : [];

  const admin = createAdminClient();
  let upserted = 0;

  for (const item of itemList) {
    const guid = typeof item.guid === "object" ? item.guid["#text"] : item.guid;
    const audioUrl = item.enclosure?.["@_url"];
    if (!guid || !audioUrl) continue; // upsert key is guid — skip anything RSS-malformed rather than fail the whole sync

    const { error } = await admin.from("podcast_episodes").upsert(
      {
        guid: String(guid),
        title: item.title ?? "Untitled episode",
        description_html: item["content:encoded"] ?? item.description ?? null,
        audio_url: audioUrl,
        duration_seconds: parseItunesDuration(item["itunes:duration"]),
        image_url: item["itunes:image"]?.["@_href"] ?? null,
        episode_number: item["itunes:episode"] ? Number(item["itunes:episode"]) : null,
        season: item["itunes:season"] ? Number(item["itunes:season"]) : null,
        published_at: item.pubDate ? new Date(item.pubDate).toISOString() : new Date().toISOString(),
        explicit: ["yes", "true"].includes(String(item["itunes:explicit"]).toLowerCase()),
        synced_at: new Date().toISOString(),
      },
      { onConflict: "guid" },
    );

    if (error) {
      console.error(`podcast-sync: failed to upsert episode ${guid}:`, error);
      continue;
    }
    upserted++;
  }

  return jsonResponse({ upserted, total: itemList.length });
});

function parseItunesDuration(raw: unknown): number | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (/^\d+$/.test(s)) return Number(s); // already plain seconds
  const parts = s.split(":").map(Number);
  if (parts.length === 0 || parts.some((p) => Number.isNaN(p))) return null;
  return parts.reduceRight((acc, val, idx, arr) => acc + val * Math.pow(60, arr.length - 1 - idx), 0);
}
