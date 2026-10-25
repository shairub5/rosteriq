import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/saved_roster_provider.dart';
import '../theme.dart';
import '../widgets/category_radar_chart.dart';
import '../widgets/common.dart';
import 'league_screen.dart';
import 'my_team_screen.dart';
import 'settings_screen.dart';

/// Standings within this margin (z units) count as a tie.
const _tieMargin = 0.1;

enum CategoryOutcome { win, loss, tie }

CategoryOutcome categoryOutcome(double you, double opp) {
  if ((you - opp).abs() < _tieMargin) return CategoryOutcome.tie;
  return you > opp ? CategoryOutcome.win : CategoryOutcome.loss;
}

/// My team vs. this week's opponent (a league team picked here or on the League
/// tab): projected category W/L from live season stats.
class MatchupScreen extends ConsumerWidget {
  const MatchupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchup'), actions: const [SettingsButton()]),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final league = ref.watch(leagueTeamsProvider).value;
          final mine = ref.watch(savedRosterPlayersProvider);
          final opponent = ref.watch(opponentRosterPlayersProvider);
          final punted = ref.watch(draftStateProvider).puntedCategories;
          final oppTeam = league?.opponent;

          if (league == null) return const Center(child: CircularProgressIndicator());
          if (mine.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'Add your team first',
              body: 'Your matchup compares your roster with this week\'s opponent, category by category.',
              action: FilledButton.icon(
                onPressed: () => addPlayersToMyTeam(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add my players'),
              ),
            );
          }

          final picker = _OpponentPicker(league: league);
          if (oppTeam == null || opponent.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                picker,
                const SizedBox(height: 24),
                EmptyState(
                  icon: Icons.sports_basketball_outlined,
                  title: 'Who are you playing?',
                  body: 'Add ${oppTeam?.name ?? 'your opponent'}\'s players to see where you win and lose this week.',
                  action: oppTeam == null
                      ? null
                      : FilledButton.icon(
                          onPressed: () => addPlayersToTeam(context, ref, oppTeam.id, oppTeam.name),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: Text('Add ${oppTeam.name}\'s players'),
                        ),
                ),
              ],
            );
          }

          final you = computeTeamStanding(myRoster: mine, fullPoolForBaseline: leagueData.players);
          final opp = computeTeamStanding(myRoster: opponent, fullPoolForBaseline: leagueData.players);
          final outcomes = [
            for (final c in allStatCategories)
              if (!punted.contains(c)) categoryOutcome(you[c] ?? 0, opp[c] ?? 0),
          ];
          int count(CategoryOutcome o) => outcomes.where((x) => x == o).length;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(leagueDataProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                picker,
                const SizedBox(height: 12),
                _Scoreboard(
                  wins: count(CategoryOutcome.win),
                  losses: count(CategoryOutcome.loss),
                  ties: count(CategoryOutcome.tie),
                  opponentName: oppTeam.name,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                    child: CategoryRadarChart(standing: you, puntedCategories: punted, opponent: opp),
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader('By category'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: MatchupTable(you: you, opp: opp, punted: punted),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Projected from season-to-date totals (z-scores). Ties are within ${_tieMargin.toStringAsFixed(1)}.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TeamEditorScreen(teamId: oppTeam.id)),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text('Edit ${oppTeam.name} (${opponent.length} players)'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OpponentPicker extends ConsumerWidget {
  final LeagueState league;

  const _OpponentPicker({required this.league});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownMenu<String>(
      key: ValueKey(league.opponentId),
      initialSelection: league.opponentId,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Opponent this week'),
      leadingIcon: const Icon(Icons.sports_basketball_outlined),
      onSelected: (id) {
        if (id != null) ref.read(leagueTeamsProvider.notifier).setOpponent(id);
      },
      dropdownMenuEntries: [
        for (final t in league.teams)
          DropdownMenuEntry(
            value: t.id,
            label: t.name,
            trailingIcon: Text('${t.playerIds.length}', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _Scoreboard extends StatelessWidget {
  final int wins;
  final int losses;
  final int ties;
  final String opponentName;

  const _Scoreboard({required this.wins, required this.losses, required this.ties, required this.opponentName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = wins > losses
        ? 'Projected win'
        : wins < losses
            ? 'Projected loss'
            : 'Too close to call';
    Widget cell(String n, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(n, style: theme.textTheme.displaySmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text('You vs $opponentName', style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
            Text(verdict, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                cell('$wins', 'WINS', context.stat.win),
                cell('$ties', 'TIES', theme.colorScheme.onSurfaceVariant),
                cell('$losses', 'LOSSES', context.stat.loss),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cat | You | Opp | result. The result is icon + text, never color alone,
/// and doubles as the precise-value fallback for the radar.
class MatchupTable extends StatelessWidget {
  final Map<StatCategory, double> you;
  final Map<StatCategory, double> opp;
  final Set<StatCategory> punted;

  const MatchupTable({super.key, required this.you, required this.opp, required this.punted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    TableRow row(List<Widget> cells, {bool divider = true}) => TableRow(
          decoration: divider ? BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))) : null,
          children: [for (final c in cells) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: c)],
        );
    Widget head(String t, {TextAlign align = TextAlign.start}) =>
        Text(t, textAlign: align, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant));
    Widget num(double v, TextStyle? s) => Text(v.toStringAsFixed(1), textAlign: TextAlign.end, style: s);

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth(1.3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row([head('CAT'), head('YOU', align: TextAlign.end), head('OPP', align: TextAlign.end), head('   RESULT')], divider: false),
        for (final c in allStatCategories)
          () {
            final isPunted = punted.contains(c);
            final base = theme.textTheme.bodyMedium?.copyWith(color: isPunted ? colors.outline : null);
            final (icon, label, color) = isPunted
                ? (Icons.block, 'Punt', colors.outline)
                : switch (categoryOutcome(you[c] ?? 0, opp[c] ?? 0)) {
                    CategoryOutcome.win => (Icons.check_circle, 'W', context.stat.win),
                    CategoryOutcome.loss => (Icons.cancel, 'L', context.stat.loss),
                    CategoryOutcome.tie => (Icons.remove_circle_outline, 'T', colors.onSurfaceVariant),
                  };
            return row([
              Text(c.label, style: base?.copyWith(fontWeight: FontWeight.w700)),
              num(you[c] ?? 0, base),
              num(opp[c] ?? 0, base),
              Row(children: [
                const SizedBox(width: 16),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
              ]),
            ]);
          }(),
      ],
    );
  }
}
