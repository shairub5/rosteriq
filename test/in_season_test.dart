import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/stat_category.dart';
import 'package:rosteriq/screens/matchup_screen.dart';
import 'package:rosteriq/services/player_repository.dart';
import 'package:rosteriq/state/ranking_provider.dart';
import 'package:rosteriq/theme.dart';
import 'package:rosteriq/widgets/category_radar_chart.dart';

Map<String, dynamic> _json(String id, String name, {int gp = 5, int pts = 100}) => {
      'id': id,
      'name': name,
      'team': 'SAS',
      'eligiblePositions': ['C'],
      'gp': gp,
      'fgPct': 0.5,
      'fgAttempted': 80,
      'ftPct': 0.8,
      'ftAttempted': 30,
      'threePM': 10,
      'pts': pts,
      'reb': 50,
      'ast': 20,
      'stl': 5,
      'blk': 15,
      'to': 12,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mergeSnapshot', () {
    final bundled = [
      Player.fromJson({..._json('victor-wembanyama', 'Victor Wembanyama', gp: 70, pts: 1800), 'nbaId': 1641705, 'careerGpHistory': [71]}),
      Player.fromJson(_json('injured-guy', 'Injured Guy', gp: 60)),
    ];
    final snapshot = {
      'updatedAt': '2026-10-25T10:00:00Z',
      'players': [
        _json('5104157', 'Victor Wembanyama'),
        _json('999', 'Rookie Unknown'),
      ],
      'injuries': [
        {'playerId': '5104157', 'name': 'Victor Wembanyama', 'team': 'SAS', 'position': 'C', 'status': 'Day-To-Day', 'detail': 'Ankle'},
      ],
    };

    test('re-keys matched players to bundled ids, keeping headshot + career GP and live stats', () async {
      final config = (await loadLeagueData(client: MockClient((_) async => http.Response('', 500)))).config;
      final data = mergeSnapshot(bundled, config, snapshot);
      final byId = {for (final p in data.players) p.id: p};

      final wemby = byId['victor-wembanyama']!;
      expect(wemby.nbaId, 1641705);
      expect(wemby.careerGpHistory, [71]);
      expect(wemby.pts, 100); // live season-to-date, not the 1800 projection
      expect(byId['999']!.name, 'Rookie Unknown'); // unmatched keeps the ESPN id
      expect(byId['injured-guy']!.gp, 0); // not in snapshot: kept, zeroed
      expect(data.injuries['victor-wembanyama']!.status, 'Day-To-Day');
      expect(data.updatedAt, DateTime.utc(2026, 10, 25, 10));
    });

    test('falls back to initial + surname for OCR-garbled names, only when unambiguous', () async {
      final config = (await loadLeagueData(client: MockClient((_) async => http.Response('', 500)))).config;
      final data = mergeSnapshot(
        [
          Player.fromJson(_json('c-bryant', 'C. Bryant')),
          Player.fromJson(_json('josh-green', 'Josh Green')),
          Player.fromJson({..._json('terance-mann', 'Terance Mann'), 'team': 'BKN'}),
        ],
        config,
        {
          'updatedAt': '2026-10-25T10:00:00Z',
          'players': [
            {..._json('1', 'Carter Bryant'), 'team': 'SA'}, // ESPN code, mapped to SAS
            _json('2', 'Jalen Green'),
            _json('3', 'Javonte Green'),
            {..._json('4', 'Tre Mann'), 'team': 'WSH'}, // different player, different team
          ],
          'injuries': [],
        },
      );
      final byId = {for (final p in data.players) p.id: p};
      expect(byId.keys, containsAll(['c-bryant', '2', '3', 'josh-green', '4', 'terance-mann']));
      expect(byId.keys, isNot(contains('1')));
      expect(byId['c-bryant']!.team, 'SAS');
      expect(byId['4']!.team, 'WAS');
      expect(byId['terance-mann']!.gp, 0);
    });
  });

  group('loadLeagueData', () {
    test('falls back to bundled projections when the snapshot fetch fails', () async {
      final data = await loadLeagueData(client: MockClient((_) async => http.Response('nope', 404)));
      expect(data.updatedAt, isNull);
      expect(data.injuries, isEmpty);
      expect(data.players, isNotEmpty);
    });

    test('uses the snapshot when the fetch succeeds', () async {
      final body = jsonEncode({'updatedAt': '2026-10-25T10:00:00Z', 'players': [_json('1', 'Some Player')], 'injuries': []});
      final data = await loadLeagueData(client: MockClient((_) async => http.Response(body, 200)));
      expect(data.updatedAt, isNotNull);
    });
  });

  test('categoryOutcome treats near-equal standings as a tie', () {
    expect(categoryOutcome(1.0, 0.5), CategoryOutcome.win);
    expect(categoryOutcome(0.5, 1.0), CategoryOutcome.loss);
    expect(categoryOutcome(1.0, 1.05), CategoryOutcome.tie);
  });

  testWidgets('radar shows a legend only with an opponent', (tester) async {
    final standing = {for (final c in allStatCategories) c: 1.0};
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: CategoryRadarChart(standing: standing, puntedCategories: const {})),
    ));
    expect(find.text('Opponent'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: CategoryRadarChart(standing: standing, puntedCategories: const {}, opponent: standing)),
    ));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Opponent'), findsOneWidget);
  });

  testWidgets('matchup table labels results with text, and punts as Punt', (tester) async {
    final you = {for (final c in allStatCategories) c: 1.0};
    final opp = {...you, StatCategory.pts: 2.0, StatCategory.reb: 0.0};
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: MatchupTable(you: you, opp: opp, punted: const {StatCategory.ftPct})),
    ));
    expect(find.text('W'), findsOneWidget); // reb
    expect(find.text('L'), findsOneWidget); // pts
    expect(find.text('Punt'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(6));
  });

  test('likelyRosteredIds takes the top N by preseason rank and ignores unranked players', () {
    final players = [
      Player.fromJson({..._json('a', 'A'), 'sourceRank': 3}),
      Player.fromJson({..._json('b', 'B'), 'sourceRank': 1}),
      Player.fromJson({..._json('c', 'C'), 'sourceRank': 2}),
      Player.fromJson(_json('d', 'D')),
    ];
    expect(likelyRosteredIds(players, 2), {'b', 'c'});
  });
}
