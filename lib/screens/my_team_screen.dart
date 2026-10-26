import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../theme.dart';
import '../widgets/category_radar_chart.dart';
import '../widgets/common.dart';
import '../widgets/league_switcher.dart';
import '../widgets/player_picker_sheet.dart';
import '../widgets/player_row.dart';
import 'league_screen.dart';
import 'settings_screen.dart';
import 'trade_evaluator_screen.dart';

class MyTeamScreen extends ConsumerWidget {
  const MyTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mine = ref.watch(savedRosterPlayersProvider);
    final hasTeam = (ref.watch(savedRosterProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const LeagueTitle('My Team'),
        actions: [
          if (hasTeam)
            PopupMenuButton<void>(
              tooltip: 'More',
              itemBuilder: (_) => [
                PopupMenuItem(onTap: () => _confirmClear(context, ref), child: const Text('Clear my team')),
              ],
            ),
          const SettingsButton(),
        ],
      ),
      floatingActionButton: hasTeam
          ? FloatingActionButton.extended(
              onPressed: () => addPlayersToMyTeam(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add players'),
            )
          : null,
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          if (!hasTeam) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'Build your team',
              body: 'Add the players on your fantasy roster to see your category strengths, '
                  'your matchup and the best pickups for you.',
              action: FilledButton.icon(
                onPressed: () => addPlayersToMyTeam(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add players'),
              ),
            );
          }

          final punted = ref.watch(draftStateProvider).puntedCategories;
          final z = ref.watch(leagueZProvider);
          final standing = computeTeamStanding(myRoster: mine, fullPoolForBaseline: leagueData.players);
          final ranked = allStatCategories.where((c) => !punted.contains(c)).toList()
            ..sort((a, b) => (standing[b] ?? 0).compareTo(standing[a] ?? 0));
          final roster = [...mine]..sort((a, b) => (z[b.id] ?? 0).compareTo(z[a.id] ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Category strength', style: theme.textTheme.titleMedium),
                      Text('Bold ring = league average · farther out = better', style: theme.textTheme.bodySmall),
                      CategoryRadarChart(standing: standing, puntedCategories: punted),
                      for (final (label, cats) in [
                        ('Strongest', ranked.where((c) => (standing[c] ?? 0) > 0).take(3)),
                        ('Weakest', ranked.reversed.where((c) => (standing[c] ?? 0) < 0).take(3)),
                      ])
                        if (cats.isNotEmpty) ...[
                          _CategoryChips(label: label, cats: cats, standing: standing),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionHeader('Roster · ${mine.length}', trailing: Text('VALUE', style: theme.textTheme.labelSmall)),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, p) in roster.indexed) ...[
                      if (i > 0) const Divider(indent: 72),
                      Dismissible(
                        key: ValueKey(p.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: theme.colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: Icon(Icons.person_remove, color: theme.colorScheme.onErrorContainer),
                        ),
                        onDismissed: (_) => _remove(context, ref, p.id, p.name),
                        child: PlayerRow(
                          player: p,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ValueText(z[p.id]),
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Remove ${p.name}',
                                onPressed: () => _remove(context, ref, p.id, p.name),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader('Tools'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                  title: const Text('Trade evaluator'),
                  subtitle: const Text('See how a trade changes each category'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TradeEvaluatorScreen()),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _remove(BuildContext context, WidgetRef ref, String id, String name) {
    final notifier = ref.read(savedRosterProvider.notifier);
    notifier.removePlayer(id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed $name'),
        action: SnackBarAction(label: 'Undo', onPressed: () => notifier.addPlayer(id)),
      ));
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear your team?'),
        content: const Text('All players will be removed from My Team.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(savedRosterProvider.notifier).clear();
  }
}

/// Picker for my roster. A player on another league team is moved to mine.
Future<void> addPlayersToMyTeam(BuildContext context, WidgetRef ref) {
  final all = ref.read(leagueDataProvider).value?.players ?? const [];
  return showPlayerPicker(
    context,
    title: 'My Team',
    candidates: byPreseasonRank(all),
    selectedIds: (ref) => (ref.watch(savedRosterProvider).value ?? const []).toSet(),
    onToggle: (ref, id) {
      final mine = ref.read(savedRosterProvider.notifier);
      if ((ref.read(savedRosterProvider).value ?? const []).contains(id)) {
        mine.removePlayer(id);
        return;
      }
      final other = ref.read(leagueTeamsProvider).value?.teamOf(id);
      if (other != null) ref.read(leagueTeamsProvider.notifier).togglePlayer(other.id, id);
      mine.addPlayer(id);
    },
    note: (p) {
      final other = ref.read(leagueTeamsProvider).value?.teamOf(p.id);
      return other == null ? null : 'on ${other.name}';
    },
  );
}

class _CategoryChips extends StatelessWidget {
  final String label;
  final Iterable<StatCategory> cats;
  final Map<StatCategory, double> standing;

  const _CategoryChips({required this.label, required this.cats, required this.standing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: theme.textTheme.bodySmall)),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cats)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${c.label} ', style: theme.textTheme.labelLarge),
                    TextSpan(
                      text: (standing[c] ?? 0).toStringAsFixed(1),
                      style: theme.textTheme.labelLarge?.copyWith(color: context.zColor(standing[c] ?? 0)),
                    ),
                  ])),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A player's value, or "—" when he hasn't played yet.
class _ValueText extends StatelessWidget {
  final double? z;

  const _ValueText(this.z);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    final v = z;
    return v == null
        ? Tooltip(message: 'No games yet', child: Text('—', style: style))
        : Text(v.toStringAsFixed(1), style: style?.copyWith(color: context.zColor(v)));
  }
}
