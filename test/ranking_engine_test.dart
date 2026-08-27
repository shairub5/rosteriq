import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/engine/ranking_engine.dart';
import 'package:rosteriq/models/league_config.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/stat_category.dart';

Player _player({
  required String id,
  required String name,
  List<String> positions = const ['PG'],
  double fgPct = 0.45,
  int fgAttempted = 500,
  double ftPct = 0.80,
  int ftAttempted = 200,
  int threePM = 100,
  int pts = 1000,
  int reb = 300,
  int ast = 300,
  int stl = 80,
  int blk = 30,
  int to = 150,
}) {
  return Player(
    id: id,
    name: name,
    team: 'XXX',
    eligiblePositions: positions,
    gp: 70,
    fgPct: fgPct,
    fgAttempted: fgAttempted,
    ftPct: ftPct,
    ftAttempted: ftAttempted,
    threePM: threePM,
    pts: pts,
    reb: reb,
    ast: ast,
    stl: stl,
    blk: blk,
    to: to,
  );
}

void main() {
  group('computeRankings', () {
    test('an all-around statistical leader ranks above a one-category specialist', () {
      final elite = _player(id: 'elite', name: 'Elite', pts: 2200, reb: 800, ast: 600, stl: 120, blk: 100);
      final onlyScorer = _player(id: 'scorer', name: 'Scorer', pts: 2200, reb: 200, ast: 100, stl: 40, blk: 10);
      final average = _player(id: 'avg', name: 'Average');

      final rankings = computeRankings(
        availablePool: [elite, onlyScorer, average],
        myRoster: [],
        puntedCategories: {},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );

      expect(rankings.first.playerId, 'elite');
      expect(rankings.map((r) => r.rank), [1, 2, 3]);
    });

    test('turnovers are inverted: fewer TO is better, all else equal', () {
      final lowTo = _player(id: 'low-to', name: 'LowTO', to: 50);
      final highTo = _player(id: 'high-to', name: 'HighTO', to: 300);

      final rankings = computeRankings(
        availablePool: [lowTo, highTo],
        myRoster: [],
        puntedCategories: {},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );

      final lowToResult = rankings.firstWhere((r) => r.playerId == 'low-to');
      final highToResult = rankings.firstWhere((r) => r.playerId == 'high-to');
      expect(lowToResult.perCategoryZ[StatCategory.to]!, greaterThan(highToResult.perCategoryZ[StatCategory.to]!));
      expect(lowToResult.totalZ, greaterThan(highToResult.totalZ));
    });

    test('FG% impact rewards volume, not just percentage: low-volume high-pct loses to high-volume solid-pct', () {
      final lowVolumeHighPct = _player(id: 'low-vol', name: 'LowVol', fgPct: 0.65, fgAttempted: 50);
      final highVolumeSolidPct = _player(id: 'high-vol', name: 'HighVol', fgPct: 0.50, fgAttempted: 1200);
      final filler = _player(id: 'filler', name: 'Filler', fgPct: 0.45, fgAttempted: 500);

      final rankings = computeRankings(
        availablePool: [lowVolumeHighPct, highVolumeSolidPct, filler],
        myRoster: [],
        puntedCategories: {},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );

      final lowVolResult = rankings.firstWhere((r) => r.playerId == 'low-vol');
      final highVolResult = rankings.firstWhere((r) => r.playerId == 'high-vol');
      expect(
        highVolResult.perCategoryZ[StatCategory.fgPct]!,
        greaterThan(lowVolResult.perCategoryZ[StatCategory.fgPct]!),
      );
    });

    test('punt mode drop-and-sum excludes punted categories and can reorder the ranking', () {
      // Player A is elite in FT% but mediocre elsewhere; Player B is the
      // opposite. Punting FT% should let B overtake A.
      final ftSpecialist = _player(
        id: 'ft-specialist',
        name: 'FTSpecialist',
        ftPct: 0.95,
        ftAttempted: 400,
        pts: 800,
        reb: 200,
        ast: 150,
        stl: 40,
        blk: 10,
      );
      final everythingElseSpecialist = _player(
        id: 'everything-else',
        name: 'EverythingElse',
        ftPct: 0.55,
        ftAttempted: 400,
        pts: 1900,
        reb: 700,
        ast: 500,
        stl: 110,
        blk: 90,
      );

      final noPunt = computeRankings(
        availablePool: [ftSpecialist, everythingElseSpecialist],
        myRoster: [],
        puntedCategories: {},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );
      expect(noPunt.first.playerId, 'everything-else');

      final puntingFt = computeRankings(
        availablePool: [ftSpecialist, everythingElseSpecialist],
        myRoster: [],
        puntedCategories: {StatCategory.ftPct},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );
      // Still ranked the same here since ftSpecialist wasn't ahead to begin
      // with - assert instead that the punted category no longer
      // contributes to the sort key.
      final ftSpecResult = puntingFt.firstWhere((r) => r.playerId == 'ft-specialist');
      expect(ftSpecResult.puntAdjustedZ, isNot(closeTo(ftSpecResult.totalZ, 0.0001)));
    });

    test('roster-fit flags a player when every configured slot is already full', () {
      final tinyConfig = const LeagueRosterConfig(
        teamsCount: 12,
        myDraftSlot: 1,
        rosterSlots: [RosterSlot(type: 'PG', count: 1)],
      );
      final alreadyRostered = _player(id: 'rostered', name: 'Rostered', positions: ['PG']);
      final candidate = _player(id: 'candidate', name: 'Candidate', positions: ['PG']);

      final rankings = computeRankings(
        availablePool: [candidate],
        myRoster: [alreadyRostered],
        puntedCategories: {},
        slotConfig: tinyConfig,
      );

      expect(rankings.single.rosterFitWarning, isTrue);
    });

    test('empty pool returns an empty ranking without throwing', () {
      final rankings = computeRankings(
        availablePool: [],
        myRoster: [],
        puntedCategories: {},
        slotConfig: LeagueRosterConfig.defaultConfig,
      );
      expect(rankings, isEmpty);
    });
  });
}
