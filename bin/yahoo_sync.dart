// Yahoo sync, run on the user's Mac (never on GitHub Actions, whose data center IPs look wrong for a
// home login): the league page, every team's roster and every matchup -> state/yahoo.json, which
// bin/yahoo_daily.sh publishes for the worker. About 19 requests, 20-60 seconds apart.
//
//   dart run bin/yahoo_sync.dart [--dump <dir>]
//
// --dump also saves each page's HTML there (for fixing the parser). The cookie is read from
// state/yahoo_cookie (gitignored). After a logout or a refusal it writes state/yahoo_stopped, alerts on
// Telegram, and refuses to run again until that file is deleted. Any failure publishes nothing.
//
// Env: TELEGRAM_TOKEN, TELEGRAM_CHAT_ID (without them, the alert is only printed).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:rosteriq/worker/telegram.dart';
import 'package:rosteriq/worker/yahoo.dart';

Future<void> main(List<String> args) async {
  final di = args.indexOf('--dump');
  final dumpDir = di >= 0 ? args[di + 1] : null;
  final stopped = File('state/yahoo_stopped');
  if (stopped.existsSync()) {
    stderr.writeln('Not running, stopped earlier: ${stopped.readAsStringSync()}\nDelete state/yahoo_stopped to allow runs again.');
    exit(1);
  }
  final cookieFile = File('state/yahoo_cookie');
  if (!cookieFile.existsSync()) {
    stderr.writeln('No cookie: save it to state/yahoo_cookie first.');
    exit(1);
  }
  final cookie = cookieFile.readAsStringSync().trim();
  if (cookie.contains('\n') || !cookie.contains('=')) {
    stderr.writeln("state/yahoo_cookie doesn't look like a cookie (should be one line of name=value pairs). Copy it again.");
    exit(1);
  }
  if (dumpDir != null) Directory(dumpDir).createSync(recursive: true);

  final client = http.Client();
  var first = true;
  var count = 0;
  Future<String> page(String name, String path) async {
    if (!first) await Future<void>.delayed(Duration(seconds: 20 + Random().nextInt(41)));
    first = false;
    count++;
    final html = await fetchYahooPage(client, path, cookie);
    if (dumpDir != null) File('$dumpDir/$name.html').writeAsStringSync(html);
    return html;
  }

  // Last run's matchups: once the league moves on to a new week, they get one more fetch for final totals.
  final lastFile = File('state/yahoo_last_matchups.json');
  final last = lastFile.existsSync() ? jsonDecode(lastFile.readAsStringSync()) as Map<String, dynamic> : null;

  try {
    final league = parseYahooLeague(await page('league', '/nba/1623'));
    final teams = [
      for (final id in league.teamIds) parseYahooTeam(await page('team$id', '/nba/1623/$id')),
    ];
    final matchups = <Map<String, dynamic>>[];
    Future<void> addWeek(int week, Iterable<String> paths, {bool isFinal = false}) async {
      for (final (i, path) in paths.indexed) {
        final sides = parseYahooMatchup(await page('matchup${week}_$i', path), isFinal: isFinal);
        matchups.add({
          'week': week,
          'teams': [for (final s in sides) {'name': s.name, 'stats': s.stats}],
        });
      }
    }

    if (last != null && (last['week'] as int) < league.week) {
      await addWeek(last['week'] as int, (last['paths'] as List).cast<String>(), isFinal: true);
    }
    await addWeek(league.week, league.matchupPaths);

    File('state/yahoo.json').writeAsStringSync(jsonEncode({
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'teams': [for (final t in teams) {'name': t.name, 'players': t.players}],
      'matchups': matchups,
    }));
    lastFile.writeAsStringSync(jsonEncode({'week': league.week, 'paths': league.matchupPaths}));
    stdout.writeln('${teams.length} teams, ${matchups.length} matchups, week ${league.week}, $count requests');
  } on YahooLoggedOut catch (e) {
    await _stop(stopped, '$e');
  } on YahooBlocked catch (e) {
    await _stop(stopped, '$e');
  } on YahooParseError catch (e) {
    // Not Yahoo refusing us, so no stop marker; tomorrow's run tries again.
    await _alert('⚠️ Yahoo sync: $e. Nothing was updated. Screenshots to the bot still work.');
    exit(1);
  } finally {
    client.close();
  }
}

Future<Never> _stop(File marker, String reason) async {
  marker
    ..createSync(recursive: true)
    ..writeAsStringSync('${DateTime.now().toUtc().toIso8601String()} $reason\n');
  await _alert('⚠️ Yahoo sync stopped: $reason.\n\nNo more requests until you save a fresh cookie to state/yahoo_cookie and delete '
      'state/yahoo_stopped on the Mac. Screenshots to the bot still work.');
  exit(1);
}

Future<void> _alert(String text) async {
  stderr.writeln(text);
  final env = Platform.environment;
  await sendTelegram([text], token: env['TELEGRAM_TOKEN'], chatId: env['TELEGRAM_CHAT_ID']);
}
