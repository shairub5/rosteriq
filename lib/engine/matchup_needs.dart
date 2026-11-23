import 'dart:math';

import '../models/player.dart';
import '../models/stat_category.dart';
import '../services/player_repository.dart';
import '../services/schedule_service.dart';
import '../worker/espn.dart' show InjuryEntry, NightLine;

/// Monday–Sunday dates of fantasy week [week]: week 1 is the week of the season opener
/// (the earliest game in the schedule). Assumes one-week matchups throughout.
({DateTime start, DateTime end}) fantasyWeekDates(int week, NbaSchedule schedule) {
  final opener = schedule.teams.values.map((t) => t.games.first).reduce((a, b) => a.isBefore(b) ? a : b);
  final monday = DateTime(opener.year, opener.month, opener.day - (opener.weekday - 1) + 7 * (week - 1));
  return (start: monday, end: DateTime(monday.year, monday.month, monday.day + 6));
}

/// Today's date in the US (games are dated by US day; Israel is ahead).
DateTime usToday([DateTime? now]) {
  final us = (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 5));
  return DateTime(us.year, us.month, us.day);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A player's games in a week: [played] = real games before today (box scores), [missed] = scheduled
/// games before today he didn't play (injury, rest), [left] = scheduled games from today on.
/// A night without box scores counts its scheduled game as played.
typedef WeekGames = ({int played, int missed, int left});

WeekGames weekGames(
  Player p,
  ({DateTime start, DateTime end}) range,
  NbaSchedule schedule,
  Map<DateTime, Set<String>> played, {
  DateTime? today,
}) {
  final t = today ?? usToday();
  var (pl, mi, le) = (0, 0, 0);
  for (final g in schedule.teams[p.team]?.games ?? const <DateTime>[]) {
    final d = _day(g);
    if (d.isBefore(range.start) || d.isAfter(range.end)) continue;
    if (!d.isBefore(t)) {
      le++;
    } else if (played[d] case final ids? when !ids.contains(p.id)) {
      mi++;
    } else {
      pl++;
    }
  }
  return (played: pl, missed: mi, left: le);
}

/// A team's week per player, including players it dropped during the week: [games] counts only
/// games in active slots, [benched] games he played on the bench (they don't score), [onRoster]
/// whether he's still on the team. Days with a saved daily lineup use it; other past days fall back
/// to the current roster and box scores; games from today on come from the schedule.
typedef TeamPlayerWeek = ({Player player, WeekGames games, int benched, bool onRoster});

List<TeamPlayerWeek> teamWeekGames({
  required List<Player> roster,
  required Map<String, Player> playersById,
  required Map<DateTime, List<LineupSlot>>? lineups,
  required ({DateTime start, DateTime end}) range,
  required NbaSchedule schedule,
  required Map<DateTime, Set<String>> played,
  DateTime? today,
}) {
  final t = today ?? usToday();
  final acc = <String, List<int>>{for (final p in roster) p.id: [0, 0, 0, 0]}; // played, missed, benched, left
  bool hasGame(Player p, DateTime d) => schedule.teams[p.team]?.hasGameOn(d) ?? false;
  for (var d = range.start; !d.isAfter(range.end); d = DateTime(d.year, d.month, d.day + 1)) {
    if (!d.isBefore(t)) {
      for (final p in roster) {
        if (hasGame(p, d)) acc[p.id]![3]++;
      }
      continue;
    }
    final day = lineups?[d];
    if (day != null) {
      for (final r in day) {
        final p = playersById[r.id];
        if (p == null || !hasGame(p, d)) continue;
        final a = acc.putIfAbsent(r.id, () => [0, 0, 0, 0]);
        final bench = isBenchSlot(r.slot);
        // Yahoo counts a game with 0 minutes as played. Its page for the latest day can show no
        // minutes at all, so the box score fills in.
        final box = played[d]?.contains(r.id) ?? false;
        if (bench) {
          if ((r.min ?? 0) > 0 || box) a[2]++;
        } else if (r.min != null || box) {
          a[0]++;
        } else {
          a[1]++;
        }
      }
      continue;
    }
    for (final p in roster) {
      if (!hasGame(p, d)) continue;
      final ids = played[d];
      acc[p.id]![ids == null || ids.contains(p.id) ? 0 : 1]++;
    }
  }
  final onRoster = {for (final p in roster) p.id};
  return [
    for (final e in acc.entries)
      if (playersById[e.key] case final p?)
        (
          player: p,
          games: (played: e.value[0], missed: e.value[1], left: e.value[3]),
          benched: e.value[2],
          onRoster: onRoster.contains(e.key),
        ),
  ];
}

/// Chance a player is available on [d]: Out until the listed return date, Day-To-Day at 75%.
double availability(InjuryEntry? i, DateTime d) {
  if (i == null) return 1;
  if (i.status == 'Out') {
    final back = DateTime.tryParse(i.returnDate ?? '');
    return back != null && !_day(back).isAfter(d) ? 1 : 0;
  }
  return 0.75;
}

const _counting = [
  StatCategory.threePM,
  StatCategory.pts,
  StatCategory.reb,
  StatCategory.ast,
  StatCategory.stl,
  StatCategory.blk,
  StatCategory.to,
];

double _total(Player p, StatCategory c) => switch (c) {
      StatCategory.threePM => p.threePM.toDouble(),
      StatCategory.pts => p.pts.toDouble(),
      StatCategory.reb => p.reb.toDouble(),
      StatCategory.ast => p.ast.toDouble(),
      StatCategory.stl => p.stl.toDouble(),
      StatCategory.blk => p.blk.toDouble(),
      StatCategory.to => p.to.toDouble(),
      _ => 0,
    };

/// Week totals if every remaining day ([from]..[to]) each side starts its 10 best available players
/// ([valueOf] decides "best") at their season per-game averages, added to [now] (the real totals so far).
/// FG%/FT% need the makes/attempts so far: from Yahoo's matchup page, or (Fantrax, which doesn't show
/// them) estimated from the same simulation over the days already played.
Map<StatCategory, double> projectSide({
  required TeamWeek now,
  required List<Player> roster,
  required NbaSchedule schedule,
  required Map<String, InjuryEntry> injuries,
  required ({DateTime start, DateTime end}) range,
  required double Function(Player) valueOf,
  DateTime? today,
  int activeSlots = 10,
}) {
  final t = today ?? usToday();
  final ps = roster.where((p) => p.gp > 0).toList()..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
  ({Map<StatCategory, double> sums, double fgm, double fga, double ftm, double fta}) sim(DateTime from, DateTime to) {
    final sums = {for (final c in _counting) c: 0.0};
    var (fgm, fga, ftm, fta) = (0.0, 0.0, 0.0, 0.0);
    for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      var started = 0;
      for (final p in ps) {
        if (started >= activeSlots) break;
        if (!(schedule.teams[p.team]?.hasGameOn(d) ?? false)) continue;
        final w = availability(injuries[p.id], d);
        if (w == 0) continue;
        started++;
        final g = p.gp.toDouble();
        for (final c in _counting) {
          sums[c] = sums[c]! + w * _total(p, c) / g;
        }
        fga += w * p.fgAttempted / g;
        fgm += w * p.fgAttempted * p.fgPct / g;
        fta += w * p.ftAttempted / g;
        ftm += w * p.ftAttempted * p.ftPct / g;
      }
    }
    return (sums: sums, fgm: fgm, fga: fga, ftm: ftm, fta: fta);
  }

  final from = t.isBefore(range.start) ? range.start : t;
  final rest = sim(from, range.end);
  var fgm = now.extra['fgm'], fga = now.extra['fga'], ftm = now.extra['ftm'], fta = now.extra['fta'];
  if (fga == null || fta == null || fgm == null || ftm == null) {
    final past = from.isAfter(range.start) ? sim(range.start, DateTime(from.year, from.month, from.day - 1)) : null;
    fga = past?.fga ?? 0;
    fta = past?.fta ?? 0;
    fgm = now.stats[StatCategory.fgPct]! * fga;
    ftm = now.stats[StatCategory.ftPct]! * fta;
  }
  double pct(double m, double a, double fallback) => a <= 0 ? fallback : m / a;
  return {
    StatCategory.fgPct: pct(fgm + rest.fgm, fga + rest.fga, now.stats[StatCategory.fgPct]!),
    StatCategory.ftPct: pct(ftm + rest.ftm, fta + rest.fta, now.stats[StatCategory.ftPct]!),
    for (final c in _counting) c: now.stats[c]! + rest.sums[c]!,
  };
}

/// Where a category stands in the matchup's projected final, from my side.
enum Need {
  tossUp('Toss-up'),
  chase('Chase'),
  hold('Hold'),
  safe('Safe'),
  lost('Out of reach');

  final String label;
  const Need(this.label);
}

/// How much a pickup should care about each [Need].
const needWeight = {Need.tossUp: 1.0, Need.chase: 1.0, Need.hold: 0.6, Need.safe: 0.15, Need.lost: 0.15};

/// "Close" margin: .010 for percentages, 5% (and 3 at least) for counting stats.
double closeMargin(StatCategory c, double x, double y) =>
    c == StatCategory.fgPct || c == StatCategory.ftPct ? 0.010 : max(3, 0.05 * max(x.abs(), y.abs()));

/// Each category's [Need] given both sides' projected finals (fewer turnovers wins).
Map<StatCategory, Need> categoryNeeds(Map<StatCategory, double> me, Map<StatCategory, double> opp) => {
      for (final c in allStatCategories)
        c: () {
          final m = closeMargin(c, me[c]!, opp[c]!);
          final lead = (me[c]! - opp[c]!) * (c.lowerIsBetter ? -1 : 1);
          if (lead.abs() <= m) return Need.tossUp;
          if (lead.abs() <= 3 * m) return lead > 0 ? Need.hold : Need.chase;
          return lead > 0 ? Need.safe : Need.lost;
        }(),
    };

/// Per-game category baselines over regular players (5+ games, 15+ minutes), for z-scoring one game
/// or a season average on the same scale. Percentages use made-above-average per game
/// ((pct - league pct) * attempts), so volume counts.
class PerGameBaseline {
  final Map<StatCategory, ({double mean, double sd})> stats;
  final double fgPct;
  final double ftPct;

  const PerGameBaseline._(this.stats, this.fgPct, this.ftPct);

  factory PerGameBaseline.of(List<Player> pool, Map<String, double> minutes) {
    final regs = pool.where((p) => p.gp >= 5 && (minutes[p.id] ?? 0) >= 15).toList();
    final use = regs.length >= 30 ? regs : pool.where((p) => p.gp > 0).toList();
    double lg(num Function(Player) made, num Function(Player) att) {
      final a = use.fold<double>(0, (s, p) => s + att(p));
      return a == 0 ? 0 : use.fold<double>(0, (s, p) => s + made(p)) / a;
    }

    final fg = lg((p) => p.fgPct * p.fgAttempted, (p) => p.fgAttempted);
    final ft = lg((p) => p.ftPct * p.ftAttempted, (p) => p.ftAttempted);
    ({double mean, double sd}) ms(Iterable<double> v) {
      final l = v.toList();
      if (l.isEmpty) return (mean: 0, sd: 1);
      final mean = l.reduce((a, b) => a + b) / l.length;
      final sd = sqrt(l.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / l.length);
      return (mean: mean, sd: sd == 0 ? 1 : sd);
    }

    final b = PerGameBaseline._(const {}, fg, ft);
    return PerGameBaseline._(
      {for (final c in allStatCategories) c: ms(use.map((p) => b._raw(c, seasonLine(p))))},
      fg,
      ft,
    );
  }

  double _raw(StatCategory c, PerGame g) => switch (c) {
        StatCategory.fgPct => g.fga == 0 ? 0 : (g.fgm / g.fga - fgPct) * g.fga,
        StatCategory.ftPct => g.fta == 0 ? 0 : (g.ftm / g.fta - ftPct) * g.fta,
        _ => g.cats[c]!,
      };

  /// z per category (turnovers flipped, so higher is always better).
  Map<StatCategory, double> z(PerGame g) => {
        for (final c in allStatCategories)
          c: (_raw(c, g) - stats[c]!.mean) / stats[c]!.sd * (c.lowerIsBetter ? -1 : 1),
      };
}

/// One game's (or an average game's) numbers.
typedef PerGame = ({Map<StatCategory, double> cats, double fgm, double fga, double ftm, double fta});

PerGame seasonLine(Player p) {
  final g = p.gp == 0 ? 1.0 : p.gp.toDouble();
  return (
    cats: {for (final c in _counting) c: _total(p, c) / g},
    fgm: p.fgAttempted * p.fgPct / g,
    fga: p.fgAttempted / g,
    ftm: p.ftAttempted * p.ftPct / g,
    fta: p.ftAttempted / g,
  );
}

PerGame nightGame(NightLine l) => (
      cats: {
        StatCategory.threePM: l.threePM.toDouble(),
        StatCategory.pts: l.pts.toDouble(),
        StatCategory.reb: l.reb.toDouble(),
        StatCategory.ast: l.ast.toDouble(),
        StatCategory.stl: l.stl.toDouble(),
        StatCategory.blk: l.blk.toDouble(),
        StatCategory.to: l.to.toDouble(),
      },
      fgm: l.fgm.toDouble(),
      fga: l.fga.toDouble(),
      ftm: l.ftm.toDouble(),
      fta: l.fta.toDouble(),
    );

/// How well a player fits what the matchup needs: z per category weighted by [weights], averaged.
/// Turnovers only count against a player: few turnovers mostly means few minutes, and adding a
/// player never lowers my team's turnovers.
double needScore(Map<StatCategory, double> z, Map<StatCategory, double> weights) {
  final total = weights.values.fold<double>(0, (a, b) => a + b);
  if (total == 0) return 0;
  double v(StatCategory c) => c == StatCategory.to ? min(0, z[c] ?? 0) : z[c] ?? 0;
  return allStatCategories.fold<double>(0, (s, c) => s + v(c) * (weights[c] ?? 0)) / total;
}

/// A player's game last night against his usual: [night] and [usual] are summed 9-category z,
/// [boost] names teammates (20+ minutes a night) who sat out hurt, the likely reason for extra usage.
typedef HotNight = ({
  Player player,
  NightLine line,
  double night,
  double usual,
  double delta,
  double usualMinutes,
  List<String> boost,
});

double _sum(Map<StatCategory, double> z) => z.values.fold(0, (a, b) => a + b);

/// Players in [candidates] whose game last night beat their usual by [minDelta] or more, best first.
List<HotNight> hotNights({
  required NightBox night,
  required Iterable<Player> candidates,
  required PerGameBaseline baseline,
  required Map<String, Player> playersById,
  required Map<String, double> minutes,
  double minDelta = 3,
}) {
  final out = <HotNight>[];
  for (final p in candidates) {
    final line = night.lines[p.id];
    if (line == null || line.min <= 0) continue;
    final n = _sum(baseline.z(nightGame(line)));
    final u = p.gp > 0 ? _sum(baseline.z(seasonLine(p))) : n - minDelta * 2;
    if (n - u < minDelta) continue;
    final boost = [
      for (final id in night.outByTeam[line.team] ?? const <String>{})
        if (id != p.id && (minutes[id] ?? 0) >= 20) ?playersById[id],
    ]..sort((a, b) => (minutes[b.id] ?? 0).compareTo(minutes[a.id] ?? 0));
    out.add((
      player: p,
      line: line,
      night: n,
      usual: u,
      delta: n - u,
      usualMinutes: minutes[p.id] ?? 0,
      boost: [for (final t in boost) t.name],
    ));
  }
  return out..sort((a, b) => b.delta.compareTo(a.delta));
}

/// A player of mine worth dropping, with why.
typedef DropCandidate = ({Player player, double fit, List<String> reasons});

/// My weakest players for this matchup, weakest first: need-weighted fit plus a little for games
/// left this week. Players ruled Out for more than a week are left alone when they're among my
/// better half (an injured star is an IL stash, not a drop).
List<DropCandidate> dropCandidates({
  required List<Player> roster,
  required PerGameBaseline baseline,
  required Map<StatCategory, double> weights,
  required Map<StatCategory, Need> needs,
  required Map<String, InjuryEntry> injuries,
  required Map<String, int> gamesLeft,
  DateTime? today,
  int take = 4,
}) {
  final t = today ?? usToday();
  final season = {for (final p in roster) p.id: _sum(baseline.z(seasonLine(p)))};
  final ranked = [...season.values]..sort();
  final median = ranked.isEmpty ? 0.0 : ranked[ranked.length ~/ 2];
  final out = <DropCandidate>[];
  for (final p in roster) {
    final inj = injuries[p.id];
    final back = DateTime.tryParse(inj?.returnDate ?? '');
    final longOut = inj?.status == 'Out' && (back == null || back.difference(t).inDays > 7);
    if (longOut && season[p.id]! >= median) continue;
    final z = baseline.z(seasonLine(p));
    final left = gamesLeft[p.id] ?? 0;
    final fit = needScore(z, weights) + 0.1 * (left - 3);
    final reasons = <String>[
      if (p.gp == 0) 'No games yet',
      if (p.fgAttempted / max(1, p.gp) >= 8 && p.fgPct < 0.43) '${(p.fgPct * 100).toStringAsFixed(1)}% FG',
      if (p.to / max(1, p.gp) >= 3) '${(p.to / max(1, p.gp)).toStringAsFixed(1)} TO a game',
      if (left <= 1) left == 0 ? 'No games left this week' : '1 game left this week',
      if (inj != null) inj.status == 'Out' ? 'Out${back == null ? '' : ' until ${back.month}/${back.day}'}' : 'Day-to-day',
    ];
    final weak = [
      for (final c in allStatCategories)
        if (c != StatCategory.to && (needs[c] == Need.chase || needs[c] == Need.tossUp) && z[c]! < 0) c.label,
    ];
    if (weak.isNotEmpty) reasons.add('Little ${weak.take(3).join('/')}');
    out.add((player: p, fit: fit, reasons: reasons));
  }
  out.sort((a, b) => a.fit.compareTo(b.fit));
  return out.take(take).toList();
}
