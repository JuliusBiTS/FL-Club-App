<?php
/**
 * Plugin Name: Frontline Club Events
 * Description: Renders events from the club's Supabase backend into the existing theme via a [frontline_events] shortcode and block. Read-only — this plugin never writes to Supabase. See briefing §12.2: the app's admin console is the single source of truth for events; the website only renders from it.
 * Version: 0.1.0
 * Author: The Frontline Club
 * License: GPL-2.0-or-later
 * Text Domain: frontline-events
 */

if (!defined('ABSPATH')) {
    exit; // no direct access
}

/**
 * Configuration. Define these in wp-config.php (NOT in this file, which is
 * version-controlled):
 *
 *   define('FLC_SUPABASE_URL', 'https://<project-ref>.supabase.co');
 *   define('FLC_SUPABASE_ANON_KEY', '<anon-key>');
 *
 * The anon key is safe to ship here — it's meaningless without RLS, which
 * is the real gate (supabase/migrations/20260817000009_rls_policies.sql
 * only ever exposes status='published' events to it). This plugin never
 * uses the service_role key and never writes to Supabase.
 */
function flc_supabase_configured(): bool
{
    return defined('FLC_SUPABASE_URL') && defined('FLC_SUPABASE_ANON_KEY');
}

const FLC_CACHE_TTL_SECONDS = 300; // 5-minute transient cache, briefing §12.2
const FLC_REWRITE_QUERY_VAR = 'flc_event_slug';

/**
 * Fetches events directly from PostgREST (no separate Edge Function
 * needed for a plain read) and caches the response in a WP transient.
 * Direction of truth is Supabase -> WordPress, read-only, always.
 *
 * @param array<string,string> $filters e.g. ['slug' => 'eq.some-slug']
 */
function flc_fetch_events(array $filters = [], int $limit = 20): array
{
    if (!flc_supabase_configured()) {
        return [];
    }

    $cache_key = 'flc_events_' . md5(serialize($filters) . $limit);
    $cached = get_transient($cache_key);
    if ($cached !== false) {
        return $cached;
    }

    $query = array_merge(
        [
            'select' => '*',
            'order' => 'starts_at.asc',
            'limit' => (string) $limit,
        ],
        $filters
    );
    if (!isset($filters['status'])) {
        $query['status'] = 'eq.published'; // never expose draft events publicly
    }

    $url = trailingslashit(FLC_SUPABASE_URL) . 'rest/v1/events?' . http_build_query($query);

    $response = wp_remote_get($url, [
        'headers' => [
            'apikey' => FLC_SUPABASE_ANON_KEY,
            'Authorization' => 'Bearer ' . FLC_SUPABASE_ANON_KEY,
        ],
        'timeout' => 8,
    ]);

    if (is_wp_error($response) || wp_remote_retrieve_response_code($response) !== 200) {
        // Fail quietly with an empty list rather than breaking the page —
        // a sync hiccup on the website must never take the site down.
        return $cached !== false ? $cached : [];
    }

    $events = json_decode(wp_remote_retrieve_body($response), true) ?: [];
    set_transient($cache_key, $events, FLC_CACHE_TTL_SECONDS);

    return $events;
}

function flc_format_event_date(string $iso8601): string
{
    try {
        $dt = new DateTime($iso8601);
        $dt->setTimezone(new DateTimeZone('Europe/London')); // venue timezone, never server/visitor timezone — briefing §7.3
        return $dt->format('D j M Y, H:i');
    } catch (Exception $e) {
        return $iso8601;
    }
}

function flc_event_permalink(string $slug): string
{
    return home_url('/events/' . rawurlencode($slug) . '/');
}

/** Renders the shared list markup used by both the shortcode and the block. */
function flc_render_events_list(array $atts = []): string
{
    $limit = isset($atts['limit']) ? (int) $atts['limit'] : 6;
    $events = flc_fetch_events([], $limit);

    if (!flc_supabase_configured()) {
        return current_user_can('manage_options')
            ? '<p><em>Frontline Events: define FLC_SUPABASE_URL and FLC_SUPABASE_ANON_KEY in wp-config.php.</em></p>'
            : '';
    }

    if (empty($events)) {
        return '<p>' . esc_html__('No events scheduled right now — check back soon.', 'frontline-events') . '</p>';
    }

    ob_start(); ?>
    <div class="flc-events-list">
        <?php foreach ($events as $event): ?>
            <a class="flc-event-card" href="<?php echo esc_url(flc_event_permalink($event['slug'])); ?>">
                <?php if (!empty($event['hero_image_path'])): ?>
                    <img src="<?php echo esc_url($event['hero_image_path']); ?>" alt="" loading="lazy" />
                <?php endif; ?>
                <div class="flc-event-card__body">
                    <?php if (!empty($event['category'])): ?>
                        <span class="flc-event-card__category"><?php echo esc_html($event['category']); ?></span>
                    <?php endif; ?>
                    <h3 class="flc-event-card__title"><?php echo esc_html($event['title']); ?></h3>
                    <p class="flc-event-card__date"><?php echo esc_html(flc_format_event_date($event['starts_at'])); ?></p>
                </div>
            </a>
        <?php endforeach; ?>
    </div>
    <?php
    return ob_get_clean();
}
add_shortcode('frontline_events', 'flc_render_events_list');

/**
 * A minimal dynamic block wrapping the shortcode — server-rendered, no
 * build step. Just enough JS to register it in the block inserter; all
 * real rendering happens in PHP via render_callback.
 */
add_action('init', function () {
    if (!function_exists('register_block_type')) {
        return; // WP too old for block support — the shortcode still works
    }
    register_block_type('frontline-club/events', [
        'render_callback' => 'flc_render_events_list',
        'attributes' => ['limit' => ['type' => 'number', 'default' => 6]],
        'editor_script' => 'flc-events-block-editor',
    ]);
});

add_action('enqueue_block_editor_assets', function () {
    wp_register_script('flc-events-block-editor', false, ['wp-blocks', 'wp-element', 'wp-block-editor'], '0.1.0', true);
    wp_add_inline_script('flc-events-block-editor', <<<'JS'
        (function (blocks, element) {
            blocks.registerBlockType('frontline-club/events', {
                title: 'Frontline Club Events',
                icon: 'calendar-alt',
                category: 'widgets',
                attributes: { limit: { type: 'number', default: 6 } },
                edit: function () {
                    return element.createElement('p', {}, 'Frontline Club Events (rendered on the front end)');
                },
                save: function () {
                    return null; // server-rendered, briefing §12.2
                },
            });
        })(window.wp.blocks, window.wp.element);
    JS);
    wp_enqueue_script('flc-events-block-editor');
});

/**
 * Individual event pages at /events/<slug>/ — briefing §12.2: "so the
 * app's deep links and share links resolve on the web too." Rendered as a
 * virtual page (no actual WP post) so the events database has exactly one
 * source of truth.
 */
add_action('init', function () {
    add_rewrite_rule('^events/([^/]+)/?$', 'index.php?' . FLC_REWRITE_QUERY_VAR . '=$matches[1]', 'top');
});
add_filter('query_vars', function (array $vars): array {
    $vars[] = FLC_REWRITE_QUERY_VAR;
    return $vars;
});

add_action('template_redirect', function () {
    $slug = get_query_var(FLC_REWRITE_QUERY_VAR);
    if (empty($slug)) {
        return;
    }

    $events = flc_fetch_events(['slug' => 'eq.' . $slug], 1);
    if (empty($events)) {
        global $wp_query;
        $wp_query->set_404();
        status_header(404);
        get_template_part(404);
        exit;
    }
    $event = $events[0];

    get_header();
    ?>
    <article class="flc-event-detail">
        <h1><?php echo esc_html($event['title']); ?></h1>
        <?php if (!empty($event['subtitle'])): ?><p class="flc-event-subtitle"><?php echo esc_html($event['subtitle']); ?></p><?php endif; ?>
        <p><?php echo esc_html(flc_format_event_date($event['starts_at'])); ?> · <?php echo esc_html($event['venue_room'] ?? $event['venue_name']); ?></p>
        <?php if (!empty($event['description_html'])): ?>
            <div class="flc-event-description">
                <?php echo wp_kses_post($event['description_html']); ?>
            </div>
        <?php endif; ?>
        <p class="flc-event-cta">
            <?php esc_html_e('Book tickets in the Frontline Club app.', 'frontline-events'); ?>
        </p>
    </article>
    <?php
    get_footer();
    exit;
});

/**
 * JSON-LD structured data for event detail pages — free SEO, and it makes
 * events appear in Google's event listings (briefing §12.2).
 */
add_action('wp_head', function () {
    $slug = get_query_var(FLC_REWRITE_QUERY_VAR);
    if (empty($slug)) {
        return;
    }
    $events = flc_fetch_events(['slug' => 'eq.' . $slug], 1);
    if (empty($events)) {
        return;
    }
    $event = $events[0];

    $json_ld = [
        '@context' => 'https://schema.org',
        '@type' => 'Event',
        'name' => $event['title'],
        'startDate' => $event['starts_at'],
        'eventAttendanceMode' => 'https://schema.org/OfflineEventAttendanceMode',
        'eventStatus' => 'https://schema.org/EventScheduled',
        'location' => [
            '@type' => 'Place',
            'name' => $event['venue_name'] ?? 'The Frontline Club',
            'address' => $event['venue_address'] ?? '13 Norfolk Place, London W2 1QJ',
        ],
        'organizer' => [
            '@type' => 'Organization',
            'name' => 'The Frontline Club',
            'url' => 'https://www.frontlineclub.com',
        ],
    ];
    echo '<script type="application/ld+json">' . wp_json_encode($json_ld) . '</script>' . "\n";
});

register_activation_hook(__FILE__, function () {
    flc_ensure_rewrite_rules_flushed();
});
function flc_ensure_rewrite_rules_flushed(): void
{
    // Rewrite rules are registered on 'init', which hasn't run yet during
    // activation — trigger it once, then flush.
    do_action('init');
    flush_rewrite_rules();
}
register_deactivation_hook(__FILE__, 'flush_rewrite_rules');
