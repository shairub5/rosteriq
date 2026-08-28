import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/draft_state_provider.dart';
import '../state/schedule_provider.dart';
import '../state/settings_provider.dart';

/// App settings: playoff window dates, ranking weight sliders, and draft reset.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final schedule = ref.watch(scheduleProvider).value;

    // Compute top-3 teams by playoff games for the live preview.
    final String playoffPreview = _buildPlayoffPreview(settings, schedule);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Fantasy Playoffs ──────────────────────────────────────────────
          _SectionHeader(title: 'Fantasy Playoffs'),
          _DateTile(
            label: 'Playoff Start',
            value: settings.playoffStart,
            onChanged: notifier.setPlayoffStart,
          ),
          _DateTile(
            label: 'Playoff End',
            value: settings.playoffEnd,
            onChanged: notifier.setPlayoffEnd,
          ),
          if (playoffPreview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Teams with most playoff games: $playoffPreview',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const Divider(height: 24),

          // ── Ranking Weights ───────────────────────────────────────────────
          _SectionHeader(title: 'Ranking Weights'),
          _SliderTile(
            label: 'Schedule Boost',
            value: settings.scheduleBoostWeight,
            subtext:
                'Boosts players whose teams have more games in your playoff window.',
            rangeLabel: 'Off → Full',
            onChanged: notifier.setScheduleBoostWeight,
          ),
          _SliderTile(
            label: 'Positional Need',
            value: settings.positionalNeedWeight,
            subtext: 'Boosts players who fill your scarcest roster slots.',
            rangeLabel: 'Off → Full',
            onChanged: notifier.setPositionalNeedWeight,
          ),
          const Divider(height: 24),

          // ── Draft ─────────────────────────────────────────────────────────
          _SectionHeader(title: 'Draft'),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.red),
            title: const Text('Reset Draft'),
            subtitle: const Text('Clears all picks and returns to the home screen.'),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }

  /// Returns a preview string like "DAL (12), MEM (12), PHX (11)" showing the
  /// top-3 teams by games in the current playoff window. Returns empty string
  /// when schedule hasn't loaded.
  String _buildPlayoffPreview(AppSettings settings, dynamic schedule) {
    if (schedule == null) return '';
    final start = DateTime.tryParse(settings.playoffStart);
    final end = DateTime.tryParse(settings.playoffEnd);
    if (start == null || end == null) return '';

    final entries = <MapEntry<String, int>>[];
    for (final entry in (schedule.teams as Map).entries) {
      final games = entry.value.gamesInWindow(start, end) as int;
      entries.add(MapEntry(entry.key as String, games));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));

    final top = entries.take(3).map((e) => '${e.key} (${e.value})').join(', ');
    return top;
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Draft?'),
        content: const Text(
          'This will erase all picks. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(draftStateProvider.notifier).resetDraft();
      if (context.mounted) Navigator.pop(context); // close settings
    }
  }
}

// ── Private helper widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A list tile that shows an ISO date string and opens a [showDatePicker] on
/// tap, writing the result back via [onChanged].
class _DateTile extends StatelessWidget {
  final String label;
  final String value; // ISO date string e.g. "2027-03-08"
  final Future<void> Function(String) onChanged;

  const _DateTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value);
    final display = parsed != null
        ? '${parsed.month}/${parsed.day}/${parsed.year}'
        : value;

    return ListTile(
      title: Text(label),
      trailing: Text(
        display,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () async {
        final now = DateTime.now();
        final initial = parsed ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          final iso =
              '${picked.year.toString().padLeft(4, '0')}-'
              '${picked.month.toString().padLeft(2, '0')}-'
              '${picked.day.toString().padLeft(2, '0')}';
          await onChanged(iso);
        }
      },
    );
  }
}

/// A list tile with a [Slider] for a 0.0–1.0 weight value.
class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final String subtext;
  final String rangeLabel;
  final void Function(double) onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.subtext,
    required this.rangeLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                rangeLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              subtext,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}
