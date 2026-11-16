import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/screens/matchup_screen.dart';
import 'package:rosteriq/services/schedule_service.dart';

void main() {
  test('fantasyWeekDates: Monday-Sunday weeks from the opener\'s week', () {
    final s = NbaSchedule.fromJson(jsonDecode(File('assets/data/nba_schedule.json').readAsStringSync()) as Map<String, dynamic>);
    expect(fantasyWeekDates(1, s), (start: DateTime(2026, 10, 19), end: DateTime(2026, 10, 25)));
    expect(fantasyWeekDates(5, s), (start: DateTime(2026, 11, 16), end: DateTime(2026, 11, 22)));
  });
}
