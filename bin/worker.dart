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

import 'package:http/http.dart' as http;
import 'package:rosteriq/engine/ranking_engine.dart';
import 'package:rosteriq/models/league_config.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/ranking_result.dart';
import 'package:rosteriq/worker/alerts.dart';
import 'package:rosteriq/worker/espn.dart';

// shortcut: league-wide relevance (no Yahoo rosters yet), switch to "my + opponent roster" once the Yahoo API is approved.
const _relevantTopN = 150;

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
  final gpById = {for (final p in stats.players) p.id: p.gp};
  final relevantIds = {
    // Early season, a handful of games says little: preseason projections decide relevance too.
    ..._projectedTopIds([
      for (final p in stats.players) (name: p.name, id: p.id),
      // Players out since day one have no stats rows, only injury rows.
      for (final i in injuries.values) (name: i.name, id: i.playerId),
    ]),
    ...ranked.where((r) => (gpById[r.playerId] ?? 0) >= 5).take(_relevantTopN).map((r) => r.playerId),
  };

  final alerts = prevJson == null
      ? ['RosterIQ alerts are live - tracking ${injuries.length} injuries across the league.']
      : injuryAlerts(
          prev: prevInjuries,
          now: injuries,
          relevantIds: relevantIds,
          pool: stats.players,
          totalZById: totalZById,
          minutes: stats.minutes,
        );

  final now = DateTime.now().toUtc();
  final reminder = keepAliveReminder(
    now: now,
    lastCommit: DateTime.tryParse(Platform.environment['LAST_COMMIT_AT'] ?? ''),
    lastReminder: DateTime.tryParse(prevJson?['lastReminderAt'] as String? ?? ''),
  );
  if (reminder != null) alerts.add(reminder);

  for (final a in alerts) {
    stdout.writeln('$a\n');
  }
  if (!dryRun) await _sendTelegram(alerts);

  snapshotFile.parent.createSync(recursive: true);
  snapshotFile.writeAsStringSync(jsonEncode({
    'updatedAt': now.toIso8601String(),
    'lastReminderAt': reminder != null ? now.toIso8601String() : prevJson?['lastReminderAt'],
    'injuries': injuries.values.map((i) => i.toJson()).toList(),
    'players': [
      for (final p in stats.players) {...p.toJson(), 'minutes': stats.minutes[p.id], 'totalZ': totalZById[p.id]},
    ],
    'alerts': alerts,
  }));
  stdout.writeln('${alerts.length} alerts, ${stats.players.length} players, ${injuries.length} injuries -> ${snapshotFile.path}');
}

List<RankingResult> _rank(List<Player> pool) => computeRankings(
      availablePool: pool,
      myRoster: const [],
      puntedCategories: const {},
      slotConfig: LeagueRosterConfig.defaultConfig,
    );

/// ESPN ids of the top [_relevantTopN] players by the bundled preseason projections, matched by name.
Set<String> _projectedTopIds(List<({String name, String id})> espnPlayers) {
  final projected = (jsonDecode(File('assets/data/players.json').readAsStringSync()) as List)
      .map((j) => Player.fromJson(j as Map<String, dynamic>))
      .toList();
  final topNames = _rank(projected).take(_relevantTopN).map((r) => projected.firstWhere((p) => p.id == r.playerId).name);
  final espnByName = {for (final p in espnPlayers) normalizeName(p.name): p.id};
  return {for (final n in topNames) ?espnByName[normalizeName(n)]};
}

/// "Jaren Jackson Jr." and "jaren jackson" match; punctuation and suffixes ignored.
String normalizeName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z ]'), '')
    .split(' ')
    .where((w) => w.isNotEmpty && !const {'jr', 'sr', 'ii', 'iii', 'iv'}.contains(w))
    .join(' ');

Future<void> _sendTelegram(List<String> alerts) async {
  final token = Platform.environment['TELEGRAM_TOKEN'];
  final chatId = Platform.environment['TELEGRAM_CHAT_ID'];
  if (token == null || chatId == null) {
    stderr.writeln('TELEGRAM_TOKEN / TELEGRAM_CHAT_ID not set - alerts printed only');
    return;
  }
  for (final text in alerts) {
    final res = await http.post(
      Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
      body: {'chat_id': chatId, 'text': text},
    );
    if (res.statusCode != 200) stderr.writeln('Telegram ${res.statusCode}: ${res.body}');
  }
}
