import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/current_league_provider.dart';
import '../state/league_data_provider.dart';

/// App-bar title with the selected league underneath; tapping it switches league.
/// Just the title when there's only one league.
class LeagueTitle extends ConsumerWidget {
  final String title;

  const LeagueTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final leagues = ref.watch(leagueDataProvider).value?.leagues ?? const [];
    if (leagues.length < 2) return Text(title);
    final current = ref.watch(currentLeagueProvider);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('League', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: current.id,
                onChanged: (id) {
                  if (id != null) ref.read(selectedLeagueIdProvider.notifier).select(id);
                  Navigator.of(ctx).pop();
                },
                child: Column(
                  children: [
                    for (final l in leagues)
                      RadioListTile<String>(
                        value: l.id,
                        title: Text(l.name),
                        subtitle: Text(l.myName == null ? 'My team not known yet' : 'My team: ${l.myName}'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    current.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
