import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/schedule_service.dart';

/// Loads and exposes the NBA schedule from the bundled JSON asset.
/// Consumers use `.when(data: ..., loading: ..., error: ...)` or `.value`
/// (with a null guard) in the same pattern as [leagueDataProvider].
final scheduleProvider = FutureProvider<NbaSchedule>((ref) => loadNbaSchedule());
