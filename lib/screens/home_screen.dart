import 'package:flutter/material.dart';

import 'draft_setup_screen.dart';
import 'roster_management_screen.dart';

/// The app's landing screen: a hub pointing at the two top-level feature
/// areas - draft-night assistance (built out) and ongoing roster management
/// (a stub today, the planned home for live Yahoo sync, injury/transaction
/// alerts, etc.). Kept separate from DraftHomeShell so RosterIQ can grow
/// into a season-long tool without draft night being the only entry point.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RosterIQ')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            _HomeCard(
              icon: Icons.sports_basketball,
              title: 'Draft Night',
              subtitle: 'Live rankings, punt strategy, and pick tracking for your draft.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DraftSetupScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _HomeCard(
              icon: Icons.manage_accounts,
              title: 'Manage Roster',
              subtitle: 'Season-long roster tools - Yahoo sync, injury/transaction alerts (coming soon).',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RosterManagementScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
