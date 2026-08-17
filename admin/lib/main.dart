import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty,
    'SUPABASE_URL / SUPABASE_ANON_KEY were not passed via --dart-define. See admin/README (root README "Getting started").',
  );

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  runApp(const FrontlineClubAdminApp());
}

class FrontlineClubAdminApp extends StatelessWidget {
  const FrontlineClubAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frontline Club — Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFC8102E)), // placeholder flcRed, see docs/OPEN_QUESTIONS.md
      home: const AdminAuthGate(),
    );
  }
}
