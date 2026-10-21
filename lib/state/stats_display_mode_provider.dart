import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether stat numbers are shown as season totals or per-game averages.
/// Purely a display choice - independent of [StatsViewMode] (which season's
/// data to show) and doesn't affect ranking, which always works in per-game
/// rate terms internally regardless of this toggle.
enum StatsDisplayMode { totals, perGame }

final statsDisplayModeProvider = StateProvider<StatsDisplayMode>((ref) => StatsDisplayMode.totals);
