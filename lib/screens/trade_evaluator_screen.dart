import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../engine/trade_evaluator.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/saved_roster_provider.dart';
import 'settings_screen.dart';

class TradeEvaluatorScreen extends ConsumerStatefulWidget {
  const TradeEvaluatorScreen({super.key});

  @override
  ConsumerState<TradeEvaluatorScreen> createState() => _TradeEvaluatorScreenState();
}

class _TradeEvaluatorScreenState extends ConsumerState<TradeEvaluatorScreen> {
  final Set<String> _giveIds = {};
  final Set<String> _getIds = {};
  final _giveController = TextEditingController();
  final _getController = TextEditingController();

  @override
  void dispose() {
    _giveController.dispose();
    _getController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (leagueData) {
        final draftState = ref.watch(draftStateProvider);
        final savedRosterPlayers = ref.watch(savedRosterPlayersProvider);

        // Use saved roster when it has players; fall back to the active draft roster.
        final myRoster = savedRosterPlayers.isNotEmpty
            ? savedRosterPlayers
            : myRosterFrom(
                leagueData.players,
                draftState,
                leagueData.config.myDraftSlot,
              );
        final usingSavedRoster = savedRosterPlayers.isNotEmpty;

        final myRosterIds = myRoster.map((p) => p.id).toSet();
        final allOtherPlayers = leagueData.players.where((p) => !myRosterIds.contains(p.id)).toList();

        final givePlayers = myRoster.where((p) => _giveIds.contains(p.id)).toList();
        final getPlayers = allOtherPlayers.where((p) => _getIds.contains(p.id)).toList();

        TradeResult? result;
        if (givePlayers.isNotEmpty || getPlayers.isNotEmpty) {
          result = evaluateTrade(
            myCurrentRoster: myRoster,
            playersIGive: givePlayers,
            playersIGet: getPlayers,
            fullPoolForBaseline: leagueData.players,
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trade Evaluator'),
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  _giveIds.clear();
                  _getIds.clear();
                }),
                child: const Text('Clear'),
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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (usingSavedRoster)
                Container(
                  color: Colors.teal.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.group, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Using your saved team · ${myRoster.length} players',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PlayerPickerColumn(
                        title: 'You Give',
                        titleColor: Colors.red.shade700,
                        candidates: myRoster,
                        selectedIds: _giveIds,
                        searchController: _giveController,
                        onToggle: (id) => setState(() {
                          if (_giveIds.contains(id)) {
                            _giveIds.remove(id);
                          } else {
                            _giveIds.add(id);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PlayerPickerColumn(
                        title: 'You Get',
                        titleColor: Colors.green.shade700,
                        candidates: allOtherPlayers,
                        selectedIds: _getIds,
                        searchController: _getController,
                        onToggle: (id) => setState(() {
                          if (_getIds.contains(id)) {
                            _getIds.remove(id);
                          } else {
                            _getIds.add(id);
                          }
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (result != null) ...[
                  _SummaryLine(result: result),
                  const SizedBox(height: 12),
                  _CategoryTable(result: result),
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Select players to give and/or receive above\nto see the trade impact.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
          ),
              ), // Expanded
            ], // outer Column children
          ), // outer Column (Scaffold.body)
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Player picker column
// ---------------------------------------------------------------------------

class _PlayerPickerColumn extends StatelessWidget {
  final String title;
  final Color titleColor;
  final List<Player> candidates;
  final Set<String> selectedIds;
  final TextEditingController searchController;
  final ValueChanged<String> onToggle;

  const _PlayerPickerColumn({
    required this.title,
    required this.titleColor,
    required this.candidates,
    required this.selectedIds,
    required this.searchController,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor),
        ),
        const SizedBox(height: 6),
        // Selected chips
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final id in selectedIds)
              Builder(builder: (ctx) {
                final player = candidates.firstWhere(
                  (p) => p.id == id,
                  orElse: () => candidates.first,
                );
                return Chip(
                  label: Text(player.name, style: const TextStyle(fontSize: 11)),
                  onDeleted: () => onToggle(id),
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }),
          ],
        ),
        const SizedBox(height: 6),
        // Search field
        _SearchablePlayerList(
          candidates: candidates,
          selectedIds: selectedIds,
          controller: searchController,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

class _SearchablePlayerList extends StatefulWidget {
  final List<Player> candidates;
  final Set<String> selectedIds;
  final TextEditingController controller;
  final ValueChanged<String> onToggle;

  const _SearchablePlayerList({
    required this.candidates,
    required this.selectedIds,
    required this.controller,
    required this.onToggle,
  });

  @override
  State<_SearchablePlayerList> createState() => _SearchablePlayerListState();
}

class _SearchablePlayerListState extends State<_SearchablePlayerList> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.candidates.take(12).toList()
        : widget.candidates.where((p) => p.name.toLowerCase().contains(query)).take(12).toList();

    return Column(
      children: [
        TextField(
          controller: widget.controller,
          decoration: const InputDecoration(
            hintText: 'Search player...',
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 4),
        ...filtered.map((p) {
          final selected = widget.selectedIds.contains(p.id);
          return InkWell(
            onTap: () => widget.onToggle(p.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Results table
// ---------------------------------------------------------------------------

class _SummaryLine extends StatelessWidget {
  final TradeResult result;

  const _SummaryLine({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'You win ${result.winsCount} categories, '
        'lose ${result.lossCount}, '
        'tie ${result.tieCount}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CategoryTable extends StatelessWidget {
  final TradeResult result;

  const _CategoryTable({required this.result});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(44),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          children: const [
            _HeaderCell('Cat'),
            _HeaderCell('After'),
            _HeaderCell('Delta'),
            _HeaderCell('Opp'),
          ],
        ),
        for (final row in result.rows) _buildRow(row),
      ],
    );
  }

  TableRow _buildRow(TradeCategoryRow row) {
    final deltaStr = row.myDelta > 0.01
        ? '+${row.myDelta.toStringAsFixed(1)}'
        : row.myDelta < -0.01
            ? row.myDelta.toStringAsFixed(1)
            : '—';
    final deltaColor = row.myDelta > 0.01
        ? Colors.green.shade700
        : row.myDelta < -0.01
            ? Colors.red.shade700
            : Colors.grey;

    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Text(row.category.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(row.myTeamAfter.toStringAsFixed(1), style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(deltaStr, style: TextStyle(fontSize: 12, color: deltaColor, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(row.oppTeamAfter.toStringAsFixed(1), style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
      ),
    ]);
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}
