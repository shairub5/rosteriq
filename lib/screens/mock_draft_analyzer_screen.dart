import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/mock_draft_advisor.dart';
import '../models/player.dart';
import '../models/ranking_result.dart';
import '../models/swap_suggestion.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import 'settings_screen.dart';

class MockDraftAnalyzerScreen extends ConsumerStatefulWidget {
  const MockDraftAnalyzerScreen({super.key});

  @override
  ConsumerState<MockDraftAnalyzerScreen> createState() => _MockDraftAnalyzerScreenState();
}

class _MockDraftAnalyzerScreenState extends ConsumerState<MockDraftAnalyzerScreen> {
  final _picksController = TextEditingController();
  int _mySlot = 1;
  List<SwapSuggestion>? _results;
  bool _analyzed = false;

  @override
  void dispose() {
    _picksController.dispose();
    super.dispose();
  }

  void _analyze(List<Player> allPlayers, List<RankingResult> rankings, int teamsCount) {
    final rawText = _picksController.text.trim();
    if (rawText.isEmpty) return;

    // Accept one name per line or comma-separated (or a mix).
    final names = rawText
        .split(RegExp(r'[\n,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final suggestions = analyzeMockDraft(
      allPicksInOrder: names,
      myDraftSlot: _mySlot,
      teamsCount: teamsCount,
      rankings: rankings,
      players: allPlayers,
    );

    setState(() {
      _results = suggestions;
      _analyzed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final leagueDataAsync = ref.watch(leagueDataProvider);
    final rankings = ref.watch(rankingsProvider);

    return leagueDataAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (leagueData) {
        final teamsCount = leagueData.config.teamsCount;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mock Draft Analyzer'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Paste all draft picks in order (one per line or comma-separated). '
                'Include every pick from every team.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _picksController,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Draft picks (all teams, in order)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  hintText: 'Nikola Jokic\nLuka Doncic\nShai Gilgeous-Alexander\n...',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('My draft slot:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _mySlot,
                    items: [
                      for (var i = 1; i <= teamsCount; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _mySlot = v);
                    },
                  ),
                  const SizedBox(width: 4),
                  Text('of $teamsCount'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Analyze Draft'),
                  onPressed: () => _analyze(leagueData.players, rankings, teamsCount),
                ),
              ),
              const SizedBox(height: 24),
              if (_analyzed)
                _buildResults(
                  leagueData.players,
                  {for (final p in leagueData.players) p.id: p},
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(List<Player> allPlayers, Map<String, Player> playerById) {
    if (_results == null || _results!.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your draft looks optimal!',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_results!.length} improvement${_results!.length == 1 ? '' : 's'} found',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        for (final suggestion in _results!)
          _buildSuggestionCard(suggestion, playerById),
      ],
    );
  }

  Widget _buildSuggestionCard(SwapSuggestion suggestion, Map<String, Player> playerById) {
    final currentName = playerById[suggestion.currentPlayerId]?.name ?? suggestion.currentPlayerId;
    final betterName = playerById[suggestion.betterPlayerId]?.name ?? suggestion.betterPlayerId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your pick #${suggestion.pickNumber}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(currentName, style: const TextStyle(color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.arrow_upward, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Should have taken $betterName',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '+${suggestion.zScoreGain.toStringAsFixed(2)} z',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
