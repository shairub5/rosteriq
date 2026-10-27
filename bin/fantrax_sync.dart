// Fantrax sync (GitHub Actions, twice a day): rosters from the public API, then a logged-in live-scoring
// call with the cookie sent to the bot. A cookie that stopped working is flagged and alerted once.
//
//   dart run bin/fantrax_sync.dart [snapshot.json] [--dump <dir>]
//
// Env: COOKIE_KEY (decrypts the stored cookie), TELEGRAM_TOKEN, TELEGRAM_CHAT_ID.
// --dump writes the raw live-scoring response there (for building/refreshing test fixtures).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/worker/cookies.dart';
import 'package:rosteriq/worker/fantrax.dart';
import 'package:rosteriq/worker/league_bot.dart';
import 'package:rosteriq/worker/telegram.dart';

Future<void> main(List<String> args) async {
  final di = args.indexOf('--dump');
  final dumpDir = di >= 0 ? args[di + 1] : null;
  final rest = [...args]..removeRange(di >= 0 ? di : 0, di >= 0 ? di + 2 : 0);
  final file = File(rest.isEmpty ? 'state/snapshot.json' : rest.first);
  final snap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final env = Platform.environment;
  final now = DateTime.now().toUtc();

  // Same name -> id pool as bin/set_team.dart: snapshot players, injured players, bundled players.
  final players = [
    for (final p in (snap['players'] as List).cast<Map<String, dynamic>>()) (name: p['name'] as String, id: p['id'] as String),
    for (final i in (snap['injuries'] as List).cast<Map<String, dynamic>>()) (name: i['name'] as String, id: i['playerId'] as String),
    for (final p in (jsonDecode(File('assets/data/players.json').readAsStringSync()) as List)
        .map((j) => Player.fromJson(j as Map<String, dynamic>)))
      (name: p.name, id: p.id),
  ];

  final alerts = <String>[];
  final leagues = [snap['league'] as Map<String, dynamic>, ...((snap['leagues'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  for (final (i, l) in leagues.indexed) {
    final id = l['fantraxLeagueId'] as String?;
    if (id == null) continue;
    var league = l;
    try {
      league = applyFantraxRosters(league, await fetchFantraxRosters(id), players, now);
      stdout.writeln('${league['name']}: ${(league['teams'] as List).length} rosters');
    } catch (e) {
      stderr.writeln('${league['name']}: roster sync failed: $e');
    }

    final entry = league['fantraxCookie'] as Map<String, dynamic>?;
    final key = env['COOKIE_KEY'];
    if (entry != null && entry['expiredAt'] == null && key != null && key.isNotEmpty) {
      await Future<void>.delayed(Duration(seconds: 5 + Random().nextInt(10)));
      try {
        final cookie = await decryptCookie(entry['sealed'] as String, key);
        final info = await fetchFantraxLeagueInfo(id);
        // A week that just ended gets its final totals; the current week its totals so far.
        for (final (period, isFinal) in [
          if (justEndedScoringPeriod(info, now) case final p?) (p, true),
          if (currentScoringPeriod(info, now) case final p?) (p, false),
        ]) {
          final live = await fetchFantraxLiveScoring(id, cookie, period);
          if (dumpDir != null) File('$dumpDir/fantrax_live_$period.json').writeAsStringSync(jsonEncode(live));
          var matchups = [...((league['matchups'] as List?) ?? const []).cast<Map<String, dynamic>>()];
          final pairs = parseFantraxLiveScoring(live, isFinal: isFinal);
          for (final sides in pairs) {
            matchups = upsertMatchup(matchups, matchupEntry(sides, period, now));
          }
          league = {...league, 'matchups': matchups};
          stdout.writeln('${league['name']}: week $period${isFinal ? ' (final)' : ''}, ${pairs.length} matchups');
        }
      } on FantraxLoggedOut {
        league = {...league, 'fantraxCookie': {...entry, 'expiredAt': now.toIso8601String()}};
        alerts.add('⚠️ ${league['name']}: the Fantrax cookie expired, so matchups stopped syncing '
            '(rosters still sync).\n\n$fantraxCookieHowTo');
      } catch (e) {
        stderr.writeln('${league['name']}: live scoring failed: $e');
      }
    }

    if (i == 0) {
      snap['league'] = league;
    } else {
      (snap['leagues'] as List)[i - 1] = league;
    }
  }

  file.writeAsStringSync(jsonEncode(snap));
  for (final a in alerts) {
    stdout.writeln(a);
  }
  await sendTelegram(alerts, token: env['TELEGRAM_TOKEN'], chatId: env['TELEGRAM_CHAT_ID']);
}
