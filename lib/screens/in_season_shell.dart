import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'league_screen.dart';
import 'matchup_screen.dart';
import 'my_team_screen.dart';
import 'trade_evaluator_screen.dart';
import 'waiver_wire_screen.dart';

/// Selected bottom tab; screens set it to send the user to another tab (e.g. Matchup -> League).
final shellTabProvider = StateProvider<int>((ref) => 0);

/// Tab indexes, so callers don't hard-code numbers.
abstract final class ShellTab {
  static const matchup = 0;
  static const addDrop = 1;
  static const myTeam = 2;
  static const trade = 3;
  static const league = 4;
}

/// Season-long main shell on live ESPN data.
class InSeasonShell extends ConsumerWidget {
  const InSeasonShell({super.key});

  static const _screens = [
    MatchupScreen(),
    WaiverWireScreen(),
    MyTeamScreen(),
    TradeEvaluatorScreen(),
    LeagueScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(shellTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_basketball_outlined), selectedIcon: Icon(Icons.sports_basketball), label: 'Matchup'),
          NavigationDestination(icon: Icon(Icons.person_add_alt_outlined), selectedIcon: Icon(Icons.person_add_alt_1), label: 'Add/Drop'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'My Team'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), selectedIcon: Icon(Icons.swap_horizontal_circle), label: 'Trade'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'League'),
        ],
      ),
    );
  }
}
