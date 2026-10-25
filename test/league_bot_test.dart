import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/state/league_teams_provider.dart';
import 'package:rosteriq/worker/espn.dart';
import 'package:rosteriq/worker/league_bot.dart';

Map<String, dynamic> _photo(int updateId, String chat, {String? group, String? caption, String file = 'f'}) => {
      'update_id': updateId,
      'message': {
        'message_id': updateId * 10,
        'chat': {'id': int.parse(chat)},
        'media_group_id': ?group,
        'caption': ?caption,
        'photo': [
          {'file_id': '$file-small'},
          {'file_id': file},
        ],
      },
    };

void main() {
  test('normalizeName folds accents', () {
    expect(normalizeName('Luka Dončić'), normalizeName('Luka Doncic'));
    expect(normalizeName('Egor Dëmin'), 'egor demin');
    expect(normalizeName('Kristaps Porziņģis'), 'kristaps porzingis');
    expect(normalizeName('Jimmy Butler III'), 'jimmy butler');
  });

  test('groupRosterMessages joins an album, takes the caption from any photo, ignores other chats', () {
    final g = groupRosterMessages([
      _photo(1, '42', group: 'a', caption: 'ForKobe', file: 'p1'),
      _photo(2, '42', group: 'a', file: 'p2'),
      _photo(3, '99', caption: 'Intruders', file: 'x'),
      _photo(4, '42', file: 'lonely'),
    ], '42');
    expect(g.requests, hasLength(1));
    expect(g.requests.single.teamName, 'ForKobe');
    expect(g.requests.single.fileIds, ['p1', 'p2']);
    expect(g.uncaptioned, 1);
    expect(g.lastUpdateId, 4);
  });

  test('matchRosterNames: exact, then unique initial + surname; ambiguous stays unmatched', () {
    final players = [
      (id: '1', name: 'Luka Doncic'),
      (id: '2', name: 'Jalen Green'),
      (id: '3', name: 'Javonte Green'),
      (id: '4', name: 'Carter Bryant'),
    ];
    final m = matchRosterNames(['Luka Dončić', 'C. Bryant', 'J. Green', 'Nobody Here'], players);
    expect(m.ids, ['1', '4']);
    expect(m.unmatched, ['J. Green', 'Nobody Here']);
  });

  test('upsertTeam replaces by name, case-insensitively, or appends', () {
    final now = DateTime.utc(2026, 10, 25);
    var teams = upsertTeam([], 'ForKobe', ['1'], now);
    teams = upsertTeam(teams, 'forkobe', ['2'], now);
    teams = upsertTeam(teams, 'Alon Tip-Top', ['3'], now);
    expect(teams.map((t) => t['playerIds']), [
      ['2'],
      ['3'],
    ]);
  });

  test('withRemoteTeam fills the first empty Team N slot and moves players off other teams', () {
    const league = LeagueState(teams: [
      LeagueTeam(id: 't1', name: 'Dunk Dynasty', playerIds: ['a', 'b']),
      LeagueTeam(id: 't2', name: 'Team 2'),
      LeagueTeam(id: 't3', name: 'Team 3'),
    ], takenIds: {'c'});
    final next = league.withRemoteTeam((name: 'ForKobe', playerIds: ['b', 'c'], updatedAt: DateTime.utc(2026)))!;
    expect(next.teams[0].playerIds, ['a']);
    expect(next.teams[1].name, 'ForKobe');
    expect(next.teams[1].playerIds, ['b', 'c']);
    expect(next.takenIds, isEmpty);
    expect(next.remoteApplied['forkobe'], isNotNull);
  });
}
