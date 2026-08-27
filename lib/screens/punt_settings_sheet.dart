import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat_category.dart';
import '../state/draft_state_provider.dart';

Future<void> showPuntSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _PuntSettingsContent(),
  );
}

class _PuntSettingsContent extends ConsumerStatefulWidget {
  const _PuntSettingsContent();

  @override
  ConsumerState<_PuntSettingsContent> createState() => _PuntSettingsContentState();
}

class _PuntSettingsContentState extends ConsumerState<_PuntSettingsContent> {
  late Set<StatCategory> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...ref.read(draftStateProvider).puntedCategories};
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Punt categories (pick up to 2)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Rankings recompute instantly, excluding these from the total.',
            style: TextStyle(color: Colors.grey),
          ),
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
                onPressed: () {
                  setState(() => _selected = {});
                },
                child: const Text('Clear'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  ref.read(draftStateProvider.notifier).setPuntedCategories(_selected);
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
