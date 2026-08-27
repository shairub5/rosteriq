import 'package:flutter/material.dart';

import 'available_pool_screen.dart';
import 'draft_board_screen.dart';
import 'my_roster_screen.dart';

class DraftHomeShell extends StatefulWidget {
  const DraftHomeShell({super.key});

  @override
  State<DraftHomeShell> createState() => _DraftHomeShellState();
}

class _DraftHomeShellState extends State<DraftHomeShell> {
  int _index = 0;

  static const _screens = [
    AvailablePoolScreen(),
    MyRosterScreen(),
    DraftBoardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Pool'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'My Roster'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Board'),
        ],
      ),
    );
  }
}
