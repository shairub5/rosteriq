import 'package:flutter/material.dart';

import '../models/player.dart';
import 'injury_badge.dart';
import 'player_avatar.dart';

/// Avatar + name + injury badge + "PG/SG · BOS" line, with an optional trailing widget.
class PlayerRow extends StatelessWidget {
  final Player player;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  const PlayerRow({super.key, required this.player, this.trailing, this.below, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              PlayerAvatar(nbaId: player.nbaId, playerName: player.name, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(player.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        InjuryBadge(playerId: player.id),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${player.eligiblePositions.join('/')} · ${player.team}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (below != null) ...[const SizedBox(height: 4), below!],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
