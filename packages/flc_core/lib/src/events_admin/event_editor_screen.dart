import 'package:flutter/material.dart';

import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import '../util/london_time.dart';
import 'event_admin_repository.dart';
import 'event_draft.dart';
import 'event_editor_controller.dart';
import 'event_preview.dart';
import 'sections/commerce_sections.dart';
import 'sections/content_sections.dart';
import 'sections/people_sections.dart';
import 'sections/promotion_sections.dart';
import 'sections/push_composer.dart';

/// The one event editor, used by the admin console (web) and by staff inside
/// the mobile app. Wide screens get a live preview + checklist beside the
/// form; phones get the form with a preview button.
///
/// Pass [eventId] to edit, [copyOf] to start from a duplicate, or neither to
/// start a blank event. [isAdmin] only decides which controls are shown —
/// the real limits are enforced in Postgres.
class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({required this.repository, required this.isAdmin, this.eventId, this.copyOf, super.key});

  final EventAdminRepository repository;
  final bool isAdmin;
  final String? eventId;
  final EventDraft? copyOf;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  late Future<EventEditorController> _controllerFuture = _init();

  Future<EventEditorController> _init() async {
    final List<TicketTypeDraft> template = await widget.repository.defaultTicketTemplate();
    final EventDraft draft = widget.eventId != null
        ? await widget.repository.loadDraft(widget.eventId!)
        : (widget.copyOf ?? EventDraft());
    return EventEditorController(
      repository: widget.repository,
      isAdmin: widget.isAdmin,
      draft: draft,
      defaultTemplate: template,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EventEditorController>(
      future: _controllerFuture,
      builder: (BuildContext context, AsyncSnapshot<EventEditorController> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Event')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(FlcSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Couldn\'t open this event.\n${EventAdminRepository.describeError(snapshot.error!)}', textAlign: TextAlign.center),
                    const SizedBox(height: FlcSpace.md),
                    OutlinedButton(onPressed: () => setState(() => _controllerFuture = _init()), child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(appBar: AppBar(title: const Text('Event')), body: const Center(child: CircularProgressIndicator()));
        }
        return _EditorView(controller: snapshot.data!);
      },
    );
  }
}

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

class _EditorView extends StatefulWidget {
  const _EditorView({required this.controller});

  final EventEditorController controller;

  @override
  State<_EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<_EditorView> {
  EventEditorController get c => widget.controller;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ saving

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showProblems(String title, List<String> problems) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (final String p in problems) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $p'))],
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, {String action = 'Continue', bool destructive = false}) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: FlcColors.error) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Save without changing whether it's live.
  Future<void> _saveKeepingStatus() async {
    final String status = c.persistedStatus ?? 'draft';
    final EventIssues issues = c.draft.validate(publishing: status == 'published');
    if (!issues.ok) return _showProblems('Fix these first', issues.errors);

    final String? error = await c.save(status: status);
    if (error != null) return _showProblems('Couldn\'t save', <String>[error]);
    _snack(status == 'published' ? 'Changes saved — live now.' : 'Draft saved.');
    await _offerToNotifyTicketHolders();
  }

  Future<void> _publish() async {
    final DateTime nowLondon = LondonTime.fromUtc(DateTime.now());
    final bool schedule = c.draft.publishAt != null && c.draft.publishAt!.isAfter(nowLondon);

    final EventIssues issues = c.draft.validate(publishing: true);
    if (!issues.ok) return _showProblems('Fix these before publishing', issues.errors);
    if (issues.warnings.isNotEmpty) {
      final bool go = await _confirm(
        schedule ? 'Schedule anyway?' : 'Publish anyway?',
        issues.warnings.map((String w) => '• $w').join('\n'),
        action: schedule ? 'Schedule' : 'Publish',
      );
      if (!go) return;
    }

    if (!schedule) c.draft.publishAt = null; // publishing by hand — drop any stale schedule
    final String? error = await c.save(status: schedule ? 'draft' : 'published');
    if (error != null) return _showProblems('Couldn\'t save', <String>[error]);

    if (schedule) {
      _snack('Scheduled — it goes live ${LondonTime.format(LondonTime.toUtc(c.draft.publishAt!))} (London).');
      return;
    }
    _snack('Published.');
    if (!mounted) return;
    final bool tell = await _confirm('Tell people about it?', 'The event is live. Want to send a notification now?', action: 'Write notification');
    if (tell && mounted) await _showComposer(kind: 'new_event');
  }

  Future<void> _offerToNotifyTicketHolders() async {
    if (!c.logisticsChangedForBuyers) return;
    c.acknowledgeLogistics();
    if (!mounted) return;
    final bool tell = await _confirm(
      'Tell ticket holders?',
      'The date, time or venue changed and ${c.draft.soldTotal} tickets are already sold. Send those people a notification?',
      action: 'Write notification',
    );
    if (tell && mounted) {
      final String when = c.draft.startsAt == null ? '' : shortWhen(c.draft.startsAt!);
      await _showComposer(
        kind: 'event_update',
        title: _clip('Update: ${c.draft.title.trim()}', 65),
        body: _clip(
          'Details have changed. It\'s now ${when.isEmpty ? 'to be confirmed' : when} at ${c.draft.venueRoom.trim().isEmpty ? c.draft.venueName : c.draft.venueRoom}.',
          240,
        ),
      );
    }
  }

  Future<void> _showComposer({required String kind, String? title, String? body}) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Send a notification'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: PushComposer(repository: c.repository, draft: c.draft, eventIsLive: c.isLive, initialKind: kind, initialTitle: title, initialBody: body),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  // ------------------------------------------------------------- menu actions

  Future<void> _duplicate() async {
    final EventDraft copy = c.draft.duplicated();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => EventEditorScreen(repository: c.repository, isAdmin: c.isAdmin, copyOf: copy),
      ),
    );
  }

  Future<void> _setStatus(String status, {required String doing}) async {
    try {
      await c.repository.setStatus(c.draft.id!, status);
      c.statusChangedElsewhere(status);
      _snack(doing);
    } catch (e) {
      await _showProblems('Couldn\'t do that', <String>[EventAdminRepository.describeError(e)]);
    }
  }

  Future<void> _postpone() async {
    if (!await _confirm('Postpone this event?', 'It stays visible but is marked Postponed, and can\'t be booked until you resume it.', action: 'Postpone')) return;
    await _setStatus('postponed', doing: 'Marked as postponed.');
    if (c.draft.soldTotal > 0 && mounted) {
      if (await _confirm('Tell ticket holders?', 'Send the ${c.draft.soldTotal} people with tickets a notification?', action: 'Write notification')) {
        await _showComposer(kind: 'event_update', title: 'Postponed: ${c.draft.title.trim()}', body: 'This event has been postponed. We\'ll confirm a new date soon.');
      }
    }
  }

  Future<void> _cancelEvent() async {
    bool refund = true;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setInner) => AlertDialog(
          title: const Text('Cancel this event?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('It will show as Cancelled and can no longer be booked. Only an admin can reopen it.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: refund,
                onChanged: (bool? v) => setInner(() => refund = v ?? true),
                title: const Text('Refund every paid order now'),
                subtitle: const Text('Uses Stripe and reverses any loyalty points. Refunds can\'t be undone.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep event')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: FlcColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel event')),
          ],
        ),
      ),
    );
    if (go != true) return;

    try {
      final CancelResult r = await c.repository.cancelEvent(c.draft.id!, refundOrders: refund);
      c.statusChangedElsewhere('cancelled');
      if (r.failures.isNotEmpty) {
        await _showProblems('Cancelled — but ${r.failures.length} refund(s) failed', <String>[
          '${r.refunded} refunded.',
          ...r.failures,
          'Refund the rest from Orders.',
        ]);
      } else {
        _snack(refund ? 'Event cancelled; ${r.refunded} order(s) refunded.' : 'Event cancelled.');
      }
      if (c.draft.soldTotal > 0 && mounted) {
        if (await _confirm('Tell ticket holders?', 'Send the people with tickets a notification?', action: 'Write notification')) {
          await _showComposer(kind: 'event_update', title: 'Cancelled: ${c.draft.title.trim()}', body: 'We\'re sorry — this event has been cancelled.${refund ? ' Your ticket will be refunded.' : ''}');
        }
      }
    } catch (e) {
      await _showProblems('Couldn\'t cancel', <String>[EventAdminRepository.describeError(e)]);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm('Delete this event?', 'This permanently removes it. Events with orders can\'t be deleted — cancel those instead.', action: 'Delete', destructive: true)) return;
    try {
      await c.repository.deleteEvent(c.draft.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      await _showProblems('Couldn\'t delete', <String>[EventAdminRepository.describeError(e)]);
    }
  }

  Future<void> _showHistory() async {
    List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    String? failure;
    try {
      rows = await c.repository.eventHistory(c.draft.id!);
    } catch (e) {
      failure = EventAdminRepository.describeError(e);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Change history'),
        content: SizedBox(
          width: 560,
          child: failure != null
              ? Text(failure)
              : rows.isEmpty
                  ? const Text('Nothing recorded yet.')
                  : ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final Map<String, dynamic> r in rows)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${r['actor_name']} · ${(r['action'] as String).replaceAll('.', ' ')}'),
                            subtitle: Text(
                              '${LondonTime.format(DateTime.parse(r['created_at'] as String), pattern: 'd MMM yyyy, HH:mm')}'
                              '${r['after'] is Map ? '\nChanged: ${(r['after'] as Map).keys.map((Object? k) => '$k'.replaceAll('_', ' ')).join(', ')}' : ''}',
                            ),
                          ),
                      ],
                    ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _showPreviewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => ListenableBuilder(
        listenable: c,
        builder: (BuildContext context, Widget? child) => Padding(
          padding: const EdgeInsets.fromLTRB(FlcSpace.md, 0, FlcSpace.md, FlcSpace.lg),
          child: SingleChildScrollView(child: _PreviewPane(controller: c)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? child) {
        return PopScope(
          canPop: !c.dirty,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) return;
            final bool leave = await _confirm('Discard your changes?', 'You have unsaved changes on this event.', action: 'Discard', destructive: true);
            if (leave && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: <Widget>[
                  Flexible(child: Text(c.isNew ? 'New event' : (c.draft.title.trim().isEmpty ? 'Event' : c.draft.title.trim()), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: FlcSpace.sm),
                  EventStatusChip(status: c.persistedStatus ?? 'draft', scheduled: c.persistedStatus == 'draft' && c.draft.publishAt != null, onDark: true),
                ],
              ),
              actions: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints _) => MediaQuery.sizeOf(context).width >= 1000
                      ? const SizedBox.shrink()
                      : IconButton(icon: const Icon(Icons.visibility_outlined), tooltip: 'Preview & checklist', onPressed: _showPreviewSheet),
                ),
                if (!c.isNew) _buildMenu(),
              ],
            ),
            body: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 1000;
                final Widget form = ListView(
                  padding: const EdgeInsets.all(FlcSpace.md),
                  children: <Widget>[
                    if (c.readOnly)
                      Card(
                        color: FlcColors.error.withValues(alpha: 0.06),
                        child: const Padding(
                          padding: EdgeInsets.all(FlcSpace.md),
                          child: Text('This event was cancelled. Only an admin can change it.'),
                        ),
                      ),
                    BasicsSection(controller: c),
                    ScheduleSection(controller: c),
                    MediaSection(controller: c),
                    AboutSection(controller: c),
                    SpeakersSection(controller: c),
                    LinksSection(controller: c),
                    TicketsSection(controller: c),
                    MembershipLoyaltySection(controller: c),
                    PromotionSection(controller: c),
                    if (!c.isNew) NotificationsSection(controller: c),
                    const SizedBox(height: FlcSpace.xl),
                  ],
                );
                if (!wide) return form;
                return Row(
                  // Stretch so the preview sits at the top of its column, not floating mid-page.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: form))),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(FlcSpace.md), child: _PreviewPane(controller: c))),
                  ],
                );
              },
            ),
            bottomNavigationBar: c.readOnly ? null : _buildActionBar(),
          ),
        );
      },
    );
  }

  Widget _buildMenu() {
    final String status = c.persistedStatus ?? 'draft';
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (String v) {
        switch (v) {
          case 'duplicate':
            _duplicate();
          case 'draft':
            _confirm('Move back to draft?', 'It disappears from the app until you publish again.', action: 'Move to draft').then((bool ok) {
              if (ok) _setStatus('draft', doing: 'Moved back to draft.');
            });
          case 'postpone':
            _postpone();
          case 'resume':
            _setStatus('published', doing: 'Live again.');
          case 'archive':
            _confirm('Archive this event?', 'It\'s hidden from the app but kept for your records.', action: 'Archive').then((bool ok) {
              if (ok) _setStatus('archived', doing: 'Archived.');
            });
          case 'history':
            _showHistory();
          case 'cancel':
            _cancelEvent();
          case 'delete':
            _delete();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Duplicate for next week'))),
        if (status == 'published' && c.draft.soldTotal == 0)
          const PopupMenuItem<String>(value: 'draft', child: ListTile(leading: Icon(Icons.edit_off_outlined), title: Text('Move back to draft'))),
        if (status == 'published')
          const PopupMenuItem<String>(value: 'postpone', child: ListTile(leading: Icon(Icons.schedule_outlined), title: Text('Postpone'))),
        if (status == 'postponed')
          const PopupMenuItem<String>(value: 'resume', child: ListTile(leading: Icon(Icons.play_circle_outline), title: Text('Resume (make live)'))),
        if (status != 'archived' && status != 'cancelled')
          const PopupMenuItem<String>(value: 'archive', child: ListTile(leading: Icon(Icons.inventory_2_outlined), title: Text('Archive'))),
        if (c.isAdmin) const PopupMenuItem<String>(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Change history'))),
        if (c.isAdmin && (status == 'published' || status == 'postponed'))
          const PopupMenuItem<String>(value: 'cancel', child: ListTile(leading: Icon(Icons.cancel_outlined, color: FlcColors.error), title: Text('Cancel event…'))),
        if (c.isAdmin)
          const PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: FlcColors.error), title: Text('Delete…'))),
      ],
    );
  }

  Widget _buildActionBar() {
    final String status = c.persistedStatus ?? 'draft';
    final bool isDraft = status == 'draft';
    final bool scheduled = isDraft && c.draft.publishAt != null && c.draft.publishAt!.isAfter(LondonTime.fromUtc(DateTime.now()));

    final Widget busy = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: const Border(top: BorderSide(color: FlcColors.line))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (c.dirty) Padding(padding: const EdgeInsets.only(right: FlcSpace.md), child: Text('Unsaved changes', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate))),
            if (isDraft) ...<Widget>[
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: c.saving ? null : _saveKeepingStatus,
                child: const Text('Save draft'),
              ),
              const SizedBox(width: FlcSpace.sm),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: c.saving ? null : _publish,
                child: c.saving ? busy : Text(scheduled ? 'Schedule' : 'Publish'),
              ),
            ] else
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: c.saving ? null : _saveKeepingStatus,
                child: c.saving ? busy : const Text('Save changes'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.controller});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Preview', style: FlcTextStyles.overline.copyWith(color: FlcColors.slate)),
        const SizedBox(height: FlcSpace.xs),
        EventPreviewCard(draft: controller.draft),
        const SizedBox(height: FlcSpace.lg),
        Text('Before you publish', style: FlcTextStyles.overline.copyWith(color: FlcColors.slate)),
        const SizedBox(height: FlcSpace.xs),
        EditorChecklist(draft: controller.draft),
      ],
    );
  }
}
