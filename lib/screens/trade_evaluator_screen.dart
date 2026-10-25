import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/trade_evaluator.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/saved_roster_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_picker_sheet.dart';
import '../widgets/player_row.dart';
import 'league_screen.dart';

/// Pick players to give and get; shows how each of my categories changes.
class TradeEvaluatorScreen extends ConsumerStatefulWidget {
  const TradeEvaluatorScreen({super.key});

  @override
  ConsumerState<TradeEvaluatorScreen> createState() => _TradeEvaluatorScreenState();
}

class _TradeEvaluatorScreenState extends ConsumerState<TradeEvaluatorScreen> {
  final Set<String> _give = {};
  final Set<String> _get = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trade'),
        actions: [
          if (_give.isNotEmpty || _get.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _give.clear();
                _get.clear();
              }),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final mine = ref.watch(savedRosterPlayersProvider);
          if (mine.isEmpty) {
            return const EmptyState(
              icon: Icons.swap_horiz,
              title: 'Add your team first',
              body: 'Trades are evaluated against your current roster.',
            );
          }
          final mineIds = mine.map((p) => p.id).toSet();
          final league = ref.watch(leagueTeamsProvider).value;
          final others = byPreseasonRank(leagueData.players.where((p) => !mineIds.contains(p.id)).toList());
          final byId = ref.watch(playersByIdProvider);
          final give = _give.map((id) => byId[id]).whereType<Player>().toList();
          final get = _get.map((id) => byId[id]).whereType<Player>().toList();
          final result = give.isEmpty && get.isEmpty
              ? null
              : evaluateTrade(
                  myCurrentRoster: mine,
                  playersIGive: give,
                  playersIGet: get,
                  fullPoolForBaseline: leagueData.players,
                );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _Side(
                title: 'You give',
                players: give,
                onEdit: () => _pick('You give', mine, _give),
                onRemove: (id) => setState(() => _give.remove(id)),
              ),
              const SizedBox(height: 12),
              _Side(
                title: 'You get',
                players: get,
                onEdit: () => _pick('You get', others, _get, note: (p) => league?.teamOf(p.id)?.name),
                onRemove: (id) => setState(() => _get.remove(id)),
              ),
              const SizedBox(height: 16),
              if (result == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Pick players on both sides to see how the trade changes each category.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                SectionHeader('Impact on your team · ${result.winsCount} up, ${result.lossCount} down'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _ImpactTable(result: result),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _pick(String title, List<Player> candidates, Set<String> target, {String? Function(Player)? note}) {
    return showPlayerPicker(
      context,
      title: title,
      candidates: candidates,
      selectedIds: (_) => target,
      onToggle: (_, id) => setState(() => target.contains(id) ? target.remove(id) : target.add(id)),
      note: note,
    );
  }
}

class _Side extends StatelessWidget {
  final String title;
  final List<Player> players;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemove;

  const _Side({required this.title, required this.players, required this.onEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            trailing: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.add),
              label: Text(players.isEmpty ? 'Choose' : 'Edit'),
            ),
          ),
          for (final p in players) ...[
            const Divider(indent: 72),
            PlayerRow(
              player: p,
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove ${p.name}',
                onPressed: () => onRemove(p.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImpactTable extends StatelessWidget {
  final TradeResult result;

  const _ImpactTable({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant);
    Widget cell(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: child);

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth(1.2)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          cell(Text('CAT', style: headStyle)),
          for (final h in ['BEFORE', 'AFTER', 'CHANGE']) cell(Text(h, textAlign: TextAlign.end, style: headStyle)),
        ]),
        for (final row in result.rows)
          () {
            final d = row.myDelta;
            final (icon, color) = d > 0.01
                ? (Icons.arrow_upward, context.stat.win)
                : d < -0.01
                    ? (Icons.arrow_downward, context.stat.loss)
                    : (Icons.remove, colors.onSurfaceVariant);
            return TableRow(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))),
              children: [
                cell(Text(row.category.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                cell(Text((row.myTeamAfter - d).toStringAsFixed(1), textAlign: TextAlign.end)),
                cell(Text(row.myTeamAfter.toStringAsFixed(1), textAlign: TextAlign.end)),
                cell(Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Text(d.abs().toStringAsFixed(1), style: theme.textTheme.labelLarge?.copyWith(color: color)),
                  ],
                )),
              ],
            );
          }(),
      ],
    );
  }
}
