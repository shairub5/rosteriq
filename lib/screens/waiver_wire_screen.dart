import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../widgets/player_avatar.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../state/schedule_provider.dart';
import 'settings_screen.dart';

class WaiverWireScreen extends ConsumerWidget {
  const WaiverWireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (leagueData) {
        final savedPlayers = ref.watch(savedRosterPlayersProvider);
        final rankings = ref.watch(rankingsProvider);
        final playersById = ref.watch(playersByIdProvider);
        final schedule = ref.watch(scheduleProvider).value;
        final today = DateTime.now();

        if (savedPlayers.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Waiver Wire')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_add_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No saved team yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Draft your team, then save it from the Recap tab. '
                      'Need Impact scores will be personalised to your weaknesses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final standing = computeTeamStanding(
          myRoster: savedPlayers,
          fullPoolForBaseline: leagueData.players,
        );

        final savedIds = savedPlayers.map((p) => p.id).toSet();

        // Waiver candidates: not on my team, sorted by needImpact desc.
        final candidates = rankings
            .where((r) => !savedIds.contains(r.playerId))
            .toList()
          ..sort((a, b) => b.needImpact.compareTo(a.needImpact));

        // Weak categories (standing < 0), worst first.
        final weakCats = [...allStatCategories]
          ..sort((a, b) => (standing[a] ?? 0).compareTo(standing[b] ?? 0));
        final top3Weak = weakCats
            .where((c) => (standing[c] ?? 0) < 0)
            .take(3)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Waiver Wire'),
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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (top3Weak.isNotEmpty)
                _WeaknessHeader(weakCats: top3Weak, standing: standing),

              Padding(
                padding: const EdgeInsets.fromLTRB(72, 4, 16, 2),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    SizedBox(
                      width: 40,
                      child: Text(
                        'Z',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 52,
                      child: Text(
                        'Need',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 52),
                  ],
                ),
              ),

              Expanded(
                child: candidates.isEmpty
                    ? const Center(child: Text('No players available.'))
                    : ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final ranking = candidates[index];
                          final player = playersById[ranking.playerId];
                          if (player == null) return const SizedBox.shrink();

                          final teamSched = schedule?.teams[player.team];
                          final gamesThisWeek = teamSched?.gamesThisWeek(today);

                          final helpCats = allStatCategories
                              .where((c) =>
                                  (ranking.perCategoryZ[c] ?? 0) > 0.2 &&
                                  (standing[c] ?? 0) < 0)
                              .toList()
                            ..sort((a, b) => (ranking.perCategoryZ[b] ?? 0)
                                .compareTo(ranking.perCategoryZ[a] ?? 0));
                          final topHelp = helpCats.take(2).toList();

                          return _WaiverTile(
                            rank: index + 1,
                            player: player,
                            totalZ: ranking.totalZ,
                            needImpact: ranking.needImpact,
                            gamesThisWeek: gamesThisWeek,
                            helpCategories: topHelp,
                            onAdd: () => _showAddDropSheet(
                              context,
                              ref,
                              addPlayer: player,
                              myRoster: savedPlayers,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddDropSheet(
    BuildContext context,
    WidgetRef ref, {
    required Player addPlayer,
    required List<Player> myRoster,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddDropSheet(
        addPlayer: addPlayer,
        myRoster: myRoster,
        onConfirm: (dropPlayer) async {
          Navigator.of(ctx).pop();
          final notifier = ref.read(savedRosterProvider.notifier);
          if (dropPlayer != null) {
            await notifier.removePlayer(dropPlayer.id);
          }
          await notifier.addPlayer(addPlayer.id);
          if (context.mounted) {
            final msg = dropPlayer != null
                ? 'Added ${addPlayer.name}, dropped ${dropPlayer.name}'
                : '${addPlayer.name} added to My Team';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await notifier.removePlayer(addPlayer.id);
                    if (dropPlayer != null) {
                      await notifier.addPlayer(dropPlayer.id);
                    }
                  },
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

/// Bottom sheet for picking who to drop (or just adding without a drop).
class _AddDropSheet extends StatefulWidget {
  final Player addPlayer;
  final List<Player> myRoster;
  final void Function(Player? dropPlayer) onConfirm;

  const _AddDropSheet({
    required this.addPlayer,
    required this.myRoster,
    required this.onConfirm,
  });

  @override
  State<_AddDropSheet> createState() => _AddDropSheetState();
}

class _AddDropSheetState extends State<_AddDropSheet> {
  Player? _selectedDrop;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  const Icon(Icons.add_circle, color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add ${widget.addPlayer.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                '${widget.addPlayer.eligiblePositions.join(",")} · ${widget.addPlayer.team}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),

              const Text(
                'Drop a player (optional):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _DropOption(
                      label: 'Add only — no drop',
                      subtitle: null,
                      selected: _selectedDrop == null,
                      onTap: () => setState(() => _selectedDrop = null),
                    ),
                    const Divider(height: 1),
                    ...widget.myRoster.map((player) => _DropOption(
                          label: player.name,
                          subtitle:
                              '${player.eligiblePositions.join(",")} · ${player.team}',
                          selected: _selectedDrop?.id == player.id,
                          onTap: () => setState(() => _selectedDrop = player),
                          trailing: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                        )),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => widget.onConfirm(_selectedDrop),
                  icon: const Icon(Icons.check),
                  label: Text(
                    _selectedDrop != null
                        ? 'Add ${widget.addPlayer.name} / Drop ${_selectedDrop!.name}'
                        : 'Add ${widget.addPlayer.name}',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeaknessHeader extends StatelessWidget {
  final List<StatCategory> weakCats;
  final Map<StatCategory, double> standing;

  const _WeaknessHeader({required this.weakCats, required this.standing});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.trending_down, size: 16, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Text(
            'Weakest: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.orange[800],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: weakCats.map((cat) {
                final z = standing[cat] ?? 0;
                return Chip(
                  label: Text(
                    '${cat.label} ${z.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: Colors.orange.shade100,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaiverTile extends StatelessWidget {
  final int rank;
  final Player player;
  final double totalZ;
  final double needImpact;
  final int? gamesThisWeek;
  final List<StatCategory> helpCategories;
  final VoidCallback onAdd;

  const _WaiverTile({
    required this.rank,
    required this.player,
    required this.totalZ,
    required this.needImpact,
    required this.gamesThisWeek,
    required this.helpCategories,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: PlayerAvatar(
        nbaId: player.nbaId,
        playerName: player.name,
        radius: 22,
      ),
      title: Text(
        player.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${player.eligiblePositions.join(",")} · ${player.team}'),
              if (gamesThisWeek != null) ...[
                const SizedBox(width: 8),
                _GamesChip(games: gamesThisWeek!),
              ],
            ],
          ),
          if (helpCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.arrow_upward, size: 11, color: Colors.teal[600]),
                  const SizedBox(width: 2),
                  Text(
                    helpCategories.map((c) => c.label).join(', '),
                    style: TextStyle(fontSize: 11, color: Colors.teal[700]),
                  ),
                ],
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              totalZ.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 52,
            child: Text(
              needImpact.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.teal),
            tooltip: 'Add / Drop',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _DropOption extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DropOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
        size: 20,
      ),
      title: Text(label),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: trailing,
      onTap: onTap,
      selected: selected,
    );
  }
}

class _GamesChip extends StatelessWidget {
  final int games;

  const _GamesChip({required this.games});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (games >= 3) {
      bg = Colors.green[700]!;
    } else if (games == 2) {
      bg = Colors.amber[700]!;
    } else {
      bg = Colors.grey[400]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        '${games}G',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}
