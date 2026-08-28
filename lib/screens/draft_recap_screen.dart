import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../state/team_standing_provider.dart';
import '../widgets/category_radar_chart.dart';

String _grade(double z) {
  if (z > 1.5) return 'A';
  if (z > 0.5) return 'B';
  if (z > -0.5) return 'C';
  if (z > -1.5) return 'D';
  return 'F';
}

Color _gradeColor(String grade) {
  switch (grade) {
    case 'A':
      return Colors.green.shade700;
    case 'B':
      return Colors.lightGreen.shade600;
    case 'C':
      return Colors.orange.shade600;
    case 'D':
      return Colors.deepOrange.shade600;
    default:
      return Colors.red.shade700;
  }
}

class DraftRecapScreen extends ConsumerWidget {
  const DraftRecapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (leagueData) {
        final draftState = ref.watch(draftStateProvider);
        final standing = ref.watch(teamStandingProvider);
        final rankings = ref.watch(rankingsProvider);
        final playersById = ref.watch(playersByIdProvider);
        final savedRosterAsync = ref.watch(savedRosterProvider);

        // My picks in pick order.
        final myPicks = draftState.picks
            .where((p) => p.teamSlot == leagueData.config.myDraftSlot)
            .toList();

        // Build a z-score lookup: playerId -> puntAdjustedZ from rankings.
        final zByPlayerId = {for (final r in rankings) r.playerId: r.puntAdjustedZ};

        // Strengths and weaknesses: sort categories by standing.
        final sortedCats = [...allStatCategories]
          ..sort((a, b) => (standing[b] ?? 0).compareTo(standing[a] ?? 0));
        final top3 = sortedCats.take(3).toList();
        final bottom3 = sortedCats.reversed.take(3).toList();

        // Build a plain-text summary for clipboard sharing.
        String buildSummary() {
          final buf = StringBuffer();
          buf.writeln('--- RosterIQ Draft Recap ---');
          buf.writeln();
          buf.writeln('My picks:');
          for (var i = 0; i < myPicks.length; i++) {
            final pick = myPicks[i];
            final player = playersById[pick.playerId];
            final z = zByPlayerId[pick.playerId]?.toStringAsFixed(1) ?? '?';
            buf.writeln('  Pick ${pick.pickNumber}: ${player?.name ?? pick.playerId} (Z=$z)');
          }
          buf.writeln();
          buf.writeln('Category grades:');
          for (final cat in allStatCategories) {
            final z = standing[cat] ?? 0;
            buf.writeln('  ${cat.label}: ${z.toStringAsFixed(2)} (${_grade(z)})');
          }
          buf.writeln();
          buf.writeln('Strengths: ${top3.map((c) => c.label).join(', ')}');
          buf.writeln('Weaknesses: ${bottom3.map((c) => c.label).join(', ')}');
          return buf.toString();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Draft Recap'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy summary to clipboard',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: buildSummary()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Summary copied to clipboard')),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Category Radar ---
              const Text(
                'Team standing',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              CategoryRadarChart(
                standing: standing,
                puntedCategories: draftState.puntedCategories,
              ),
              const SizedBox(height: 20),

              // --- Category Grades ---
              const Text(
                'Category grades',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...allStatCategories.map((cat) {
                final z = standing[cat] ?? 0;
                final grade = _grade(z);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 32,
                        child: Text(
                          grade,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _gradeColor(grade),
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        z.toStringAsFixed(2),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              // --- Strengths / Weaknesses ---
              Row(
                children: [
                  Expanded(
                    child: _StrengthsCard(
                      title: 'Strengths',
                      categories: top3,
                      standing: standing,
                      color: Colors.green.shade700,
                      icon: Icons.trending_up,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StrengthsCard(
                      title: 'Weaknesses',
                      categories: bottom3,
                      standing: standing,
                      color: Colors.red.shade700,
                      icon: Icons.trending_down,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Save My Team ---
              _SaveTeamButton(
                myPickIds: myPicks.map((p) => p.playerId).toList(),
                savedRosterAsync: savedRosterAsync,
              ),
              const SizedBox(height: 20),

              // --- Pick List ---
              const Text(
                'My picks',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (myPicks.isEmpty)
                const Text('No picks recorded yet.', style: TextStyle(color: Colors.grey))
              else
                ...myPicks.map((pick) {
                  final player = playersById[pick.playerId];
                  final z = zByPlayerId[pick.playerId];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            '#${pick.pickNumber}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player?.name ?? pick.playerId,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              if (player != null)
                                Text(
                                  '${player.eligiblePositions.join(",")} · ${player.team}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ),
                        if (z != null)
                          Text(
                            'Z ${z.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: z >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _SaveTeamButton extends ConsumerWidget {
  final List<String> myPickIds;
  final AsyncValue<List<String>> savedRosterAsync;

  const _SaveTeamButton({
    required this.myPickIds,
    required this.savedRosterAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alreadySaved = (savedRosterAsync.value ?? []).isNotEmpty;

    Future<void> onSave() async {
      if (alreadySaved) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace saved team?'),
            content: const Text(
              'This will replace your previously saved roster with your current draft picks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      await ref.read(savedRosterProvider.notifier).saveRoster(myPickIds);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Team saved! You can now use Trade and Waiver tools with your roster.',
            ),
          ),
        );
      }
    }

    if (myPickIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save_outlined),
          label: Text(alreadySaved ? 'Update Saved Team' : 'Save My Team'),
        ),
        if (alreadySaved)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A team is already saved. Tapping above will replace it.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _StrengthsCard extends StatelessWidget {
  final String title;
  final List<StatCategory> categories;
  final Map<StatCategory, double> standing;
  final Color color;
  final IconData icon;

  const _StrengthsCard({
    required this.title,
    required this.categories,
    required this.standing,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            ...categories.map((cat) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(cat.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Text(
                        (standing[cat] ?? 0).toStringAsFixed(1),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
