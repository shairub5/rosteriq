import 'dart:convert';

import 'package:http/http.dart' as http;

import 'espn.dart';

/// Telegram roster updates: send a team name as the caption of 1+ roster
/// screenshots, and that team's roster in `snapshot.json` (`league.teams`) is
/// replaced. The app pulls it from there. Shape:
///   league: {telegramOffset: int, teams: [{name, playerIds, updatedAt}]}
/// playerIds are ESPN ids (or bundled ids for players ESPN doesn't list); the
/// app re-keys them the same way as snapshot players.

/// One roster update request: a caption plus the photos sent with it.
typedef RosterRequest = ({String teamName, List<String> fileIds});

/// Groups this chat's updates into roster requests. Photos sent together share
/// a media_group_id; the caption sits on just one of them. Other chats are
/// ignored (the bot token is the only thing standing between strangers and the league).
({List<RosterRequest> requests, int uncaptioned, int? lastUpdateId}) groupRosterMessages(List<dynamic> updates, String chatId) {
  int? last;
  final groups = <String, ({String? caption, List<String> fileIds})>{};
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
    groups[key] = (
      caption: (m['caption'] as String?)?.trim() ?? g?.caption,
      fileIds: [...?g?.fileIds, fileId],
    );
  }
  return (
    requests: [
      for (final g in groups.values)
        if (g.caption != null && g.caption!.isNotEmpty) (teamName: g.caption!, fileIds: g.fileIds),
    ],
    uncaptioned: groups.values.where((g) => g.caption == null || g.caption!.isEmpty).length,
    lastUpdateId: last,
  );
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

const _model = 'claude-opus-5-5';

/// Reads player names off roster screenshots with Claude (vision + JSON schema output).
Future<List<String>> extractRosterNames(String apiKey, List<({List<int> bytes, String mediaType})> images) async {
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
              'players': {'type': 'array', 'items': {'type': 'string'}},
            },
            'required': ['players'],
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
              'text': 'These screenshots show one fantasy basketball team\'s roster (Yahoo or similar). '
                  'List the full name of every NBA player on the roster, including bench and IL slots, '
                  'each once, exactly as written. Ignore team names, opponents, stats and empty slots.',
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
  return ((jsonDecode(text as String) as Map<String, dynamic>)['players'] as List).cast<String>();
}

/// Polls the bot for roster screenshots, updates `league`, and replies to each request.
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
  var offset = previous?['telegramOffset'] as int?;
  if (token == null || chatId == null) return {'teams': teams, 'telegramOffset': offset};

  final api = 'https://api.telegram.org/bot$token';
  final res = await http.get(Uri.parse('$api/getUpdates?timeout=0${offset == null ? '' : '&offset=${offset + 1}'}'));
  if (res.statusCode != 200) throw Exception('Telegram getUpdates ${res.statusCode}: ${res.body}');
  final grouped = groupRosterMessages((jsonDecode(res.body) as Map<String, dynamic>)['result'] as List, chatId);
  offset = grouped.lastUpdateId ?? offset;

  Future<void> reply(String text) => http.post(Uri.parse('$api/sendMessage'), body: {'chat_id': chatId, 'text': text});

  if (grouped.uncaptioned > 0) {
    await reply('Got screenshots without a team name. Send them again with the team name as the caption '
        '(select both images, type the name, send).');
  }
  for (final r in grouped.requests) {
    if (apiKey == null) {
      await reply('Can\'t read screenshots yet: ANTHROPIC_API_KEY isn\'t set in the repo secrets.');
      continue;
    }
    try {
      final images = <({List<int> bytes, String mediaType})>[];
      for (final id in r.fileIds) {
        final file = jsonDecode((await http.get(Uri.parse('$api/getFile?file_id=$id'))).body)['result'];
        final path = file['file_path'] as String;
        final bytes = (await http.get(Uri.parse('https://api.telegram.org/file/bot$token/$path'))).bodyBytes;
        images.add((bytes: bytes, mediaType: path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'));
      }
      final names = await extractRosterNames(apiKey, images);
      final m = matchRosterNames(names, players);
      teams = upsertTeam(teams, r.teamName, m.ids, now);
      await reply([
        '✅ ${r.teamName}: ${m.ids.length} players saved. The app picks it up on next refresh.',
        if (m.unmatched.isNotEmpty) 'Couldn\'t match: ${m.unmatched.join(', ')}',
      ].join('\n'));
    } catch (e) {
      await reply('❌ ${r.teamName}: couldn\'t update ($e). Try sending the screenshots again.');
    }
  }
  return {'teams': teams, 'telegramOffset': offset};
}
