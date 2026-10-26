import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/league_teams_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/league_switcher.dart';
import '../widgets/player_picker_sheet.dart';
import '../widgets/player_row.dart';
import 'matchup_screen.dart' show ordinal;
import 'settings_screen.dart';

/// The [n] players to cut from [roster] after a trade: lowest value first, never anyone in [keep].
/// Players with no games yet (no value, e.g. an injured star on IL) are never suggested.
List<Player> suggestDrops(List<Player> roster, int n, Map<String, double> z, {Set<String> keep = const {}}) {
  if (n <= 0) return const [];
  final pool = roster.where((p) => !keep.contains(p.id) && z.containsKey(p.id)).toList()
    ..sort((a, b) => z[a.id]!.compareTo(z[b.id]!));
  return pool.take(n).toList();
}

/// Rank (1 = best) of [team] per category among [standings] (team -> category standing).
Map<StatCategory, int> categoryRanks(Map<String, Map<StatCategory, double>> standings, String team) => {
      for (final c in allStatCategories)
        c: standings.values.where((s) => (s[c] ?? 0) > (standings[team]![c] ?? 0)).length + 1,
    };

const _me = '__me__';

/// Trade calculator: pick a partner, who goes each way, who gets dropped; shows the value
/// swing for both sides and my category totals and league ranks before and after.
class TradeEvaluatorScreen extends ConsumerStatefulWidget {
  const TradeEvaluatorScreen({super.key});

  @override
  ConsumerState<TradeEvaluatorScreen> createState() => _TradeEvaluatorScreenState();
}

class _TradeEvaluatorScreenState extends ConsumerState<TradeEvaluatorScreen> {
  String? _partnerId;
  final Set<String> _give = {};
  final Set<String> _get = {};

  /// My drops picked by hand; null = use the suggestion.
  Set<String>? _myDrops;

  void _reset() => setState(() {
        _give.clear();
        _get.clear();
        _myDrops = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const LeagueTitle('Trade'),
        actions: [
          if (_give.isNotEmpty || _get.isNotEmpty) TextButton(onPressed: _reset, child: const Text('Clear')),
          const SettingsButton(),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final mine = ref.watch(savedRosterPlayersProvider);
          final league = ref.watch(leagueTeamsProvider).value;
          if (mine.isEmpty) {
            return const EmptyState(
              icon: Icons.swap_horiz,
              title: 'Add your team first',
              body: 'Trades are evaluated against your current roster.',
            );
          }
          final byId = ref.watch(playersByIdProvider);
          final z = ref.watch(leagueZProvider);
          final punted = ref.watch(draftStateProvider).puntedCategories;
          final teams = [...?league?.teams.where((t) => t.playerIds.isNotEmpty)];
          final partner = teams.where((t) => t.id == _partnerId).firstOrNull;
          final theirs = partner == null ? <Player>[] : [for (final id in partner.playerIds) ?byId[id]];
          final give = [for (final id in _give) ?byId[id]];
          final get = [for (final id in _get) ?byId[id]];

          // Full rosters assumed: whoever receives more players drops the difference.
          final myExtra = get.length - give.length;
          final mineAfterTrade = [...mine.where((p) => !_give.contains(p.id)), ...get];
          final theirsAfterTrade = [...theirs.where((p) => !_get.contains(p.id)), ...give];
          final suggestedMyDrops = suggestDrops(mineAfterTrade, myExtra, z, keep: _get);
          final myDrops = _myDrops == null || _myDrops!.length != myExtra
              ? suggestedMyDrops
              : [for (final id in _myDrops!) ?byId[id]];
          final theirDrops = suggestDrops(theirsAfterTrade, -myExtra, z, keep: _give);
          final mineAfter = mineAfterTrade.where((p) => !myDrops.contains(p)).toList();
          final theirsAfter = theirsAfterTrade.where((p) => !theirDrops.contains(p)).toList();

          double value(Iterable<Player> ps) => ps.fold(0.0, (a, p) => a + (z[p.id] ?? 0));
          final myDelta = value(get) - value(give) - value(myDrops);
          final theirDelta = value(give) - value(get) - value(theirDrops);

          // Every team's category standing, before and after, for league ranks.
          Map<StatCategory, double> standing(List<Player> roster) =>
              computeTeamStanding(myRoster: roster, fullPoolForBaseline: leagueData.players);
          final before = {
            _me: standing(mine),
            for (final t in teams) t.id: standing([for (final id in t.playerIds) ?byId[id]]),
          };
          final after = {...before, _me: standing(mineAfter), if (partner != null) partner.id: standing(theirsAfter)};
          final ready = partner != null && (give.isNotEmpty || get.isNotEmpty);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (teams.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('No other rosters yet'),
                    subtitle: Text('Add the other teams on the League tab to trade with them.'),
                  ),
                )
              else
                DropdownMenu<String>(
                  key: ValueKey(_partnerId),
                  initialSelection: partner?.id,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Trade with'),
                  leadingIcon: const Icon(Icons.handshake_outlined),
                  onSelected: (id) => setState(() {
                    _partnerId = id;
                    _get.clear();
                    _myDrops = null;
                  }),
                  dropdownMenuEntries: [for (final t in teams) DropdownMenuEntry(value: t.id, label: t.name)],
                ),
              const SizedBox(height: 12),
              _Side(
                title: 'You send',
                players: give,
                z: z,
                onEdit: () => _pick('You send', mine, _give),
                onRemove: (id) => setState(() => _give.remove(id)),
              ),
              const SizedBox(height: 12),
              _Side(
                title: partner == null ? 'You receive' : 'You receive from ${partner.name}',
                players: get,
                z: z,
                onEdit: partner == null ? null : () => _pick(partner.name, theirs, _get),
                onRemove: (id) => setState(() => _get.remove(id)),
              ),
              if (ready && myExtra != 0) ...[
                const SizedBox(height: 12),
                if (myExtra > 0)
                  _Side(
                    title: 'You drop $myExtra',
                    players: myDrops,
                    z: z,
                    note: _myDrops == null ? 'Suggested: your lowest value' : null,
                    onEdit: () => _pickDrops(mineAfterTrade.where((p) => !_get.contains(p.id)).toList(), myExtra, myDrops),
                  )
                else
                  _Side(
                    title: '${partner.name} drops ${-myExtra}',
                    players: theirDrops,
                    z: z,
                    note: 'Their lowest value; you get ${-myExtra} open spot${myExtra == -1 ? '' : 's'}',
                  ),
                if (myExtra < 0)
                  if (ref.watch(rankingsProvider) case final fa when fa.isNotEmpty)
                    () {
                      final best = ([...fa]..sort((a, b) => b.puntAdjustedZ.compareTo(a.puntAdjustedZ))).first;
                      final p = byId[best.playerId];
                      return p == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _Side(
                                title: 'Fill your open spot',
                                players: [p],
                                z: z,
                                note: 'Best free agent for your categories',
                              ),
                            );
                    }(),
              ],
              const SizedBox(height: 16),
              if (!ready)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    partner == null
                        ? 'Pick a team to trade with, then who goes each way.'
                        : 'Pick at least one player to send or receive.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                _Verdict(myDelta: myDelta, theirDelta: theirDelta, partner: partner.name),
                const SizedBox(height: 16),
                const SectionHeader('My team · before and after'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _ImpactTable(
                      before: before[_me]!,
                      after: after[_me]!,
                      rankBefore: categoryRanks(before, _me),
                      rankAfter: categoryRanks(after, _me),
                      teams: before.length,
                      punted: punted,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Totals are summed per-game values (z) of the roster this season; rank is among all '
                  '${before.length} rosters in this league.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SectionHeader('${partner.name} · what changes for them'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _TheirSummary(before: before[partner.id]!, after: after[partner.id]!),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _pick(String title, List<Player> candidates, Set<String> target) => showPlayerPicker(
        context,
        title: title,
        candidates: candidates,
        selectedIds: (_) => target,
        onToggle: (_, id) => setState(() {
          target.contains(id) ? target.remove(id) : target.add(id);
          _myDrops = null;
        }),
      );

  Future<void> _pickDrops(List<Player> candidates, int n, List<Player> current) {
    final chosen = {for (final p in current) p.id};
    return showPlayerPicker(
      context,
      title: 'Drop $n',
      candidates: candidates,
      selectedIds: (_) => chosen,
      onToggle: (_, id) => setState(() {
        if (chosen.contains(id)) {
          chosen.remove(id);
        } else if (chosen.length < n) {
          chosen.add(id);
        }
        _myDrops = {...chosen};
      }),
    );
  }
}

class _Side extends StatelessWidget {
  final String title;
  final List<Player> players;
  final Map<String, double> z;
  final String? note;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onRemove;

  const _Side({required this.title, required this.players, required this.z, this.note, this.onEdit, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: theme.textTheme.titleMedium),
            subtitle: note == null ? null : Text(note!),
            trailing: onEdit == null
                ? null
                : TextButton.icon(
                    onPressed: onEdit,
                    icon: Icon(players.isEmpty ? Icons.add : Icons.edit_outlined),
                    label: Text(players.isEmpty ? 'Choose' : 'Change'),
                  ),
          ),
          for (final p in players) ...[
            const Divider(indent: 72),
            PlayerRow(
              player: p,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    z[p.id]?.toStringAsFixed(1) ?? '—',
                    style: theme.textTheme.titleSmall?.copyWith(color: z[p.id] == null ? null : context.zColor(z[p.id]!)),
                  ),
                  if (onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove ${p.name}',
                      onPressed: () => onRemove!(p.id),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final double myDelta;
  final double theirDelta;
  final String partner;

  const _Verdict({required this.myDelta, required this.theirDelta, required this.partner});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = myDelta > 1
        ? ('Good for you', context.stat.win, Icons.thumb_up_alt_outlined)
        : myDelta < -1
            ? ('Bad for you', context.stat.loss, Icons.thumb_down_alt_outlined)
            : ('About even', theme.colorScheme.onSurfaceVariant, Icons.balance);
    Widget side(String who, double d) => Expanded(
          child: Column(
            children: [
              Text('${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}',
                  style: theme.textTheme.headlineMedium?.copyWith(color: context.zColor(d), fontWeight: FontWeight.w800)),
              Text(who, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.titleLarge?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [side('YOU', myDelta), side(partner.toUpperCase(), theirDelta)]),
            const SizedBox(height: 8),
            Text(
              'Value change (sum of players\' per-game value, incl. drops). '
              '${theirDelta < -1 ? 'They lose value, so they may say no.' : 'They don\'t lose much, so it\'s a realistic offer.'}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// CAT | BEFORE | AFTER | RANK before → after, with an arrow for the change. Punted categories greyed.
class _ImpactTable extends StatelessWidget {
  final Map<StatCategory, double> before;
  final Map<StatCategory, double> after;
  final Map<StatCategory, int> rankBefore;
  final Map<StatCategory, int> rankAfter;
  final int teams;
  final Set<StatCategory> punted;

  const _ImpactTable({
    required this.before,
    required this.after,
    required this.rankBefore,
    required this.rankAfter,
    required this.teams,
    required this.punted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant);
    Widget cell(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: child);

    return Table(
      columnWidths: const {0: FlexColumnWidth(0.9), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1.9)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          cell(Text('CAT', style: headStyle)),
          for (final h in ['BEFORE', 'AFTER', 'LEAGUE RANK']) cell(Text(h, textAlign: TextAlign.end, style: headStyle)),
        ]),
        for (final c in allStatCategories)
          () {
            final d = after[c]! - before[c]!;
            final isPunted = punted.contains(c);
            final rb = rankBefore[c]!, ra = rankAfter[c]!;
            final (icon, color) = isPunted
                ? (Icons.block, colors.outline)
                : ra < rb
                    ? (Icons.arrow_upward, context.stat.win)
                    : ra > rb
                        ? (Icons.arrow_downward, context.stat.loss)
                        : (Icons.remove, colors.onSurfaceVariant);
            final base = theme.textTheme.bodyMedium?.copyWith(color: isPunted ? colors.outline : null);
            return TableRow(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))),
              children: [
                cell(Text(c.label, style: base?.copyWith(fontWeight: FontWeight.w700))),
                cell(Text(before[c]!.toStringAsFixed(1), textAlign: TextAlign.end, style: base)),
                cell(Text(
                  after[c]!.toStringAsFixed(1),
                  textAlign: TextAlign.end,
                  style: base?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isPunted || d.abs() < 0.05 ? null : (d > 0 ? context.stat.win : context.stat.loss),
                  ),
                )),
                cell(Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(ordinal(rb), style: base),
                    Icon(Icons.arrow_right_alt, size: 18, color: colors.onSurfaceVariant),
                    Text(ordinal(ra), style: theme.textTheme.labelLarge?.copyWith(color: color)),
                    const SizedBox(width: 2),
                    Icon(icon, size: 16, color: color),
                  ],
                )),
              ],
            );
          }(),
      ],
    );
  }
}

/// "Gains: REB, BLK · Loses: PTS" for the trade partner.
class _TheirSummary extends StatelessWidget {
  final Map<StatCategory, double> before;
  final Map<StatCategory, double> after;

  const _TheirSummary({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gains = [for (final c in allStatCategories) if (after[c]! - before[c]! > 0.3) c];
    final losses = [for (final c in allStatCategories) if (after[c]! - before[c]! < -0.3) c];
    Widget line(IconData icon, Color color, String label, List<StatCategory> cats) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text('$label: ', style: theme.textTheme.titleSmall),
              Expanded(child: Text(cats.isEmpty ? 'nothing notable' : cats.map((c) => c.label).join(', '))),
            ],
          ),
        );
    return Column(
      children: [
        line(Icons.arrow_upward, context.stat.win, 'Gains', gains),
        line(Icons.arrow_downward, context.stat.loss, 'Loses', losses),
      ],
    );
  }
}
