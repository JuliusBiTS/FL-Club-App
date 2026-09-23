import 'package:flutter/material.dart';

import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../event_admin_repository.dart';
import '../event_autofill.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';

/// "Paste details to auto-fill" — sits above the rest of the form. Turns a
/// pasted email/press release into a first draft of the blank fields below;
/// never touches anything already filled in, and never touches price,
/// capacity, or ticket types (those aren't fields the server can return).
class AutoFillSection extends StatelessWidget {
  const AutoFillSection({required this.controller, super.key});

  final EventEditorController controller;

  Future<void> _open(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => _AutoFillDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Paste details to auto-fill',
      subtitle: 'Got an email, a press release, or a blurb from a partner? Paste it in — it fills in blank fields below, and never touches price, capacity, or anything already filled in.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Paste details'),
          onPressed: () => _open(context),
        ),
      ),
    );
  }
}

class _AutoFillDialog extends StatefulWidget {
  const _AutoFillDialog({required this.controller});

  final EventEditorController controller;

  @override
  State<_AutoFillDialog> createState() => _AutoFillDialogState();
}

class _AutoFillDialogState extends State<_AutoFillDialog> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final String text = _text.text.trim();
    if (text.length < 20) {
      setState(() => _error = 'Paste a bit more — a couple of sentences at least.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ExtractedEventFields extracted = await widget.controller.repository.extractEventDetails(text);
      final AutoFillResult result = extracted.applyTo(widget.controller.draft);
      widget.controller.touch();
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showResult(context, extracted.isEmpty ? null : result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = EventAdminRepository.describeError(e);
      });
    }
  }

  static Future<void> _showResult(BuildContext context, AutoFillResult? result) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Auto-fill'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: result == null || result.isEmpty
                ? const Text('Couldn\'t find anything usable in that text — nothing was changed.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (result.filled.isNotEmpty) ...<Widget>[
                        Text('Filled in', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: FlcSpace.xxs),
                        Text(result.filled.join(', ')),
                        const SizedBox(height: FlcSpace.sm),
                      ],
                      if (result.keptExisting.isNotEmpty) ...<Widget>[
                        Text('Left alone (already had something)', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: FlcColors.secondary(context))),
                        const SizedBox(height: FlcSpace.xxs),
                        Text(result.keptExisting.join(', '), style: TextStyle(color: FlcColors.secondary(context))),
                        const SizedBox(height: FlcSpace.sm),
                      ],
                      if (result.notes.isNotEmpty) ...<Widget>[
                        Text('Worth checking', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: FlcColors.warning)),
                        const SizedBox(height: FlcSpace.xxs),
                        for (final String n in result.notes) Text('• $n'),
                      ],
                      const SizedBox(height: FlcSpace.sm),
                      const Text('Price, capacity and ticket types are never auto-filled — set those yourself below.', style: FlcTextStyles.bodySmall),
                    ],
                  ),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste details'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Paste an email, press release, or blurb about the event. Nothing is saved until you review it and click Save/Publish yourself.', style: FlcTextStyles.bodySmall),
            const SizedBox(height: FlcSpace.sm),
            TextField(
              controller: _text,
              enabled: !_busy,
              minLines: 8,
              maxLines: 14,
              maxLength: 8000,
              decoration: const InputDecoration(hintText: 'Paste the text here…', alignLabelWithHint: true),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FlcSpace.xs),
                child: Text(_error!, style: const TextStyle(color: FlcColors.error)),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high_outlined),
          label: Text(_busy ? 'Reading…' : 'Auto-fill'),
        ),
      ],
    );
  }
}
