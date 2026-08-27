import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/engine/snake_position.dart';

void main() {
  group('teamSlotForPick', () {
    test('round 1 goes straight 1..N', () {
      for (var pick = 1; pick <= 12; pick++) {
        expect(teamSlotForPick(pick, 12), pick);
      }
    });

    test('round 2 reverses N..1', () {
      expect(teamSlotForPick(13, 12), 12);
      expect(teamSlotForPick(14, 12), 11);
      expect(teamSlotForPick(24, 12), 1);
    });

    test('round 3 goes straight again', () {
      expect(teamSlotForPick(25, 12), 1);
      expect(teamSlotForPick(36, 12), 12);
    });
  });

  group('computeSnakeWindow - last-slot drafter (e.g. 12th of 12)', () {
    const teamsCount = 12;
    const myDraftSlot = 12;

    test('gets a back-to-back pair at the turn (picks 12 & 13)', () {
      final window = computeSnakeWindow(
        nextPickNumber: 12,
        teamsCount: teamsCount,
        myDraftSlot: myDraftSlot,
      );
      expect(window.isMyTurn, isTrue);
      expect(window.myPicksThisTurn, [12, 13]);
    });

    test('counts down correctly from an early pick', () {
      final window = computeSnakeWindow(
        nextPickNumber: 1,
        teamsCount: teamsCount,
        myDraftSlot: myDraftSlot,
      );
      expect(window.isMyTurn, isFalse);
      expect(window.picksUntilMyTurn, 11);
      expect(window.myPicksThisTurn, [12, 13]);
    });
  });

  group('computeSnakeWindow - first-slot drafter (generic, not hardcoded to last)', () {
    const teamsCount = 12;
    const myDraftSlot = 1;

    test('single pick at the very start, no back-to-back yet', () {
      final window = computeSnakeWindow(
        nextPickNumber: 1,
        teamsCount: teamsCount,
        myDraftSlot: myDraftSlot,
      );
      expect(window.isMyTurn, isTrue);
      expect(window.myPicksThisTurn, [1]);
    });

    test('gets a back-to-back later at the round 2/3 boundary (picks 24 & 25)', () {
      final window = computeSnakeWindow(
        nextPickNumber: 14,
        teamsCount: teamsCount,
        myDraftSlot: myDraftSlot,
      );
      expect(window.isMyTurn, isFalse);
      expect(window.myPicksThisTurn, [24, 25]);
    });
  });

  group('computeSnakeWindow - a middle slot (e.g. 6th of 12)', () {
    test('works the same generic way', () {
      final window = computeSnakeWindow(
        nextPickNumber: 1,
        teamsCount: 12,
        myDraftSlot: 6,
      );
      expect(window.isMyTurn, isFalse);
      expect(window.picksUntilMyTurn, 5);
      // Round 1 pick 6, round 2 pick (12+ (12-6+1))=19 -> not adjacent, so no back-to-back yet.
      expect(window.myPicksThisTurn, [6]);
    });
  });
}
