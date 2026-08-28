import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../engine/roster_fit.dart';
import 'settings_screen.dart';
import '../models/player.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/team_standing_provider.dart';
import '../widgets/category_radar_chart.dart';

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

        final slotAssignments = assignRosterSlots(leagueData.config, myRoster);

        // Partition into starters (non-BN) and bench (BN).
        final starterSlots = slotAssignments.where((s) => !s.slotLabel.startsWith('BN')).toList();
        final benchSlots = slotAssignments.where((s) => s.slotLabel.startsWith('BN')).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Roster'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
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
              CategoryRadarChart(standing: standing, puntedCategories: draftState.puntedCategories),
              const SizedBox(height: 24),
              const Text('Starters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final slot in starterSlots)
                _SlotRow(slotLabel: slot.slotLabel, player: slot.player),
              const SizedBox(height: 16),
              const Text('Bench', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final slot in benchSlots)
                _SlotRow(slotLabel: slot.slotLabel, player: slot.player),
            ],
          ),
        );
      },
    );
  }
}

class _SlotRow extends StatelessWidget {
  final String slotLabel;
  final Player? player;

  const _SlotRow({required this.slotLabel, required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              slotLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: player != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player!.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${player!.eligiblePositions.join(",")} · ${player!.team}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  )
                : Text(
                    'Empty',
                    style: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                  ),
          ),
        ],
      ),
    );
  }
}
