// Generic snake-draft position math: given a team count and which slot the
// user drafts from, works out whose turn it is and how far away the user's
// next turn is - for ANY draft slot (1st through last), not hardcoded to a
// specific position. Overall pick numbers are 1-indexed.

/// The 1-indexed team slot that is on the clock for [overallPickNumber].
int teamSlotForPick(int overallPickNumber, int teamsCount) {
  final zeroIndexedPick = overallPickNumber - 1;
  final round = zeroIndexedPick ~/ teamsCount; // 0-indexed
  final positionInRound = zeroIndexedPick % teamsCount; // 0-indexed
  final isEvenRound = round % 2 == 0; // round 0 goes 1..N, round 1 goes N..1
  return isEvenRound ? positionInRound + 1 : teamsCount - positionInRound;
}

class SnakePickWindow {
  final bool isMyTurn;
  final int currentPickNumber;
  final List<int> myPicksThisTurn; // usually 1, or 2 for the back-to-back snake turn
  final int picksUntilMyTurn; // 0 if isMyTurn

  const SnakePickWindow({
    required this.isMyTurn,
    required this.currentPickNumber,
    required this.myPicksThisTurn,
    required this.picksUntilMyTurn,
  });
}

/// Computes the current snake-pick context for the user's [myDraftSlot],
/// given the [nextPickNumber] about to happen and [teamsCount]. Every slot
/// except the very first/last gets a "back-to-back" pair of picks at each
/// snake turn (e.g. picks 12 & 13 in a 12-team league for slot 12); slot 1
/// gets its back-to-back at the START of even rounds instead (picks 1 & 24,
/// etc. don't overlap the same way, so this only ever reports the single
/// upcoming pick plus whether a second one immediately follows).
SnakePickWindow computeSnakeWindow({
  required int nextPickNumber,
  required int teamsCount,
  required int myDraftSlot,
}) {
  final currentSlot = teamSlotForPick(nextPickNumber, teamsCount);
  final isMyTurn = currentSlot == myDraftSlot;

  if (isMyTurn) {
    final myPicks = [nextPickNumber];
    final followingSlot = teamSlotForPick(nextPickNumber + 1, teamsCount);
    if (followingSlot == myDraftSlot) {
      myPicks.add(nextPickNumber + 1);
    }
    return SnakePickWindow(
      isMyTurn: true,
      currentPickNumber: nextPickNumber,
      myPicksThisTurn: myPicks,
      picksUntilMyTurn: 0,
    );
  }

  var lookaheadPick = nextPickNumber;
  var picksUntil = 0;
  while (teamSlotForPick(lookaheadPick, teamsCount) != myDraftSlot) {
    lookaheadPick++;
    picksUntil++;
  }
  final myPicks = [lookaheadPick];
  if (teamSlotForPick(lookaheadPick + 1, teamsCount) == myDraftSlot) {
    myPicks.add(lookaheadPick + 1);
  }
  return SnakePickWindow(
    isMyTurn: false,
    currentPickNumber: nextPickNumber,
    myPicksThisTurn: myPicks,
    picksUntilMyTurn: picksUntil,
  );
}
