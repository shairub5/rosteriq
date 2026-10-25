import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import 'player_avatar.dart';

/// Full-height searchable player list in a bottom sheet. Selection is read
/// live from providers via [selectedIds] so toggles show immediately, and the
/// sheet stays open for picking several players.
Future<void> showPlayerPicker(
  BuildContext context, {
  required String title,
  required List<Player> candidates,
  required Set<String> Function(WidgetRef ref) selectedIds,
  required void Function(WidgetRef ref, String playerId) onToggle,
  String? Function(Player p)? note,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PlayerPickerSheet(
      title: title,
      candidates: candidates,
      selectedIds: selectedIds,
      onToggle: onToggle,
      note: note,
    ),
  );
}

class _PlayerPickerSheet extends ConsumerStatefulWidget {
  final String title;
  final List<Player> candidates;
  final Set<String> Function(WidgetRef ref) selectedIds;
  final void Function(WidgetRef ref, String playerId) onToggle;
  final String? Function(Player p)? note;

  const _PlayerPickerSheet({
    required this.title,
    required this.candidates,
    required this.selectedIds,
    required this.onToggle,
    required this.note,
  });

  @override
  ConsumerState<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends ConsumerState<_PlayerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selectedIds(ref);
    final q = _query.trim().toLowerCase();
    final shown = (q.isEmpty
            ? widget.candidates
            : widget.candidates.where((p) => p.name.toLowerCase().contains(q) || p.team.toLowerCase() == q))
        .take(60)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(widget.title, style: theme.textTheme.titleLarge)),
                Text('${selected.length} selected', style: theme.textTheme.bodySmall),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Search players or team (e.g. BOS)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text('No players match "$_query"', style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    controller: scroll,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final p = shown[i];
                      final isSelected = selected.contains(p.id);
                      final extra = widget.note?.call(p);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) => setState(() => widget.onToggle(ref, p.id)),
                        controlAffinity: ListTileControlAffinity.trailing,
                        secondary: PlayerAvatar(nbaId: p.nbaId, playerName: p.name, radius: 20),
                        title: Text(p.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [p.eligiblePositions.join('/'), p.team, ?extra].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
