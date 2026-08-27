import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/league_config.dart';
import '../models/player.dart';

class LeagueData {
  final List<Player> players;
  final LeagueRosterConfig config;

  const LeagueData({required this.players, required this.config});
}

/// Loads the bundled, pre-generated player pool and league config. This data
/// is produced ahead of time by data_prep + the screenshot-parsing step and
/// bundled as Flutter assets - there is no runtime network call here.
Future<LeagueData> loadLeagueData() async {
  final playersJson = await rootBundle.loadString('assets/data/players.json');
  final configJson = await rootBundle.loadString('assets/data/league_config.json');

  final playersList = (jsonDecode(playersJson) as List)
      .map((e) => Player.fromJson(e as Map<String, dynamic>))
      .toList();
  final config = LeagueRosterConfig.fromJson(jsonDecode(configJson) as Map<String, dynamic>);

  return LeagueData(players: playersList, config: config);
}
