// Yahoo fetch, run on the user's Mac (never on GitHub Actions, whose data center IPs look wrong for a
// home login). For now it only saves a few pages, to build the parser from.
//
//   dart run bin/yahoo_sync.dart --dump state/yahoo_dump
//
// The cookie is read from state/yahoo_cookie (gitignored). After a logout or a refusal it writes
// state/yahoo_stopped, alerts on Telegram, and refuses to run again until that file is deleted.
//
// Env: TELEGRAM_TOKEN, TELEGRAM_CHAT_ID (without them, the alert is only printed).
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:rosteriq/worker/telegram.dart';
import 'package:rosteriq/worker/yahoo.dart';

const _pages = {
  'league': '/nba/1623',
  'matchup': '/nba/1623/matchup',
  'team': '/nba/1623/1',
};

Future<void> main(List<String> args) async {
  final di = args.indexOf('--dump');
  if (di < 0 || di + 1 >= args.length) {
    stderr.writeln('usage: dart run bin/yahoo_sync.dart --dump <dir>');
    exit(64);
  }
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
  final dir = Directory(args[di + 1])..createSync(recursive: true);

  final client = http.Client();
  try {
    var first = true;
    for (final MapEntry(key: name, value: path) in _pages.entries) {
      if (!first) await Future<void>.delayed(Duration(seconds: 5 + Random().nextInt(10)));
      first = false;
      final html = await fetchYahooPage(client, path, cookie);
      File('${dir.path}/$name.html').writeAsStringSync(html);
      stdout.writeln('$name: ${html.length} chars');
    }
  } on YahooLoggedOut catch (e) {
    await _stop(stopped, '$e');
  } on YahooBlocked catch (e) {
    await _stop(stopped, '$e');
  } finally {
    client.close();
  }
}

Future<Never> _stop(File marker, String reason) async {
  marker
    ..createSync(recursive: true)
    ..writeAsStringSync('${DateTime.now().toUtc().toIso8601String()} $reason\n');
  stderr.writeln('Stopped: $reason');
  final env = Platform.environment;
  await sendTelegram(
    ['⚠️ Yahoo sync stopped: $reason.\n\nNo more requests until you save a fresh cookie to state/yahoo_cookie and delete '
        'state/yahoo_stopped on the Mac. Screenshots to the bot still work.'],
    token: env['TELEGRAM_TOKEN'],
    chatId: env['TELEGRAM_CHAT_ID'],
  );
  exit(1);
}
