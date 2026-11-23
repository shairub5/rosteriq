import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/matchup_needs.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../services/player_repository.dart';
import '../services/schedule_service.dart';
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
import '../worker/espn.dart' show normalizeName;
import 'matchup_screen.dart' show CategoryOutcome, categoryOutcome, sideOf;
import 'my_team_screen.dart';
import 'settings_screen.dart';

/// true: rank by what this week's matchup needs; false: by the categories I play (season value).
final _matchupModeProvider = StateProvider<bool>((ref) => true);
final _hideInjuredProvider = StateProvider<bool>((ref) => true);
final _tabProvider = StateProvider<_Tab>((ref) => _Tab.pickups);

enum _Tab { pickups, hot, drop }

/// This week's matchup as Add/Drop sees it: both sides' projected finals and what each category needs.
typedef _MatchupView = ({
  int week,
  String opp,
  Map<StatCategory, Need> needs,
  ({int w, int l, int t}) score,
  ({DateTime start, DateTime end}) range,
});

_MatchupView? _matchupView(WidgetRef ref, List<Player> mine, PerGameBaseline baseline) {
  final data = ref.watch(leagueDataProvider).value;
  final schedule = ref.watch(scheduleProvider).value;
  final league = ref.watch(currentLeagueProvider);
  if (data == null || schedule == null || league.matchups.isEmpty) return null;
  final week = league.matchups.map((m) => m.week).reduce(max);
  final side = league.matchups.where((m) => m.week == week).map((m) => sideOf(m, league.myName)).nonNulls.firstOrNull;
  if (side == null) return null;
  final byId = ref.watch(playersByIdProvider);
  final oppRoster = [
    for (final id in ref
            .watch(leagueTeamsProvider)
            .value
            ?.teams
            .where((t) => normalizeName(t.name) == normalizeName(side.opp.name))
            .firstOrNull
            ?.playerIds ??
        const <String>[])
      ?byId[id],
  ];
  final range = fantasyWeekDates(week, schedule);
  double value(Player p) => baseline.z(seasonLine(p)).values.fold(0, (a, b) => a + b);
  Map<StatCategory, double> project(TeamWeek t, List<Player> roster) => projectSide(
        now: t,
        roster: roster,
        schedule: schedule,
        injuries: data.injuries,
        range: range,
        valueOf: value,
      );
  final me = project(side.me, mine);
  // Without the opponent's roster, their side stays at the real totals so far.
  final opp = oppRoster.isEmpty ? side.opp.stats : project(side.opp, oppRoster);
  final needs = categoryNeeds(me, opp);
  final outcomes = [
    for (final c in allStatCategories) categoryOutcome(c, me[c]!, opp[c]!),
  ];
  return (
    week: week,
    opp: side.opp.name,
    needs: needs,
    score: (
      w: outcomes.where((o) => o == CategoryOutcome.win).length,
      l: outcomes.where((o) => o == CategoryOutcome.loss).length,
      t: outcomes.where((o) => o == CategoryOutcome.tie).length,
    ),
    range: range,
  );
}

/// Pickups ranked for this week's matchup (or my categories), last night's breakout games, and my
/// weakest players to drop.
class WaiverWireScreen extends ConsumerWidget {
  const WaiverWireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          final baseline = PerGameBaseline.of(leagueData.players, leagueData.minutes);
          final view = _matchupView(ref, mine, baseline);
          final matchupMode = ref.watch(_matchupModeProvider) && view != null;
          final punted = ref.watch(draftStateProvider).puntedCategories;
          final weights = {
            for (final c in allStatCategories)
              c: punted.contains(c) ? 0.0 : (matchupMode ? needWeight[view.needs[c]]! : 1.0),
          };
          final schedule = ref.watch(scheduleProvider).value;
          final range = view?.range ?? (schedule == null ? null : fantasyWeekDates(_weekOf(schedule), schedule));
          int left(Player p) => schedule == null || range == null
              ? 0
              : weekGames(p, range, schedule, leagueData.played).left;
          final tab = ref.watch(_tabProvider);

          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (view != null) _NeedsCard(view: view) else const _NoMatchupCard(),
                const SizedBox(height: 12),
                SegmentedButton<_Tab>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Tab.pickups, label: Text('Pickups'), icon: Icon(Icons.person_add_alt_1_outlined)),
                    ButtonSegment(value: _Tab.hot, label: Text('Hot'), icon: Icon(Icons.local_fire_department_outlined)),
                    ButtonSegment(value: _Tab.drop, label: Text('Drop'), icon: Icon(Icons.person_remove_outlined)),
                  ],
                  selected: {tab},
                  onSelectionChanged: (s) => ref.read(_tabProvider.notifier).state = s.first,
                ),
              ],
            ),
          );

          final List<Widget> body = switch (tab) {
            _Tab.pickups => _pickups(context, ref, leagueData, mine, baseline, view, weights, matchupMode, left),
            _Tab.hot => _hot(context, ref, leagueData, mine, baseline, view, left),
            _Tab.drop => _drops(context, ref, leagueData, mine, baseline, view, weights, left),
          };
          return RefreshIndicator(
            onRefresh: () => ref.refresh(leagueDataProvider.future),
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [header, ...body]),
          );
        },
      ),
    );
  }

  /// The current week number from the schedule (when no matchup is loaded).
  static int _weekOf(NbaSchedule s) {
    final today = usToday();
    for (var w = 1; w < 30; w++) {
      if (!fantasyWeekDates(w, s).end.isBefore(today)) return w;
    }
    return 1;
  }

  /// Free agents that aren't hidden: played this season or are on the injury report.
  List<Player> _freeAgents(WidgetRef ref, LeagueData data, {required bool hideInjured}) => [
        for (final p in ref.watch(freeAgentsProvider))
          if ((p.gp > 0 || data.injuries.containsKey(p.id)) && !(hideInjured && data.injuries[p.id]?.status == 'Out')) p,
      ];

  List<Widget> _pickups(
    BuildContext context,
    WidgetRef ref,
    LeagueData data,
    List<Player> mine,
    PerGameBaseline baseline,
    _MatchupView? view,
    Map<StatCategory, double> weights,
    bool matchupMode,
    int Function(Player) left,
  ) {
    final theme = Theme.of(context);
    final hideInjured = ref.watch(_hideInjuredProvider);
    final scored = [
      for (final p in _freeAgents(ref, data, hideInjured: hideInjured))
        () {
          final z = baseline.z(seasonLine(p));
          final g = left(p);
          // This week, games left matter: a game is worth about a tenth of a category z.
          final fit = needScore(z, weights) + (matchupMode ? 0.1 * (g - 3) : 0);
          return (player: p, z: z, fit: fit, left: g);
        }(),
    ]..sort((a, b) => b.fit.compareTo(a.fit));
    final complete = ref.watch(leagueCompleteProvider);

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!complete) ...[
              _Banner(
                icon: Icons.info_outline,
                text: 'Top preseason players are hidden as "probably rostered" until all league rosters are entered.',
                onTap: () => ref.read(shellTabProvider.notifier).state = ShellTab.league,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (view != null)
                  FilterChip(
                    avatar: Icon(matchupMode ? Icons.sports_basketball : Icons.leaderboard_outlined, size: 18),
                    label: Text(matchupMode ? 'For this matchup' : 'Season value'),
                    selected: matchupMode,
                    onSelected: (v) => ref.read(_matchupModeProvider.notifier).state = v,
                  ),
                FilterChip(
                  label: const Text('Hide injured (OUT)'),
                  selected: hideInjured,
                  onSelected: (v) => ref.read(_hideInjuredProvider.notifier).state = v,
                ),
              ],
            ),
            SectionHeader('${scored.length} free agents', trailing: Text('FIT', style: theme.textTheme.labelSmall)),
          ],
        ),
      ),
      for (final r in scored.take(60))
        PlayerRow(
          player: r.player,
          onTap: () => _showAddDropSheet(context, ref, r.player, mine),
          below: _HelpsLine(
            left: r.left,
            helps: [
              for (final c in _byNeed(view, r.z))
                if (c != StatCategory.to && r.z[c]! > 0.25 && (weights[c] ?? 0) > 0) c,
            ],
            urgent: {
              if (view != null)
                for (final c in allStatCategories)
                  if (view.needs[c] == Need.chase || view.needs[c] == Need.tossUp) c,
            },
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.fit.toStringAsFixed(1), style: theme.textTheme.titleMedium?.copyWith(color: context.zColor(r.fit))),
              IconButton(
                icon: Icon(Icons.add_circle, color: theme.colorScheme.primary),
                tooltip: 'Add ${r.player.name}',
                onPressed: () => _showAddDropSheet(context, ref, r.player, mine),
              ),
            ],
          ),
        ),
    ];
  }

  /// Categories ordered most-needed first (then by the player's strength).
  static List<StatCategory> _byNeed(_MatchupView? view, Map<StatCategory, double> z) {
    int rank(StatCategory c) => switch (view?.needs[c]) {
          Need.chase || Need.tossUp => 0,
          Need.hold => 1,
          _ => 2,
        };
    return [...allStatCategories]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : z[b]!.compareTo(z[a]!);
      });
  }

  List<Widget> _hot(
    BuildContext context,
    WidgetRef ref,
    LeagueData data,
    List<Player> mine,
    PerGameBaseline baseline,
    _MatchupView? view,
    int Function(Player) left,
  ) {
    final theme = Theme.of(context);
    final night = data.lastNight;
    if (night == null) {
      return const [
        _InlineEmpty(icon: Icons.nights_stay_outlined, text: 'No box scores yet. They arrive with the next data update.'),
      ];
    }
    final byId = ref.watch(playersByIdProvider);
    final hot = hotNights(
      night: night,
      candidates: _freeAgents(ref, data, hideInjured: false),
      baseline: baseline,
      playersById: byId,
      minutes: data.minutes,
    );
    final mineHot = hotNights(
      night: night,
      candidates: mine,
      baseline: baseline,
      playersById: byId,
      minutes: data.minutes,
    );
    final date = '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][night.date.weekday - 1]} '
        '${_months[night.date.month - 1]} ${night.date.day}';
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: SectionHeader('Free agents who beat their usual · $date'),
      ),
      if (hot.isEmpty)
        const _InlineEmpty(icon: Icons.ac_unit, text: 'No free agent had a big night.')
      else
        for (final h in hot.take(25))
          _HotTile(hot: h, left: left(h.player), onAdd: () => _showAddDropSheet(context, ref, h.player, mine)),
      if (mineHot.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SectionHeader('My players', trailing: Text('${mineHot.length}', style: theme.textTheme.labelSmall)),
        ),
        for (final h in mineHot) _HotTile(hot: h, left: left(h.player)),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Compared with each player\'s season average across all 9 categories. A teammate listed as out '
          '(20+ minutes a game, missed the game injured) usually explains extra shots and minutes.',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  List<Widget> _drops(
    BuildContext context,
    WidgetRef ref,
    LeagueData data,
    List<Player> mine,
    PerGameBaseline baseline,
    _MatchupView? view,
    Map<StatCategory, double> weights,
    int Function(Player) left,
  ) {
    final theme = Theme.of(context);
    final drops = dropCandidates(
      roster: mine,
      baseline: baseline,
      weights: weights,
      needs: view?.needs ?? const {},
      injuries: data.injuries,
      gamesLeft: {for (final p in mine) p.id: left(p)},
      take: 5,
    );
    // Best pickups for the swap sheet, same ranking as the Pickups tab.
    final pickups = [
      for (final p in _freeAgents(ref, data, hideInjured: true))
        (player: p, fit: needScore(baseline.z(seasonLine(p)), weights) + (view == null ? 0 : 0.1 * (left(p) - 3))),
    ]..sort((a, b) => b.fit.compareTo(a.fit));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: SectionHeader(view == null ? 'Weakest on my roster' : 'Least help this week'),
      ),
      for (final (i, d) in drops.indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlayerAvatar(nbaId: d.player.nbaId, playerName: d.player.name, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (i == 0) ...[
                            Icon(Icons.arrow_downward, size: 16, color: context.stat.loss),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(d.player.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        Text('${d.player.eligiblePositions.join('/')} · ${d.player.team} · ${left(d.player)} games left',
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        if (d.reasons.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: [for (final r in d.reasons) _Pill(text: r)]),
                        ],
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: pickups.isEmpty
                        ? null
                        : () => _showSwapSheet(context, ref, d.player, mine, pickups.take(8).toList(), left),
                    child: const Text('Swap…'),
                  ),
                ],
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          view == null
              ? 'Ranked by season value in the categories you play.'
              : 'Ranked by help in the categories this matchup needs, plus games left. '
                  'Injured players among your better half are kept (stash them on IL instead).',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  Future<void> _showSwapSheet(
    BuildContext context,
    WidgetRef ref,
    Player drop,
    List<Player> mine,
    List<({Player player, double fit})> pickups,
    int Function(Player) left,
  ) {
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Drop ${drop.name} for…', style: theme.textTheme.titleLarge),
              ),
              for (final p in pickups)
                PlayerRow(
                  player: p.player,
                  below: Text('${left(p.player)} games left this week',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  trailing: Text(p.fit.toStringAsFixed(1),
                      style: theme.textTheme.titleMedium?.copyWith(color: ctx.zColor(p.fit))),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showAddDropSheet(context, ref, p.player, mine, initialDrop: drop);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddDropSheet(BuildContext context, WidgetRef ref, Player add, List<Player> mine, {Player? initialDrop}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _AddDropSheet(
        addPlayer: add,
        myRoster: mine,
        initialDrop: initialDrop,
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
  final Player? initialDrop;
  final void Function(Player? drop) onConfirm;

  /// Called with a league team id, or null for "taken, team unknown".
  final void Function(String? teamId) onRostered;

  const _AddDropSheet({
    required this.addPlayer,
    required this.myRoster,
    required this.onConfirm,
    required this.onRostered,
    this.initialDrop,
  });

  @override
  ConsumerState<_AddDropSheet> createState() => _AddDropSheetState();
}

class _AddDropSheetState extends ConsumerState<_AddDropSheet> {
  late Player? _drop = widget.initialDrop;

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

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Projected result of this week's matchup and what each category needs, as 9 labelled chips.
class _NeedsCard extends StatelessWidget {
  final _MatchupView view;

  const _NeedsCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final s = view.score;
    final verdict = s.w > s.l ? 'projected win' : s.w < s.l ? 'projected loss' : 'projected tie';
    final chase = [
      for (final c in allStatCategories)
        if (view.needs[c] == Need.chase || view.needs[c] == Need.tossUp) c.label,
    ];
    (IconData, Color, Color) look(Need n) => switch (n) {
          Need.tossUp => (Icons.balance, context.stat.onWarnContainer, context.stat.warnContainer),
          Need.chase => (Icons.trending_up, context.stat.onWarnContainer, context.stat.warnContainer),
          Need.hold => (Icons.shield_outlined, colors.onSecondaryContainer, colors.secondaryContainer),
          Need.safe => (Icons.check_circle, context.stat.win, colors.surfaceContainerHighest),
          Need.lost => (Icons.remove_circle_outline, colors.onSurfaceVariant, colors.surfaceContainerHighest),
        };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WEEK ${view.week} · VS ${view.opp.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0.6)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${s.w}–${s.l}${s.t > 0 ? '–${s.t}' : ''} ',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: s.w > s.l ? context.stat.win : s.w < s.l ? context.stat.loss : null,
                  ),
                ),
                TextSpan(text: verdict, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              ]),
            ),
            Text(
              chase.isEmpty ? 'Nothing close: pick up for the long run.' : 'Swing categories: ${chase.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in allStatCategories)
                  () {
                    final n = view.needs[c]!;
                    final (icon, fg, bg) = look(n);
                    return Tooltip(
                      message: '${c.label}: ${n.label}',
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: fg),
                            const SizedBox(width: 4),
                            Text(c.label, style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final n in Need.values)
                  if (view.needs.values.contains(n))
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(look(n).$1, size: 12, color: colors.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(n.label, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                    ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchupCard extends StatelessWidget {
  const _NoMatchupCard();

  @override
  Widget build(BuildContext context) => const _Banner(
        icon: Icons.info_outline,
        text: 'No live matchup yet, so pickups are ranked by season value. Sync the league to rank by this week\'s needs.',
      );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const _Banner({required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: context.stat.warnContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: context.stat.onWarnContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: context.stat.onWarnContainer)),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: context.stat.onWarnContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 left · Helps ⚡STL, ⚡3PM, AST" under a pickup.
class _HelpsLine extends StatelessWidget {
  final int left;
  final List<StatCategory> helps;
  final Set<StatCategory> urgent;

  const _HelpsLine({required this.left, required this.helps, required this.urgent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(text: '$left left this week', strong: left >= 4),
        if (helps.isNotEmpty)
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Helps '),
              for (final (i, c) in helps.take(3).indexed) ...[
                if (i > 0) const TextSpan(text: ', '),
                if (urgent.contains(c))
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.bolt, size: 14, color: context.stat.warn),
                  ),
                TextSpan(text: c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ]),
            style: theme.textTheme.labelMedium?.copyWith(color: context.stat.win),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool strong;

  const _Pill({required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = strong
        ? (theme.colorScheme.primaryContainer, theme.colorScheme.onPrimaryContainer)
        : (theme.colorScheme.surfaceContainerHighest, theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(children: [
        Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      ]),
    );
  }
}

/// One breakout game: the line, minutes vs usual, the margin over his usual, and hurt teammates.
class _HotTile extends StatelessWidget {
  final HotNight hot;
  final int left;
  final VoidCallback? onAdd;

  const _HotTile({required this.hot, required this.left, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = hot.line;
    final parts = [
      '${l.pts} PTS',
      if (l.reb >= 5) '${l.reb} REB',
      if (l.ast >= 4) '${l.ast} AST',
      if (l.threePM >= 2) '${l.threePM} 3PM',
      if (l.stl >= 2) '${l.stl} STL',
      if (l.blk >= 2) '${l.blk} BLK',
      '${l.fgm}/${l.fga} FG',
    ];
    final minUp = hot.usualMinutes > 0 && l.min - hot.usualMinutes >= 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlayerAvatar(nbaId: hot.player.nbaId, playerName: hot.player.name, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(hot.player.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Text(hot.player.team, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 2),
                      Text(parts.join(' · '), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${l.min.round()} min'),
                          if (hot.usualMinutes > 0)
                            TextSpan(
                              text: ' (usually ${hot.usualMinutes.round()})',
                              style: minUp ? TextStyle(color: context.stat.win, fontWeight: FontWeight.w700) : null,
                            ),
                          TextSpan(text: ' · $left left this week'),
                        ]),
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      if (hot.boost.isNotEmpty)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.healing, size: 14, color: context.stat.warn),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('With ${hot.boost.take(3).join(', ')} out',
                                style: theme.textTheme.labelSmall?.copyWith(color: context.stat.warn, fontWeight: FontWeight.w700)),
                          ),
                        ])
                      else
                        Row(children: [
                          Icon(Icons.trending_up, size: 14, color: colors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(minUp ? 'No regular out: maybe a bigger role' : 'No regular out',
                                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                          ),
                        ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: context.stat.warnContainer, borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.local_fire_department, size: 14, color: context.stat.onWarnContainer),
                        Text('+${hot.delta.toStringAsFixed(1)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: context.stat.onWarnContainer, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    Text('vs usual', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                    if (onAdd != null)
                      IconButton(
                        icon: Icon(Icons.add_circle, color: colors.primary),
                        tooltip: 'Add ${hot.player.name}',
                        onPressed: onAdd,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
