import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat_category.dart';
import '../services/schedule_service.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/schedule_provider.dart';
import '../state/settings_provider.dart';
import '../widgets/common.dart';

/// App-bar gear that opens [SettingsScreen]; used on every tab.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Settings',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      );
}

/// Live-data status, punted categories, playoff window and ranking weights.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final schedule = ref.watch(scheduleProvider).value;
    final leagueData = ref.watch(leagueDataProvider);
    final punted = ref.watch(draftStateProvider).puntedCategories;
    final playoffPreview = _playoffPreview(settings, schedule);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionHeader('Data'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: Text(switch (leagueData) {
                AsyncData(value: final d) when d.updatedAt != null => 'Live stats updated ${_ago(d.updatedAt!)}',
                AsyncData() => 'Offline: preseason projections',
                AsyncError() => 'Couldn\'t load player data',
                _ => 'Loading…',
              }),
              subtitle: const Text('ESPN stats and injuries, refreshed every 30 min. Tap to reload.'),
              onTap: () => ref.invalidate(leagueDataProvider),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader('My categories · ${9 - punted.length} of 9'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The categories you play for. Player values and Add/Drop rankings count only these; '
                    'unselected ones are punted. Same setting as the chips on Add/Drop.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in allStatCategories)
                        FilterChip(
                          label: Text(c.label),
                          selected: !punted.contains(c),
                          onSelected: (on) => ref.read(draftStateProvider.notifier).setPuntedCategories(
                                on ? ({...punted}..remove(c)) : {...punted, c},
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader('Fantasy playoffs'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _DateTile(label: 'Start', value: settings.playoffStart, onChanged: notifier.setPlayoffStart),
                const Divider(indent: 16),
                _DateTile(label: 'End', value: settings.playoffEnd, onChanged: notifier.setPlayoffEnd),
                if (playoffPreview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Most playoff games: $playoffPreview', style: theme.textTheme.bodySmall),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader('Add/Drop ranking'),
          Card(
            child: Column(
              children: [
                _SliderTile(
                  label: 'Playoff schedule boost',
                  value: settings.scheduleBoostWeight,
                  subtext: 'Favors players whose teams play more games in your playoff window.',
                  onChanged: notifier.setScheduleBoostWeight,
                ),
                const Divider(indent: 16),
                _SliderTile(
                  label: 'Roster fit',
                  value: settings.positionalNeedWeight,
                  subtext: 'Favors players who fill positions your roster is short on.',
                  onChanged: notifier.setPositionalNeedWeight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "DAL (12), MEM (12), PHX (11)": top-3 teams by games in the playoff window.
  String _playoffPreview(AppSettings settings, NbaSchedule? schedule) {
    final start = DateTime.tryParse(settings.playoffStart);
    final end = DateTime.tryParse(settings.playoffEnd);
    if (schedule == null || start == null || end == null) return '';
    final entries = [for (final e in schedule.teams.entries) MapEntry(e.key, e.value.gamesInWindow(start, end))]
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => '${e.key} (${e.value})').join(', ');
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final String value; // ISO date, e.g. "2027-03-08"
  final Future<void> Function(String) onChanged;

  const _DateTile({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value);
    return ListTile(
      title: Text(label),
      trailing: Text(
        parsed == null ? value : MaterialLocalizations.of(context).formatMediumDate(parsed),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
        );
        if (picked != null) await onChanged(picked.toIso8601String().substring(0, 10));
      },
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final String subtext;
  final void Function(double) onChanged;

  const _SliderTile({required this.label, required this.value, required this.subtext, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              Text('${(value * 100).round()}%', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          Slider(value: value, divisions: 20, label: '${(value * 100).round()}%', onChanged: onChanged),
          Text(subtext, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}
