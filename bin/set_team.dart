// Sets one league team's roster in a snapshot.json, using the same matching as
// the Telegram bot. For rosters entered outside Telegram (e.g. by hand).
//
//   dart run bin/set_team.dart <snapshot.json> "<team name>" "Player One" "Player Two" ...
import 'dart:convert';
import 'dart:io';

import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/worker/league_bot.dart';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: dart run bin/set_team.dart <snapshot.json> "<team name>" "<player>" ...');
    exit(64);
  }
  final file = File(args[0]);
  final snap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final bundled = (jsonDecode(File('assets/data/players.json').readAsStringSync()) as List)
      .map((j) => Player.fromJson(j as Map<String, dynamic>));
  final players = [
    for (final p in (snap['players'] as List).cast<Map<String, dynamic>>()) (name: p['name'] as String, id: p['id'] as String),
    for (final i in (snap['injuries'] as List).cast<Map<String, dynamic>>()) (name: i['name'] as String, id: i['playerId'] as String),
    for (final p in bundled) (name: p.name, id: p.id),
  ];

  final m = matchRosterNames(args.sublist(2), players);
  final league = (snap['league'] as Map<String, dynamic>?) ?? {};
  snap['league'] = {
    ...league,
    'teams': upsertTeam(
      [...((league['teams'] as List?) ?? const []).cast<Map<String, dynamic>>()],
      args[1],
      m.ids,
      DateTime.now().toUtc(),
    ),
  };
  file.writeAsStringSync(jsonEncode(snap));
  stdout.writeln('${args[1]}: ${m.ids.length} matched${m.unmatched.isEmpty ? '' : ', unmatched: ${m.unmatched.join(', ')}'}');
  if (m.unmatched.isNotEmpty) exitCode = 1;
}
