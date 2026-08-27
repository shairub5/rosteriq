import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/league_data_provider.dart';
import '../state/team_names_provider.dart';
import 'draft_home_shell.dart';

/// Shown before entering the draft: lets the user name the other teams in
/// the league (their own slot is always "You") so picks/board/team-picker
/// read naturally instead of "Team 3" throughout the draft.
class DraftSetupScreen extends ConsumerStatefulWidget {
  const DraftSetupScreen({super.key});

  @override
  ConsumerState<DraftSetupScreen> createState() => _DraftSetupScreenState();
}

class _DraftSetupScreenState extends ConsumerState<DraftSetupScreen> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int slot, String initial) {
    return _controllers.putIfAbsent(slot, () => TextEditingController(text: initial));
  }

  @override
  Widget build(BuildContext context) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Draft Setup')),
      body: leagueDataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Failed to load league data: $err')),
        data: (leagueData) {
          final teamNames = ref.watch(teamNamesProvider);
          final myDraftSlot = leagueData.config.myDraftSlot;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Name the other teams (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Shown throughout the draft instead of "Team N". Leave blank to keep the default.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              for (var slot = 1; slot <= leagueData.config.teamsCount; slot++)
                if (slot == myDraftSlot)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text('#$slot', style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Expanded(
                          child: Text('You', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text('#$slot')),
                        Expanded(
                          child: TextField(
                            controller: _controllerFor(slot, teamNames[slot] ?? ''),
                            decoration: InputDecoration(hintText: 'Team $slot', isDense: true),
                            onChanged: (value) =>
                                ref.read(teamNamesProvider.notifier).setName(slot, value),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DraftHomeShell()),
                ),
                child: const Text('Continue to Draft'),
              ),
            ],
          );
        },
      ),
    );
  }
}
