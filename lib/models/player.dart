/// Where a player's numbers came from, so the UI/engine can be honest about
/// confidence instead of presenting everything as an equally-solid projection.
enum DataSource { screenshotProjection, priorSeasonActual, priorSeasonRegressed }

DataSource dataSourceFromKey(String key) => DataSource.values.firstWhere(
      (d) => d.name == key,
      orElse: () => DataSource.screenshotProjection,
    );

/// One full per-category stat line - used both for this season's projection
/// (the fields on [Player] itself) and, optionally, for last season's actual
/// numbers ([Player.priorSeason]), so the pool screen can show either.
class StatLine {
  final double fgPct;
  final int fgAttempted; // 0 if unknown
  final double ftPct;
  final int ftAttempted; // 0 if unknown
  final int threePM;
  final int pts;
  final int reb;
  final int ast;
  final int stl;
  final int blk;
  final int to;

  const StatLine({
    required this.fgPct,
    required this.fgAttempted,
    required this.ftPct,
    required this.ftAttempted,
    required this.threePM,
    required this.pts,
    required this.reb,
    required this.ast,
    required this.stl,
    required this.blk,
    required this.to,
  });

  factory StatLine.fromJson(Map<String, dynamic> json) {
    return StatLine(
      fgPct: (json['fgPct'] as num).toDouble(),
      fgAttempted: (json['fgAttempted'] as num?)?.toInt() ?? 0,
      ftPct: (json['ftPct'] as num).toDouble(),
      ftAttempted: (json['ftAttempted'] as num?)?.toInt() ?? 0,
      threePM: json['threePM'] as int,
      pts: json['pts'] as int,
      reb: json['reb'] as int,
      ast: json['ast'] as int,
      stl: json['stl'] as int,
      blk: json['blk'] as int,
      to: json['to'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'fgPct': fgPct,
        'fgAttempted': fgAttempted,
        'ftPct': ftPct,
        'ftAttempted': ftAttempted,
        'threePM': threePM,
        'pts': pts,
        'reb': reb,
        'ast': ast,
        'stl': stl,
        'blk': blk,
        'to': to,
      };
}

class Player {
  final String id;
  final String name;
  final String team;
  final List<String> eligiblePositions;
  final int gp;

  final double fgPct;
  final int fgAttempted; // 0 if unknown (not yet merged with prior-season data)
  final double ftPct;
  final int ftAttempted; // 0 if unknown

  final int threePM;
  final int pts;
  final int reb;
  final int ast;
  final int stl;
  final int blk;
  final int to;

  final double? adp;

  /// The rank this player had in the original source (e.g. Yahoo's XRank
  /// column from the pre-draft screenshots) - kept alongside our own
  /// z-score-derived rank so the pool screen can sort by either.
  final int? sourceRank;

  final DataSource dataSource;

  /// Last completed season's actual full stat line, fetched once via the
  /// data_prep Yahoo pull (not re-fetched live) - null for rookies with no
  /// prior NBA season. Purely a display/reference alternative in the pool
  /// screen; ranking always uses the projected fields above.
  final StatLine? priorSeason;

  /// NBA Stats player ID, used to load the official headshot from the CDN:
  /// https://cdn.nba.com/headshots/nba/latest/260x190/{nbaId}.png
  /// Null for players not yet matched (e.g. 2026-27 draft picks).
  final int? nbaId;

  const Player({
    required this.id,
    required this.name,
    required this.team,
    required this.eligiblePositions,
    required this.gp,
    required this.fgPct,
    required this.fgAttempted,
    required this.ftPct,
    required this.ftAttempted,
    required this.threePM,
    required this.pts,
    required this.reb,
    required this.ast,
    required this.stl,
    required this.blk,
    required this.to,
    this.adp,
    this.sourceRank,
    this.dataSource = DataSource.screenshotProjection,
    this.priorSeason,
    this.nbaId,
  });

  StatLine get projectedStatLine => StatLine(
        fgPct: fgPct,
        fgAttempted: fgAttempted,
        ftPct: ftPct,
        ftAttempted: ftAttempted,
        threePM: threePM,
        pts: pts,
        reb: reb,
        ast: ast,
        stl: stl,
        blk: blk,
        to: to,
      );

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      team: json['team'] as String,
      eligiblePositions: (json['eligiblePositions'] as List).cast<String>(),
      gp: json['gp'] as int,
      fgPct: (json['fgPct'] as num).toDouble(),
      fgAttempted: (json['fgAttempted'] as num?)?.toInt() ?? 0,
      ftPct: (json['ftPct'] as num).toDouble(),
      ftAttempted: (json['ftAttempted'] as num?)?.toInt() ?? 0,
      threePM: json['threePM'] as int,
      pts: json['pts'] as int,
      reb: json['reb'] as int,
      ast: json['ast'] as int,
      stl: json['stl'] as int,
      blk: json['blk'] as int,
      to: json['to'] as int,
      adp: (json['adp'] as num?)?.toDouble(),
      sourceRank: (json['sourceRank'] as num?)?.toInt(),
      dataSource: dataSourceFromKey(json['dataSource'] as String? ?? 'screenshotProjection'),
      priorSeason: json['priorSeason'] == null
          ? null
          : StatLine.fromJson(json['priorSeason'] as Map<String, dynamic>),
      nbaId: (json['nbaId'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'team': team,
        'eligiblePositions': eligiblePositions,
        'gp': gp,
        'fgPct': fgPct,
        'fgAttempted': fgAttempted,
        'ftPct': ftPct,
        'ftAttempted': ftAttempted,
        'threePM': threePM,
        'pts': pts,
        'reb': reb,
        'ast': ast,
        'stl': stl,
        'blk': blk,
        'to': to,
        'adp': adp,
        'sourceRank': sourceRank,
        'dataSource': dataSource.name,
        'priorSeason': priorSeason?.toJson(),
      };
}
