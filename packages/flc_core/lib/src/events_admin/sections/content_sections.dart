import 'package:flutter/material.dart';

import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../event_draft.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';

/// Title, summary, category, tags.
class BasicsSection extends StatelessWidget {
  const BasicsSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;
    // A category the club added outside this list (older events) must still show.
    final List<String> categories = <String>[
      ...kEventCategories,
      if (d.category != null && !kEventCategories.contains(d.category)) d.category!,
    ];

    return SectionCard(
      title: 'The basics',
      subtitle: 'What people see first, on the event card.',
      child: Column(
        children: <Widget>[
          TextFormField(
            initialValue: d.title,
            enabled: enabled,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title *', hintText: 'e.g. Afghanistan 2026'),
            onChanged: (String v) {
              d.title = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.sm),
          TextFormField(
            initialValue: d.subtitle,
            enabled: enabled,
            maxLength: 140,
            decoration: const InputDecoration(
              labelText: 'Subtitle',
              hintText: 'e.g. An updated look at power, exile and the situation for women',
            ),
            onChanged: (String v) {
              d.subtitle = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.sm),
          TextFormField(
            initialValue: d.summary,
            enabled: enabled,
            maxLength: 200,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Short summary',
              helperText: 'One or two sentences. Shown on the card and in search results.',
              helperMaxLines: 2,
            ),
            onChanged: (String v) {
              d.summary = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.sm),
          DropdownButtonFormField<String>(
            key: ValueKey('category-${controller.formGeneration}'),
            initialValue: d.category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: <DropdownMenuItem<String>>[
              for (final String c in categories) DropdownMenuItem<String>(value: c, child: Text(c)),
            ],
            onChanged: enabled
                ? (String? v) {
                    d.category = v;
                    controller.touch();
                  }
                : null,
          ),
          const SizedBox(height: FlcSpace.sm),
          ChipsInput(
            label: 'Tags',
            hint: 'e.g. Ukraine, press freedom — press Enter to add',
            values: d.tags,
            enabled: enabled,
            maxItems: 12,
            onChanged: (List<String> v) {
              d.tags = v;
              controller.touch();
            },
          ),
        ],
      ),
    );
  }
}

/// Date, time, venue, online.
class ScheduleSection extends StatelessWidget {
  const ScheduleSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    return SectionCard(
      title: 'When & where',
      subtitle: 'All times are London time, whatever time zone you\'re in right now.',
      child: Column(
        children: <Widget>[
          ResponsiveRow(
            children: <Widget>[
              DateTimeField(
                label: 'Starts *',
                value: d.startsAt,
                enabled: enabled,
                onChanged: (DateTime? v) {
                  d.startsAt = v;
                  controller.touch();
                },
              ),
              DateTimeField(
                label: 'Ends',
                value: d.endsAt,
                enabled: enabled,
                clearable: true,
                onChanged: (DateTime? v) {
                  d.endsAt = v;
                  controller.touch();
                },
              ),
              DateTimeField(
                label: 'Doors open',
                value: d.doorsAt,
                enabled: enabled,
                clearable: true,
                onChanged: (DateTime? v) {
                  d.doorsAt = v;
                  controller.touch();
                },
              ),
            ],
          ),
          const SizedBox(height: FlcSpace.sm),
          ResponsiveRow(
            children: <Widget>[
              TextFormField(
                key: ValueKey('venueName-${controller.formGeneration}'),
                initialValue: d.venueName,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Venue'),
                onChanged: (String v) {
                  d.venueName = v;
                  controller.touch();
                },
              ),
              TextFormField(
                key: ValueKey('venueRoom-${controller.formGeneration}'),
                initialValue: d.venueRoom,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Room', hintText: 'The Forum, Clubroom…'),
                onChanged: (String v) {
                  d.venueRoom = v;
                  controller.touch();
                },
              ),
            ],
          ),
          const SizedBox(height: FlcSpace.sm),
          TextFormField(
            key: ValueKey('venueAddress-${controller.formGeneration}'),
            initialValue: d.venueAddress,
            enabled: enabled,
            decoration: const InputDecoration(labelText: 'Address'),
            onChanged: (String v) {
              d.venueAddress = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('This is an online event (or has a livestream)'),
            value: d.isOnline,
            onChanged: enabled
                ? (bool v) {
                    d.isOnline = v;
                    controller.touch();
                  }
                : null,
          ),
          if (d.isOnline)
            TextFormField(
              initialValue: d.livestreamUrl,
              enabled: enabled,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Livestream link',
                hintText: 'https://…',
                helperText: 'A "Watch live" button appears on the event page from 15 minutes before it starts. For a paid stream, leave this empty and send the link to ticket holders yourself.',
                helperMaxLines: 3,
              ),
              onChanged: (String v) {
                d.livestreamUrl = v;
                controller.touch();
              },
            ),
        ],
      ),
    );
  }
}

/// Hero picture + gallery.
class MediaSection extends StatelessWidget {
  const MediaSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    return SectionCard(
      title: 'Pictures',
      subtitle: 'JPG, PNG or WebP, up to 8 MB. The main picture is cropped to 16:9 — around 1600 × 900 works best.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ImageSlot(
            repository: controller.repository,
            url: d.heroImageUrl,
            enabled: enabled,
            label: 'Add the main picture',
            onChanged: (String? url) {
              d.heroImageUrl = url;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.md),
          Text('Gallery (optional)', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: FlcSpace.xs),
          Wrap(
            spacing: FlcSpace.xs,
            runSpacing: FlcSpace.xs,
            children: <Widget>[
              for (int i = 0; i < d.gallery.length; i++)
                SizedBox(
                  width: 120,
                  child: ImageSlot(
                    repository: controller.repository,
                    url: d.gallery[i],
                    aspectRatio: 1,
                    enabled: enabled,
                    onChanged: (String? url) {
                      if (url == null) {
                        d.gallery.removeAt(i);
                      } else {
                        d.gallery[i] = url;
                      }
                      controller.touch();
                    },
                  ),
                ),
              if (enabled && d.gallery.length < 8)
                SizedBox(
                  width: 120,
                  child: ImageSlot(
                    repository: controller.repository,
                    url: null,
                    aspectRatio: 1,
                    label: 'Add',
                    onChanged: (String? url) {
                      if (url != null) {
                        d.gallery.add(url);
                        controller.touch();
                      }
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The long description and filming notice.
class AboutSection extends StatelessWidget {
  const AboutSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    return SectionCard(
      title: 'About this event',
      subtitle: 'The full description on the event page.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkdownField(
            initialValue: d.descriptionMd,
            enabled: enabled,
            onChanged: (String v) {
              d.descriptionMd = v;
              controller.touch();
            },
          ),
          const SizedBox(height: FlcSpace.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('This event will be filmed'),
            subtitle: Text(
              'Shows the filming notice: footage may be used publicly and commercially.',
              style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
            ),
            value: d.isFilmed,
            onChanged: enabled
                ? (bool v) {
                    d.isFilmed = v;
                    controller.touch();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
