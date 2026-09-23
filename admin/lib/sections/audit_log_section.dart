import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only record of every privileged change (role changes, membership
/// edits, refunds, photo changes…). The database refuses edits and deletes
/// here; this screen only ever reads.
class AuditLogSection extends StatefulWidget {
  const AuditLogSection({super.key});

  @override
  State<AuditLogSection> createState() => _AuditLogSectionState();
}

class _AuditLogSectionState extends State<AuditLogSection> {
  late Future<List<Map<String, dynamic>>> _rows = _load();
  String _search = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('audit_log')
        .select('action, entity, entity_id, created_at, actor:profiles!audit_log_actor_id_fkey(full_name, email)')
        .order('created_at', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat when = DateFormat('d MMM yyyy, HH:mm');
    return ListView(
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Audit log', style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter…', isDense: true),
                onChanged: (String v) => setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => setState(() => _rows = _load())),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Every privileged change, newest first. Read-only.'),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _rows,
          builder: (BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snap) {
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (snap.hasError) return const Text("Couldn't load the log. Try refreshing.");
            final rows = (snap.data ?? const <Map<String, dynamic>>[]).where((Map<String, dynamic> r) {
              if (_search.isEmpty) return true;
              final actor = r['actor'] as Map?;
              return '${r['action']} ${r['entity']} ${actor?['full_name']} ${actor?['email']}'.toLowerCase().contains(_search);
            }).toList();
            if (rows.isEmpty) return const Text('Nothing recorded yet.');
            return Card(
              child: Column(
                children: <Widget>[
                  for (final Map<String, dynamic> r in rows)
                    ListTile(
                      dense: true,
                      title: Text('${r['action']}  ·  ${r['entity']}'),
                      subtitle: Text(
                        '${when.format(DateTime.parse(r['created_at'] as String).toLocal())}  ·  '
                        '${(r['actor'] as Map?)?['full_name'] ?? (r['actor'] as Map?)?['email'] ?? 'the system'}',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
