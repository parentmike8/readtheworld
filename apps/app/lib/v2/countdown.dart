/// Countdown to the next 00:00 America/New_York rollover — the single daily
/// moment when every room closes yesterday's set, scores it, and reveals.
///
/// The backend rollover runs on `EASTERN_TIME_ZONE` (functions/src/scoring.ts).
/// The client has no timezone package, so we compute the US Eastern offset with
/// the fixed federal DST rule: EDT (UTC-4) from the 2nd Sunday of March 02:00
/// to the 1st Sunday of November 02:00, EST (UTC-5) otherwise.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens_v2.dart';
import 'widgets_v2.dart';

DateTime _nthSundayUtc(int year, int month, int nth, int hourUtc) {
  var day = DateTime.utc(year, month, 1);
  var count = 0;
  while (true) {
    if (day.weekday == DateTime.sunday) {
      count++;
      if (count == nth) break;
    }
    day = day.add(const Duration(days: 1));
  }
  return DateTime.utc(year, month, day.day, hourUtc);
}

/// Hours to subtract from UTC to reach US Eastern wall-clock time.
Duration easternUtcOffset(DateTime instantUtc) {
  final utc = instantUtc.toUtc();
  final year = utc.year;
  final dstStart = _nthSundayUtc(year, DateTime.march, 2, 7); // 02:00 EST
  final dstEnd = _nthSundayUtc(year, DateTime.november, 1, 6); // 02:00 EDT
  final isDst = utc.isAfter(dstStart) && utc.isBefore(dstEnd);
  return Duration(hours: isDst ? 4 : 5);
}

/// The UTC instant of the next 00:00 America/New_York (the daily reveal).
///
/// The offset must be sampled AT the target midnight, not now — on DST
/// transition days the current offset is an hour off for the next midnight.
/// Mirrors the backend's easternMidnightUtcForDailyKey
/// (functions/src/seedQuestions.ts): sample the offset near the target
/// instant, form a candidate, then correct once with the offset at the
/// candidate itself.
DateTime nextEasternMidnightUtc(DateTime nowUtc) {
  final now = nowUtc.toUtc();
  final etWall =
      now.subtract(easternUtcOffset(now)); // ET wall clock in UTC fields
  final nextEtDate = DateTime.utc(etWall.year, etWall.month, etWall.day)
      .add(const Duration(days: 1));
  // 05:00 UTC on the target date is midnight EST / 01:00 EDT — always on the
  // same side of the 02:00 ET transition as the target midnight (same probe
  // the backend uses).
  final offset = easternUtcOffset(
    DateTime.utc(nextEtDate.year, nextEtDate.month, nextEtDate.day, 5),
  );
  var candidate = nextEtDate.add(offset);
  final sampledAtCandidate = easternUtcOffset(candidate);
  if (sampledAtCandidate != offset) {
    candidate = nextEtDate.add(sampledAtCandidate);
  }
  return candidate;
}

/// "Reveal in 7h 04m" / "Reveal in 42m 18s" / "Revealing now".
String revealCountdownLabel(Duration remaining, {String prefix = 'Reveal in '}) {
  if (remaining.inSeconds <= 0) return 'Revealing now';
  if (remaining.inHours >= 1) {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return '$prefix${h}h ${m.toString().padLeft(2, '0')}m';
  }
  final m = remaining.inMinutes;
  final s = remaining.inSeconds % 60;
  return '$prefix${m}m ${s.toString().padLeft(2, '0')}s';
}

/// Live "Reveal in Xh XXm" text that ticks toward the next 00:00 ET rollover.
class RevealCountdown extends StatefulWidget {
  const RevealCountdown({
    super.key,
    this.builder,
    this.prefix = 'Reveal in ',
    this.style,
  });

  /// Optional custom rendering; receives the formatted label + raw remaining.
  final Widget Function(BuildContext, String label, Duration remaining)? builder;
  final String prefix;
  final TextStyle? style;

  @override
  State<RevealCountdown> createState() => _RevealCountdownState();
}

class _RevealCountdownState extends State<RevealCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _compute();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _compute());
    });
  }

  Duration _compute() {
    final now = DateTime.now().toUtc();
    final target = nextEasternMidnightUtc(now);
    final diff = target.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = revealCountdownLabel(_remaining, prefix: widget.prefix);
    if (widget.builder != null) {
      return widget.builder!(context, label, _remaining);
    }
    return Text(
      label,
      style: widget.style ??
          v2Sans(13.5, color: RtwV2Colors.blue, weight: FontWeight.w700),
    );
  }
}
