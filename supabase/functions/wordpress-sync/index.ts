// wordpress-sync — briefing §12.3. News/blog posts stay authored in
// WordPress, where the club already works. Read-only, one direction: we
// never write back. Sanitises with the same strict tag allow-list used for
// event descriptions client-side (§9.2) — belt and braces, sanitise at
// sync time too, not only in the Flutter widget. Runs hourly via pg_cron.

import sanitizeHtml from "npm:sanitize-html@2.13.0";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, requireEnv } from "../_shared/supabase-clients.ts";

const ALLOWED_TAGS = ["p", "br", "strong", "em", "ul", "ol", "li", "a", "blockquote", "h2", "h3", "img"];
const PER_PAGE = 20;
const MAX_PAGES = 50; // safety valve — an hourly sync never needs to backfill 1000 posts in one run

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const baseUrl = requireEnv("WORDPRESS_BASE_URL").replace(/\/$/, "");
  const admin = createAdminClient();

  let page = 1;
  let upserted = 0;

  while (page <= MAX_PAGES) {
    const res = await fetch(`${baseUrl}/wp-json/wp/v2/posts?_embed&per_page=${PER_PAGE}&page=${page}`);
    if (res.status === 400) break; // WP returns 400 once you page past the last page
    if (!res.ok) {
      console.error(`wordpress-sync: fetch failed with ${res.status}`);
      break;
    }
    const posts = (await res.json()) as WpPost[];
    if (!Array.isArray(posts) || posts.length === 0) break;

    for (const post of posts) {
      const heroImage = post._embedded?.["wp:featuredmedia"]?.[0]?.source_url ?? null;
      const author = post._embedded?.author?.[0]?.name ?? null;
      const categories = (post._embedded?.["wp:term"]?.[0] ?? []).map((t) => t.name);

      const { error } = await admin.from("articles").upsert(
        {
          wp_post_id: post.id,
          slug: post.slug,
          title: stripHtml(post.title?.rendered ?? ""),
          excerpt: stripHtml(post.excerpt?.rendered ?? ""),
          content_html: sanitizeHtml(collapseSoftLineBreaks(post.content?.rendered ?? ""), {
            allowedTags: ALLOWED_TAGS,
            allowedAttributes: { a: ["href"], img: ["src", "alt"] },
          }),
          hero_image_url: heroImage,
          author_name: author,
          categories,
          canonical_url: post.link,
          published_at: post.date_gmt ? `${post.date_gmt}Z` : new Date().toISOString(),
          synced_at: new Date().toISOString(),
        },
        { onConflict: "wp_post_id" },
      );

      if (error) {
        console.error(`wordpress-sync: failed to upsert post ${post.id}:`, error);
        continue;
      }
      upserted++;
    }

    if (posts.length < PER_PAGE) break;
    page++;
  }

  return jsonResponse({ upserted });
});

// Title/excerpt are shown as plain text (Flutter Text widgets), unlike
// content_html which goes through an HTML renderer that decodes entities
// itself — these two need decoding here or WordPress's literal "&nbsp;"
// etc. shows up verbatim on screen.
const HTML_ENTITIES: Record<string, string> = {
  nbsp: " ",
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  "#039": "'",
  hellip: "…",
  mdash: "—",
  ndash: "–",
  ldquo: "“",
  rdquo: "”",
  lsquo: "‘",
  rsquo: "’",
};

function decodeHtmlEntities(text: string): string {
  return text.replace(/&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+\d*);/g, (match, entity) => {
    if (entity in HTML_ENTITIES) return HTML_ENTITIES[entity];
    if (entity.startsWith("#x")) return String.fromCodePoint(parseInt(entity.slice(2), 16));
    if (entity.startsWith("#")) return String.fromCodePoint(parseInt(entity.slice(1), 10));
    return match;
  });
}

// WordPress posts pasted from a word processor often carry a literal <br>
// after every line, hard-wrapped at desktop width — renders as a staircase
// of short lines on a phone instead of reflowing. Real paragraph breaks in
// this content use separate <p> tags or a run of 2+ <br>s; a lone <br>
// between two words is always a soft wrap, never a real paragraph break,
// so it's safe to fold into a space and let it reflow at any width.
function collapseSoftLineBreaks(html: string): string {
  return html.replace(/(?:<br\s*\/?>\s*)+/gi, (run) => {
    const count = (run.match(/<br\s*\/?>/gi) ?? []).length;
    return count === 1 ? " " : run;
  });
}

function stripHtml(html: string): string {
  return decodeHtmlEntities(html.replace(/<[^>]*>/g, "")).replace(/\s+/g, " ").trim();
}

interface WpPost {
  id: number;
  slug: string;
  link: string;
  date_gmt?: string;
  title?: { rendered: string };
  excerpt?: { rendered: string };
  content?: { rendered: string };
  _embedded?: {
    "wp:featuredmedia"?: Array<{ source_url: string }>;
    author?: Array<{ name: string }>;
    "wp:term"?: Array<Array<{ name: string }>>;
  };
}
