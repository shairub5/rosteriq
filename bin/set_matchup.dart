// Stores one matchup's real weekly totals in a snapshot.json, like a matchup
// screenshot sent to the Telegram bot. Values in category order:
// FG% FT% 3PM PTS REB AST STL BLK TO (percentages as decimals), optionally followed by
// FGM FGA FTM FTA GP REMAINING (for the projected final).
//
//   dart run bin/set_matchup.dart <snapshot.json> [--league "<league>"] <week> "<team A>" ".484,.758,60,..." "<team B>" ".497,.773,50,..."
import 'dart:convert';
import 'dart:io';

import 'package:rosteriq/worker/league_bot.dart';

void main(List<String> argv) {
  final li = argv.indexOf('--league');
  final leagueName = li >= 0 ? argv[li + 1] : null;
  final args = [...argv]..removeRange(li >= 0 ? li : 0, li >= 0 ? li + 2 : 0);
  if (args.length != 6) {
    stderr.writeln('usage: dart run bin/set_matchup.dart <snapshot.json> <week> "<team A>" "<9 values>" "<team B>" "<9 values>"');
    exit(64);
  }
  Map<String, num> stats(String csv) {
    final v = csv.split(',').map((s) => num.parse(s.trim())).toList();
    final keys = [...statKeys, ...extraKeys];
    if (v.length != statKeys.length && v.length != keys.length) {
      throw ArgumentError('need ${statKeys.length} or ${keys.length} values, got ${v.length}: $csv');
    }
    return {for (var i = 0; i < v.length; i++) keys[i]: v[i]};
  }

  final file = File(args[0]);
  final snap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final league = leagueFor(snap, leagueName);
  final sides = [(name: args[2], stats: stats(args[3])), (name: args[4], stats: stats(args[5]))];
  final others = [for (final t in (league['teams'] as List? ?? const [])) t['name'] as String].where((n) => !isMyTeamName(n));
  league['myName'] ??= inferMyName(sides, others);
  league['matchups'] = upsertMatchup(
    [...((league['matchups'] as List?) ?? const []).cast<Map<String, dynamic>>()],
    matchupEntry(sides, int.parse(args[1]), DateTime.now().toUtc()),
  );
  file.writeAsStringSync(jsonEncode(snap));
  final s = matchupScore(sides[0].stats, sides[1].stats);
  stdout.writeln('Week ${args[1]}: ${args[2]} ${s.w}-${s.l}-${s.t} ${args[4]}');
}
