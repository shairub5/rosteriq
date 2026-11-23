import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/assistant.dart';
import '../state/current_league_provider.dart';
import '../state/league_data_provider.dart';
import '../state/schedule_provider.dart';
import '../theme.dart';

const _historyKey = 'assistant_history_v1';

/// Chat with Claude about the app's data: matchups, trades, add/drops, schedules, news.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ApiMessage> _history = [];
  String? _apiKey;
  bool _loaded = false;
  bool _busy = false;
  String? _step;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await loadApiKey();
    List<ApiMessage> history = [];
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_historyKey);
      if (raw != null) history = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _apiKey = key;
      _history = history;
      _loaded = true;
    });
    _toBottom();
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_historyKey, jsonEncode(_history));

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy || _apiKey == null) return;
    final data = ref.read(leagueDataProvider).value;
    final schedule = ref.read(scheduleProvider).value;
    if (data == null || schedule == null) {
      setState(() => _error = 'Data is still loading. Try again in a moment.');
      return;
    }
    _input.clear();
    setState(() {
      _history = [
        ..._history,
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ];
      _busy = true;
      _step = 'Thinking…';
      _error = null;
    });
    _toBottom();
    try {
      final added = await askAssistant(
        apiKey: _apiKey!,
        data: AssistantData(data: data, schedule: schedule, selectedLeagueId: ref.read(currentLeagueProvider).id),
        history: _history,
        onStep: (s) => mounted ? setState(() => _step = s) : null,
      );
      if (!mounted) return;
      setState(() => _history = [..._history, ...added]);
      await _save();
    } catch (e) {
      if (!mounted) return;
      // Drop the unanswered question so the conversation stays valid (user/assistant alternating).
      setState(() {
        _history = _history.sublist(0, _history.length - 1);
        _input.text = text;
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
        _toBottom();
      }
    }
  }

  Future<void> _restart() async {
    setState(() {
      _history = [];
      _error = null;
    });
    await _save();
  }

  Future<void> _editKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claude API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste a key from platform.claude.com. It\'s stored in this phone\'s Keychain only.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'sk-ant-…', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (_apiKey != null)
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (key == null) return;
    await saveApiKey(key);
    final loaded = await loadApiKey();
    if (mounted) setState(() => _apiKey = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = [
      for (final m in _history)
        if (m['role'] == 'user')
          if (((m['content'] as List).first as Map)['type'] == 'text') (user: true, text: ((m['content'] as List).first as Map)['text'] as String)
          else null
        else if (assistantText(m) case final t when t.isNotEmpty)
          (user: false, text: t),
    ].nonNulls.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask RosterIQ'),
        actions: [
          IconButton(icon: const Icon(Icons.key_outlined), tooltip: 'API key', onPressed: _editKey),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'New chat',
            onPressed: _history.isEmpty || _busy ? null : _restart,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _apiKey == null
              ? _NeedsKey(onSet: _editKey)
              : Column(
                  children: [
                    Expanded(
                      child: visible.isEmpty && !_busy
                          ? _Suggestions(onPick: _send)
                          : ListView(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              children: [
                                for (final m in visible) _Bubble(user: m.user, text: m.text),
                                if (_busy) _Progress(step: _step ?? 'Thinking…'),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: context.stat.loss)),
                                  ),
                              ],
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: 'Ask about your matchup, trades, pickups…',
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filled(
                              icon: const Icon(Icons.arrow_upward),
                              tooltip: 'Send',
                              onPressed: _busy ? null : () => _send(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _NeedsKey extends StatelessWidget {
  final VoidCallback onSet;

  const _NeedsKey({required this.onSet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Add your Claude API key', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'The assistant runs on Claude Opus 5.5 with your key, and sees all the app\'s data.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onSet, icon: const Icon(Icons.key), label: const Text('Add key')),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  final void Function(String) onPick;

  const _Suggestions({required this.onPick});

  static const _ideas = [
    'How will my matchup finish this week, and what should I change?',
    'Who are the best free agents for the categories I need?',
    'Compare my team with my opponent across all weeks so far.',
    'Suggest a trade that fixes my weakest categories.',
    'Who should I drop when Haliburton comes back?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.auto_awesome, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text('Ask anything about your leagues', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'It sees every roster, matchup, player stat, injury, schedule and last night\'s games, and can search the web.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        for (final i in _ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => onPick(i),
              child: Text(i, style: theme.textTheme.bodyMedium),
            ),
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final String step;

  const _Progress({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(step, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool user;
  final String text;

  const _Bubble({required this.user, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
          child: SelectableText(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: MarkdownLite(text));
  }
}

/// Small markdown renderer for chat answers: headings, bullets, numbered lists, pipe tables,
/// **bold** and `code`.
class MarkdownLite extends StatelessWidget {
  final String text;

  const MarkdownLite(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!;
    final lines = text.split('\n');
    final out = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.trimLeft().startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
          final cells = lines[i].trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
          if (!cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) rows.add(cells);
          i++;
        }
        i--;
        out.add(_table(context, rows, base));
        continue;
      }
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 6));
        continue;
      }
      final h = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (h != null) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text.rich(_inline(h[2]!, (h[1]!.length <= 2 ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)!
              .copyWith(fontWeight: FontWeight.w700))),
        ));
        continue;
      }
      final bullet = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        final indent = bullet[1]!.length ~/ 2;
        final marker = RegExp(r'\d').hasMatch(bullet[2]!) ? bullet[2]! : '•';
        out.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + indent * 14, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 20, child: Text(marker, style: base)),
            Expanded(child: Text.rich(_inline(bullet[3]!, base))),
          ]),
        ));
        continue;
      }
      out.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text.rich(_inline(line, base))));
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: out));
  }

  TextSpan _inline(String s, TextStyle style) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(?!\s)([^*]+?)\*');
    var at = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
      if (m[1] != null) {
        spans.add(TextSpan(text: m[1], style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (m[2] != null) {
        spans.add(TextSpan(text: m[2], style: const TextStyle(fontFamily: 'monospace')));
      } else {
        spans.add(TextSpan(text: m[3], style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      at = m.end;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  Widget _table(BuildContext context, List<List<String>> rows, TextStyle base) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final n = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: colors.outlineVariant)),
          children: [
            for (final (i, r) in rows.indexed)
              TableRow(
                decoration: i == 0 ? BoxDecoration(color: colors.surfaceContainerHighest) : null,
                children: [
                  for (var c = 0; c < n; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text.rich(_inline(c < r.length ? r[c] : '',
                          i == 0 ? base.copyWith(fontWeight: FontWeight.w700) : base)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
