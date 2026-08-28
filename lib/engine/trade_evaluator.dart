import '../models/player.dart';
import '../models/stat_category.dart';
import 'ranking_engine.dart';

/// Per-category breakdown of a trade evaluation.
class TradeCategoryRow {
  final StatCategory category;
  final double myTeamBefore;
  final double myTeamAfter;
  final double myDelta; // after - before
  final double oppTeamAfter;

  const TradeCategoryRow({
    required this.category,
    required this.myTeamBefore,
    required this.myTeamAfter,
    required this.myDelta,
    required this.oppTeamAfter,
  });
}

class TradeResult {
  final List<TradeCategoryRow> rows;
  final int winsCount; // categories where myDelta > 0
  final int lossCount; // categories where myDelta < 0
  final int tieCount; // categories where myDelta == 0

  const TradeResult({
    required this.rows,
    required this.winsCount,
    required this.lossCount,
    required this.tieCount,
  });
}

/// Evaluates a trade from the perspective of the user.
///
/// [myCurrentRoster]     - the user's players before the trade
/// [playersIGive]        - players the user sends away
/// [playersIGet]         - players the user receives
/// [fullPoolForBaseline] - the full player list used as the z-score baseline
///
/// Uses [computeTeamStanding] so the z-score baseline is consistent with
/// every other part of the app.
TradeResult evaluateTrade({
  required List<Player> myCurrentRoster,
  required List<Player> playersIGive,
  required List<Player> playersIGet,
  required List<Player> fullPoolForBaseline,
}) {
  // The opponent's hypothetical roster is the players I give (simplified:
  // we only know their side of the trade, not their full roster, so we
  // evaluate the incremental value of the inbound players to that side).
  final giveIds = playersIGive.map((p) => p.id).toSet();
  final myRosterAfter = [
    ...myCurrentRoster.where((p) => !giveIds.contains(p.id)),
    ...playersIGet,
  ];

  final before = computeTeamStanding(
    myRoster: myCurrentRoster,
    fullPoolForBaseline: fullPoolForBaseline,
  );
  final after = computeTeamStanding(
    myRoster: myRosterAfter,
    fullPoolForBaseline: fullPoolForBaseline,
  );
  // Opponent side: treat playersIGet as if added to an empty roster
  // (relative boost that side gains).
  final oppAfter = computeTeamStanding(
    myRoster: playersIGet,
    fullPoolForBaseline: fullPoolForBaseline,
  );

  int wins = 0, losses = 0, ties = 0;
  final rows = <TradeCategoryRow>[];
  for (final cat in allStatCategories) {
    final myBefore = before[cat] ?? 0;
    final myAfterZ = after[cat] ?? 0;
    final delta = myAfterZ - myBefore;
    if (delta > 0.01) {
      wins++;
    } else if (delta < -0.01) {
      losses++;
    } else {
      ties++;
    }
    rows.add(TradeCategoryRow(
      category: cat,
      myTeamBefore: myBefore,
      myTeamAfter: myAfterZ,
      myDelta: delta,
      oppTeamAfter: oppAfter[cat] ?? 0,
    ));
  }

  return TradeResult(rows: rows, winsCount: wins, lossCount: losses, tieCount: ties);
}
