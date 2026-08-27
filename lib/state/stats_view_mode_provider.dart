import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which stat line the pool screen displays per player - the ranking itself
/// always uses the projected fields regardless of this toggle; this only
/// controls what's shown alongside the z-score for reference/comparison.
enum StatsViewMode { projected, lastYear }

final statsViewModeProvider = StateProvider<StatsViewMode>((ref) => StatsViewMode.projected);
