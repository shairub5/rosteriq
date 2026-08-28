import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import 'settings_screen.dart';
import '../state/team_names_provider.dart';
import 'draft_recap_screen.dart';

class DraftBoardScreen extends ConsumerWidget {
  const DraftBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text('Failed to load player data: $err')),
      data: (leagueData) {
        final draftState = ref.watch(draftStateProvider);
        final playersById = ref.watch(playersByIdProvider);
        final teamNames = ref.watch(teamNamesProvider);
        final picks = draftState.picks.reversed.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Draft Board'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.summarize_outlined, size: 18),
                label: const Text('Recap'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DraftRecapScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo last pick',
                onPressed: draftState.picks.isEmpty
                    ? null
                    : () => ref.read(draftStateProvider.notifier).undoLastPick(),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: picks.isEmpty
              ? const Center(child: Text('No picks recorded yet.'))
              : ListView.builder(
                  itemCount: picks.length,
                  itemBuilder: (context, index) {
                    final pick = picks[index];
                    final player = playersById[pick.playerId];
                    final isMe = pick.teamSlot == leagueData.config.myDraftSlot;
                    return ListTile(
                      leading: CircleAvatar(child: Text('${pick.pickNumber}')),
                      title: Text(player?.name ?? pick.playerId),
                      subtitle: Text(displayNameForSlot(teamNames, pick.teamSlot, leagueData.config.myDraftSlot)),
                      tileColor: isMe ? Colors.green.withValues(alpha: 0.08) : null,
                    );
                  },
                ),
        );
      },
    );
  }
}
