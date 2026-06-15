import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/room_observation.dart';
import 'package:saturday_consumer_app/providers/room_observation_provider.dart';

/// One quiet line in the witness register — the room remembering. See
/// `docs/ROOM_OBSERVATIONS.md` for the categories, thresholds, and voice
/// rules. Renders nothing when no observation is available; absence is a
/// valid outcome per the constitution.
class RoomObservationLine extends ConsumerWidget {
  const RoomObservationLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SaturdayColorTokens.of(context);
    final async = ref.watch(roomObservationProvider);

    final observation = async.maybeWhen(
      data: (o) => o,
      orElse: () => null,
    );
    if (observation == null) return const SizedBox.shrink();

    return _ObservationText(observation: observation, colors: colors);
  }
}

class _ObservationText extends StatelessWidget {
  const _ObservationText({
    required this.observation,
    required this.colors,
  });

  final RoomObservation observation;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final baseStyle = SaturdayType.bodySerif.copyWith(
      color: colors.inkSecondary,
      fontSize: 16,
    );
    final emphasis = TextStyle(
      fontStyle: FontStyle.italic,
      color: colors.ink,
    );

    final spans = _spansFor(observation, emphasis);
    final destination = _destinationFor(observation);

    final text = RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );

    if (destination == null) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(destination),
      child: text,
    );
  }

  String? _destinationFor(RoomObservation o) {
    switch (o) {
      case TemporalEchoObservation(:final libraryAlbumId):
        return libraryAlbumId == null ? null : '/library/album/$libraryAlbumId';
      case RecurringRecordObservation(:final libraryAlbumId):
        return libraryAlbumId == null ? null : '/library/album/$libraryAlbumId';
      case CratelistQuietObservation(:final cratelistId):
        return cratelistId == null
            ? null
            : '/library/cratelists/$cratelistId';
    }
  }

  List<InlineSpan> _spansFor(RoomObservation o, TextStyle emphasis) {
    switch (o) {
      case TemporalEchoObservation():
        return _temporalEchoSpans(o, emphasis);
      case CratelistQuietObservation():
        return _cratelistQuietSpans(o);
      case RecurringRecordObservation():
        return _recurringRecordSpans(o, emphasis);
    }
  }

  List<InlineSpan> _temporalEchoSpans(
    TemporalEchoObservation o,
    TextStyle emphasis,
  ) {
    // The RPC only returns days_ago values inside three named windows;
    // each window has its own phrasing.
    final lede = switch (o.daysAgo) {
      >= 7 && <= 14 => 'Last week around this time, ',
      >= 28 && <= 35 => 'A month ago tonight: ',
      >= 360 && <= 370 => 'A year ago tonight: ',
      _ => 'Around this time before, ',
    };
    final tail = o.daysAgo >= 28 ? '.' : ' was on the stand.';
    return [
      TextSpan(text: lede),
      TextSpan(text: o.albumTitle, style: emphasis),
      TextSpan(text: tail),
    ];
  }

  List<InlineSpan> _cratelistQuietSpans(CratelistQuietObservation o) {
    final days = o.daysSinceLastPlay;
    final duration = days == null
        ? 'a while'
        : days >= 365
            ? 'a year'
            : days >= 60
                ? '${_spell(days ~/ 30)} months'
                : 'a month';
    return [
      TextSpan(text: "It's been $duration since anything from the "),
      TextSpan(
        text: o.cratelistName,
        style: TextStyle(color: colors.ink),
      ),
      const TextSpan(text: ' cratelist came off the shelf.'),
    ];
  }

  List<InlineSpan> _recurringRecordSpans(
    RecurringRecordObservation o,
    TextStyle emphasis,
  ) {
    return [
      TextSpan(text: o.albumTitle, style: emphasis),
      TextSpan(text: ' has come back ${_spell(o.playCount)} times this season.'),
    ];
  }
}

/// Spells small whole numbers per the constitution's witness register
/// ("twenty-three plays," not "23"). Falls back to digits past 99 — play
/// counts in a 90-day window won't realistically reach that.
String _spell(int n) {
  if (n < 0) return n.toString();
  if (n < 20) return _ones[n];
  if (n < 100) {
    final tens = _tens[n ~/ 10];
    final remainder = n % 10;
    return remainder == 0 ? tens : '$tens-${_ones[remainder]}';
  }
  return n.toString();
}

const _ones = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];

const _tens = [
  '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
  'eighty', 'ninety',
];
