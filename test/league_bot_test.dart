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

  test('groupPhotoMessages joins an album, takes the caption from any photo, ignores other chats', () {
    final g = groupPhotoMessages([
      _photo(1, '42', group: 'a', caption: 'ForKobe', file: 'p1'),
      _photo(2, '42', group: 'a', file: 'p2'),
      _photo(3, '99', caption: 'Intruders', file: 'x'),
      _photo(4, '42', file: 'matchup'),
    ], '42');
    expect(g.groups.map((x) => x.caption), ['ForKobe', null]);
    expect(g.groups.map((x) => x.fileIds), [
      ['p1', 'p2'],
      ['matchup'],
    ]);
    expect(g.lastUpdateId, 4);
  });

  test('upsertMatchup replaces the same week\'s matchup of either team, keeps other weeks', () {
    final now = DateTime.utc(2026);
    Map<String, dynamic> m(int week, String a, String b) => matchupEntry([
          (name: a, stats: {for (final k in statKeys) k: 1}),
          (name: b, stats: {for (final k in statKeys) k: 1}),
        ], week, now);
    var all = upsertMatchup([], m(2, 'A', 'B'));
    all = upsertMatchup(all, m(1, 'A', 'B'));
    all = upsertMatchup(all, m(1, 'C', 'D'));
    all = upsertMatchup(all, m(1, 'b', 'A')); // mid-week update of A vs B
    expect(all.map((x) => x['week']), [1, 1, 2]);
    expect(all.where((x) => x['week'] == 1), hasLength(2));
  });

  test('inferMyName picks the one side that isn\'t a known league team', () {
    final s = {for (final k in statKeys) k: 1};
    expect(inferMyName([(name: 'Ironi shaide', stats: s), (name: 'Alon Tip-Top', stats: s)], ['Alon Tip-Top', 'ForKobe']),
        'Ironi shaide');
    expect(inferMyName([(name: 'ForKobe', stats: s), (name: 'Alon Tip-Top', stats: s)], ['Alon Tip-Top', 'ForKobe']), isNull);
  });

  test('weekFromCaption and matchupScore', () {
    expect(weekFromCaption('Week 3'), 3);
    expect(weekFromCaption(null), isNull);
    final me = {'fgPct': .484, 'ftPct': .758, 'threePM': 60, 'pts': 542, 'reb': 178, 'ast': 106, 'stl': 27, 'blk': 14, 'to': 70};
    final opp = {'fgPct': .497, 'ftPct': .773, 'threePM': 50, 'pts': 523, 'reb': 192, 'ast': 134, 'stl': 29, 'blk': 21, 'to': 86};
    expect(matchupScore(me, opp), (w: 3, l: 6, t: 0));
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
