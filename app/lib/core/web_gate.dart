import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A shared-password screen in front of the WEB PREVIEW build only (phones
/// are never affected). Purpose: keep casual visitors out of a preview link
/// that was shared with a colleague. It is NOT strong security — the check
/// runs in the browser — so it never protects anything that matters: real
/// data is still guarded by sign-in and database rules, exactly as in the app.
///
/// The password itself is never in the code, only its SHA-256, passed at build
/// time with --dart-define=WEB_GATE_HASH=… . No hash = no gate.
class WebGate extends StatefulWidget {
  const WebGate({required this.child, super.key});

  final Widget child;

  static const String _hash = String.fromEnvironment('WEB_GATE_HASH');
  static const String _prefKey = 'web_gate_unlocked_for';

  static bool get enabled => kIsWeb && _hash.isNotEmpty;

  @override
  State<WebGate> createState() => _WebGateState();
}

class _WebGateState extends State<WebGate> {
  final TextEditingController _password = TextEditingController();
  bool _checkedStored = false;
  bool _unlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _unlocked = prefs.getString(WebGate._prefKey) == WebGate._hash;
      _checkedStored = true;
    });
  }

  Future<void> _submit() async {
    final String attempt = sha256.convert(utf8.encode(_password.text.trim())).toString();
    if (attempt == WebGate._hash) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(WebGate._prefKey, WebGate._hash);
      if (mounted) setState(() => _unlocked = true);
    } else {
      setState(() => _error = "That isn't the password.");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF33460C), useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF33460C),
        body: Center(
          child: !_checkedStored
              ? const SizedBox.shrink()
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          'FRONTLINE CLUB',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 6),
                        const Text('Private preview', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          autofocus: true,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Colors.white70),
                            errorText: _error,
                            errorStyle: const TextStyle(color: Color(0xFFFFD6D6)),
                            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF33460C)),
                          onPressed: _submit,
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
