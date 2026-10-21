import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';
import '../state/sort_mode_provider.dart';
import '../state/stats_display_mode_provider.dart';
import '../state/stats_view_mode_provider.dart';

Future<void> showPuntSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _FilterSheetContent(),
  );
}

class _FilterSheetContent extends ConsumerStatefulWidget {
  const _FilterSheetContent();

  @override
  ConsumerState<_FilterSheetContent> createState() => _FilterSheetContentState();
}

class _FilterSheetContentState extends ConsumerState<_FilterSheetContent> {
  late Set<StatCategory> _selected;
  late SortMode _sortMode;
  late StatsViewMode _statsViewMode;
  late StatsDisplayMode _statsDisplayMode;

  @override
  void initState() {
    super.initState();
    _selected = {...ref.read(draftStateProvider).puntedCategories};
    _sortMode = ref.read(sortModeProvider);
    _statsViewMode = ref.read(statsViewModeProvider);
    _statsDisplayMode = ref.read(statsDisplayModeProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filter & Sort', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<SortMode>(
              segments: const [
                ButtonSegment(value: SortMode.ourRanking, label: Text('Our Rank')),
                ButtonSegment(value: SortMode.sourceRank, label: Text('Source')),
                ButtonSegment(value: SortMode.adp, label: Text('ADP')),
                ButtonSegment(value: SortMode.needImpact, label: Text('Need')),
              ],
              selected: {_sortMode},
              onSelectionChanged: (v) => setState(() => _sortMode = v.first),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Stats view', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<StatsViewMode>(
            segments: const [
              ButtonSegment(value: StatsViewMode.projected, label: Text('Projected')),
              ButtonSegment(value: StatsViewMode.lastYear, label: Text('Last Year')),
            ],
            selected: {_statsViewMode},
            onSelectionChanged: (v) => setState(() => _statsViewMode = v.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),

          const SizedBox(height: 16),
          const Text('Stat numbers', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<StatsDisplayMode>(
            segments: const [
              ButtonSegment(value: StatsDisplayMode.totals, label: Text('Totals')),
              ButtonSegment(value: StatsDisplayMode.perGame, label: Text('Per Game')),
            ],
            selected: {_statsDisplayMode},
            onSelectionChanged: (v) => setState(() => _statsDisplayMode = v.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Punt categories (pick up to 2)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Rankings recompute instantly, excluding these from the total.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in allStatCategories)
                FilterChip(
                  label: Text(category.label),
                  selected: _selected.contains(category),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (_selected.length < 2) _selected.add(category);
                      } else {
                        _selected.remove(category);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _selected = {};
                  _sortMode = SortMode.ourRanking;
                  _statsViewMode = StatsViewMode.projected;
                  _statsDisplayMode = StatsDisplayMode.totals;
                }),
                child: const Text('Reset all'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  ref.read(draftStateProvider.notifier).setPuntedCategories(_selected);
                  ref.read(sortModeProvider.notifier).state = _sortMode;
                  ref.read(statsViewModeProvider.notifier).state = _statsViewMode;
                  ref.read(statsDisplayModeProvider.notifier).state = _statsDisplayMode;
                  Navigator.of(context).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
