import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import '../models/ranking_result.dart';
import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/current_league_provider.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../state/schedule_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/league_switcher.dart';
import '../widgets/player_avatar.dart';
import '../widgets/player_row.dart';
import 'in_season_shell.dart';
import 'matchup_screen.dart' show isClose, sideOf;
import 'my_team_screen.dart';
import 'settings_screen.dart';

/// true: rank by my selected categories only; false: by all 9.
final _myCatsProvider = StateProvider<bool>((ref) => true);
final _hideInjuredProvider = StateProvider<bool>((ref) => true);

/// Free agents ranked for my team, with add/drop and "already rostered" actions.
class WaiverWireScreen extends ConsumerWidget {
  const WaiverWireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const LeagueTitle('Add/Drop'), actions: const [SettingsButton()]),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final mine = ref.watch(savedRosterPlayersProvider);
          if (mine.isEmpty) {
            return EmptyState(
              icon: Icons.person_add_alt_outlined,
              title: 'Add your team first',
              body: 'Pickups are ranked by how much they help the categories you play for.',
              action: FilledButton.icon(
                onPressed: () => addPlayersToMyTeam(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add my players'),
              ),
            );
          }

          final byMyCats = ref.watch(_myCatsProvider);
          final hideInjured = ref.watch(_hideInjuredProvider);
          final punted = ref.watch(draftStateProvider).puntedCategories;
          final playersById = ref.watch(playersByIdProvider);
          final schedule = ref.watch(scheduleProvider).value;
          final complete = ref.watch(leagueCompleteProvider);
          final today = DateTime.now();
          // Categories that are close in my current real matchup: the ones a pickup can flip this week.
          final league = ref.watch(currentLeagueProvider);
          final current = league.matchups.isEmpty ? null : league.matchups.last.week;
          final live = league.matchups
              .where((m) => m.week == current)
              .map((m) => sideOf(m, league.myName))
              .nonNulls
              .firstOrNull;
          final close = {
            if (live != null)
              for (final c in allStatCategories)
                if (isClose(c, live.me.stats[c]!, live.opp.stats[c]!)) c,
          };
          double value(RankingResult r) => byMyCats ? r.puntAdjustedZ : r.totalZ;
          final candidates = [
            for (final r in ref.watch(rankingsProvider))
              if (playersById[r.playerId] case final p?)
                // 0 games and not injured = unsigned or inactive; injured hidden unless asked for.
                if ((p.gp > 0 || leagueData.injuries.containsKey(p.id)) &&
                    !(hideInjured && leagueData.injuries[p.id]?.status == 'Out'))
                  r,
          ]..sort((a, b) => value(b).compareTo(value(a)));

          return RefreshIndicator(
            onRefresh: () => ref.refresh(leagueDataProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: candidates.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('My categories', style: theme.textTheme.titleSmall),
                                Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(text: 'Tap to add or remove. Rankings count only the selected ones.'),
                                    if (close.isNotEmpty) ...[
                                      const TextSpan(text: ' '),
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Icon(Icons.bolt, size: 16, color: context.stat.warn),
                                      ),
                                      const TextSpan(text: ' = close in this week\'s matchup.'),
                                    ],
                                  ]),
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final c in allStatCategories)
                                      FilterChip(
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (close.contains(c)) ...[
                                              Icon(Icons.bolt, size: 16, color: context.stat.warn),
                                              const SizedBox(width: 2),
                                            ],
                                            Text(c.label),
                                          ],
                                        ),
                                        tooltip: close.contains(c) ? '${c.label} is close in this week\'s matchup' : null,
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
                        if (!complete) ...[
                          const SizedBox(height: 8),
                          Material(
                            color: context.stat.warnContainer,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => ref.read(shellTabProvider.notifier).state = ShellTab.league,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: context.stat.onWarnContainer),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Top preseason players are hidden as "probably rostered" until all league rosters are entered.',
                                        style: theme.textTheme.bodySmall?.copyWith(color: context.stat.onWarnContainer),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, color: context.stat.onWarnContainer),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('My categories'), icon: Icon(Icons.track_changes)),
                            ButtonSegment(value: false, label: Text('All 9'), icon: Icon(Icons.leaderboard)),
                          ],
                          selected: {byMyCats},
                          onSelectionChanged: (s) => ref.read(_myCatsProvider.notifier).state = s.first,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: const Text('Hide injured (OUT)'),
                            selected: hideInjured,
                            onSelected: (v) => ref.read(_hideInjuredProvider.notifier).state = v,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SectionHeader(
                          '${candidates.length} free agents',
                          trailing: Text('VALUE', style: theme.textTheme.labelSmall),
                        ),
                      ],
                    ),
                  );
                }

                final r = candidates[index - 1];
                final player = playersById[r.playerId];
                if (player == null) return const SizedBox.shrink();
                final games = schedule?.teams[player.team]?.gamesThisWeek(today);
                // Strongest selected categories for this player, close-this-week ones first.
                final helps = allStatCategories.where((c) => (r.perCategoryZ[c] ?? 0) > 0.2 && !punted.contains(c)).toList()
                  ..sort((a, b) {
                    final byClose = (close.contains(b) ? 1 : 0).compareTo(close.contains(a) ? 1 : 0);
                    return byClose != 0 ? byClose : (r.perCategoryZ[b] ?? 0).compareTo(r.perCategoryZ[a] ?? 0);
                  });
                final score = value(r);

                return PlayerRow(
                  player: player,
                  onTap: () => _showAddDropSheet(context, ref, player, mine),
                  below: (games == null && helps.isEmpty)
                      ? null
                      : Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (games != null) _GamesChip(games: games),
                            if (helps.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_upward, size: 14, color: context.stat.win),
                                  const SizedBox(width: 2),
                                  Text.rich(
                                    TextSpan(children: [
                                      const TextSpan(text: 'Helps '),
                                      for (final (i, c) in helps.take(3).indexed) ...[
                                        if (i > 0) const TextSpan(text: ', '),
                                        if (close.contains(c))
                                          WidgetSpan(
                                            alignment: PlaceholderAlignment.middle,
                                            child: Icon(Icons.bolt, size: 14, color: context.stat.warn),
                                          ),
                                        TextSpan(text: c.label),
                                      ],
                                    ]),
                                    style: theme.textTheme.labelMedium?.copyWith(color: context.stat.win),
                                  ),
                                ],
                              ),
                          ],
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(score.toStringAsFixed(1), style: theme.textTheme.titleMedium?.copyWith(color: context.zColor(score))),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: theme.colorScheme.primary),
                        tooltip: 'Add ${player.name}',
                        onPressed: () => _showAddDropSheet(context, ref, player, mine),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddDropSheet(BuildContext context, WidgetRef ref, Player add, List<Player> mine) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _AddDropSheet(
        addPlayer: add,
        myRoster: mine,
        onConfirm: (drop) async {
          Navigator.of(ctx).pop();
          final notifier = ref.read(savedRosterProvider.notifier);
          if (drop != null) await notifier.removePlayer(drop.id);
          await notifier.addPlayer(add.id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(drop != null ? 'Added ${add.name}, dropped ${drop.name}' : 'Added ${add.name}'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await notifier.removePlayer(add.id);
                  if (drop != null) await notifier.addPlayer(drop.id);
                },
              ),
            ));
        },
        onRostered: (teamId) async {
          Navigator.of(ctx).pop();
          final league = ref.read(leagueTeamsProvider.notifier);
          teamId == null ? await league.markTaken(add.id) : await league.togglePlayer(teamId, add.id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('${add.name} hidden from free agents')));
        },
      ),
    );
  }
}

class _AddDropSheet extends ConsumerStatefulWidget {
  final Player addPlayer;
  final List<Player> myRoster;
  final void Function(Player? drop) onConfirm;

  /// Called with a league team id, or null for "taken, team unknown".
  final void Function(String? teamId) onRostered;

  const _AddDropSheet({required this.addPlayer, required this.myRoster, required this.onConfirm, required this.onRostered});

  @override
  ConsumerState<_AddDropSheet> createState() => _AddDropSheetState();
}

class _AddDropSheetState extends ConsumerState<_AddDropSheet> {
  Player? _drop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final z = ref.watch(leagueZProvider);
    final add = widget.addPlayer;
    final roster = [...widget.myRoster]..sort((a, b) => (z[a.id] ?? 0).compareTo(z[b.id] ?? 0));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      PlayerAvatar(nbaId: add.nbaId, playerName: add.name, radius: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add ${add.name}', style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                            Text('${add.eligiblePositions.join('/')} · ${add.team}', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: SectionHeader('Drop (weakest first)')),
                RadioGroup<String?>(
                  groupValue: _drop?.id,
                  onChanged: (id) => setState(() => _drop = roster.where((p) => p.id == id).firstOrNull),
                  child: Column(
                    children: [
                      const RadioListTile<String?>(value: null, title: Text('Nobody, I have an open spot')),
                      for (final p in roster)
                        RadioListTile<String?>(
                          value: p.id,
                          title: Text(p.name),
                          subtitle: Text('${p.eligiblePositions.join('/')} · ${p.team}'),
                          secondary: Text(
                            z[p.id]?.toStringAsFixed(1) ?? '—',
                            style: theme.textTheme.titleSmall?.copyWith(color: z[p.id] == null ? null : context.zColor(z[p.id]!)),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Not actually available?', style: theme.textTheme.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _pickTeam(context),
                        icon: const Icon(Icons.groups_outlined),
                        label: const Text('On another team…'),
                      ),
                      TextButton.icon(
                        onPressed: () => widget.onRostered(null),
                        icon: const Icon(Icons.block),
                        label: const Text('Taken, team unknown'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => widget.onConfirm(_drop),
                  icon: const Icon(Icons.check),
                  label: Text(_drop == null ? 'Add ${add.name}' : 'Add ${add.name}, drop ${_drop!.name}',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTeam(BuildContext context) async {
    final teams = ref.read(leagueTeamsProvider).value?.teams ?? const [];
    final teamId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Who has ${widget.addPlayer.name}?'),
        children: [
          for (final t in teams)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(ctx, t.id),
              child: Text(t.name),
            ),
        ],
      ),
    );
    if (teamId != null) widget.onRostered(teamId);
  }
}

class _GamesChip extends StatelessWidget {
  final int games;

  const _GamesChip({required this.games});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = games >= 4
        ? (theme.colorScheme.primaryContainer, theme.colorScheme.onPrimaryContainer)
        : (theme.colorScheme.surfaceContainerHighest, theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text('$games games this week', style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
