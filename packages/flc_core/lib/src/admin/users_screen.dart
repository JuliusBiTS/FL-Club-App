import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../events_admin/event_admin_repository.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import 'user_admin_repository.dart';

/// User, member and staff management — one screen, several starting views
/// ("Members", "Staff", ...). Everyone who registers in the app or on a
/// future website lands in the same list as a plain user; an admin finds
/// them here and can make them a member, staff or admin.
class UsersScreen extends StatefulWidget {
  const UsersScreen({
    required this.repository,
    this.title = 'Users',
    this.description,
    this.initialFilter = UserFilter.all,
    this.embedded = false,
    super.key,
  });

  final UserAdminRepository repository;
  final String title;
  final String? description;
  final UserFilter initialFilter;

  /// True inside the admin console's shell (no app bar of its own).
  final bool embedded;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late UserFilter _filter = widget.initialFilter;
  String _search = '';
  Timer? _debounce;
  late Future<List<ManagedUser>> _users = _load();

  Future<List<ManagedUser>> _load() => widget.repository.listUsers(search: _search, filter: _filter);

  void _reload() => setState(() => _users = _load());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _edit(ManagedUser user) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _EditUserDialog(repository: widget.repository, user: user),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final double gutter = widget.embedded ? FlcSpace.xl : FlcSpace.md;

    final Widget body = ListView(
      padding: EdgeInsets.all(gutter),
      children: <Widget>[
        if (widget.embedded) ...<Widget>[
          Text(widget.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: FlcSpace.xs),
        ],
        if (widget.description != null) ...<Widget>[
          Text(widget.description!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
          const SizedBox(height: FlcSpace.md),
        ],
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or email'),
                  onChanged: (String v) {
                    _search = v;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), _reload);
                  },
                ),
                const SizedBox(height: FlcSpace.sm),
                Wrap(
                  spacing: FlcSpace.xs,
                  children: <Widget>[
                    for (final (UserFilter f, String label) in <(UserFilter, String)>[
                      (UserFilter.all, 'Everyone'),
                      (UserFilter.members, 'Members'),
                      (UserFilter.staff, 'Staff & admins'),
                      (UserFilter.applied, 'Applied to join'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) {
                          _filter = f;
                          _reload();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: FlcSpace.md),
                FutureBuilder<List<ManagedUser>>(
                  future: _users,
                  builder: (BuildContext context, AsyncSnapshot<List<ManagedUser>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(FlcSpace.md), child: LinearProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Text(
                        "Couldn't load people. ${EventAdminRepository.describeError(snap.error!)}",
                        style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context)),
                      );
                    }
                    final List<ManagedUser> users = snap.data ?? const <ManagedUser>[];
                    if (users.isEmpty) {
                      return Text('Nobody matches.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)));
                    }
                    return Card(
                      child: Column(
                        children: <Widget>[
                          for (final ManagedUser u in users)
                            ListTile(
                              title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(u.displayName == u.email ? _summary(u) : '${u.email} · ${_summary(u)}'),
                              trailing: const Icon(Icons.edit_outlined, size: 18),
                              onTap: () => _edit(u),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }

  static String _summary(ManagedUser u) {
    final List<String> parts = <String>[
      if (u.role != 'user') u.role == 'admin' ? 'Admin' : 'Staff',
      switch (u.memberStatus) {
        'active' => 'Member',
        'applied' => 'Applied',
        'lapsed' => 'Lapsed member',
        'suspended' => 'Suspended',
        _ => 'Not a member',
      },
    ];
    return parts.join(' · ');
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.repository, required this.user});

  final UserAdminRepository repository;
  final ManagedUser user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late String _role = widget.user.role;
  late String _status = widget.user.memberStatus;
  late String? _kind = widget.user.membershipKind;
  late DateTime? _expires = widget.user.membershipExpiresAt;
  late final TextEditingController _number = TextEditingController(text: widget.user.membershipNumber ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.user.notes ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateUser(
        userId: widget.user.id,
        role: _role,
        memberStatus: _status,
        membershipKind: _kind,
        membershipNumber: _number.text,
        membershipExpiresAt: _expires,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = EventAdminRepository.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool promoting = _role != widget.user.role && _role != 'user';
    return AlertDialog(
      title: Text(widget.user.displayName),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.user.email, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
              if (widget.user.createdAt != null)
                Text(
                  'Registered ${DateFormat('d MMM yyyy').format(widget.user.createdAt!.toLocal())}'
                  '${widget.user.registrationSource == null ? '' : ' via ${widget.user.registrationSource}'}'
                  '${widget.user.marketingOptIn ? ' · OK to send news' : ''}',
                  style: FlcTextStyles.caption.copyWith(color: FlcColors.secondary(context)),
                ),
              const SizedBox(height: FlcSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Access'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'user', child: Text('Regular user')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (String? v) => setState(() => _role = v ?? _role),
              ),
              if (promoting) ...<Widget>[
                const SizedBox(height: FlcSpace.xs),
                Text(
                  _role == 'admin'
                      ? 'Admins can do everything — including changing anyone\'s access. Only give this to people you fully trust.'
                      : 'Staff can create and publish events, send notifications and manage media. They can\'t change prices once an event is live or manage people.',
                  style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.warning),
                ),
              ],
              const SizedBox(height: FlcSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Membership'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'none', child: Text('Not a member')),
                  DropdownMenuItem(value: 'applied', child: Text('Applied')),
                  DropdownMenuItem(value: 'active', child: Text('Active member')),
                  DropdownMenuItem(value: 'lapsed', child: Text('Lapsed')),
                  DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                ],
                onChanged: (String? v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: FlcSpace.sm),
              DropdownButtonFormField<String?>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Membership type'),
                items: const <DropdownMenuItem<String?>>[
                  DropdownMenuItem(value: null, child: Text('—')),
                  DropdownMenuItem(value: 'full', child: Text('Full')),
                  DropdownMenuItem(value: 'honorary', child: Text('Honorary')),
                  DropdownMenuItem(value: 'lifetime', child: Text('Lifetime')),
                ],
                onChanged: (String? v) => setState(() => _kind = v),
              ),
              const SizedBox(height: FlcSpace.sm),
              TextField(controller: _number, decoration: const InputDecoration(labelText: 'Membership number')),
              const SizedBox(height: FlcSpace.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _expires == null ? 'No expiry date' : 'Expires ${DateFormat('d MMM yyyy').format(_expires!)}',
                      style: FlcTextStyles.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _expires ?? DateTime.now().add(const Duration(days: 365)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _expires = picked);
                    },
                    child: const Text('Set'),
                  ),
                  if (_expires != null) TextButton(onPressed: () => setState(() => _expires = null), child: const Text('Clear')),
                ],
              ),
              const SizedBox(height: FlcSpace.xs),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Internal notes (never shown to the person)'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: FlcSpace.sm),
                Text(_error!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context))),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
