import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';

/// Composite cover art for a cratelist: a 2x2 grid of the first up to four
/// album covers in the list. Falls back gracefully when fewer covers are
/// available. No drop shadow — separation comes from the surrounding card
/// or grid layout.
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
    final colors = SaturdayColorTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(8);

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: radius,
        child: _content(colors),
      ),
    );
  }

  Widget _content(SaturdayColorTokens colors) {
    if (coverUrls.isEmpty) {
      return _placeholder(colors);
    }
    if (coverUrls.length == 1) {
      return _coverImage(coverUrls[0], colors);
    }

    // 2x2 grid; pad missing slots with the placeholder so the layout
    // stays square even with 2 or 3 covers.
    final slots = <Widget>[
      for (var i = 0; i < 4; i++)
        i < coverUrls.length
            ? _coverImage(coverUrls[i], colors)
            : _placeholder(colors),
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

  Widget _coverImage(String url, SaturdayColorTokens colors) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => Container(color: colors.paperElevated),
      errorWidget: (context, _, __) => _placeholder(colors),
    );
  }

  Widget _placeholder(SaturdayColorTokens colors) {
    return Container(
      color: colors.paperElevated,
      child: Center(
        child: Icon(Icons.album_outlined, size: 20, color: colors.inkTertiary),
      ),
    );
  }
}
