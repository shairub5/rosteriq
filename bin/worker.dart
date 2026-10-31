// Scheduled worker (GitHub Actions, every 30 min): pulls ESPN stats + injuries,
// diffs against the previous snapshot, sends Telegram alerts, writes the new
// snapshot for the next run and for the app.
//
//   dart run bin/worker.dart [snapshot.json] [--dry-run]
//
// Env: TELEGRAM_TOKEN, TELEGRAM_CHAT_ID (without them, alerts are only printed),
// LAST_COMMIT_AT (ISO date of main's last commit, for the keep-alive reminder).
import 'dart:convert';
import 'dart:io';

import 'package:rosteriq/engine/ranking_engine.dart';
import 'package:rosteriq/models/league_config.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/ranking_result.dart';
import 'package:rosteriq/worker/alerts.dart';
import 'package:rosteriq/worker/espn.dart';
import 'package:rosteriq/worker/league_bot.dart';
import 'package:rosteriq/worker/telegram.dart';
import 'package:rosteriq/worker/yahoo.dart';


Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final snapshotFile = File(args.firstWhere((a) => !a.startsWith('--'), orElse: () => 'state/snapshot.json'));

  final prevJson = snapshotFile.existsSync()
      ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>
      : null;
  final prevInjuries = {
    for (final j in (prevJson?['injuries'] as List? ?? const []))
      (j['playerId'] as String): InjuryEntry.fromJson(j as Map<String, dynamic>),
  };

  final stats = await fetchStats(currentSeason(DateTime.now()));
  final injuries = {for (final i in await fetchInjuries()) i.playerId: i};

  final ranked = _rank(stats.players);
  final totalZById = {for (final r in ranked) r.playerId: r.totalZ};
  final now = DateTime.now().toUtc();
  final prevLeagues = [
    (prevJson?['league'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    ...((prevJson?['leagues'] as List?) ?? const []).cast<Map<String, dynamic>>(),
  ];
  final players = [
    for (final p in stats.players) (name: p.name, id: p.id),
    for (final i in injuries.values) (name: i.name, id: i.playerId),
    // Bundled ids for anyone ESPN lists nowhere (no games, not injured); the app keeps them as-is.
    for (final p in _bundledPlayers()) (name: p.name, id: p.id),
  ];
  final synced = dryRun
      ? prevLeagues
      : await syncLeaguesFromTelegram(
          leagues: prevLeagues,
          players: players,
          token: Platform.environment['TELEGRAM_TOKEN'],
          chatId: Platform.environment['TELEGRAM_CHAT_ID'],
          apiKey: Platform.environment['ANTHROPIC_API_KEY'],
          // An unset repo secret arrives as an empty string.
          cookieKey: switch (Platform.environment['COOKIE_KEY']) { '' => null, final k => k },
          now: now,
        );
  // What the Mac last fetched from Yahoo (primary league), when the workflow found one.
  final yahooFile = File('${snapshotFile.parent.path}/yahoo.json');
  final leagues = [
    yahooFile.existsSync()
        ? applyYahooData(synced.first, jsonDecode(yahooFile.readAsStringSync()) as Map<String, dynamic>, players, now)
        : synced.first,
    ...synced.skip(1),
  ];

  // Who owns whom in each league, by name (roster ids are ESPN or bundled ids).
  final nameById = {
    for (final p in _bundledPlayers()) p.id: p.name,
    for (final i in injuries.values) i.playerId: i.name,
    for (final p in stats.players) p.id: p.name,
  };
  final views = [
    for (final l in leagues)
      () {
        final owners = <String, String>{
          for (final t in (l['teams'] as List? ?? const []))
            for (final id in (t['playerIds'] as List).cast<String>())
              if (nameById[id] case final name?)
                normalizeName(name): isMyTeamName(t['name'] as String) ? 'you' : t['name'] as String,
        };
        return (
          name: l['name'] as String? ?? 'League',
          ownerOf: (String playerName) => owners[normalizeName(playerName)],
          hasRosters: owners.isNotEmpty,
        );
      }(),
  ];

  final alerts = prevJson == null
      ? ['RosterIQ alerts are live - tracking ${injuries.length} injuries across the league.']
      : injuryAlerts(
          prev: prevInjuries,
          now: injuries,
          pool: stats.players,
          totalZById: totalZById,
          minutes: stats.minutes,
          leagues: views,
          gamesNote: _gamesNote(now),
        );

  final reminder = keepAliveReminder(
    now: now,
    lastCommit: DateTime.tryParse(Platform.environment['LAST_COMMIT_AT'] ?? ''),
    lastReminder: DateTime.tryParse(prevJson?['lastReminderAt'] as String? ?? ''),
  );
  if (reminder != null) alerts.add(reminder);

  for (final a in alerts) {
    stdout.writeln('$a\n');
  }
  if (!dryRun) {
    await sendTelegram(alerts, token: Platform.environment['TELEGRAM_TOKEN'], chatId: Platform.environment['TELEGRAM_CHAT_ID']);
  }

  snapshotFile.parent.createSync(recursive: true);
  snapshotFile.writeAsStringSync(jsonEncode({
    'updatedAt': now.toIso8601String(),
    'lastReminderAt': reminder != null ? now.toIso8601String() : prevJson?['lastReminderAt'],
    'injuries': injuries.values.map((i) => i.toJson()).toList(),
    'players': [
      for (final p in stats.players) {...p.toJson(), 'minutes': stats.minutes[p.id], 'totalZ': totalZById[p.id]},
    ],
    'alerts': alerts,
    'league': leagues.first,
    'leagues': leagues.skip(1).toList(),
  }));
  stdout.writeln('${alerts.length} alerts, ${stats.players.length} players, ${injuries.length} injuries -> ${snapshotFile.path}');
}

List<RankingResult> _rank(List<Player> pool) => computeRankings(
      availablePool: pool,
      myRoster: const [],
      puntedCategories: const {},
      slotConfig: LeagueRosterConfig.defaultConfig,
    );

List<Player> _bundledPlayers() => (jsonDecode(File('assets/data/players.json').readAsStringSync()) as List)
    .map((j) => Player.fromJson(j as Map<String, dynamic>))
    .toList();

/// "3 games left this week (next: Wed Oct 28)" for an ESPN team code, from the bundled
/// schedule (dates only). Weeks run Monday-Sunday; "today" is the US date.
String? Function(String team) _gamesNote(DateTime nowUtc) {
  final teams = (jsonDecode(File('assets/data/nba_schedule.json').readAsStringSync())['teams'] as Map<String, dynamic>);
  final us = nowUtc.subtract(const Duration(hours: 5));
  final today = DateTime.utc(us.year, us.month, us.day);
  final sunday = today.add(Duration(days: 7 - today.weekday));
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (team) {
    final games = ((teams[espnTeams[team] ?? team] as Map?)?['games'] as List?)
        ?.map((d) => DateTime.parse(d as String))
        .map((d) => DateTime.utc(d.year, d.month, d.day))
        .where((d) => !d.isBefore(today))
        .toList()
      ?..sort();
    if (games == null || games.isEmpty) return null;
    final left = games.where((d) => !d.isAfter(sunday)).length;
    final next = games.first;
    return '${left == 0 ? 'no' : left} game${left == 1 ? '' : 's'} left this week '
        '(next: ${days[next.weekday - 1]} ${months[next.month - 1]} ${next.day})';
  };
}
