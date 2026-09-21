import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../event_draft.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';

/// The speaker list — name, role, bio, photo.
class SpeakersSection extends StatelessWidget {
  const SpeakersSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    return SectionCard(
      title: 'Speakers',
      subtitle: 'In the order they should appear.',
      trailing: enabled
          ? TextButton.icon(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add speaker'),
              onPressed: () {
                d.speakers.add(SpeakerDraft());
                controller.touch();
              },
            )
          : null,
      child: d.speakers.isEmpty
          ? Text('No speakers yet.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate))
          : Column(
              children: <Widget>[
                for (int i = 0; i < d.speakers.length; i++)
                  _SpeakerRow(
                    key: ObjectKey(d.speakers[i]),
                    controller: controller,
                    speaker: d.speakers[i],
                    index: i,
                    enabled: enabled,
                  ),
              ],
            ),
    );
  }
}

class _SpeakerRow extends StatelessWidget {
  const _SpeakerRow({required this.controller, required this.speaker, required this.index, required this.enabled, super.key});

  final EventEditorController controller;
  final SpeakerDraft speaker;
  final int index;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;

    Future<void> pickPhoto() async {
      final String? url = await pickAndUploadImage(context, controller.repository);
      if (url != null) {
        speaker.photoUrl = url;
        controller.touch();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: FlcSpace.sm),
      padding: const EdgeInsets.all(FlcSpace.sm),
      decoration: BoxDecoration(
        border: Border.all(color: FlcColors.line),
        borderRadius: BorderRadius.circular(FlcRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: enabled ? pickPhoto : null,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: FlcColors.brand.withValues(alpha: 0.08),
              backgroundImage: speaker.photoUrl == null ? null : NetworkImage(speaker.photoUrl!),
              child: speaker.photoUrl == null ? const Icon(Icons.add_a_photo_outlined, color: FlcColors.brand) : null,
            ),
          ),
          const SizedBox(width: FlcSpace.sm),
          Expanded(
            child: Column(
              children: <Widget>[
                ResponsiveRow(
                  children: <Widget>[
                    TextFormField(
                      initialValue: speaker.name,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Name', isDense: true),
                      onChanged: (String v) {
                        speaker.name = v;
                        controller.touch();
                      },
                    ),
                    TextFormField(
                      initialValue: speaker.role,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Role', hintText: 'BBC correspondent', isDense: true),
                      onChanged: (String v) {
                        speaker.role = v;
                        controller.touch();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: FlcSpace.xs),
                TextFormField(
                  initialValue: speaker.bio,
                  enabled: enabled,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: 'Short bio', isDense: true),
                  onChanged: (String v) {
                    speaker.bio = v;
                    controller.touch();
                  },
                ),
              ],
            ),
          ),
          if (enabled)
            Column(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Move up',
                  onPressed: index == 0
                      ? null
                      : () {
                          d.speakers.insert(index - 1, d.speakers.removeAt(index));
                          controller.touch();
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Move down',
                  onPressed: index == d.speakers.length - 1
                      ? null
                      : () {
                          d.speakers.insert(index + 1, d.speakers.removeAt(index));
                          controller.touch();
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () {
                    d.speakers.removeAt(index);
                    controller.touch();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Extra links — the book to buy, the film's page, a reading list…
class LinksSection extends StatelessWidget {
  const LinksSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;

    return SectionCard(
      title: 'Links',
      subtitle: 'Buttons on the event page — e.g. "Buy the book", "Watch the trailer", "Donate".',
      trailing: enabled
          ? TextButton.icon(
              icon: const Icon(Icons.add_link),
              label: const Text('Add link'),
              onPressed: () {
                d.links.add(LinkDraft());
                controller.touch();
              },
            )
          : null,
      child: d.links.isEmpty
          ? Text('No links yet.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate))
          : Column(
              children: <Widget>[
                for (final LinkDraft link in d.links)
                  _LinkRow(key: ObjectKey(link), controller: controller, link: link, enabled: enabled),
              ],
            ),
    );
  }
}

/// One link: type · button text · address on a wide screen; stacked on a phone.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.controller, required this.link, required this.enabled, super.key});

  final EventEditorController controller;
  final LinkDraft link;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget kind = DropdownButtonFormField<String>(
      initialValue: link.kind,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Type', isDense: true),
      items: <DropdownMenuItem<String>>[
        for (final String k in EventLinkKind.all) DropdownMenuItem<String>(value: k, child: Text(EventLinkKind.label(k))),
      ],
      onChanged: enabled
          ? (String? v) {
              link.kind = v ?? EventLinkKind.link;
              controller.touch();
            }
          : null,
    );
    final Widget label = TextFormField(
      initialValue: link.label,
      enabled: enabled,
      decoration: const InputDecoration(labelText: 'Button text', hintText: 'Buy the book', isDense: true),
      onChanged: (String v) {
        link.label = v;
        controller.touch();
      },
    );
    final Widget url = TextFormField(
      initialValue: link.url,
      enabled: enabled,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(labelText: 'Web address', hintText: 'https://…', isDense: true),
      onChanged: (String v) {
        link.url = v;
        controller.touch();
      },
    );
    final Widget remove = enabled
        ? IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: () {
              controller.draft.links.remove(link);
              controller.touch();
            },
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth >= 620) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 130, child: kind),
                const SizedBox(width: FlcSpace.xs),
                Expanded(flex: 2, child: label),
                const SizedBox(width: FlcSpace.xs),
                Expanded(flex: 3, child: url),
                remove,
              ],
            );
          }
          return Container(
            padding: const EdgeInsets.all(FlcSpace.sm),
            decoration: BoxDecoration(border: Border.all(color: FlcColors.line), borderRadius: BorderRadius.circular(FlcRadius.card)),
            child: Column(
              children: <Widget>[
                Row(children: <Widget>[Expanded(child: kind), remove]),
                const SizedBox(height: FlcSpace.xs),
                label,
                const SizedBox(height: FlcSpace.xs),
                url,
              ],
            ),
          );
        },
      ),
    );
  }
}
