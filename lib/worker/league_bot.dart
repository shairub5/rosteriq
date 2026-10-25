import 'dart:convert';

import 'package:http/http.dart' as http;

import 'espn.dart';

/// League data sent to the Telegram bot as Yahoo screenshots, stored in
/// `snapshot.json` for the app:
///   league: {telegramOffset, myName, teams: [{name, playerIds, updatedAt}],
///            matchups: [{week, teams: [{name, stats: {cat: n}}, {...}], updatedAt}]}
/// - Roster screenshots + the team name as caption replace that team's roster.
///   playerIds are ESPN ids (or bundled ids for players ESPN doesn't list); the
///   app re-keys them the same way as snapshot players.
/// - Matchup screenshots (any of the league's matchups, no caption needed)
///   store that week's real category totals for both teams. `myName` (my Yahoo
///   team name) is learned from the first matchup with exactly one team that
///   isn't on the roster list - roster screenshots don't show it.

/// Photos sent together (one album, or a single photo) and their caption, if any.
typedef PhotoGroup = ({String? caption, List<String> fileIds});

/// Team names that mean "my own roster".
bool isMyTeamName(String name) => const {'my team', 'me', 'mine', 'my roster'}.contains(normalizeName(name));

/// The 9 categories in the key order the app uses (`StatCategory.name`).
const statKeys = ['fgPct', 'ftPct', 'threePM', 'pts', 'reb', 'ast', 'stl', 'blk', 'to'];

/// Groups this chat's updates into photo groups. Photos sent together share a
/// media_group_id; the caption sits on just one of them. Other chats are
/// ignored (the bot token is the only thing standing between strangers and the league).
({List<PhotoGroup> groups, int? lastUpdateId}) groupPhotoMessages(List<dynamic> updates, String chatId) {
  int? last;
  final groups = <String, PhotoGroup>{};
  for (final u in updates.cast<Map<String, dynamic>>()) {
    last = u['update_id'] as int;
    final m = u['message'] as Map<String, dynamic>?;
    if (m == null || '${(m['chat'] as Map)['id']}' != chatId) continue;
    final photos = m['photo'] as List?;
    final doc = m['document'] as Map<String, dynamic>?;
    // Largest photo size; screenshots sent "as file" arrive as an image document.
    final fileId = photos != null && photos.isNotEmpty
        ? (photos.last as Map)['file_id'] as String
        : (doc != null && '${doc['mime_type']}'.startsWith('image/') ? doc['file_id'] as String : null);
    if (fileId == null) continue;
    final key = '${m['media_group_id'] ?? 'msg${m['message_id']}'}';
    final g = groups[key];
    final caption = (m['caption'] as String?)?.trim();
    groups[key] = (
      caption: caption != null && caption.isNotEmpty ? caption : g?.caption,
      fileIds: [...?g?.fileIds, fileId],
    );
  }
  return (groups: groups.values.toList(), lastUpdateId: last);
}

/// Names read off a screenshot -> player ids. Exact name first (punctuation and
/// suffixes ignored), then first initial + surname when only one player fits.
({List<String> ids, List<String> unmatched}) matchRosterNames(
  List<String> names,
  List<({String id, String name})> players,
) {
  final exact = <String, String>{};
  final loose = <String, Set<String>>{};
  for (final p in players) {
    final n = normalizeName(p.name);
    exact.putIfAbsent(n, () => p.id);
    loose.putIfAbsent(_initialKey(n), () => {}).add(exact[n]!);
  }
  final ids = <String>[];
  final unmatched = <String>[];
  for (final name in names) {
    final n = normalizeName(name);
    final candidates = loose[_initialKey(n)];
    final id = exact[n] ?? (candidates?.length == 1 ? candidates!.single : null);
    if (id == null) {
      unmatched.add(name);
    } else if (!ids.contains(id)) {
      ids.add(id);
    }
  }
  return (ids: ids, unmatched: unmatched);
}

String _initialKey(String normalized) {
  final w = normalized.split(' ');
  return w.length < 2 ? normalized : '${w.first[0]} ${w.skip(1).join(' ')}';
}

/// Replaces the roster of the team with this name (case/punctuation-insensitive), or adds the team.
List<Map<String, dynamic>> upsertTeam(List<Map<String, dynamic>> teams, String name, List<String> ids, DateTime now) {
  final key = normalizeName(name);
  final entry = {'name': name, 'playerIds': ids, 'updatedAt': now.toIso8601String()};
  final i = teams.indexWhere((t) => normalizeName(t['name'] as String) == key);
  return i < 0 ? [...teams, entry] : [...teams.sublist(0, i), entry, ...teams.sublist(i + 1)];
}

/// A matchup read off a screenshot: both teams' names and category totals.
typedef MatchupSide = ({String name, Map<String, num> stats});

Map<String, dynamic> matchupEntry(List<MatchupSide> sides, int week, DateTime now) => {
      'week': week,
      'teams': [
        for (final s in sides) {'name': s.name, 'stats': s.stats},
      ],
      'updatedAt': now.toIso8601String(),
    };

List<String> _names(Map<String, dynamic> m) => [for (final t in (m['teams'] as List)) normalizeName(t['name'] as String)];

/// Replaces the same week's matchup of either team (each team plays once a week, so
/// mid-week screenshots update it), keeping entries sorted by week.
List<Map<String, dynamic>> upsertMatchup(List<Map<String, dynamic>> matchups, Map<String, dynamic> entry) {
  final names = _names(entry).toSet();
  return [
    ...matchups.where((m) => m['week'] != entry['week'] || !_names(m).any(names.contains)),
    entry,
  ]..sort((a, b) => (a['week'] as int).compareTo(b['week'] as int));
}

/// My Yahoo team name: the one side of a matchup that isn't a known other team.
String? inferMyName(List<MatchupSide> sides, Iterable<String> otherTeamNames) {
  final others = otherTeamNames.map(normalizeName).toSet();
  final unknown = sides.where((s) => !others.contains(normalizeName(s.name))).toList();
  return unknown.length == 1 ? unknown.single.name : null;
}

/// "Week 3", "w3", "3" -> 3.
int? weekFromCaption(String? caption) => int.tryParse(RegExp(r'\d+').firstMatch(caption ?? '')?.group(0) ?? '');

/// Wins/losses/ties of side [a] against side [b] across the 9 categories (TO: fewer wins).
({int w, int l, int t}) matchupScore(Map<String, dynamic> a, Map<String, dynamic> b) {
  var w = 0, l = 0, t = 0;
  for (final k in statKeys) {
    final x = (a[k] as num).toDouble(), y = (b[k] as num).toDouble();
    if (x == y) {
      t++;
    } else if ((x > y) != (k == 'to')) {
      w++;
    } else {
      l++;
    }
  }
  return (w: w, l: l, t: t);
}

typedef ScreenshotRead = ({String kind, List<String> players, int week, List<MatchupSide> teams});

const _model = 'claude-opus-5-5';

/// Reads roster or matchup screenshots with Claude (vision + JSON schema output).
Future<ScreenshotRead> readScreenshots(String apiKey, List<({List<int> bytes, String mediaType})> images) async {
  final res = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2026-10-21',
      'anthropic-beta': 'server-side-fallback-2026-07-01',
    },
    body: jsonEncode({
      'model': _model,
      'max_tokens': 4000,
      'fallbacks': 'default',
      'output_config': {
        'effort': 'low',
        'format': {
          'type': 'json_schema',
          'schema': {
            'type': 'object',
            'properties': {
              'kind': {'type': 'string', 'enum': ['roster', 'matchup']},
              'players': {'type': 'array', 'items': {'type': 'string'}},
              'week': {'type': 'integer'},
              'teams': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    for (final k in statKeys) k: {'type': 'number'},
                  },
                  'required': ['name', ...statKeys],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['kind', 'players', 'week', 'teams'],
            'additionalProperties': false,
          },
        },
      },
      'messages': [
        {
          'role': 'user',
          'content': [
            for (final img in images)
              {
                'type': 'image',
                'source': {'type': 'base64', 'media_type': img.mediaType, 'data': base64Encode(img.bytes)},
              },
            {
              'type': 'text',
              'text': 'These are screenshots from a 9-category fantasy basketball league (Yahoo or similar).\n'
                  'If they show one team\'s roster (players by position): kind "roster", list the full name of '
                  'every NBA player including bench and IL slots, each once, exactly as written; teams empty, week 0.\n'
                  'If they show a head-to-head matchup with both teams\' category totals: kind "matchup", give both '
                  'team names exactly as written and each team\'s totals: fgPct and ftPct as decimals (".472" -> 0.472), '
                  'threePM, pts, reb, ast, stl, blk, to as numbers; week = the matchup week number if shown, else 0; '
                  'players empty.',
            },
          ],
        },
      ],
    }),
  );
  if (res.statusCode != 200) throw Exception('Claude API ${res.statusCode}: ${res.body}');
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (body['stop_reason'] == 'refusal') throw Exception('Claude declined to read the screenshots');
  final text = (body['content'] as List).cast<Map<String, dynamic>>().firstWhere((b) => b['type'] == 'text')['text'];
  final j = jsonDecode(text as String) as Map<String, dynamic>;
  return (
    kind: j['kind'] as String,
    players: (j['players'] as List).cast<String>(),
    week: j['week'] as int,
    teams: [
      for (final t in (j['teams'] as List).cast<Map<String, dynamic>>())
        (name: t['name'] as String, stats: {for (final k in statKeys) k: t[k] as num}),
    ],
  );
}

/// Polls the bot for screenshots, updates `league`, and replies to each one.
/// Returns the new `league` object for the snapshot (the previous one if nothing came in).
Future<Map<String, dynamic>> syncLeagueFromTelegram({
  required Map<String, dynamic>? previous,
  required List<({String id, String name})> players,
  required String? token,
  required String? chatId,
  required String? apiKey,
  required DateTime now,
}) async {
  var teams = [...((previous?['teams'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  var matchups = [...((previous?['matchups'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  var offset = previous?['telegramOffset'] as int?;
  var myName = previous?['myName'] as String?;
  Map<String, dynamic> result() => {'teams': teams, 'matchups': matchups, 'myName': myName, 'telegramOffset': offset};
  if (token == null || chatId == null) return result();

  final api = 'https://api.telegram.org/bot$token';
  final res = await http.get(Uri.parse('$api/getUpdates?timeout=0${offset == null ? '' : '&offset=${offset + 1}'}'));
  if (res.statusCode != 200) throw Exception('Telegram getUpdates ${res.statusCode}: ${res.body}');
  final grouped = groupPhotoMessages((jsonDecode(res.body) as Map<String, dynamic>)['result'] as List, chatId);
  offset = grouped.lastUpdateId ?? offset;

  Future<void> reply(String text) => http.post(Uri.parse('$api/sendMessage'), body: {'chat_id': chatId, 'text': text});

  for (final g in grouped.groups) {
    if (apiKey == null) {
      await reply('Can\'t read screenshots yet: ANTHROPIC_API_KEY isn\'t set in the repo secrets.');
      continue;
    }
    try {
      final images = <({List<int> bytes, String mediaType})>[];
      for (final id in g.fileIds) {
        final file = jsonDecode((await http.get(Uri.parse('$api/getFile?file_id=$id'))).body)['result'];
        final path = file['file_path'] as String;
        final bytes = (await http.get(Uri.parse('https://api.telegram.org/file/bot$token/$path'))).bodyBytes;
        images.add((bytes: bytes, mediaType: path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'));
      }
      final read = await readScreenshots(apiKey, images);
      if (read.kind == 'roster') {
        final name = g.caption;
        if (name == null) {
          await reply('That looks like a roster. Send it again with the team name as the caption ("My Team" for yours).');
          continue;
        }
        final m = matchRosterNames(read.players, players);
        teams = upsertTeam(teams, name, m.ids, now);
        await reply([
          '✅ $name: ${m.ids.length} players saved. The app picks it up on next refresh.',
          if (m.unmatched.isNotEmpty) 'Couldn\'t match: ${m.unmatched.join(', ')}',
        ].join('\n'));
      } else {
        if (read.teams.length != 2) {
          await reply('❌ Expected 2 teams in the matchup, found ${read.teams.length}.');
          continue;
        }
        // Yahoo's matchup page often has no week number: caption, else the latest stored week.
        final week = read.week > 0
            ? read.week
            : weekFromCaption(g.caption) ?? (matchups.isEmpty ? 1 : matchups.last['week'] as int);
        myName ??= inferMyName(read.teams, teams.map((t) => t['name'] as String).where((n) => !isMyTeamName(n)));
        matchups = upsertMatchup(matchups, matchupEntry(read.teams, week, now));
        final s = matchupScore(read.teams[0].stats, read.teams[1].stats);
        await reply('✅ Week $week: ${read.teams[0].name} ${s.w}-${s.l}-${s.t} ${read.teams[1].name}. '
            '${read.week > 0 || weekFromCaption(g.caption) != null ? '' : '(Wrong week? Resend with a caption like "Week 2".) '}'
            'The app picks it up on next refresh.');
      }
    } catch (e) {
      await reply('❌ ${g.caption ?? 'Screenshot'}: couldn\'t read it ($e). Try sending it again.');
    }
  }
  return result();
}
