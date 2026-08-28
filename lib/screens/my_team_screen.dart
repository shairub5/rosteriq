import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/player.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../widgets/category_radar_chart.dart';
import '../widgets/player_avatar.dart';
import 'settings_screen.dart';

class MyTeamScreen extends ConsumerWidget {
  const MyTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedRosterAsync = ref.watch(savedRosterProvider);
    final savedPlayers = ref.watch(savedRosterPlayersProvider);
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return savedRosterAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (savedIds) {
        if (savedIds.isEmpty) {
          return _EmptyTeamScaffold();
        }

        return leagueDataAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
          data: (leagueData) {
            final rankings = ref.watch(rankingsProvider);
            final zByPlayerId = {for (final r in rankings) r.playerId: r.puntAdjustedZ};

            final standing = computeTeamStanding(
              myRoster: savedPlayers,
              fullPoolForBaseline: leagueData.players,
            );

            // All players not on the saved roster, for the add-player dialog.
            final savedIds = ref.watch(savedRosterProvider).value ?? [];
            final savedIdsSet = savedIds.toSet();
            final otherPlayers = leagueData.players
                .where((p) => !savedIdsSet.contains(p.id))
                .toList();

            return Scaffold(
              appBar: AppBar(
                title: const Text('My Team'),
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
                  // --- Radar chart ---
                  const Text(
                    'Category standing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  CategoryRadarChart(
                    standing: standing,
                    puntedCategories: const {},
                  ),
                  const SizedBox(height: 24),

                  // --- Roster list ---
                  Row(
                    children: [
                      Text(
                        'Roster (${savedPlayers.length} players)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear saved team?'),
                              content: const Text(
                                'This will remove your saved roster. You can re-save it from the Draft Recap screen.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await ref.read(savedRosterProvider.notifier).clear();
                          }
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Clear team'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...savedPlayers.map((player) {
                    final z = zByPlayerId[player.id];
                    return _TeamPlayerRow(
                      player: player,
                      z: z,
                      onRemove: () => ref
                          .read(savedRosterProvider.notifier)
                          .removePlayer(player.id),
                    );
                  }),
                  const SizedBox(height: 16),

                  // --- Add Player button ---
                  OutlinedButton.icon(
                    onPressed: () => _showAddPlayerDialog(context, ref, otherPlayers, zByPlayerId),
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Add Player'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddPlayerDialog(
    BuildContext context,
    WidgetRef ref,
    List<Player> candidates,
    Map<String, double> zByPlayerId,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddPlayerDialog(
        candidates: candidates,
        zByPlayerId: zByPlayerId,
        onAdd: (playerId) => ref.read(savedRosterProvider.notifier).addPlayer(playerId),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyTeamScaffold extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Team')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No team saved yet.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Complete a draft and tap "Save My Team" on the recap screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  // Navigate to Draft Board tab (index 2 in the shell).
                  // We pop back to the shell and let the user navigate; a
                  // direct tab-jump would require lifting state, so this is
                  // the minimal safe approach.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Go to the Board tab, tap Recap, then tap "Save My Team".',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.sports_basketball_outlined),
                label: const Text('Go to Draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Roster row
// ---------------------------------------------------------------------------

class _TeamPlayerRow extends StatelessWidget {
  final Player player;
  final double? z;
  final VoidCallback onRemove;

  const _TeamPlayerRow({
    required this.player,
    required this.z,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          PlayerAvatar(
            nbaId: player.nbaId,
            playerName: player.name,
            radius: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  '${player.eligiblePositions.join(",")} · ${player.team}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (z != null)
            Text(
              'Z ${z!.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 12,
                color: z! >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: Colors.red.shade700,
            tooltip: 'Drop player',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
          // Placeholder for future Yahoo sync replace action.
          IconButton(
            icon: const Icon(Icons.swap_horiz_outlined),
            color: Colors.grey.shade400,
            tooltip: 'Replace (coming soon)',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: null, // disabled until Yahoo sync is wired
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-player dialog
// ---------------------------------------------------------------------------

class _AddPlayerDialog extends StatefulWidget {
  final List<Player> candidates;
  final Map<String, double> zByPlayerId;
  final void Function(String playerId) onAdd;

  const _AddPlayerDialog({
    required this.candidates,
    required this.zByPlayerId,
    required this.onAdd,
  });

  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.candidates.take(20).toList()
        : widget.candidates
            .where((p) => p.name.toLowerCase().contains(query))
            .take(20)
            .toList();

    return AlertDialog(
      title: const Text('Add Player'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final player = filtered[i];
                  final z = widget.zByPlayerId[player.id];
                  return ListTile(
                    dense: true,
                    leading: PlayerAvatar(
                      nbaId: player.nbaId,
                      playerName: player.name,
                      radius: 16,
                    ),
                    title: Text(player.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${player.eligiblePositions.join(",")} · ${player.team}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: z != null
                        ? Text(
                            'Z ${z.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: z >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          )
                        : null,
                    onTap: () {
                      widget.onAdd(player.id);
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
