import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat_category.dart';
import '../services/player_repository.dart';
import '../state/league_data_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

enum CategoryOutcome { win, loss, tie }

/// Real head-to-head result for one category (fewer turnovers wins).
CategoryOutcome categoryOutcome(StatCategory c, double mine, double theirs) {
  if (mine == theirs) return CategoryOutcome.tie;
  return (mine > theirs) != c.lowerIsBetter ? CategoryOutcome.win : CategoryOutcome.loss;
}

typedef Score = ({int w, int l, int t});

/// W/L/T of [x] against [y] across the 9 categories.
Score score(TeamWeek x, TeamWeek y) {
  final o = [for (final c in allStatCategories) categoryOutcome(c, x.stats[c]!, y.stats[c]!)];
  return (
    w: o.where((v) => v == CategoryOutcome.win).length,
    l: o.where((v) => v == CategoryOutcome.loss).length,
    t: o.where((v) => v == CategoryOutcome.tie).length,
  );
}

/// The matchup from [name]'s side, or null when that team isn't in it.
({TeamWeek me, TeamWeek opp})? sideOf(LeagueMatchup m, String? name) =>
    name == null ? null : (m.a.name == name ? (me: m.a, opp: m.b) : m.b.name == name ? (me: m.b, opp: m.a) : null);

/// Within reach: percentages within .010, counting stats within 5% (and 3 at least).
bool isClose(StatCategory c, double x, double y) => c == StatCategory.fgPct || c == StatCategory.ftPct
    ? (x - y).abs() <= 0.010
    : (x - y).abs() <= [3.0, 0.05 * (x > y ? x : y)].reduce((a, b) => a > b ? a : b);

String formatStat(StatCategory c, double v) => c == StatCategory.fgPct || c == StatCategory.ftPct
    ? v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')
    : v.toStringAsFixed(0);

/// One team's results over a period: matchup record, category record, and wins per category.
typedef TeamPeriod = ({String name, Score record, Score cats, Map<StatCategory, int> catWins});

List<TeamPeriod> leagueTable(Iterable<LeagueMatchup> matchups) {
  final rows = <String, TeamPeriod>{};
  void add(TeamWeek x, TeamWeek y) {
    final s = score(x, y);
    final r = rows[x.name] ??
        (name: x.name, record: (w: 0, l: 0, t: 0), cats: (w: 0, l: 0, t: 0), catWins: {for (final c in allStatCategories) c: 0});
    rows[x.name] = (
      name: x.name,
      record: (w: r.record.w + (s.w > s.l ? 1 : 0), l: r.record.l + (s.w < s.l ? 1 : 0), t: r.record.t + (s.w == s.l ? 1 : 0)),
      cats: (w: r.cats.w + s.w, l: r.cats.l + s.l, t: r.cats.t + s.t),
      catWins: {
        for (final c in allStatCategories)
          c: r.catWins[c]! + (categoryOutcome(c, x.stats[c]!, y.stats[c]!) == CategoryOutcome.win ? 1 : 0),
      },
    );
  }

  for (final m in matchups) {
    add(m.a, m.b);
    add(m.b, m.a);
  }
  return rows.values.toList();
}

/// Week chip selection: a week number, [_season], or null for the latest week.
const _season = 0;
final _selectedProvider = StateProvider<int?>((ref) => null);
final _opponentFilterProvider = StateProvider<String?>((ref) => null);

/// Real weekly matchups (from Yahoo screenshots): mine, the rest of the league,
/// and a league table, for one week or the whole season.
class MatchupScreen extends ConsumerWidget {
  const MatchupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchup'), actions: const [SettingsButton()]),
      body: AsyncBody(
        value: ref.watch(leagueDataProvider),
        builder: (leagueData) {
          final all = leagueData.matchups;
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_basketball_outlined,
              title: 'No matchups yet',
              body: 'Send screenshots of the Yahoo matchup pages to the RosterIQ Telegram bot '
                  '(no caption needed). Each week\'s real category totals show up here.',
            );
          }
          final weeks = {for (final m in all) m.week}.toList()..sort();
          final selected = ref.watch(_selectedProvider) ?? weeks.last;
          final period = selected == _season ? all : all.where((m) => m.week == selected).toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(leagueDataProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in [
                        (_season, 'Season'),
                        for (final w in weeks.reversed) (w, 'Week $w'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: selected == value,
                            onSelected: (_) => ref.read(_selectedProvider.notifier).state = value,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (selected == _season)
                  ..._seasonView(context, ref, all, leagueData.myName)
                else
                  ..._weekView(context, period, leagueData.myName, isLatest: selected == weeks.last),
                const SizedBox(height: 16),
                SectionHeader(selected == _season ? 'League table · season' : 'League table · week $selected'),
                Card(clipBehavior: Clip.antiAlias, child: LeagueTable(rows: leagueTable(period), myName: leagueData.myName)),
                const SizedBox(height: 6),
                Text(
                  'Each number is how many times the team won that category. '
                  'Swipe the table sideways for all 9; tap a column to sort.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _weekView(BuildContext context, List<LeagueMatchup> week, String? myName, {required bool isLatest}) {
    final theme = Theme.of(context);
    final mine = week.map((m) => sideOf(m, myName)).nonNulls.firstOrNull;
    final others = week.where((m) => sideOf(m, myName) == null).toList();
    final w = week.first;
    return [
      if (mine != null) ...[
        () {
          final s = score(mine.me, mine.opp);
          return _Scoreboard(
            title: 'Week ${w.week} · You vs ${mine.opp.name}',
            subtitle: '${_verdict(s, inProgress: isLatest)} · updated ${_ago(w.updatedAt)}',
            score: s,
          );
        }(),
        const SizedBox(height: 16),
        const SectionHeader('By category'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: MatchupTable(a: mine.me, b: mine.opp, aLabel: 'YOU', bLabel: 'OPP'),
          ),
        ),
        if (isLatest)
          () {
            final close = [
              for (final c in allStatCategories)
                if (isClose(c, mine.me.stats[c]!, mine.opp.stats[c]!)) c,
            ];
            if (close.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: context.stat.warnContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: context.stat.onWarnContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Still close: ${close.map((c) => c.label).join(', ')}. '
                          'A streamer or a lineup change could swing ${close.length == 1 ? 'it' : 'these'}.',
                          style: theme.textTheme.bodySmall?.copyWith(color: context.stat.onWarnContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ] else
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Your matchup isn\'t in yet'),
            subtitle: const Text('Send the screenshot of your own matchup page to the bot.'),
          ),
        ),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionHeader('Around the league'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, m) in others.indexed) ...[
                if (i > 0) const Divider(indent: 16),
                _MatchupRow(m: m),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _seasonView(BuildContext context, WidgetRef ref, List<LeagueMatchup> all, String? myName) {
    final theme = Theme.of(context);
    final mine = [
      for (final m in all)
        if (sideOf(m, myName) case final s?) (week: m.week, me: s.me, opp: s.opp),
    ];
    if (mine.isEmpty) return const [];
    final opponents = {for (final m in mine) m.opp.name}.toList()..sort();
    final filter = ref.watch(_opponentFilterProvider);
    final shown = filter == null ? mine : mine.where((m) => m.opp.name == filter).toList();
    final scores = [for (final m in shown) score(m.me, m.opp)];
    int sum(int Function(Score s) f) => scores.fold(0, (a, s) => a + f(s));

    return [
      DropdownMenu<String?>(
        key: ValueKey(filter),
        initialSelection: filter,
        expandedInsets: EdgeInsets.zero,
        label: const Text('My matchups vs'),
        leadingIcon: const Icon(Icons.filter_list),
        onSelected: (v) => ref.read(_opponentFilterProvider.notifier).state = v,
        dropdownMenuEntries: [
          const DropdownMenuEntry(value: null, label: 'All opponents'),
          for (final o in opponents) DropdownMenuEntry(value: o, label: o),
        ],
      ),
      const SizedBox(height: 12),
      _Scoreboard(
        title: filter == null ? 'My season' : 'Head to head vs $filter',
        subtitle: 'Categories ${sum((s) => s.w)}-${sum((s) => s.l)}-${sum((s) => s.t)} '
            'over ${shown.length} week${shown.length == 1 ? '' : 's'}'
            '${shown.any((m) => m.week == all.last.week) ? ' (week ${all.last.week} still in progress)' : ''}',
        score: (
          w: scores.where((s) => s.w > s.l).length,
          l: scores.where((s) => s.w < s.l).length,
          t: scores.where((s) => s.w == s.l).length,
        ),
      ),
      const SizedBox(height: 16),
      const SectionHeader('How often I win each category'),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              for (final c in allStatCategories)
                () {
                  final won = shown.where((m) => categoryOutcome(c, m.me.stats[c]!, m.opp.stats[c]!) == CategoryOutcome.win).length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 44, child: Text(c.label, style: theme.textTheme.titleSmall)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: shown.isEmpty ? 0 : won / shown.length,
                              minHeight: 10,
                              color: context.stat.win,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        SizedBox(width: 64, child: Text('$won of ${shown.length}', textAlign: TextAlign.end)),
                      ],
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const SectionHeader('My weeks'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, m) in shown.reversed.indexed) ...[
              if (i > 0) const Divider(indent: 16),
              () {
                final s = score(m.me, m.opp);
                final (label, color) = s.w > s.l
                    ? ('W', context.stat.win)
                    : s.w < s.l
                        ? ('L', context.stat.loss)
                        : ('T', theme.colorScheme.onSurfaceVariant);
                return ListTile(
                  title: Text('Week ${m.week}'),
                  subtitle: Text('vs ${m.opp.name}'),
                  trailing: Text('$label ${s.w}-${s.l}-${s.t}', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                  onTap: () => ref.read(_selectedProvider.notifier).state = m.week,
                );
              }(),
            ],
          ],
        ),
      ),
    ];
  }

  String _verdict(Score s, {required bool inProgress}) {
    if (s.w == s.l) return inProgress ? 'Tied right now' : 'Tie';
    final ahead = s.w > s.l;
    return inProgress ? (ahead ? 'Leading' : 'Trailing') : (ahead ? 'Won' : 'Lost');
  }
}

/// "A 4-5 B" row; tap for the full category table.
class _MatchupRow extends StatelessWidget {
  final LeagueMatchup m;

  const _MatchupRow({required this.m});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = score(m.a, m.b);
    TextStyle? style(bool won) => theme.textTheme.bodyMedium?.copyWith(fontWeight: won ? FontWeight.w700 : null);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Week ${m.week}', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              MatchupTable(a: m.a, b: m.b, aLabel: _short(m.a.name), bLabel: _short(m.b.name)),
            ],
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(m.a.name, style: style(s.w > s.l), overflow: TextOverflow.ellipsis)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${s.w} – ${s.l}${s.t > 0 ? ' – ${s.t}' : ''}', style: theme.textTheme.titleSmall),
              ),
              Expanded(
                child: Text(m.b.name, style: style(s.l > s.w), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String name) => name.length <= 10 ? name.toUpperCase() : '${name.substring(0, 9).toUpperCase()}…';
}

class _Scoreboard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Score score;

  const _Scoreboard({required this.title, required this.subtitle, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(int n, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text('$n', style: theme.textTheme.displaySmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(subtitle, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              children: [
                cell(score.w, 'WINS', context.stat.win),
                cell(score.t, 'TIES', theme.colorScheme.onSurfaceVariant),
                cell(score.l, 'LOSSES', context.stat.loss),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cat | A | B | result for A, with real totals. The result is icon + text, never color alone.
class MatchupTable extends StatelessWidget {
  final TeamWeek a;
  final TeamWeek b;
  final String aLabel;
  final String bLabel;

  const MatchupTable({super.key, required this.a, required this.b, required this.aLabel, required this.bLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    TableRow row(List<Widget> cells, {bool divider = true}) => TableRow(
          decoration: divider ? BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))) : null,
          children: [for (final c in cells) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: c)],
        );
    Widget head(String t, {TextAlign align = TextAlign.start}) =>
        Text(t, textAlign: align, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant));

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row([head('CAT'), head(aLabel, align: TextAlign.end), head(bLabel, align: TextAlign.end), head('    RESULT')],
            divider: false),
        for (final c in allStatCategories)
          () {
            final (icon, label, color) = switch (categoryOutcome(c, a.stats[c]!, b.stats[c]!)) {
              CategoryOutcome.win => (Icons.check_circle, 'W', context.stat.win),
              CategoryOutcome.loss => (Icons.cancel, 'L', context.stat.loss),
              CategoryOutcome.tie => (Icons.remove_circle_outline, 'T', colors.onSurfaceVariant),
            };
            return row([
              Text(c.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(formatStat(c, a.stats[c]!), textAlign: TextAlign.end),
              Text(formatStat(c, b.stats[c]!), textAlign: TextAlign.end),
              Row(children: [
                const SizedBox(width: 16),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
              ]),
            ]);
          }(),
      ],
    );
  }
}

/// Every team's record and category wins for the period; sortable by any column.
class LeagueTable extends StatefulWidget {
  final List<TeamPeriod> rows;
  final String? myName;

  const LeagueTable({super.key, required this.rows, required this.myName});

  @override
  State<LeagueTable> createState() => _LeagueTableState();
}

class _LeagueTableState extends State<LeagueTable> {
  /// null = category wins total; otherwise one category.
  StatCategory? _sortBy;

  int _value(TeamPeriod r) => _sortBy == null ? r.cats.w : r.catWins[_sortBy]!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...widget.rows]..sort((a, b) {
        final byValue = _value(b).compareTo(_value(a));
        return byValue != 0 ? byValue : b.cats.w.compareTo(a.cats.w);
      });
    final best = {
      for (final c in allStatCategories) c: rows.fold(0, (m, r) => r.catWins[c]! > m ? r.catWins[c]! : m),
    };
    final bestTotal = rows.fold(0, (m, r) => r.cats.w > m ? r.cats.w : m);
    TextStyle? cell(bool top) => theme.textTheme.bodyMedium?.copyWith(
          fontWeight: top ? FontWeight.w800 : null,
          color: top ? context.stat.win : null,
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 16,
        headingRowHeight: 44,
        sortColumnIndex: _sortBy == null ? 2 : 3 + allStatCategories.indexOf(_sortBy!),
        sortAscending: false,
        columns: [
          const DataColumn(label: Text('TEAM')),
          const DataColumn(label: Text('W-L-T')),
          DataColumn(label: const Text('CATS'), numeric: true, onSort: (_, _) => setState(() => _sortBy = null)),
          for (final c in allStatCategories)
            DataColumn(label: Text(c.label), numeric: true, onSort: (_, _) => setState(() => _sortBy = c)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              color: WidgetStatePropertyAll(r.name == widget.myName ? theme.colorScheme.primaryContainer : null),
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    r.name == widget.myName ? '${r.name} (you)' : r.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                )),
                DataCell(Text('${r.record.w}-${r.record.l}-${r.record.t}')),
                DataCell(Text('${r.cats.w}', style: cell(r.cats.w == bestTotal && bestTotal > 0))),
                for (final c in allStatCategories)
                  // Leaders only mean something over several weeks; in one week every winner has 1.
                  DataCell(Text('${r.catWins[c]}', style: cell(r.catWins[c] == best[c] && best[c]! > 1))),
              ],
            ),
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}
