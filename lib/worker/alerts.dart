import '../models/player.dart';
import 'espn.dart';

/// Where players are in one fantasy league: [ownerOf] gives the team that has a player
/// ("you" for my team) or null for a free agent. [hasRosters] false = rosters not entered.
typedef LeagueView = ({String name, String? Function(String playerName) ownerOf, bool hasRosters});

/// Diffs two injury reports and returns one Telegram-ready message per change, for every
/// player. An unchanged status produces nothing, so a 30-minute cron never repeats itself.
/// Each message names the teammates who absorb the minutes (any injury, not only OUT) and,
/// per fantasy league, who owns the injured player and whether each fill-in is available.
///
/// [totalZById] ranks fill-in candidates; [pool] / [minutes] are this season's ESPN stats;
/// [gamesNote] says when the player's NBA team plays next (e.g. "3 games left this week").
List<String> injuryAlerts({
  required Map<String, InjuryEntry> prev,
  required Map<String, InjuryEntry> now,
  required List<Player> pool,
  required Map<String, double> totalZById,
  required Map<String, double> minutes,
  List<LeagueView> leagues = const [],
  String? Function(String team)? gamesNote,
}) {
  String last(String name) => name.split(' ').where((w) => !const {'Jr.', 'Sr.', 'II', 'III', 'IV'}.contains(w)).last;
  String owner(LeagueView l, String name) => l.ownerOf(name) ?? 'free agent';

  final alerts = <String>[];
  for (final inj in now.values) {
    if (prev[inj.playerId]?.status == inj.status) continue;
    final out = inj.status == 'Out';
    final back = inj.returnDate == null ? '' : ', est. return ${inj.returnDate}';
    final buf = StringBuffer(
        '${out ? '🚑 OUT' : '⚠️ ${inj.status.toUpperCase()}'}: ${inj.name} (${inj.team}, ${inj.position})'
        '${inj.detail.isEmpty ? '' : ' - ${inj.detail}'}$back');
    if (gamesNote?.call(inj.team) case final note?) buf.write('\n📅 ${inj.team}: $note');
    final fillIns = fillInCandidates(inj, now: now, pool: pool, totalZById: totalZById, minutes: minutes);
    if (fillIns.isNotEmpty) {
      buf.write('\nWho absorbs the minutes (${inj.team} ${inj.position}):');
      for (final p in fillIns) {
        buf.write('\n• ${p.name} - ${_line(p, minutes[p.id] ?? 0)}');
      }
    }
    for (final l in leagues) {
      buf.write('\n\n🏀 ${l.name} - ${last(inj.name)}: ${owner(l, inj.name)}');
      if (!l.hasRosters) {
        buf.write('\n   (rosters not entered yet)');
      } else if (fillIns.isNotEmpty) {
        buf.write('\n   ${fillIns.map((p) {
          final o = l.ownerOf(p.name);
          return o == null ? '✅ ${last(p.name)} FA' : '❌ ${last(p.name)} ($o)';
        }).join(' · ')}');
      }
    }
    alerts.add(buf.toString());
  }
  for (final old in prev.values) {
    if (now.containsKey(old.playerId)) continue;
    alerts.add([
      '✅ BACK: ${old.name} (${old.team}) is off the injury report',
      for (final l in leagues)
        if (l.hasRosters) '🏀 ${l.name}: ${owner(l, old.name)}',
    ].join('\n'));
  }
  return alerts;
}

/// Healthy teammates who share a position with [inj] and already play real
/// minutes, best fantasy value first. Same NBA team = they inherit the minutes.
List<Player> fillInCandidates(
  InjuryEntry inj, {
  required Map<String, InjuryEntry> now,
  required List<Player> pool,
  required Map<String, double> totalZById,
  required Map<String, double> minutes,
  int limit = 3,
  double minMinutes = 10,
}) {
  final positions = espnPositions(inj.position).toSet();
  final candidates = pool
      .where((p) =>
          p.team == inj.team &&
          p.id != inj.playerId &&
          now[p.id]?.status != 'Out' &&
          (minutes[p.id] ?? 0) >= minMinutes &&
          p.eligiblePositions.any(positions.contains))
      .toList()
    ..sort((a, b) => (totalZById[b.id] ?? 0).compareTo(totalZById[a.id] ?? 0));
  return candidates.take(limit).toList();
}

String _line(Player p, double min) {
  if (p.gp == 0) return 'no games yet';
  String pg(int v) => (v / p.gp).toStringAsFixed(1);
  return '${min.toStringAsFixed(1)} min · ${pg(p.pts)}p ${pg(p.reb)}r ${pg(p.ast)}a';
}

/// GitHub pauses cron workflows after 60 days without repo activity. From day
/// [warnAfterDays] on, nag at most once a day until someone pushes to main.
String? keepAliveReminder({required DateTime now, DateTime? lastCommit, DateTime? lastReminder, int warnAfterDays = 50}) {
  if (lastCommit == null) return null;
  final idle = now.difference(lastCommit).inDays;
  if (idle < warnAfterDays) return null;
  if (lastReminder != null && now.difference(lastReminder).inHours < 24) return null;
  return '⏰ No commits to rosteriq for $idle days. GitHub pauses these alerts at 60 - '
      'push any commit to main (e.g. a README tweak) to keep them running.';
}
