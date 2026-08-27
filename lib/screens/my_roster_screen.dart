import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/team_standing_provider.dart';
import '../widgets/category_standing_bar.dart';

class MyRosterScreen extends ConsumerWidget {
  const MyRosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text('Failed to load player data: $err')),
      data: (leagueData) {
        final draftState = ref.watch(draftStateProvider);
        final myRoster = myRosterFrom(leagueData.players, draftState, leagueData.config.myDraftSlot);
        final standing = ref.watch(teamStandingProvider);
        final totalSlots = leagueData.config.totalRosterSize;

        return Scaffold(
          appBar: AppBar(title: const Text('My Roster')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${myRoster.length} / $totalSlots roster spots filled',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Category standing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              CategoryStandingBar(standing: standing, puntedCategories: draftState.puntedCategories),
              const SizedBox(height: 24),
              const Text('Drafted players', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (myRoster.isEmpty) const Text('No picks yet.', style: TextStyle(color: Colors.grey)),
              for (final player in myRoster)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(player.name),
                  subtitle: Text('${player.eligiblePositions.join(",")} · ${player.team}'),
                ),
            ],
          ),
        );
      },
    );
  }
}
