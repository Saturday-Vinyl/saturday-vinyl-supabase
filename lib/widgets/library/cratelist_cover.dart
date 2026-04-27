import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Composite cover art for a cratelist: a 2x2 grid of the first up to four
/// album covers in the list. Falls back gracefully when fewer covers are
/// available.
class CratelistCover extends StatelessWidget {
  const CratelistCover({
    super.key,
    required this.coverUrls,
    this.borderRadius,
  });

  final List<String> coverUrls;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.largeRadius;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (coverUrls.isEmpty) {
      return _placeholder();
    }
    if (coverUrls.length == 1) {
      return _coverImage(coverUrls[0]);
    }

    // 2x2 grid; pad missing slots with the placeholder so the layout
    // stays square even with 2 or 3 covers.
    final slots = <Widget>[
      for (var i = 0; i < 4; i++)
        i < coverUrls.length ? _coverImage(coverUrls[i]) : _placeholder(),
    ];

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: slots[0]),
              Expanded(child: slots[1]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: slots[2]),
              Expanded(child: slots[3]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => _shimmer(),
      errorWidget: (context, _, __) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: AppIconSizes.md,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }

  Widget _shimmer() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.1),
    );
  }
}
