/// The 9 roto/H2H categories for this league. Order here drives display order
/// and is not significant to the math.
enum StatCategory { fgPct, ftPct, threePM, pts, reb, ast, stl, blk, to }

const List<StatCategory> allStatCategories = StatCategory.values;

extension StatCategoryX on StatCategory {
  String get label {
    switch (this) {
      case StatCategory.fgPct:
        return 'FG%';
      case StatCategory.ftPct:
        return 'FT%';
      case StatCategory.threePM:
        return '3PM';
      case StatCategory.pts:
        return 'PTS';
      case StatCategory.reb:
        return 'REB';
      case StatCategory.ast:
        return 'AST';
      case StatCategory.stl:
        return 'STL';
      case StatCategory.blk:
        return 'BLK';
      case StatCategory.to:
        return 'TO';
    }
  }

  /// Turnovers are the one category where a lower raw value is better.
  bool get lowerIsBetter => this == StatCategory.to;

  String get key => name;

  static StatCategory fromKey(String key) =>
      StatCategory.values.firstWhere((c) => c.name == key);
}
