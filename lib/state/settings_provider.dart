import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyScheduleBoost = 'settings_schedule_boost';
const _keyPositionalNeed = 'settings_positional_need';
const _keyPlayoffStart = 'settings_playoff_start';
const _keyPlayoffEnd = 'settings_playoff_end';

const _defaultPlayoffStart = '2027-03-08';
const _defaultPlayoffEnd = '2027-03-28';

/// Persisted app settings that affect the ranking engine.
class AppSettings {
  /// Weight applied to schedule-strength (playoff games) bonus. Range 0.0–1.0.
  final double scheduleBoostWeight;

  /// Weight applied to positional scarcity bonus. Range 0.0–1.0.
  final double positionalNeedWeight;

  /// ISO date string for the start of the fantasy playoff window.
  final String playoffStart;

  /// ISO date string for the end of the fantasy playoff window.
  final String playoffEnd;

  const AppSettings({
    this.scheduleBoostWeight = 0.5,
    this.positionalNeedWeight = 1.0,
    this.playoffStart = _defaultPlayoffStart,
    this.playoffEnd = _defaultPlayoffEnd,
  });

  AppSettings copyWith({
    double? scheduleBoostWeight,
    double? positionalNeedWeight,
    String? playoffStart,
    String? playoffEnd,
  }) {
    return AppSettings(
      scheduleBoostWeight: scheduleBoostWeight ?? this.scheduleBoostWeight,
      positionalNeedWeight: positionalNeedWeight ?? this.positionalNeedWeight,
      playoffStart: playoffStart ?? this.playoffStart,
      playoffEnd: playoffEnd ?? this.playoffEnd,
    );
  }
}

/// [StateNotifier] that persists [AppSettings] via shared_preferences.
/// Loads initial values from disk during construction; callers can read
/// `.state` immediately (defaults are used until the async load resolves).
class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      scheduleBoostWeight: prefs.getDouble(_keyScheduleBoost) ?? 0.5,
      positionalNeedWeight: prefs.getDouble(_keyPositionalNeed) ?? 1.0,
      playoffStart: prefs.getString(_keyPlayoffStart) ?? _defaultPlayoffStart,
      playoffEnd: prefs.getString(_keyPlayoffEnd) ?? _defaultPlayoffEnd,
    );
  }

  Future<void> setScheduleBoostWeight(double value) async {
    state = state.copyWith(scheduleBoostWeight: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyScheduleBoost, value);
  }

  Future<void> setPositionalNeedWeight(double value) async {
    state = state.copyWith(positionalNeedWeight: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPositionalNeed, value);
  }

  Future<void> setPlayoffStart(String isoDate) async {
    state = state.copyWith(playoffStart: isoDate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayoffStart, isoDate);
  }

  Future<void> setPlayoffEnd(String isoDate) async {
    state = state.copyWith(playoffEnd: isoDate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayoffEnd, isoDate);
  }
}

final settingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);
