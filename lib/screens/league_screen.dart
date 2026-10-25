import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/saved_roster_provider.dart';
import '../widgets/common.dart';
import '../widgets/player_picker_sheet.dart';
import '../widgets/player_row.dart';
import '../worker/espn.dart' show normalizeName;
import 'in_season_shell.dart';
import 'settings_screen.dart';

/// Players sorted by preseason rank, so likely-rostered names come first when entering rosters.
List<Player> byPreseasonRank(List<Player> players) => [...players]
  ..sort((a, b) => (a.sourceRank ?? 9999).compareTo(b.sourceRank ?? 9999));

/// The 12 teams: mine plus the 11 others, entered by hand until Yahoo sync.
class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final leagueData = ref.watch(leagueDataProvider).value;
    final mine = ref.watch(savedRosterProvider).value ?? const [];
    final size = leagueData?.config.totalRosterSize ?? 13;

    return Scaffold(
      appBar: AppBar(title: const Text('League'), actions: const [SettingsButton()]),
      body: AsyncBody(
        value: ref.watch(leagueTeamsProvider),
        builder: (league) {
          final filled = league.teams.where((t) => t.playerIds.length >= size).length + (mine.length >= size ? 1 : 0);
          final teamCount = league.teams.length + 1;
          final myName = leagueData?.myName;
          final myLast = leagueData?.matchups.where((m) => m.a.name == myName || m.b.name == myName).lastOrNull;
          final lastOpponent = myLast == null ? null : (myLast.a.name == myName ? myLast.b.name : myLast.a.name);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$filled of $teamCount rosters complete', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: filled / teamCount, minHeight: 8),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        filled == teamCount
                            ? 'Add/Drop now shows exactly the players nobody has.'
                            : 'Until every roster is in, Add/Drop also hides the top ${teamCount * size} preseason players '
                                'as "probably rostered". Yahoo sync will fill this in automatically later.',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader('Teams'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _TeamTile(
                      name: 'My Team',
                      count: mine.length,
                      size: size,
                      badge: 'You',
                      onTap: () => ref.read(shellTabProvider.notifier).state = ShellTab.myTeam,
                    ),
                    for (final t in league.teams) ...[
                      const Divider(indent: 16),
                      _TeamTile(
                        name: t.name,
                        count: t.playerIds.length,
                        size: size,
                        badge: lastOpponent != null && normalizeName(lastOpponent) == normalizeName(t.name)
                            ? 'Latest matchup'
                            : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TeamEditorScreen(teamId: t.id)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (league.takenIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionHeader('Other'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text('${league.takenIds.length} marked taken, team unknown'),
                    subtitle: const Text('Hidden from Add/Drop'),
                    trailing: TextButton(
                      onPressed: () => ref.read(leagueTeamsProvider.notifier).clearTaken(),
                      child: const Text('Clear'),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final String name;
  final int count;
  final int size;
  final String? badge;
  final VoidCallback onTap;

  const _TeamTile({required this.name, required this.count, required this.size, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = count >= size;
    return ListTile(
      minVerticalPadding: 12,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(complete ? '$count players' : '$count of $size players'),
      trailing: Icon(complete ? Icons.check_circle : Icons.chevron_right,
          color: complete ? theme.colorScheme.primary : null),
    );
  }
}

/// One other team: rename, set as opponent, edit its roster.
class TeamEditorScreen extends ConsumerWidget {
  final String teamId;

  const TeamEditorScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(leagueTeamsProvider).value;
    final team = league?.teams.where((t) => t.id == teamId).firstOrNull;
    final byId = ref.watch(playersByIdProvider);
    if (league == null || team == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final notifier = ref.read(leagueTeamsProvider.notifier);
    final players = team.playerIds.map((id) => byId[id]).whereType<Player>().toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(team.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename team',
            onPressed: () => _rename(context, ref, team.name),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addPlayersToTeam(context, ref, teamId, team.name),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add players'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          SectionHeader('Roster · ${players.length}'),
          if (players.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No players yet. Tap "Add players" and pick from the list, best-ranked first.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, p) in players.indexed) ...[
                    if (i > 0) const Divider(indent: 72),
                    PlayerRow(
                      player: p,
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove ${p.name}',
                        onPressed: () => notifier.togglePlayer(teamId, p.id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await ref.read(leagueTeamsProvider.notifier).rename(teamId, name);
  }
}

/// Picker for one league team's roster. Players on my team are excluded; players
/// on another team are shown with that team's name and move over when picked.
Future<void> addPlayersToTeam(BuildContext context, WidgetRef ref, String teamId, String teamName) {
  final mine = (ref.read(savedRosterProvider).value ?? const []).toSet();
  final all = ref.read(leagueDataProvider).value?.players ?? const [];
  return showPlayerPicker(
    context,
    title: teamName,
    candidates: byPreseasonRank(all.where((p) => !mine.contains(p.id)).toList()),
    selectedIds: (ref) => (ref.watch(leagueTeamsProvider).value?.teams.firstWhere((t) => t.id == teamId).playerIds ?? const []).toSet(),
    onToggle: (ref, id) => ref.read(leagueTeamsProvider.notifier).togglePlayer(teamId, id),
    note: (p) {
      final other = ref.read(leagueTeamsProvider).value?.teamOf(p.id);
      return other == null || other.id == teamId ? null : 'on ${other.name}';
    },
  );
}
