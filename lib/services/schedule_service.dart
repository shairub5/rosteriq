import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The full parsed NBA schedule for the 2025-26 season, loaded from the
/// bundled `assets/data/nba_schedule.json`. Replace that file with real data
/// when available — the service parses whatever is in it.
class NbaSchedule {
  final DateTime fantasyPlayoffStart;
  final DateTime fantasyPlayoffEnd;

  /// Keyed by 3-letter team abbreviation (e.g. "LAL", "BOS").
  final Map<String, TeamSchedule> teams;

  const NbaSchedule({
    required this.fantasyPlayoffStart,
    required this.fantasyPlayoffEnd,
    required this.teams,
  });

  factory NbaSchedule.fromJson(Map<String, dynamic> json) {
    final teamsJson = json['teams'] as Map<String, dynamic>;
    return NbaSchedule(
      fantasyPlayoffStart: DateTime.parse(json['fantasyPlayoffStart'] as String),
      fantasyPlayoffEnd: DateTime.parse(json['fantasyPlayoffEnd'] as String),
      teams: {
        for (final entry in teamsJson.entries)
          entry.key: TeamSchedule.fromJson(entry.value as Map<String, dynamic>),
      },
    );
  }
}

/// Schedule for a single NBA team.
class TeamSchedule {
  /// All regular-season game dates, sorted ascending.
  final List<DateTime> games;

  /// Dates on which this team plays the second leg of a back-to-back
  /// (i.e. they also played the day before). Stored as a Set for O(1) lookup.
  final Set<DateTime> backToBacks;

  const TeamSchedule({required this.games, required this.backToBacks});

  factory TeamSchedule.fromJson(Map<String, dynamic> json) {
    final gamesList = (json['games'] as List)
        .map((d) => DateTime.parse(d as String))
        .toList()
      ..sort();
    final b2bSet = (json['backToBacks'] as List)
        .map((d) => DateTime.parse(d as String))
        .toSet();
    return TeamSchedule(games: gamesList, backToBacks: b2bSet);
  }

  /// Number of games whose date falls within [start, end] inclusive.
  int gamesInWindow(DateTime start, DateTime end) {
    final startDay = _dateOnly(start);
    final endDay = _dateOnly(end);
    return games
        .where((g) {
          final day = _dateOnly(g);
          return !day.isBefore(startDay) && !day.isAfter(endDay);
        })
        .length;
  }

  /// Whether [date] is in the back-to-back set (date comparison, time ignored).
  bool hasBackToBackOn(DateTime date) {
    final target = _dateOnly(date);
    return backToBacks.any((b) => _dateOnly(b) == target);
  }

  /// Whether this team has a game on [date] (time ignored).
  bool hasGameOn(DateTime date) {
    final target = _dateOnly(date);
    return games.any((g) => _dateOnly(g) == target);
  }

  /// Number of games in the current week (Monday–Sunday window containing
  /// [today]).
  int gamesThisWeek(DateTime today) {
    final monday = _weekMonday(today);
    final sunday = monday.add(const Duration(days: 6));
    return gamesInWindow(monday, sunday);
  }
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Returns the Monday of the week containing [date] (ISO week: Mon=1 … Sun=7).
DateTime _weekMonday(DateTime date) {
  final day = _dateOnly(date);
  // DateTime.weekday: Mon=1, Tue=2, … Sun=7
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Loads the bundled schedule JSON and returns a parsed [NbaSchedule].
Future<NbaSchedule> loadNbaSchedule() async {
  final raw = await rootBundle.loadString('assets/data/nba_schedule.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return NbaSchedule.fromJson(json);
}
