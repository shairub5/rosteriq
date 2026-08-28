import '../models/league_config.dart';
import '../models/player.dart';

bool canFillSlotType(Player player, String slotType) {
  if (player.eligiblePositions.contains(slotType)) return true;
  final flex = flexSlotEligibility[slotType];
  return flex != null && player.eligiblePositions.any(flex.contains);
}

/// Returns the slot types (e.g. ["UTIL", "BN", "C"]) that are unfilled given
/// the current roster. Uses the same greedy assignment as [assignRosterSlots].
List<String> openSlotTypesFor(LeagueRosterConfig config, List<Player> roster) {
  final slotTypes = <String>[];
  for (final slot in config.rosterSlots) {
    for (var i = 0; i < slot.count; i++) {
      slotTypes.add(slot.type);
    }
  }

  List<String> eligibleFor(Player p) => slotTypes.toSet().where((t) => canFillSlotType(p, t)).toList();

  final byConstraint = [...roster]..sort((a, b) => eligibleFor(a).length.compareTo(eligibleFor(b).length));
  final used = <int>{};
  for (final player in byConstraint) {
    final eligible = eligibleFor(player).toSet();
    for (var i = 0; i < slotTypes.length; i++) {
      if (used.contains(i)) continue;
      if (eligible.contains(slotTypes[i])) {
        used.add(i);
        break;
      }
    }
  }
  return [for (var i = 0; i < slotTypes.length; i++) if (!used.contains(i)) slotTypes[i]];
}

/// Returns the greedy slot-to-player assignment for the current roster as a
/// list of (slotLabel, player?) pairs in the order slots appear in [config].
/// Each element is a record with [slotLabel] (e.g. "PG", "BN 1") and
/// [player] (null if the slot is empty). Uses the same greedy most-constrained-
/// first logic as [hasOpenSlotFor], so results are consistent with the warning
/// badge shown on the pool screen.
List<({String slotLabel, Player? player})> assignRosterSlots(
  LeagueRosterConfig config,
  List<Player> roster,
) {
  // Build the flat list of slot instances (type + label).
  final slotTypes = <String>[];
  final slotLabels = <String>[];
  for (final slot in config.rosterSlots) {
    for (var i = 0; i < slot.count; i++) {
      slotTypes.add(slot.type);
      slotLabels.add(slot.count > 1 ? '${slot.type} ${i + 1}' : slot.type);
    }
  }

  List<String> eligibleSlotTypesFor(Player p) {
    return slotTypes.toSet().where((slotType) {
      if (p.eligiblePositions.contains(slotType)) return true;
      final flexEligible = flexSlotEligibility[slotType];
      return flexEligible != null && p.eligiblePositions.any(flexEligible.contains);
    }).toList();
  }

  // Assign most-constrained players first (same approach as hasOpenSlotFor).
  final playersByConstraint = [...roster]
    ..sort((a, b) => eligibleSlotTypesFor(a).length.compareTo(eligibleSlotTypesFor(b).length));

  final slotAssignment = List<Player?>.filled(slotTypes.length, null);
  final usedSlotIndices = <int>{};

  for (final player in playersByConstraint) {
    final eligibleTypes = eligibleSlotTypesFor(player).toSet();
    for (var i = 0; i < slotTypes.length; i++) {
      if (usedSlotIndices.contains(i)) continue;
      if (eligibleTypes.contains(slotTypes[i])) {
        slotAssignment[i] = player;
        usedSlotIndices.add(i);
        break;
      }
    }
    // If no slot found the player simply goes unassigned (shouldn't happen for
    // a valid roster, but we don't crash - the slot view will just show empty).
  }

  return [
    for (var i = 0; i < slotTypes.length; i++)
      (slotLabel: slotLabels[i], player: slotAssignment[i]),
  ];
}

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
