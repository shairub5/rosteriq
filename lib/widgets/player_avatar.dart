import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shows an NBA headshot from the official CDN when [nbaId] is available,
/// falling back to a circular initials avatar otherwise.
///
/// Headshot URL: https://cdn.nba.com/headshots/nba/latest/260x190/{nbaId}.png
class PlayerAvatar extends StatelessWidget {
  final int? nbaId;
  final String playerName;
  final double radius;

  const PlayerAvatar({
    super.key,
    required this.nbaId,
    required this.playerName,
    this.radius = 20,
  });

  String get _initials {
    final parts = playerName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final id = nbaId;
    if (id == null) {
      return _InitialsAvatar(initials: _initials, radius: radius);
    }

    final url =
        'https://cdn.nba.com/headshots/nba/latest/260x190/$id.png';

    return CachedNetworkImage(
      imageUrl: url,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      placeholder: (context, url) => _InitialsAvatar(
        initials: _initials,
        radius: radius,
        loading: true,
      ),
      errorWidget: (context, url, error) => _InitialsAvatar(
        initials: _initials,
        radius: radius,
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final double radius;
  final bool loading;

  const _InitialsAvatar({
    required this.initials,
    required this.radius,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primaryContainer;
    final onColor = Theme.of(context).colorScheme.onPrimaryContainer;
    return CircleAvatar(
      radius: radius,
      backgroundColor: loading ? Theme.of(context).colorScheme.surfaceContainerHighest : color,
      child: loading
          ? SizedBox(
              width: radius * 0.8,
              height: radius * 0.8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Theme.of(context).colorScheme.outline,
              ),
            )
          : Text(
              initials,
              style: TextStyle(
                fontSize: radius * 0.65,
                fontWeight: FontWeight.w700,
                color: onColor,
              ),
            ),
    );
  }
}
