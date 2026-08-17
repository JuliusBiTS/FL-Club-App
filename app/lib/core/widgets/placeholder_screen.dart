import 'package:flutter/material.dart';

/// Marks a screen that exists to establish routing/navigation now but has
/// its real implementation scheduled for a later milestone (see README
/// "Delivery plan"). Never ship this to a store build — it's a scaffolding
/// aid, not a feature-flagged placeholder for production.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, required this.milestone, super.key});

  final String title;
  final String milestone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.construction_outlined, size: 40, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 12),
              Text('$title lands in $milestone', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
