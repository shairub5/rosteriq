import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../engine/matchup_needs.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../worker/espn.dart' show normalizeName;
import 'player_repository.dart';
import 'schedule_service.dart';

const assistantModel = 'claude-opus-5-5';
const _keyName = 'anthropic_api_key';
const _storage = FlutterSecureStorage();

/// The Claude API key: saved on the phone (Keychain), or baked in with --dart-define for dev builds.
Future<String?> loadApiKey() async {
  final saved = await _storage.read(key: _keyName);
  if (saved != null && saved.isNotEmpty) return saved;
  const built = String.fromEnvironment('ANTHROPIC_API_KEY');
  return built.isEmpty ? null : built;
}

Future<void> saveApiKey(String? key) =>
    key == null || key.isEmpty ? _storage.delete(key: _keyName) : _storage.write(key: _keyName, value: key.trim());

/// Everything the assistant can see: all leagues, rosters, matchups, player stats, injuries,
/// schedules, last night's box scores and daily lineups.
class AssistantData {
  final LeagueData data;
  final NbaSchedule schedule;
  final String selectedLeagueId;
  final DateTime today;
  late final PerGameBaseline baseline = PerGameBaseline.of(data.players, data.minutes);
  late final Map<String, Player> byId = {for (final p in data.players) p.id: p};

  AssistantData({required this.data, required this.schedule, required this.selectedLeagueId, DateTime? today})
      : today = today ?? usToday();

  double value(Player p) => baseline.z(seasonLine(p)).values.fold(0, (a, b) => a + b);

  /// League by id or (part of its) name; the selected one when [q] is empty.
  LeagueInfo league(String? q) {
    if (q == null || q.isEmpty) return data.leagues.firstWhere((l) => l.id == selectedLeagueId, orElse: () => data.leagues.first);
    final n = q.toLowerCase();
    return data.leagues.firstWhere(
      (l) => l.id == q || l.name.toLowerCase().contains(n),
      orElse: () => throw ArgumentError('No league "$q". Leagues: ${data.leagues.map((l) => l.name).join(', ')}'),
    );
  }

  /// My team's name in [l]'s matchups (the synced roster is stored as "My Team").
  String myName(LeagueInfo l) => l.myName ?? 'My Team';

  /// Team names as in the matchups, with "My Team" shown as my real team name.
  List<({String name, List<Player> roster})> teams(LeagueInfo l) => [
        for (final t in l.remoteTeams)
          (
            name: t.name == 'My Team' ? myName(l) : t.name,
            roster: [for (final id in t.playerIds) ?byId[id]],
          ),
      ];

  ({String name, List<Player> roster}) team(LeagueInfo l, String? q) {
    final all = teams(l);
    if (q == null || q.isEmpty || const {'me', 'my team', 'mine'}.contains(q.toLowerCase())) {
      return all.firstWhere((t) => t.name == myName(l), orElse: () => throw ArgumentError('My team isn\'t synced in ${l.name}'));
    }
    final n = normalizeName(q);
    return all.firstWhere(
      (t) => normalizeName(t.name) == n,
      orElse: () => all.firstWhere(
        (t) => normalizeName(t.name).contains(n),
        orElse: () => throw ArgumentError('No team "$q" in ${l.name}. Teams: ${all.map((t) => t.name).join(', ')}'),
      ),
    );
  }

  Player player(String q) {
    final n = normalizeName(q);
    final exact = data.players.where((p) => normalizeName(p.name) == n).toList();
    if (exact.isNotEmpty) return (exact..sort((a, b) => b.gp.compareTo(a.gp))).first;
    final partial = data.players.where((p) => normalizeName(p.name).contains(n)).toList();
    if (partial.length == 1) return partial.single;
    if (partial.isEmpty) throw ArgumentError('No player "$q"');
    throw ArgumentError('"$q" matches ${partial.take(6).map((p) => p.name).join(', ')}; be more specific');
  }

  int currentWeek(LeagueInfo l) {
    if (l.matchups.isNotEmpty) return l.matchups.map((m) => m.week).reduce((a, b) => a > b ? a : b);
    for (var w = 1; w < 30; w++) {
      if (!fantasyWeekDates(w, schedule).end.isBefore(today)) return w;
    }
    return 1;
  }

  int gamesBetween(Player p, DateTime from, DateTime to) => schedule.teams[p.team]?.gamesInWindow(from, to) ?? 0;

  // ---------------------------------------------------------------- context

  static String _f(double v, [int d = 1]) => v.toStringAsFixed(d);
  static String _pct(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
  String _date(DateTime d) =>
      '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

  String _stats(TeamWeek t) => [
        for (final c in allStatCategories)
          '${c.label} ${c == StatCategory.fgPct || c == StatCategory.ftPct ? _pct(t.stats[c]!) : t.stats[c]!.round()}',
        if (t.extra['remaining'] case final r?) 'games left ${r.round()}',
        if (t.extra['gp'] case final g? when g > 0) 'played ${g.round()}',
      ].join(', ');

  /// The data snapshot given to the model with every question.
  String context() {
    final b = StringBuffer();
    final sel = league(null);
    b.writeln('TODAY (US date): ${_date(today)}. Data updated ${data.updatedAt?.toIso8601String() ?? 'unknown'}.');
    b.writeln('The app is showing league "${sel.name}" right now; assume that league unless the user names another.');
    b.writeln();
    for (final l in data.leagues) {
      final week = currentWeek(l);
      final range = fantasyWeekDates(week, schedule);
      b.writeln('=== LEAGUE "${l.name}" (id ${l.id}) · my team: "${myName(l)}" · current week $week (${_date(range.start)} to ${_date(range.end)}) ===');
      b.writeln('Rosters:');
      for (final t in teams(l)) {
        b.writeln('- ${t.name}${t.name == myName(l) ? ' (ME)' : ''}: ${t.roster.map((p) => p.name).join(', ')}');
      }
      b.writeln('Matchups (category totals; "games left" = Yahoo starts remaining):');
      for (final m in [...l.matchups]..sort((a, b) => a.week.compareTo(b.week))) {
        b.writeln('- W${m.week} ${m.a.name} [${_stats(m.a)}] vs ${m.b.name} [${_stats(m.b)}]');
      }
      if (l.lineups.isNotEmpty) {
        b.writeln('Daily lineups saved (team -> days): '
            '${l.lineups.entries.map((e) => '${e.key}: ${e.value.length} days').join('; ')} (use the week_games tool for counts).');
      }
      b.writeln();
    }

    // Who owns whom, per league.
    final owner = <String, List<String>>{};
    for (final l in data.leagues) {
      for (final t in teams(l)) {
        for (final p in t.roster) {
          (owner[p.id] ??= []).add('${l.name}: ${t.name == myName(l) ? 'ME' : t.name}');
        }
      }
    }
    final week = currentWeek(sel);
    final range = fantasyWeekDates(week, schedule);
    final next = (start: range.start.add(const Duration(days: 7)), end: range.end.add(const Duration(days: 7)));
    b.writeln('=== PLAYERS (season per-game; value = sum of 9-category z per game; FA = free agent in every league) ===');
    b.writeln('name | NBA team | pos | GP | MIN | PTS | REB | AST | 3PM | STL | BLK | TO | FG% (FGA) | FT% (FTA) | value | injury | '
        'owners | games left this week from today | games next week');
    final shown = data.players.where((p) => p.gp > 0 || data.injuries.containsKey(p.id) || owner.containsKey(p.id)).toList()
      ..sort((a, b) => value(b).compareTo(value(a)));
    for (final p in shown) {
      final g = p.gp == 0 ? 1 : p.gp;
      final inj = data.injuries[p.id];
      b.writeln([
        p.name,
        p.team,
        p.eligiblePositions.join('/'),
        p.gp,
        _f(data.minutes[p.id] ?? 0),
        _f(p.pts / g),
        _f(p.reb / g),
        _f(p.ast / g),
        _f(p.threePM / g),
        _f(p.stl / g),
        _f(p.blk / g),
        _f(p.to / g),
        '${_pct(p.fgPct)} (${_f(p.fgAttempted / g)})',
        '${_pct(p.ftPct)} (${_f(p.ftAttempted / g)})',
        p.gp == 0 ? '-' : _f(value(p)),
        inj == null ? '' : '${inj.status}${inj.returnDate == null ? '' : ' until ${inj.returnDate}'} ${inj.detail}',
        owner[p.id]?.join('; ') ?? 'FA',
        gamesBetween(p, today.isBefore(range.start) ? range.start : today, range.end),
        gamesBetween(p, next.start, next.end),
      ].join(' | '));
    }

    if (data.lastNight case final n?) {
      b.writeln();
      b.writeln('=== LAST NIGHT ${_date(n.date)} box scores (MIN PTS REB AST 3PM STL BLK TO FGM-FGA FTM-FTA) ===');
      for (final l in n.lines.values.where((l) => l.min > 0)) {
        b.writeln('${l.name} (${l.team}) ${l.min.round()}m ${l.pts}p ${l.reb}r ${l.ast}a ${l.threePM}3 ${l.stl}s ${l.blk}b ${l.to}to '
            '${l.fgm}-${l.fga} ${l.ftm}-${l.fta}');
      }
      b.writeln('Out injured last night by team: ${n.outByTeam.entries.map((e) => '${e.key}: ${e.value.map((id) => byId[id]?.name ?? id).join(', ')}').join('; ')}');
    }
    return b.toString();
  }

  // ------------------------------------------------------------------ tools

  static const tools = [
    {
      'name': 'project_matchup',
      'description': 'Project a fantasy matchup week to its final category totals, day by day from today: each team starts its 10 '
          'best healthy players each day at season per-game averages, added to the real totals so far. Optionally apply '
          'hypothetical adds/drops to the first team (to test pickups or trades). Returns per-category now/projected, '
          'the projected W-L-T and each category\'s need (toss-up, chase, hold, safe, out of reach).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'league': {'type': 'string', 'description': 'League name or id; default the selected league'},
          'week': {'type': 'integer', 'description': 'Default the current week'},
          'team': {'type': 'string', 'description': 'Team name; default my team'},
          'opponent': {'type': 'string', 'description': 'Team to compare against; default the real opponent that week'},
          'add': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Player names to add to team'},
          'drop': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Player names to drop from team'},
        },
      },
    },
    {
      'name': 'evaluate_trade',
      'description': 'Evaluate a trade or add/drop for one team: per-category per-game z of what leaves vs what arrives, the '
          'team\'s season per-game category totals before/after, games left this week for each player, and the current '
          'matchup projection before/after.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'league': {'type': 'string'},
          'team': {'type': 'string', 'description': 'Default my team'},
          'give': {'type': 'array', 'items': {'type': 'string'}},
          'receive': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['give', 'receive'],
      },
    },
    {
      'name': 'week_games',
      'description': 'Games per player for a team in a fantasy week: played (in active lineup slots when daily lineups are '
          'saved, else box scores), missed, on bench, left from today, including players dropped during the week.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'league': {'type': 'string'},
          'team': {'type': 'string', 'description': 'Default my team'},
          'week': {'type': 'integer', 'description': 'Default the current week'},
        },
      },
    },
    {
      'name': 'schedule',
      'description': 'NBA game dates for players or NBA team codes between two dates (inclusive).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'players': {'type': 'array', 'items': {'type': 'string'}},
          'nba_teams': {'type': 'array', 'items': {'type': 'string'}},
          'from': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'to': {'type': 'string', 'description': 'YYYY-MM-DD'},
        },
        'required': ['from', 'to'],
      },
    },
  ];

  String runTool(String name, Map<String, dynamic> input) {
    List<String> names(String k) => ((input[k] as List?) ?? const []).cast<String>();
    switch (name) {
      case 'project_matchup':
        final l = league(input['league'] as String?);
        final week = (input['week'] as num?)?.toInt() ?? currentWeek(l);
        final me = team(l, input['team'] as String?);
        final ms = l.matchups.where((m) => m.week == week).toList();
        final mine = ms.map((m) => m.a.name == me.name ? (me: m.a, opp: m.b) : m.b.name == me.name ? (me: m.b, opp: m.a) : null).nonNulls.firstOrNull;
        final oppName = input['opponent'] as String? ?? mine?.opp.name;
        if (oppName == null) throw ArgumentError('${me.name} has no week $week matchup; pass opponent');
        final opp = team(l, oppName);
        TeamWeek now(String n) =>
            ms.expand((m) => [m.a, m.b]).where((t) => t.name == n).firstOrNull ??
            (name: n, stats: {for (final c in allStatCategories) c: 0.0}, extra: const {});
        final drop = {for (final n in names('drop')) player(n).id};
        final roster = [...me.roster.where((p) => !drop.contains(p.id)), for (final n in names('add')) player(n)];
        return jsonEncode(_projection(week, now(me.name), roster, now(opp.name), opp.roster));
      case 'evaluate_trade':
        final l = league(input['league'] as String?);
        final me = team(l, input['team'] as String?);
        final give = [for (final n in names('give')) player(n)];
        final receive = [for (final n in names('receive')) player(n)];
        Map<String, double> z(List<Player> ps) => {
              for (final c in allStatCategories)
                c.label: double.parse(ps.fold<double>(0, (s, p) => s + baseline.z(seasonLine(p))[c]!).toStringAsFixed(2)),
            };
        Map<String, String> totals(List<Player> ps) {
          final lines = ps.where((p) => p.gp > 0).map(seasonLine).toList();
          double sum(double Function(PerGame) f) => lines.fold(0, (s, g) => s + f(g));
          return {
            for (final c in allStatCategories)
              c.label: switch (c) {
                StatCategory.fgPct => _pct(sum((g) => g.fgm) / sum((g) => g.fga)),
                StatCategory.ftPct => _pct(sum((g) => g.ftm) / sum((g) => g.fta)),
                _ => _f(sum((g) => g.cats[c]!)),
              },
          };
        }
        final ids = {for (final p in give) p.id};
        final after = [...me.roster.where((p) => !ids.contains(p.id)), ...receive];
        final week = currentWeek(l);
        final range = fantasyWeekDates(week, schedule);
        final from = today.isBefore(range.start) ? range.start : today;
        final m = l.matchups.where((m) => m.week == week && (m.a.name == me.name || m.b.name == me.name)).firstOrNull;
        final result = <String, dynamic>{
          'team': me.name,
          'give_z': z(give),
          'receive_z': z(receive),
          'give_value': give.map((p) => '${p.name} ${_f(value(p))}').toList(),
          'receive_value': receive.map((p) => '${p.name} ${_f(value(p))}').toList(),
          'roster_per_game_totals_before': totals(me.roster),
          'roster_per_game_totals_after': totals(after),
          'games_left_this_week': {for (final p in [...give, ...receive]) p.name: gamesBetween(p, from, range.end)},
        };
        if (m != null) {
          final mine = m.a.name == me.name ? m.a : m.b;
          final opp = m.a.name == me.name ? m.b : m.a;
          final oppRoster = team(l, opp.name).roster;
          result['matchup_before'] = _projection(week, mine, me.roster, opp, oppRoster);
          result['matchup_after'] = _projection(week, mine, after, opp, oppRoster);
        }
        return jsonEncode(result);
      case 'week_games':
        final l = league(input['league'] as String?);
        final t = team(l, input['team'] as String?);
        final week = (input['week'] as num?)?.toInt() ?? currentWeek(l);
        final rows = teamWeekGames(
          roster: t.roster,
          playersById: byId,
          lineups: l.lineups[t.name],
          range: fantasyWeekDates(week, schedule),
          schedule: schedule,
          played: data.played,
          today: today,
        );
        return jsonEncode({
          'team': t.name,
          'week': week,
          'lineups_saved': l.lineups[t.name] != null,
          'total_played': rows.fold<int>(0, (s, r) => s + r.games.played),
          'players': [
            for (final r in rows..sort((a, b) => b.games.played.compareTo(a.games.played)))
              {
                'name': r.player.name,
                'played': r.games.played,
                'missed': r.games.missed,
                'bench': r.benched,
                'left': r.games.left,
                if (!r.onRoster) 'dropped': true,
              },
          ],
        });
      case 'schedule':
        final from = DateTime.parse(input['from'] as String);
        final to = DateTime.parse(input['to'] as String);
        String days(String team) => (schedule.teams[team]?.games ?? const <DateTime>[])
            .where((d) => !d.isBefore(DateTime(from.year, from.month, from.day)) && !d.isAfter(DateTime(to.year, to.month, to.day)))
            .map(_date)
            .join(', ');
        return jsonEncode({
          for (final n in names('players'))
            () {
              final p = player(n);
              return '${p.name} (${p.team})';
            }(): days(player(n).team),
          for (final t in names('nba_teams')) t: days(t.toUpperCase()),
        });
    }
    throw ArgumentError('Unknown tool $name');
  }

  Map<String, dynamic> _projection(int week, TeamWeek me, List<Player> mine, TeamWeek opp, List<Player> theirs) {
    final range = fantasyWeekDates(week, schedule);
    Map<StatCategory, double> proj(TeamWeek t, List<Player> r) => projectSide(
          now: t,
          roster: r,
          schedule: schedule,
          injuries: data.injuries,
          range: range,
          valueOf: value,
          today: today,
        );
    final a = proj(me, mine), b = proj(opp, theirs);
    final needs = categoryNeeds(a, b);
    var (w, l, t) = (0, 0, 0);
    final cats = <String, String>{};
    for (final c in allStatCategories) {
      final lead = (a[c]! - b[c]!) * (c.lowerIsBetter ? -1 : 1);
      lead > 0 ? w++ : lead < 0 ? l++ : t++;
      String f(double v) => c == StatCategory.fgPct || c == StatCategory.ftPct ? _pct(v) : _f(v);
      cats[c.label] = 'now ${f(me.stats[c]!)}-${f(opp.stats[c]!)}, projected ${f(a[c]!)}-${f(b[c]!)}, ${needs[c]!.label}';
    }
    return {'week': week, 'team': me.name, 'opponent': opp.name, 'projected': '$w-$l-$t', 'categories': cats};
  }
}

/// One turn of the conversation as the API sees it (content blocks kept verbatim, thinking included).
typedef ApiMessage = Map<String, dynamic>;

const _system = '''
You are the fantasy basketball assistant inside RosterIQ, the user's personal app for their 9-category head-to-head
leagues (FG%, FT%, 3PM, PTS, REB, AST, STL, BLK, TO; fewer turnovers wins). Weeks run Monday to Sunday; each day a team
starts 10 players and the rest sit on the bench or IL.

You have the app's full data below the instructions: every league's rosters and weekly matchups, every NBA player's
season per-game stats, injuries with return dates, who owns whom in each league (FA = free agent), games left this week
and next, and last night's box scores. Use the tools for projections, trade and add/drop evaluations, games played per
week, and NBA schedules; use web search for news the data can't show (injury updates, role changes, trades, rumors).

Answer what was asked, directly, with your recommendation first. Back it with the numbers that matter (category
margins, per-game stats, games left) rather than generic advice. Be concrete with names: who to add, who to drop, which
trade to offer and why it works for the other team too. Say when data is thin (few games, injury uncertainty).
Keep it readable on a phone: short paragraphs, bullet lists, and small tables (at most 4 columns).
''';

/// Sends the conversation to Claude, running the app's tools until it answers. [onStep] reports
/// progress ("Searching the web…"). Returns the new API messages to append (assistant turns and
/// tool results), the last one being the final assistant answer.
Future<List<ApiMessage>> askAssistant({
  required String apiKey,
  required AssistantData data,
  required List<ApiMessage> history,
  void Function(String step)? onStep,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final context = data.context();
  final added = <ApiMessage>[];
  for (var round = 0; round < 25; round++) {
    final res = await c
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2026-10-21',
            'anthropic-beta': 'server-side-fallback-2026-07-01',
          },
          body: jsonEncode({
            'model': assistantModel,
            'max_tokens': 16000,
            'fallbacks': 'default',
            'thinking': {'type': 'adaptive'},
            'output_config': {'effort': 'high'},
            // Caches the conversation so far; the system block below caches the data snapshot.
            'cache_control': {'type': 'ephemeral'},
            'system': [
              {'type': 'text', 'text': _system},
              {'type': 'text', 'text': context, 'cache_control': {'type': 'ephemeral'}},
            ],
            'tools': [
              ...AssistantData.tools,
              {'type': 'web_search_20260209', 'name': 'web_search'},
              {'type': 'web_fetch_20260209', 'name': 'web_fetch'},
            ],
            'messages': [...history, ...added],
          }),
        )
        .timeout(const Duration(minutes: 6));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final err = (body['error'] as Map?)?['message'] ?? res.body;
      throw AssistantError(res.statusCode == 401 ? 'The API key was rejected. Tap the key icon to change it.' : '$err');
    }
    final content = (body['content'] as List).cast<Map<String, dynamic>>();
    added.add({'role': 'assistant', 'content': content});
    switch (body['stop_reason']) {
      case 'tool_use':
        final results = <Map<String, dynamic>>[];
        for (final b in content.where((b) => b['type'] == 'tool_use')) {
          final name = b['name'] as String;
          onStep?.call(_stepLabel(name));
          try {
            results.add({'type': 'tool_result', 'tool_use_id': b['id'], 'content': data.runTool(name, (b['input'] as Map).cast<String, dynamic>())});
          } catch (e) {
            results.add({'type': 'tool_result', 'tool_use_id': b['id'], 'content': '$e', 'is_error': true});
          }
        }
        added.add({'role': 'user', 'content': results});
      case 'pause_turn':
        onStep?.call('Still researching…');
      case 'refusal':
        throw AssistantError('Claude declined to answer that one.');
      default:
        if (content.any((b) => b['type'] == 'server_tool_use')) onStep?.call('Searched the web');
        return added;
    }
  }
  throw AssistantError('Gave up after too many steps.');
}

String _stepLabel(String tool) => switch (tool) {
      'project_matchup' => 'Projecting the matchup…',
      'evaluate_trade' => 'Evaluating the move…',
      'week_games' => 'Counting games…',
      'schedule' => 'Checking the schedule…',
      _ => 'Working…',
    };

class AssistantError implements Exception {
  final String message;
  AssistantError(this.message);
  @override
  String toString() => message;
}

/// The visible text of an assistant turn (thinking and tool blocks left out).
String assistantText(ApiMessage m) => ((m['content'] as List?) ?? const [])
    .whereType<Map>()
    .where((b) => b['type'] == 'text')
    .map((b) => b['text'] as String)
    .join('\n\n')
    .trim();
