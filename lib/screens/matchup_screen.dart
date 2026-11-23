import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import '../models/stat_category.dart';
import '../services/player_repository.dart';
import '../engine/matchup_needs.dart';
import '../state/current_league_provider.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/saved_roster_provider.dart';
import '../state/schedule_provider.dart';
import '../worker/espn.dart' show InjuryEntry, normalizeName;
import '../theme.dart';
import '../widgets/category_radar_chart.dart';
import '../widgets/common.dart';
import '../widgets/league_switcher.dart';
import 'settings_screen.dart';

enum CategoryOutcome { win, loss, tie }

/// Real head-to-head result for one category (fewer turnovers wins).
CategoryOutcome categoryOutcome(StatCategory c, double mine, double theirs) {
  if (mine == theirs) return CategoryOutcome.tie;
  return (mine > theirs) != c.lowerIsBetter ? CategoryOutcome.win : CategoryOutcome.loss;
}

typedef Score = ({int w, int l, int t});

/// W/L/T of [x] against [y] across the 9 categories.
Score score(TeamWeek x, TeamWeek y) {
  final o = [for (final c in allStatCategories) categoryOutcome(c, x.stats[c]!, y.stats[c]!)];
  return (
    w: o.where((v) => v == CategoryOutcome.win).length,
    l: o.where((v) => v == CategoryOutcome.loss).length,
    t: o.where((v) => v == CategoryOutcome.tie).length,
  );
}

/// The matchup from [name]'s side, or null when that team isn't in it.
({TeamWeek me, TeamWeek opp})? sideOf(LeagueMatchup m, String? name) =>
    name == null ? null : (m.a.name == name ? (me: m.a, opp: m.b) : m.b.name == name ? (me: m.b, opp: m.a) : null);

/// Within reach: percentages within .010, counting stats within 5% (and 3 at least).
bool isClose(StatCategory c, double x, double y) => c == StatCategory.fgPct || c == StatCategory.ftPct
    ? (x - y).abs() <= 0.010
    : (x - y).abs() <= [3.0, 0.05 * (x > y ? x : y)].reduce((a, b) => a > b ? a : b);

String formatStat(StatCategory c, double v) => c == StatCategory.fgPct || c == StatCategory.ftPct
    ? v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')
    : v.toStringAsFixed(0);

/// One team's results over a period: matchup record, category record, and wins per category.
typedef TeamPeriod = ({String name, Score record, Score cats, Map<StatCategory, int> catWins});

List<TeamPeriod> leagueTable(Iterable<LeagueMatchup> matchups) {
  final rows = <String, TeamPeriod>{};
  void add(TeamWeek x, TeamWeek y) {
    final s = score(x, y);
    final r = rows[x.name] ??
        (name: x.name, record: (w: 0, l: 0, t: 0), cats: (w: 0, l: 0, t: 0), catWins: {for (final c in allStatCategories) c: 0});
    rows[x.name] = (
      name: x.name,
      record: (w: r.record.w + (s.w > s.l ? 1 : 0), l: r.record.l + (s.w < s.l ? 1 : 0), t: r.record.t + (s.w == s.l ? 1 : 0)),
      cats: (w: r.cats.w + s.w, l: r.cats.l + s.l, t: r.cats.t + s.t),
      catWins: {
        for (final c in allStatCategories)
          c: r.catWins[c]! + (categoryOutcome(c, x.stats[c]!, y.stats[c]!) == CategoryOutcome.win ? 1 : 0),
      },
    );
  }

  for (final m in matchups) {
    add(m.a, m.b);
    add(m.b, m.a);
  }
  return rows.values.toList();
}

/// Each team's category values over the period (weekly average) as z-scores across the
/// league's teams, sign-flipped for TO so farther out is always better. Feeds the radar,
/// whose middle ring is then "league average".
Map<String, Map<StatCategory, double>> leagueZ(Iterable<LeagueMatchup> matchups) {
  final sums = <String, Map<StatCategory, double>>{};
  final weeks = <String, int>{};
  for (final m in matchups) {
    for (final t in [m.a, m.b]) {
      final acc = sums.putIfAbsent(t.name, () => {for (final c in allStatCategories) c: 0});
      for (final c in allStatCategories) {
        acc[c] = acc[c]! + t.stats[c]!;
      }
      weeks[t.name] = (weeks[t.name] ?? 0) + 1;
    }
  }
  final avg = {
    for (final e in sums.entries) e.key: {for (final c in allStatCategories) c: e.value[c]! / weeks[e.key]!},
  };
  final out = {for (final t in avg.keys) t: <StatCategory, double>{}};
  for (final c in allStatCategories) {
    final values = [for (final t in avg.values) t[c]!];
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sd = values.length < 2
        ? 0.0
        : (values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length).sqrtOr0();
    for (final t in avg.keys) {
      final z = sd == 0 ? 0.0 : (avg[t]![c]! - mean) / sd;
      out[t]![c] = c.lowerIsBetter ? -z : z;
    }
  }
  return out;
}

extension on double {
  double sqrtOr0() => this <= 0 ? 0 : math.sqrt(this);
}

/// "All-play": every team compared with every other team, per category, as if
/// it had played the whole league each week. `cats[c]` = wins/losses/ties over
/// the period (11 opponents per week); `avg[c]` = the team's weekly average.
typedef AllPlayRow = ({String name, Map<StatCategory, Score> cats, Score total, Map<StatCategory, double> avg});

List<AllPlayRow> allPlay(Iterable<LeagueMatchup> matchups) {
  final byWeek = <int, List<TeamWeek>>{};
  for (final m in matchups) {
    byWeek.putIfAbsent(m.week, () => []).addAll([m.a, m.b]);
  }
  final cats = <String, Map<StatCategory, List<int>>>{};
  final sums = <String, Map<StatCategory, double>>{};
  final weeks = <String, int>{};
  for (final teams in byWeek.values) {
    for (final t in teams) {
      final acc = cats.putIfAbsent(t.name, () => {for (final c in allStatCategories) c: [0, 0, 0]});
      final sum = sums.putIfAbsent(t.name, () => {for (final c in allStatCategories) c: 0});
      weeks[t.name] = (weeks[t.name] ?? 0) + 1;
      for (final c in allStatCategories) {
        sum[c] = sum[c]! + t.stats[c]!;
        for (final o in teams) {
          if (o.name == t.name) continue;
          acc[c]![switch (categoryOutcome(c, t.stats[c]!, o.stats[c]!)) {
            CategoryOutcome.win => 0,
            CategoryOutcome.loss => 1,
            CategoryOutcome.tie => 2,
          }]++;
        }
      }
    }
  }
  return [
    for (final name in cats.keys)
      () {
        final per = {for (final c in allStatCategories) c: (w: cats[name]![c]![0], l: cats[name]![c]![1], t: cats[name]![c]![2])};
        return (
          name: name,
          cats: per,
          total: per.values.fold<Score>((w: 0, l: 0, t: 0), (a, s) => (w: a.w + s.w, l: a.l + s.l, t: a.t + s.t)),
          avg: {for (final c in allStatCategories) c: sums[name]![c]! / weeks[name]!},
        );
      }(),
  ];
}

/// 1-based league rank of [name] in category [c] by all-play wins (ties share a rank).
int allPlayRank(List<AllPlayRow> rows, String name, StatCategory c) {
  final mine = rows.firstWhere((r) => r.name == name).cats[c]!.w;
  return rows.where((r) => r.cats[c]!.w > mine).length + 1;
}

String ordinal(int n) => '$n${n % 100 >= 11 && n % 100 <= 13 ? 'th' : const {1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th'}';

/// Projected final for the week: totals so far + games remaining x the roster's average
/// per-game line this season (healthy players with games only). FG%/FT% are recomputed from
/// projected makes/attempts when the screenshot gave them. Null when there's nothing to project.
/// [t]'s projected final for [week]: day by day from today, each day's 10 best healthy players at
/// their season averages (see [projectSide]). Falls back to [projectWeek] until the schedule loads.
TeamWeek? _projectTeam(WidgetRef ref, TeamWeek t, List<Player> roster, int week) {
  final data = ref.watch(leagueDataProvider).value;
  final schedule = ref.watch(scheduleProvider).value;
  final injuries = data?.injuries ?? const <String, InjuryEntry>{};
  if (data == null || schedule == null) return projectWeek(t, roster, injuries);
  if (roster.where((p) => p.gp > 0).isEmpty) return null;
  final baseline = PerGameBaseline.of(data.players, data.minutes);
  return (
    name: t.name,
    extra: t.extra,
    stats: projectSide(
      now: t,
      roster: roster,
      schedule: schedule,
      injuries: injuries,
      range: fantasyWeekDates(week, schedule),
      valueOf: (p) => baseline.z(seasonLine(p)).values.fold(0, (a, b) => a + b),
    ),
  );
}

TeamWeek? projectWeek(TeamWeek t, List<Player> roster, Map<String, InjuryEntry> injuries) {
  final remaining = t.extra['remaining'] ?? 0;
  final active = roster.where((p) => p.gp > 0 && injuries[p.id]?.status != 'Out').toList();
  if (remaining <= 0 || active.isEmpty) return null;
  // shortcut: every remaining game counts as an average roster game; Yahoo's per-player schedule would be more exact.
  double perGame(num Function(Player p) total) =>
      active.map((p) => total(p) / p.gp).reduce((a, b) => a + b) / active.length * remaining;
  double pct(StatCategory c, String made, String att, num Function(Player p) pctOf, num Function(Player p) attOf) {
    final m = t.extra[made], a = t.extra[att];
    if (m == null || a == null || a <= 0) return t.stats[c]!;
    return (m + perGame((p) => pctOf(p) * attOf(p))) / (a + perGame(attOf));
  }

  return (
    name: t.name,
    extra: t.extra,
    stats: {
      StatCategory.fgPct: pct(StatCategory.fgPct, 'fgm', 'fga', (p) => p.fgPct, (p) => p.fgAttempted),
      StatCategory.ftPct: pct(StatCategory.ftPct, 'ftm', 'fta', (p) => p.ftPct, (p) => p.ftAttempted),
      StatCategory.threePM: t.stats[StatCategory.threePM]! + perGame((p) => p.threePM),
      StatCategory.pts: t.stats[StatCategory.pts]! + perGame((p) => p.pts),
      StatCategory.reb: t.stats[StatCategory.reb]! + perGame((p) => p.reb),
      StatCategory.ast: t.stats[StatCategory.ast]! + perGame((p) => p.ast),
      StatCategory.stl: t.stats[StatCategory.stl]! + perGame((p) => p.stl),
      StatCategory.blk: t.stats[StatCategory.blk]! + perGame((p) => p.blk),
      StatCategory.to: t.stats[StatCategory.to]! + perGame((p) => p.to),
    },
  );
}

/// A week is over once both teams in a matchup show 0 games remaining (unknown counts as not over).
bool isFinal(LeagueMatchup m) => m.a.extra['remaining'] == 0 && m.b.extra['remaining'] == 0;

/// Week chip selection: a week number, [_season], or null for the latest week.
const _season = 0;
final _selectedProvider = StateProvider<int?>((ref) => null);
final _opponentFilterProvider = StateProvider<String?>((ref) => null);
final _leagueViewProvider = StateProvider<bool>((ref) => false);

final _projectedProvider = StateProvider<bool>((ref) => false);

/// Team to compare the week against; null = the real opponent of [_sideProvider]'s team.
final _compareProvider = StateProvider<String?>((ref) => null);

/// Team whose week is shown; null = mine.
final _sideProvider = StateProvider<String?>((ref) => null);

/// Keep both team picks when switching weeks; off = back to my own matchup.
final _keepProvider = StateProvider<bool>((ref) => false);

/// Real weekly matchups (from Yahoo screenshots): mine, the rest of the league,
/// and a league table, for one week or the whole season.
class MatchupScreen extends ConsumerWidget {
  const MatchupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const LeagueTitle('Matchup'), actions: const [SettingsButton()]),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final current = ref.watch(currentLeagueProvider);
          final all = current.matchups;
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_basketball_outlined,
              title: 'No matchups yet',
              body: 'Send screenshots of the Yahoo matchup pages to the RosterIQ Telegram bot '
                  '(no caption needed). Each week\'s real category totals show up here.',
            );
          }
          final weeks = {for (final m in all) m.week}.toList()..sort();
          // A week from another league (after switching) falls back to this league's latest.
          final picked = ref.watch(_selectedProvider);
          final selected = picked == _season || weeks.contains(picked) ? picked! : weeks.last;
          final period = selected == _season ? all : all.where((m) => m.week == selected).toList();
          final league = ref.watch(_leagueViewProvider);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(leagueDataProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                DropdownMenu<int>(
                  key: ValueKey('period$selected'),
                  initialSelection: selected,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Period'),
                  leadingIcon: const Icon(Icons.calendar_month_outlined),
                  onSelected: (v) {
                    ref.read(_selectedProvider.notifier).state = v;
                    if (!ref.read(_keepProvider)) {
                      ref.read(_compareProvider.notifier).state = null;
                      ref.read(_sideProvider.notifier).state = null;
                    }
                  },
                  dropdownMenuEntries: [
                    for (final w in weeks.reversed)
                      DropdownMenuEntry(
                        value: w,
                        label: w == weeks.last && !all.where((m) => m.week == w).every(isFinal) ? 'Week $w (current)' : 'Week $w',
                      ),
                    const DropdownMenuEntry(value: _season, label: 'Season'),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Me'), icon: Icon(Icons.person_outline)),
                    ButtonSegment(value: true, label: Text('League'), icon: Icon(Icons.leaderboard_outlined)),
                  ],
                  selected: {league},
                  onSelectionChanged: (v) => ref.read(_leagueViewProvider.notifier).state = v.first,
                ),
                const SizedBox(height: 12),
                if (league)
                  ..._leagueView(context, period, all, current.myName, season: selected == _season)
                else if (selected == _season)
                  ..._seasonView(context, ref, all, current.myName)
                else
                  ..._weekView(context, ref, period, current.myName, isLatest: selected == weeks.last),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _weekView(
    BuildContext context,
    WidgetRef ref,
    List<LeagueMatchup> week,
    String? myName, {
    required bool isLatest,
  }) {
    final theme = Theme.of(context);
    final w = week.first;
    // Every team's totals this week, so any two can be compared.
    final teams = {
      for (final m in week)
        for (final t in [m.a, m.b]) t.name: t,
    };
    // A picked team missing from this week (kept from another week) falls back to mine.
    final picked = ref.watch(_sideProvider);
    final sideName = teams.containsKey(picked) ? picked : myName;
    final isMe = sideName == myName;
    final real = week.map((m) => sideOf(m, sideName)).nonNulls.firstOrNull;
    final compareName = ref.watch(_compareProvider);
    final now = real == null
        ? null
        : (me: real.me, opp: compareName != sideName ? teams[compareName] ?? real.opp : real.opp);
    final hypothetical = now != null && now.opp.name != real!.opp.name;
    final sideLabel = isMe ? 'You' : sideName!;

    // Projected final: needs each side's roster (mine from My Team, others from League by name).
    final leagueData = ref.watch(leagueDataProvider).value;
    final byId = ref.watch(playersByIdProvider);
    List<Player> rosterOf(String name) => name == myName
        ? ref.watch(savedRosterPlayersProvider)
        : [
            for (final id in ref
                    .watch(leagueTeamsProvider)
                    .value
                    ?.teams
                    .where((t) => normalizeName(t.name) == normalizeName(name))
                    .firstOrNull
                    ?.playerIds ??
                const <String>[])
              ?byId[id],
          ];
    final live = isLatest && !week.every(isFinal);
    final wantProjected = ref.watch(_projectedProvider) && live;
    final projected = now == null || !wantProjected
        ? null
        : (
            me: _projectTeam(ref, now.me, rosterOf(now.me.name), w.week),
            opp: _projectTeam(ref, now.opp, rosterOf(now.opp.name), w.week),
          );
    final showProjected = projected != null && (projected.me != null || projected.opp != null);
    final mine = now == null
        ? null
        : showProjected
            ? (me: projected.me ?? now.me, opp: projected.opp ?? now.opp)
            : now;
    return [
      if (mine != null) ...[
        DropdownMenu<String>(
          key: ValueKey('side${mine.me.name}'),
          initialSelection: mine.me.name,
          expandedInsets: EdgeInsets.zero,
          label: const Text('Team'),
          leadingIcon: const Icon(Icons.person_outline),
          onSelected: (v) {
            ref.read(_sideProvider.notifier).state = v;
            // A new team starts against its real opponent this week (pinned by name when keeping).
            ref.read(_compareProvider.notifier).state =
                ref.read(_keepProvider) ? week.map((m) => sideOf(m, v)).nonNulls.firstOrNull?.opp.name : null;
          },
          dropdownMenuEntries: [
            if (myName != null && teams.containsKey(myName)) DropdownMenuEntry(value: myName, label: '$myName (me)'),
            for (final name in teams.keys.where((n) => n != myName).toList()..sort())
              DropdownMenuEntry(value: name, label: name),
          ],
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          key: ValueKey('cmp${mine.me.name}${mine.opp.name}'),
          initialSelection: mine.opp.name,
          expandedInsets: EdgeInsets.zero,
          label: const Text('Compare with'),
          leadingIcon: const Icon(Icons.compare_arrows),
          // The name itself, even for the real opponent, so Keep selection holds it across weeks.
          onSelected: (v) => ref.read(_compareProvider.notifier).state = v,
          dropdownMenuEntries: [
            DropdownMenuEntry(value: real!.opp.name, label: '${real.opp.name} (${isMe ? 'my' : 'their'} opponent)'),
            for (final name in teams.keys.where((n) => n != real.opp.name && n != sideName).toList()..sort())
              DropdownMenuEntry(value: name, label: name),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Keep selection'),
          subtitle: const Text('Same teams when you change week'),
          value: ref.watch(_keepProvider),
          onChanged: (v) {
            ref.read(_keepProvider.notifier).state = v;
            // Pin the two teams on screen, including an untouched default (my real matchup).
            if (v) {
              ref.read(_sideProvider.notifier).state = mine.me.name;
              ref.read(_compareProvider.notifier).state = mine.opp.name;
            }
          },
        ),
        if (live) ...[
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Now'), icon: Icon(Icons.schedule)),
              ButtonSegment(value: true, label: Text('Projected final'), icon: Icon(Icons.trending_up)),
            ],
            selected: {wantProjected},
            onSelectionChanged: (v) => ref.read(_projectedProvider.notifier).state = v.first,
          ),
          if (wantProjected && !showProjected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Can\'t project yet: both rosters need to be in League.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 12),
        () {
          final s = score(mine.me, mine.opp);
          final nowScore = score(now!.me, now.opp);
          String games(TeamWeek t) => '${(t.extra['remaining'] ?? 0).round()}';
          return _Scoreboard(
            title: 'Week ${w.week} · $sideLabel vs ${mine.opp.name}',
            subtitle: showProjected
                ? 'Projected final · now ${nowScore.w}-${nowScore.l}-${nowScore.t} · games left: '
                    'you ${games(now.me)}, them ${games(now.opp)}'
                : hypothetical
                    ? 'If ${isMe ? 'you' : 'they'} had played them · '
                        '${s.w > s.l ? '${isMe ? 'you' : 'they'}\'d win' : s.w < s.l ? '${isMe ? 'you' : 'they'}\'d lose' : 'a tie'}'
                    : '${_verdict(s, inProgress: live)}${live ? ' · updated ${_ago(w.updatedAt)}' : ' · final'}',
            score: s,
          );
        }(),
        if (sideName != null) ...[
          const SizedBox(height: 16),
          SectionHeader(isMe ? 'My rank in the league' : '$sideName: rank in the league'),
          Card(child: MyRanks(rows: allPlay(week), myName: sideName)),
        ],
        const SizedBox(height: 12),
        _RadarCard(
          me: leagueZ(week)[mine.me.name]!,
          opp: leagueZ(week)[mine.opp.name],
          oppName: mine.opp.name,
          meName: sideLabel,
          caption: 'Each category vs all 12 teams this week',
        ),
        const SizedBox(height: 16),
        const SectionHeader('By category'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: MatchupTable(
              a: mine.me,
              b: mine.opp,
              aLabel: isMe ? 'YOU' : _short(sideName!),
              bLabel: hypothetical || !isMe ? _short(mine.opp.name) : 'OPP',
              aNow: showProjected ? now!.me : null,
              bNow: showProjected ? now!.opp : null,
            ),
          ),
        ),
        // Before the week's first game everything is 0-0, which isn't "close".
        if (live && !hypothetical && (now!.me.stats[StatCategory.pts]! > 0 || now.opp.stats[StatCategory.pts]! > 0))
          () {
            final close = [
              for (final c in allStatCategories)
                if (isClose(c, mine.me.stats[c]!, mine.opp.stats[c]!)) c,
            ];
            if (close.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: context.stat.warnContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: context.stat.onWarnContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Still close: ${close.map((c) => c.label).join(', ')}. '
                          'A streamer or a lineup change could swing ${close.length == 1 ? 'it' : 'these'}.',
                          style: theme.textTheme.bodySmall?.copyWith(color: context.stat.onWarnContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
        if (ref.watch(scheduleProvider).value case final schedule?)
          () {
            final range = fantasyWeekDates(w.week, schedule);
            final today = usToday();
            final current = !today.isBefore(range.start) && !today.isAfter(range.end);
            final injuries = leagueData?.injuries ?? const <String, InjuryEntry>{};
            final lineups = ref.watch(currentLeagueProvider).lineups;
            List<PlayerGames> rows(TeamWeek t, bool mineSide) => [
                  for (final g in teamWeekGames(
                    roster: rosterOf(t.name),
                    playersById: byId,
                    lineups: lineups[t.name],
                    range: range,
                    schedule: schedule,
                    played: leagueData?.played ?? const {},
                    today: today,
                  ))
                    (
                      player: g.player,
                      mine: mineSide,
                      games: g.games,
                      benched: g.benched,
                      dropped: !g.onRoster,
                      status: injuries[g.player.id]?.status,
                    ),
                ];
            final all = [...rows(mine.me, true), ...rows(mine.opp, false)];
            if (all.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader('Games per player · week ${w.week}'),
                  Card(
                    child: PlayerGamesTable(
                      rows: all,
                      meLabel: sideLabel,
                      oppLabel: mine.opp.name,
                      showLeft: current,
                      caption: '${_md(range.start)} – ${_md(range.end)} · played = games in the lineup'
                          '${lineups[mine.me.name] == null ? ' (box scores until a Yahoo sync saves lineups)' : ''}'
                          '${current ? ', left = NBA schedule from today' : ''}',
                    ),
                  ),
                ],
              ),
            );
          }(),
      ] else
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Your matchup isn\'t in yet'),
            subtitle: const Text('Send the screenshot of your own matchup page to the bot.'),
          ),
        ),
    ];
  }

  List<Widget> _leagueView(
    BuildContext context,
    List<LeagueMatchup> period,
    List<LeagueMatchup> all,
    String? myName, {
    required bool season,
  }) {
    final rows = leagueTable(period);
    final label = season ? 'season' : 'week ${period.first.week}';
    return [
      SectionHeader('Category ranks · all teams · $label'),
      Card(clipBehavior: Clip.antiAlias, child: AllPlayTable(rows: allPlay(period), myName: myName)),
      const SizedBox(height: 6),
      Text(
        'Each team\'s rank among all 12 in every category, with its total underneath'
        '${season ? ' (weekly average)' : ''}. Swipe sideways for all 9; tap a column to sort.',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      SectionHeader('Standings · $label'),
      Card(clipBehavior: Clip.antiAlias, child: Standings(rows: rows, period: period, myName: myName)),
      const SizedBox(height: 6),
      Text('Ranked by categories won. Tap a team for its splits.',
          style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      const SectionHeader('Head-to-head category wins'),
      Card(clipBehavior: Clip.antiAlias, child: LeagueTable(rows: rows, myName: myName)),
      const SizedBox(height: 6),
      Text('Only against the team actually played. Swipe sideways; tap a column to sort.',
          style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      if (!season) ...[
        const SizedBox(height: 16),
        const SectionHeader('Matchups'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, m) in period.indexed) ...[
                if (i > 0) const Divider(indent: 16),
                _MatchupRow(m: m),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _seasonView(BuildContext context, WidgetRef ref, List<LeagueMatchup> all, String? myName) {
    final theme = Theme.of(context);
    final mine = [
      for (final m in all)
        if (sideOf(m, myName) case final s?) (week: m.week, me: s.me, opp: s.opp),
    ];
    if (mine.isEmpty) return const [];
    final opponents = {for (final m in mine) m.opp.name}.toList()..sort();
    // A filter left over from another league (after switching) means "all".
    final filter = opponents.contains(ref.watch(_opponentFilterProvider)) ? ref.watch(_opponentFilterProvider) : null;
    final shown = filter == null ? mine : mine.where((m) => m.opp.name == filter).toList();
    final scores = [for (final m in shown) score(m.me, m.opp)];
    int sum(int Function(Score s) f) => scores.fold(0, (a, s) => a + f(s));

    return [
      DropdownMenu<String?>(
        key: ValueKey(filter),
        initialSelection: filter,
        expandedInsets: EdgeInsets.zero,
        label: const Text('My matchups vs'),
        leadingIcon: const Icon(Icons.filter_list),
        onSelected: (v) => ref.read(_opponentFilterProvider.notifier).state = v,
        dropdownMenuEntries: [
          const DropdownMenuEntry(value: null, label: 'All opponents'),
          for (final o in opponents) DropdownMenuEntry(value: o, label: o),
        ],
      ),
      const SizedBox(height: 12),
      _Scoreboard(
        title: filter == null ? 'My season' : 'Head to head vs $filter',
        subtitle: 'Categories ${sum((s) => s.w)}-${sum((s) => s.l)}-${sum((s) => s.t)} '
            'over ${shown.length} week${shown.length == 1 ? '' : 's'}'
            '${shown.any((m) => m.week == all.last.week) && !all.where((m) => m.week == all.last.week).every(isFinal) ? ' (week ${all.last.week} still in progress)' : ''}',
        score: (
          w: scores.where((s) => s.w > s.l).length,
          l: scores.where((s) => s.w < s.l).length,
          t: scores.where((s) => s.w == s.l).length,
        ),
      ),
      if (leagueZ(all)[myName] case final me?) ...[
        const SizedBox(height: 12),
        _RadarCard(
          me: me,
          opp: filter == null ? null : leagueZ(all)[filter],
          oppName: filter,
          caption: 'Weekly average vs all 12 teams this season',
        ),
        const SizedBox(height: 16),
        const SectionHeader('My rank in the league · season'),
        Card(child: MyRanks(rows: allPlay(all), myName: myName!)),
      ],
      const SizedBox(height: 16),
      const SectionHeader('How often I win each category'),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              for (final c in allStatCategories)
                () {
                  final won = shown.where((m) => categoryOutcome(c, m.me.stats[c]!, m.opp.stats[c]!) == CategoryOutcome.win).length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 44, child: Text(c.label, style: theme.textTheme.titleSmall)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: shown.isEmpty ? 0 : won / shown.length,
                              minHeight: 10,
                              color: context.stat.win,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        SizedBox(width: 64, child: Text('$won of ${shown.length}', textAlign: TextAlign.end)),
                      ],
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const SectionHeader('My weeks'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, m) in shown.reversed.indexed) ...[
              if (i > 0) const Divider(indent: 16),
              () {
                final s = score(m.me, m.opp);
                final (label, color) = s.w > s.l
                    ? ('W', context.stat.win)
                    : s.w < s.l
                        ? ('L', context.stat.loss)
                        : ('T', theme.colorScheme.onSurfaceVariant);
                return ListTile(
                  title: Text('Week ${m.week}'),
                  subtitle: Text('vs ${m.opp.name}'),
                  trailing: Text('$label ${s.w}-${s.l}-${s.t}', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                  onTap: () => ref.read(_selectedProvider.notifier).state = m.week,
                );
              }(),
            ],
          ],
        ),
      ),
    ];
  }

  String _verdict(Score s, {required bool inProgress}) {
    if (s.w == s.l) return inProgress ? 'Tied right now' : 'Tie';
    final ahead = s.w > s.l;
    return inProgress ? (ahead ? 'Leading' : 'Trailing') : (ahead ? 'Won' : 'Lost');
  }
}

/// Me (filled) vs an opponent (outline) on league-relative scales.
class _RadarCard extends StatelessWidget {
  final Map<StatCategory, double> me;
  final Map<StatCategory, double>? opp;
  final String? oppName;
  final String meName;
  final String caption;

  const _RadarCard({required this.me, required this.opp, this.oppName, this.meName = 'You', required this.caption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          children: [
            Text(caption, style: theme.textTheme.bodySmall),
            Text('Bold ring = league average · farther out = better', style: theme.textTheme.bodySmall),
            CategoryRadarChart(standing: me, puntedCategories: const {}, opponent: opp, opponentLabel: oppName ?? 'Opponent', label: meName),
          ],
        ),
      ),
    );
  }
}

/// Teams ranked by categories won in the period; each row expands into its splits.
class Standings extends StatelessWidget {
  final List<TeamPeriod> rows;
  final List<LeagueMatchup> period;
  final String? myName;

  const Standings({super.key, required this.rows, required this.period, required this.myName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double pct(Score s) => s.w + s.l + s.t == 0 ? 0 : (s.w + s.t / 2) / (s.w + s.l + s.t);
    final ranked = [...rows]..sort((a, b) {
        final byWins = b.cats.w.compareTo(a.cats.w);
        return byWins != 0 ? byWins : pct(b.cats).compareTo(pct(a.cats));
      });
    final weeks = {for (final m in period) m.week}.toList()..sort();

    return Column(
      children: [
        for (final (i, r) in ranked.indexed) ...[
          if (i > 0) const Divider(height: 1),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              backgroundColor: r.name == myName ? theme.colorScheme.primaryContainer : null,
              collapsedBackgroundColor: r.name == myName ? theme.colorScheme.primaryContainer : null,
              leading: SizedBox(
                width: 28,
                child: Text('${ranked.indexWhere((x) => x.cats.w == r.cats.w) + 1}',
                    style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              ),
              title: Text(r.name == myName ? '${r.name} (you)' : r.name,
                  overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              subtitle: Text('Matchups ${r.record.w}-${r.record.l}-${r.record.t}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${r.cats.w}-${r.cats.l}-${r.cats.t}', style: theme.textTheme.titleSmall),
                  Text('${(pct(r.cats) * 100).round()}%', style: theme.textTheme.bodySmall),
                ],
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categories won', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in allStatCategories)
                      _SplitChip(label: c.label, value: '${r.catWins[c]}/${r.record.w + r.record.l + r.record.t}'),
                  ],
                ),
                if (weeks.length > 1) ...[
                  const SizedBox(height: 10),
                  Text('By week', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final w in weeks)
                        if (period.where((m) => m.week == w).map((m) => sideOf(m, r.name)).nonNulls.firstOrNull
                            case final side?)
                          () {
                            final s = score(side.me, side.opp);
                            return _SplitChip(label: 'W$w', value: '${s.w}-${s.l}-${s.t}', won: s.w > s.l);
                          }(),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SplitChip extends StatelessWidget {
  final String label;
  final String value;
  final bool? won;

  const _SplitChip({required this.label, required this.value, this.won});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = won == null ? null : (won! ? context.stat.win : context.stat.loss);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label ', style: theme.textTheme.labelMedium),
        TextSpan(text: value, style: theme.textTheme.labelLarge?.copyWith(color: color)),
      ])),
    );
  }
}

/// "A 4-5 B" row; tap for the full category table.
class _MatchupRow extends StatelessWidget {
  final LeagueMatchup m;

  const _MatchupRow({required this.m});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = score(m.a, m.b);
    TextStyle? style(bool won) => theme.textTheme.bodyMedium?.copyWith(fontWeight: won ? FontWeight.w700 : null);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Week ${m.week}', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              MatchupTable(a: m.a, b: m.b, aLabel: _short(m.a.name), bLabel: _short(m.b.name)),
            ],
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(m.a.name, style: style(s.w > s.l), overflow: TextOverflow.ellipsis)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${s.w} – ${s.l}${s.t > 0 ? ' – ${s.t}' : ''}', style: theme.textTheme.titleSmall),
              ),
              Expanded(
                child: Text(m.b.name, style: style(s.l > s.w), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String name) => name.length <= 10 ? name.toUpperCase() : '${name.substring(0, 9).toUpperCase()}…';
}

class _Scoreboard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Score score;

  const _Scoreboard({required this.title, required this.subtitle, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(int n, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text('$n', style: theme.textTheme.displaySmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(subtitle, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              children: [
                cell(score.w, 'WINS', context.stat.win),
                cell(score.t, 'TIES', theme.colorScheme.onSurfaceVariant),
                cell(score.l, 'LOSSES', context.stat.loss),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cat | A | B | result for A, with real totals. The result is icon + text, never color alone.
class MatchupTable extends StatelessWidget {
  final TeamWeek a;
  final TeamWeek b;
  final String aLabel;
  final String bLabel;

  /// Current totals when [a]/[b] are projections: shown as "now X" under each value, and a
  /// category whose result would change is marked.
  final TeamWeek? aNow;
  final TeamWeek? bNow;

  const MatchupTable({
    super.key,
    required this.a,
    required this.b,
    required this.aLabel,
    required this.bLabel,
    this.aNow,
    this.bNow,
  });

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

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row([head('CAT'), head(aLabel, align: TextAlign.end), head(bLabel, align: TextAlign.end), head('    RESULT')],
            divider: false),
        for (final c in allStatCategories)
          () {
            final (icon, label, color) = switch (categoryOutcome(c, a.stats[c]!, b.stats[c]!)) {
              CategoryOutcome.win => (Icons.check_circle, 'W', context.stat.win),
              CategoryOutcome.loss => (Icons.cancel, 'L', context.stat.loss),
              CategoryOutcome.tie => (Icons.remove_circle_outline, 'T', colors.onSurfaceVariant),
            };
            Widget value(TeamWeek t, TeamWeek? was) => was == null
                ? Text(formatStat(c, t.stats[c]!), textAlign: TextAlign.end)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatStat(c, t.stats[c]!), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text('now ${formatStat(c, was.stats[c]!)}',
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  );
            final flips = aNow != null &&
                bNow != null &&
                categoryOutcome(c, aNow!.stats[c]!, bNow!.stats[c]!) != categoryOutcome(c, a.stats[c]!, b.stats[c]!);
            return row([
              Text(c.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              value(a, aNow),
              value(b, bNow),
              Row(children: [
                const SizedBox(width: 16),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
                if (flips) ...[
                  const SizedBox(width: 4),
                  Tooltip(message: 'Flips from now', child: Icon(Icons.swap_vert, size: 16, color: context.stat.warn)),
                ],
              ]),
            ]);
          }(),
      ],
    );
  }
}

/// My league rank per category (by all-play wins), my total, and how many teams I beat.
class MyRanks extends StatelessWidget {
  final List<AllPlayRow> rows;
  final String myName;

  const MyRanks({super.key, required this.rows, required this.myName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = rows.where((r) => r.name == myName).firstOrNull;
    if (me == null) return const SizedBox.shrink();
    final n = rows.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (final c in allStatCategories)
            () {
              final rank = allPlayRank(rows, myName, c);
              final s = me.cats[c]!;
              final color = rank <= 3
                  ? context.stat.win
                  : rank > n - 3
                      ? context.stat.loss
                      : theme.colorScheme.onSurface;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 44, child: Text(c.label, style: theme.textTheme.titleSmall)),
                    SizedBox(
                      width: 72,
                      child: Text('${ordinal(rank)} of $n', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: s.w + s.l + s.t == 0 ? 0 : s.w / (s.w + s.l + s.t),
                          minHeight: 8,
                          color: color,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(formatStat(c, me.avg[c]!), textAlign: TextAlign.end, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              );
            }(),
          const SizedBox(height: 4),
          Text('Rank among all 12 teams · bar = share of teams beaten · right = my total',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Every team's league rank in each category (by all-play wins) with its total underneath;
/// sortable by any column, top 3 green and bottom 3 red.
class AllPlayTable extends StatefulWidget {
  final List<AllPlayRow> rows;
  final String? myName;

  const AllPlayTable({super.key, required this.rows, required this.myName});

  @override
  State<AllPlayTable> createState() => _AllPlayTableState();
}

class _AllPlayTableState extends State<AllPlayTable> {
  /// null = total; otherwise one category.
  StatCategory? _sortBy;

  int _value(AllPlayRow r) => _sortBy == null ? r.total.w : r.cats[_sortBy]!.w;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...widget.rows]..sort((a, b) {
        final byValue = _value(b).compareTo(_value(a));
        return byValue != 0 ? byValue : b.total.w.compareTo(a.total.w);
      });
    final n = rows.length;
    // Rank = 1 + teams with more all-play wins (ties share a rank).
    int rank(int Function(AllPlayRow r) wins, AllPlayRow r) => rows.where((o) => wins(o) > wins(r)).length + 1;
    Widget cell(int rank, String sub) {
      final color = rank <= 3
          ? context.stat.win
          : rank > n - 3
              ? context.stat.loss
              : null;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(ordinal(rank),
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.w600,
              )),
          Text(sub, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    }

    Color? rowColor(AllPlayRow r) => r.name == widget.myName ? theme.colorScheme.primaryContainer : null;
    // Team names stay put; the 10 numeric columns scroll sideways next to them. Both tables use
    // the same fixed row heights so the rows line up.
    DataTable table({required List<DataColumn> columns, required List<DataCell> Function(AllPlayRow r) cells, double spacing = 16}) =>
        DataTable(
          columnSpacing: spacing,
          horizontalMargin: 12,
          headingRowHeight: 44,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 56,
          sortColumnIndex: columns.length == 1 ? null : (_sortBy == null ? 0 : 1 + allStatCategories.indexOf(_sortBy!)),
          sortAscending: false,
          columns: columns,
          rows: [for (final r in rows) DataRow(color: WidgetStatePropertyAll(rowColor(r)), cells: cells(r))],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant))),
          child: table(
            columns: const [DataColumn(label: Text('TEAM'))],
            cells: (r) => [
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  r.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                ),
              )),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table(
              spacing: 14,
              columns: [
                DataColumn(label: const Text('OVERALL'), numeric: true, onSort: (_, _) => setState(() => _sortBy = null)),
                for (final c in allStatCategories)
                  DataColumn(label: Text(c.label), numeric: true, onSort: (_, _) => setState(() => _sortBy = c)),
              ],
              cells: (r) => [
                DataCell(cell(rank((x) => x.total.w, r), '${r.total.w} wins')),
                for (final c in allStatCategories) DataCell(cell(rank((x) => x.cats[c]!.w, r), formatStat(c, r.avg[c]!))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


/// Every team's record and category wins for the period; sortable by any column.
class LeagueTable extends StatefulWidget {
  final List<TeamPeriod> rows;
  final String? myName;

  const LeagueTable({super.key, required this.rows, required this.myName});

  @override
  State<LeagueTable> createState() => _LeagueTableState();
}

class _LeagueTableState extends State<LeagueTable> {
  /// null = category wins total; otherwise one category.
  StatCategory? _sortBy;

  int _value(TeamPeriod r) => _sortBy == null ? r.cats.w : r.catWins[_sortBy]!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...widget.rows]..sort((a, b) {
        final byValue = _value(b).compareTo(_value(a));
        return byValue != 0 ? byValue : b.cats.w.compareTo(a.cats.w);
      });
    final best = {
      for (final c in allStatCategories) c: rows.fold(0, (m, r) => r.catWins[c]! > m ? r.catWins[c]! : m),
    };
    final bestTotal = rows.fold(0, (m, r) => r.cats.w > m ? r.cats.w : m);
    TextStyle? cell(bool top) => theme.textTheme.bodyMedium?.copyWith(
          fontWeight: top ? FontWeight.w800 : null,
          color: top ? context.stat.win : null,
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 16,
        headingRowHeight: 44,
        sortColumnIndex: _sortBy == null ? 2 : 3 + allStatCategories.indexOf(_sortBy!),
        sortAscending: false,
        columns: [
          const DataColumn(label: Text('TEAM')),
          const DataColumn(label: Text('W-L-T')),
          DataColumn(label: const Text('CATS'), numeric: true, onSort: (_, _) => setState(() => _sortBy = null)),
          for (final c in allStatCategories)
            DataColumn(label: Text(c.label), numeric: true, onSort: (_, _) => setState(() => _sortBy = c)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              color: WidgetStatePropertyAll(r.name == widget.myName ? theme.colorScheme.primaryContainer : null),
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    r.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                )),
                DataCell(Text('${r.record.w}-${r.record.l}-${r.record.t}')),
                DataCell(Text('${r.cats.w}', style: cell(r.cats.w == bestTotal && bestTotal > 0))),
                for (final c in allStatCategories)
                  // Leaders only mean something over several weeks; in one week every winner has 1.
                  DataCell(Text('${r.catWins[c]}', style: cell(r.catWins[c] == best[c] && best[c]! > 1))),
              ],
            ),
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

/// A team name short enough for a table column header.
String _short(String name) {
  final t = name.trim().toUpperCase();
  return t.length <= 8 ? t : '${t.substring(0, 7)}…';
}

String _md(DateTime d) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.day}';

typedef PlayerGames = ({Player player, bool mine, WeekGames games, int benched, bool dropped, String? status});

/// Both rosters' players with their NBA games this week; sortable by games, games left or name,
/// and filterable to one side. Team totals on top.
class PlayerGamesTable extends StatefulWidget {
  final List<PlayerGames> rows;
  final String meLabel;
  final String oppLabel;
  final bool showLeft;
  final String caption;

  const PlayerGamesTable({
    super.key,
    required this.rows,
    required this.meLabel,
    required this.oppLabel,
    required this.showLeft,
    required this.caption,
  });

  @override
  State<PlayerGamesTable> createState() => _PlayerGamesTableState();
}

enum _GamesSort { total, played, left, name }

class _PlayerGamesTableState extends State<PlayerGamesTable> {
  _GamesSort _sort = _GamesSort.total;
  bool _desc = true;
  bool? _side; // null = both, true = mine, false = opponent

  void _tap(_GamesSort s) => setState(() {
        if (_sort == s) {
          _desc = !_desc;
        } else {
          _sort = s;
          _desc = s != _GamesSort.name;
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sort = (_sort == _GamesSort.left || _sort == _GamesSort.total) && !widget.showLeft ? _GamesSort.played : _sort;
    int key(PlayerGames r) => switch (sort) {
          _GamesSort.left => r.games.left,
          _GamesSort.played => r.games.played,
          _ => r.games.played + r.games.left,
        };
    final rows = widget.rows.where((r) => _side == null || r.mine == _side).toList()
      ..sort((a, b) {
        final byName = a.player.name.compareTo(b.player.name);
        if (sort == _GamesSort.name) return _desc ? -byName : byName;
        final c = _desc ? key(b).compareTo(key(a)) : key(a).compareTo(key(b));
        return c != 0 ? c : byName;
      });

    // Played games are real; games left count healthy players only (an "Out" player won't play them).
    ({int played, int left}) total(bool mine) {
      final r = widget.rows.where((r) => r.mine == mine);
      return (
        played: r.fold(0, (s, r) => s + r.games.played),
        left: r.where((r) => r.status != 'Out' && !r.dropped).fold(0, (s, r) => s + r.games.left),
      );
    }

    Widget totalTile(bool mine) {
      final t = total(mine);
      final color = mine ? colors.primary : colors.tertiary;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(mine ? widget.meLabel : widget.oppLabel,
                    overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('${t.played + t.left} games', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(widget.showLeft ? '${t.played} played · ${t.left} left' : 'played',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      );
    }

    Widget head(String label, _GamesSort s, {TextAlign align = TextAlign.end}) {
      final active = sort == s;
      return InkWell(
        onTap: () => _tap(s),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: align == TextAlign.end ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: active ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w800 : null,
                  )),
              Icon(active ? (_desc ? Icons.arrow_downward : Icons.arrow_upward) : Icons.unfold_more,
                  size: 14, color: active ? colors.primary : colors.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    const numW = 50.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [totalTile(true), const SizedBox(width: 12), totalTile(false)]),
          const SizedBox(height: 12),
          SegmentedButton<bool?>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: null, label: Text('Both')),
              ButtonSegment(value: true, label: Text(widget.meLabel, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: false, label: Text(widget.oppLabel, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_side},
            onSelectionChanged: (v) => setState(() => _side = v.first),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: head('PLAYER', _GamesSort.name, align: TextAlign.start)),
            SizedBox(width: numW + 8, child: head('PLAYED', _GamesSort.played)),
            if (widget.showLeft) ...[
              SizedBox(width: numW, child: head('LEFT', _GamesSort.left)),
              SizedBox(width: numW, child: head('TOTAL', _GamesSort.total)),
            ],
          ]),
          for (final r in rows)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: r.mine ? colors.primary : colors.tertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.player.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: r.status == 'Out' ? colors.onSurfaceVariant : null,
                            )),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: r.player.team),
                            if (r.dropped)
                              TextSpan(text: ' · dropped', style: TextStyle(color: colors.onSurfaceVariant, fontStyle: FontStyle.italic)),
                            if (r.status != null && !r.dropped)
                              TextSpan(
                                text: ' · ${r.status == 'Out' ? 'OUT' : r.status}',
                                style: TextStyle(color: r.status == 'Out' ? context.stat.loss : context.stat.warn),
                              ),
                            if (r.games.missed > 0)
                              TextSpan(
                                text: ' · missed ${r.games.missed}',
                                style: TextStyle(color: context.stat.warn, fontWeight: FontWeight.w700),
                              ),
                            if (r.benched > 0) TextSpan(text: ' · ${r.benched} on bench'),
                          ]),
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: numW + 8,
                    child: Text('${r.games.played}',
                        textAlign: TextAlign.end,
                        style: widget.showLeft
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (widget.showLeft) ...[
                    SizedBox(
                      width: numW,
                      child: Text('${r.games.left}', textAlign: TextAlign.end, style: theme.textTheme.bodyMedium),
                    ),
                    SizedBox(
                      width: numW,
                      child: Text('${r.games.played + r.games.left}',
                          textAlign: TextAlign.end, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${widget.caption}${widget.showLeft ? ' · games left leave out players ruled Out' : ''}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
