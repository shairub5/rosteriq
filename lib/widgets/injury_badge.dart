import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/league_data_provider.dart';
import '../theme.dart';

/// "OUT" / "DTD" chip from the live ESPN injury report; nothing when healthy.
/// Icon + text, so the status never relies on color alone.
class InjuryBadge extends ConsumerWidget {
  final String playerId;

  const InjuryBadge({super.key, required this.playerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injury = ref.watch(leagueDataProvider).value?.injuries[playerId];
    if (injury == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final out = injury.status == 'Out';
    final fg = out ? colors.onErrorContainer : context.stat.onWarnContainer;
    return Tooltip(
      message: '${injury.status}: ${injury.detail}${injury.returnDate == null ? '' : ' (back ~${injury.returnDate})'}',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: out ? colors.errorContainer : context.stat.warnContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(out ? Icons.local_hospital : Icons.warning_amber, size: 12, color: fg),
            const SizedBox(width: 3),
            Text(
              out ? 'OUT' : 'DTD',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
