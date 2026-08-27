import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/engine/positional_run_detector.dart';
import 'package:rosteriq/models/draft_state.dart';
import 'package:rosteriq/models/player.dart';

Player _center(String id) => Player(
      id: id,
      name: id,
      team: 'XXX',
      eligiblePositions: const ['C'],
      gp: 70,
      fgPct: 0.5,
      fgAttempted: 500,
      ftPct: 0.7,
      ftAttempted: 100,
      threePM: 0,
      pts: 800,
      reb: 500,
      ast: 50,
      stl: 30,
      blk: 80,
      to: 100,
    );

Player _guard(String id) => Player(
      id: id,
      name: id,
      team: 'XXX',
      eligiblePositions: const ['PG'],
      gp: 70,
      fgPct: 0.45,
      fgAttempted: 500,
      ftPct: 0.85,
      ftAttempted: 200,
      threePM: 150,
      pts: 1200,
      reb: 250,
      ast: 400,
      stl: 90,
      blk: 10,
      to: 150,
    );

void main() {
  test('flags a positional run when a position dominates the recent window', () {
    final players = {
      for (final id in ['c1', 'c2', 'c3', 'c4']) id: _center(id),
      'g1': _guard('g1'),
      'g2': _guard('g2'),
    };
    final picks = [
      const DraftPick(pickNumber: 1, teamSlot: 1, playerId: 'g1'),
      const DraftPick(pickNumber: 2, teamSlot: 2, playerId: 'c1'),
      const DraftPick(pickNumber: 3, teamSlot: 3, playerId: 'c2'),
      const DraftPick(pickNumber: 4, teamSlot: 4, playerId: 'g2'),
      const DraftPick(pickNumber: 5, teamSlot: 5, playerId: 'c3'),
      const DraftPick(pickNumber: 6, teamSlot: 6, playerId: 'c4'),
    ];

    final warning = detectPositionalRun(picks, players, windowSize: 6, threshold: 4);
    expect(warning, isNotNull);
    expect(warning!.position, 'C');
    expect(warning.countInWindow, 4);
  });

  test('does not flag a balanced draft', () {
    final players = {'c1': _center('c1'), 'g1': _guard('g1'), 'g2': _guard('g2')};
    final picks = [
      const DraftPick(pickNumber: 1, teamSlot: 1, playerId: 'g1'),
      const DraftPick(pickNumber: 2, teamSlot: 2, playerId: 'c1'),
      const DraftPick(pickNumber: 3, teamSlot: 3, playerId: 'g2'),
    ];

    final warning = detectPositionalRun(picks, players, windowSize: 6, threshold: 4);
    expect(warning, isNull);
  });

  test('empty draft board returns no warning', () {
    expect(detectPositionalRun([], {}), isNull);
  });
}
