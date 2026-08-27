import '../models/league_config.dart';
import '../models/player.dart';

/// Soft "no open slot" flag, not a hard filter - a player is only flagged
/// once literally no slot (dedicated, flex, or bench) remains that could
/// hold them. This is a greedy feasibility check, not an optimal assignment
/// solver: it asks "is there any way the CURRENT roster + this new player
/// could all fit," not "what's the best overall assignment." That's fine for
/// a live draft-time badge, where the cost of a false "fits" is much lower
/// than hiding a player the user might actually want.
bool hasOpenSlotFor(
  Player candidate,
  LeagueRosterConfig config,
  List<Player> currentRoster,
) {
  final remainingRoster = [...currentRoster, candidate];
  if (remainingRoster.length > config.totalRosterSize) return false;

  // Build slot instances, then greedily assign the most-constrained players
  // (fewest eligible slots) first.
  final slotInstances = <String>[];
  for (final slot in config.rosterSlots) {
    for (var i = 0; i < slot.count; i++) {
      slotInstances.add(slot.type);
    }
  }

  List<String> eligibleSlotTypesFor(Player p) {
    return slotInstances.toSet().where((slotType) {
      if (p.eligiblePositions.contains(slotType)) return true;
      final flexEligible = flexSlotEligibility[slotType];
      return flexEligible != null && p.eligiblePositions.any(flexEligible.contains);
    }).toList();
  }

  final playersByConstraint = [...remainingRoster]
    ..sort((a, b) => eligibleSlotTypesFor(a).length.compareTo(eligibleSlotTypesFor(b).length));

  final usedSlotIndices = <int>{};
  for (final player in playersByConstraint) {
    final eligibleTypes = eligibleSlotTypesFor(player).toSet();
    int? matchIndex;
    for (var i = 0; i < slotInstances.length; i++) {
      if (usedSlotIndices.contains(i)) continue;
      if (eligibleTypes.contains(slotInstances[i])) {
        matchIndex = i;
        break;
      }
    }
    if (matchIndex == null) return false; // no slot left for this player
    usedSlotIndices.add(matchIndex);
  }
  return true;
}
