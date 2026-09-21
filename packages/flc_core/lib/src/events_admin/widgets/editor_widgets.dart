import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';

import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../../util/event_text.dart';
import '../event_admin_repository.dart';

/// A titled card that groups one part of the event form.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.child, this.subtitle, this.trailing, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: FlcSpace.md),
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: FlcTextStyles.h3),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: FlcSpace.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Side by side on a wide screen, stacked on a phone.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({required this.children, this.breakpoint = 520, super.key});

  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: FlcSpace.sm),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: FlcSpace.sm),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Date + time picker for London wall-clock values (see LondonTime). 24-hour.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.enabled = true,
    this.clearable = false,
    this.defaultTime = const TimeOfDay(hour: 19, minute: 0),
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;
  final bool enabled;
  final bool clearable;
  final TimeOfDay defaultTime;

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initial = value ?? now;
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 4),
    );
    if (date == null || !context.mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: value == null ? defaultTime : TimeOfDay(hour: value!.hour, minute: value!.minute),
      builder: (BuildContext ctx, Widget? child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (time == null) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(FlcRadius.input),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          enabled: enabled,
          suffixIcon: value != null && clearable && enabled
              ? IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Clear', onPressed: () => onChanged(null))
              : const Icon(Icons.event_outlined, size: 20),
        ),
        child: Text(
          value == null ? 'Not set' : DateFormat('EEE d MMM yyyy, HH:mm').format(value!),
          style: FlcTextStyles.body.copyWith(color: value == null ? FlcColors.slate : null),
        ),
      ),
    );
  }
}

/// £ ⇄ pence. Accepts "12.50" and "12,50" (German keyboards).
int? poundsToMinor(String text) {
  final String t = text.trim().replaceAll(',', '.').replaceAll('£', '');
  if (t.isEmpty) return null;
  final double? v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

String minorToPounds(int minor) => minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

class MoneyField extends StatelessWidget {
  const MoneyField({required this.label, required this.valueMinor, required this.onChanged, this.enabled = true, super.key});

  final String label;
  final int valueMinor;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: minorToPounds(valueMinor),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, prefixText: '£ '),
      onChanged: (String v) => onChanged(poundsToMinor(v) ?? 0),
    );
  }
}

class IntField extends StatelessWidget {
  const IntField({required this.label, required this.value, required this.onChanged, this.enabled = true, this.helper, super.key});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toString(),
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
      onChanged: (String v) => onChanged(int.tryParse(v) ?? 0),
    );
  }
}

/// Picks an image from the device and uploads it. Returns the public URL, or
/// null if the person cancelled. Errors surface as a snackbar.
Future<String?> pickAndUploadImage(BuildContext context, EventAdminRepository repository) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final PlatformFile? file = result?.files.single;
    if (file == null) return null;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) throw EventAdminException('That picture couldn\'t be read. Try another.');
    return await repository.uploadImage(bytes: bytes, fileName: file.name);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(EventAdminRepository.describeError(e))));
    return null;
  }
}

/// A 16:9 picture slot with upload / replace / remove.
class ImageSlot extends StatefulWidget {
  const ImageSlot({
    required this.repository,
    required this.url,
    required this.onChanged,
    this.aspectRatio = 16 / 9,
    this.label = 'Add a picture',
    this.enabled = true,
    super.key,
  });

  final EventAdminRepository repository;
  final String? url;
  final ValueChanged<String?> onChanged;
  final double aspectRatio;
  final String label;
  final bool enabled;

  @override
  State<ImageSlot> createState() => _ImageSlotState();
}

class _ImageSlotState extends State<ImageSlot> {
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    final String? url = await pickAndUploadImage(context, widget.repository);
    if (!mounted) return;
    setState(() => _busy = false);
    if (url != null) widget.onChanged(url);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = widget.url != null && widget.url!.isNotEmpty;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FlcRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasImage)
              Image.network(
                widget.url!,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    const ColoredBox(color: FlcColors.line, child: Center(child: Icon(Icons.broken_image_outlined))),
              )
            else
              InkWell(
                onTap: widget.enabled && !_busy ? _pick : null,
                child: ColoredBox(
                  color: FlcColors.brand.withValues(alpha: 0.06),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.add_photo_alternate_outlined, color: FlcColors.brand, size: 32),
                        const SizedBox(height: FlcSpace.xs),
                        Text(widget.label, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.brand)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_busy) const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
            if (hasImage && widget.enabled && !_busy)
              Positioned(
                right: FlcSpace.xs,
                top: FlcSpace.xs,
                child: Row(
                  children: <Widget>[
                    IconButton.filledTonal(icon: const Icon(Icons.swap_horiz), tooltip: 'Replace', onPressed: _pick),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => widget.onChanged(null),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Free-text tags/perks as chips: type, press Enter (or comma) to add.
class ChipsInput extends StatefulWidget {
  const ChipsInput({
    required this.label,
    required this.values,
    required this.onChanged,
    this.suggestions = const <String>[],
    this.maxItems = 20,
    this.maxLength = 40,
    this.enabled = true,
    this.hint,
    super.key,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final int maxItems;
  final int maxLength;
  final bool enabled;
  final String? hint;

  @override
  State<ChipsInput> createState() => _ChipsInputState();
}

class _ChipsInputState extends State<ChipsInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final String v = raw.trim().replaceAll(',', '');
    if (v.isEmpty || widget.values.contains(v) || widget.values.length >= widget.maxItems) return;
    widget.onChanged(<String>[...widget.values, v.length > widget.maxLength ? v.substring(0, widget.maxLength) : v]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bool full = widget.values.length >= widget.maxItems;
    final List<String> unused = widget.suggestions.where((String s) => !widget.values.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FlcSpace.xs),
            child: Wrap(
              spacing: FlcSpace.xs,
              runSpacing: FlcSpace.xxs,
              children: <Widget>[
                for (final String v in widget.values)
                  InputChip(
                    label: Text(v),
                    onDeleted: widget.enabled ? () => widget.onChanged(widget.values.where((String x) => x != v).toList()) : null,
                  ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          enabled: widget.enabled && !full,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: full ? 'Limit reached (${widget.maxItems})' : widget.hint,
            counterText: '',
            suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: () => _add(_controller.text)),
          ),
          onSubmitted: _add,
          onChanged: (String v) {
            if (v.endsWith(',')) _add(v);
          },
        ),
        if (unused.isNotEmpty && !full && widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: FlcSpace.xs),
            child: Wrap(
              spacing: FlcSpace.xs,
              runSpacing: FlcSpace.xxs,
              children: <Widget>[
                for (final String s in unused) ActionChip(label: Text(s), avatar: const Icon(Icons.add, size: 16), onPressed: () => _add(s)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Multi-line text with a small formatting toolbar. The marks it inserts are
/// the ones EventText.markdownToHtml understands.
class MarkdownField extends StatefulWidget {
  const MarkdownField({required this.initialValue, required this.onChanged, this.enabled = true, super.key});

  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<MarkdownField> createState() => _MarkdownFieldState();
}

class _MarkdownFieldState extends State<MarkdownField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String text, TextSelection selection) {
    _controller.value = TextEditingValue(text: text, selection: selection);
    widget.onChanged(text);
  }

  void _wrap(String mark, {String placeholder = 'text'}) {
    final TextSelection sel = _controller.selection.isValid ? _controller.selection : TextSelection.collapsed(offset: _controller.text.length);
    final String text = _controller.text;
    final String selected = sel.textInside(text);
    final String inner = selected.isEmpty ? placeholder : selected;
    final String replaced = text.replaceRange(sel.start, sel.end, '$mark$inner$mark');
    _set(replaced, TextSelection(baseOffset: sel.start + mark.length, extentOffset: sel.start + mark.length + inner.length));
  }

  void _prefixLines(String prefix) {
    final TextSelection sel = _controller.selection.isValid ? _controller.selection : TextSelection.collapsed(offset: _controller.text.length);
    final String text = _controller.text;
    final int start = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1) + 1;
    int end = text.indexOf('\n', sel.end);
    if (end == -1) end = text.length;
    final String block = text.substring(start, end);
    final String prefixed = block.split('\n').map((String l) => l.startsWith(prefix) ? l : '$prefix$l').join('\n');
    _set(text.replaceRange(start, end, prefixed), TextSelection.collapsed(offset: start + prefixed.length));
  }

  Future<void> _link() async {
    final TextEditingController url = TextEditingController(text: 'https://');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Add a link'),
        content: TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Web address', hintText: 'https://…'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, url.text.trim()), child: const Text('Add link')),
        ],
      ),
    );
    url.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    final TextSelection sel = _controller.selection.isValid ? _controller.selection : TextSelection.collapsed(offset: _controller.text.length);
    final String label = sel.textInside(_controller.text).isEmpty ? 'link text' : sel.textInside(_controller.text);
    final String md = '[$label]($result)';
    _set(_controller.text.replaceRange(sel.start, sel.end, md), TextSelection.collapsed(offset: sel.start + md.length));
  }

  void _preview() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('How it will read'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: _controller.text.trim().isEmpty
                ? const Text('Nothing written yet.')
                : HtmlWidget(EventText.markdownToHtml(_controller.text)),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 2,
          children: <Widget>[
            IconButton(icon: const Icon(Icons.format_bold), tooltip: 'Bold', onPressed: widget.enabled ? () => _wrap('**') : null),
            IconButton(icon: const Icon(Icons.format_italic), tooltip: 'Italic', onPressed: widget.enabled ? () => _wrap('*') : null),
            IconButton(icon: const Icon(Icons.title), tooltip: 'Heading', onPressed: widget.enabled ? () => _prefixLines('## ') : null),
            IconButton(icon: const Icon(Icons.format_list_bulleted), tooltip: 'Bullet list', onPressed: widget.enabled ? () => _prefixLines('- ') : null),
            IconButton(icon: const Icon(Icons.link), tooltip: 'Link', onPressed: widget.enabled ? _link : null),
            TextButton.icon(onPressed: _preview, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Preview')),
          ],
        ),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          minLines: 6,
          maxLines: 18,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Tell people what the evening is about, who\'s speaking, and why it matters.\n\nLeave a blank line between paragraphs.',
            alignLabelWithHint: true,
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
