import 'package:flutter_test/flutter_test.dart';

import 'package:read_the_world/v2/countdown.dart';
import 'package:read_the_world/v2/screens/play_surface.dart';

void main() {
  group('nextEasternMidnightUtc', () {
    test('regular summer and winter days', () {
      // 2026-07-15 00:00 UTC is 20:00 EDT on Jul 14 → next ET midnight is
      // Jul 15 00:00 EDT = 04:00 UTC.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 7, 15)),
        DateTime.utc(2026, 7, 15, 4),
      );
      // 2026-01-10 12:00 UTC is 07:00 EST → next midnight = Jan 11 05:00 UTC.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 1, 10, 12)),
        DateTime.utc(2026, 1, 11, 5),
      );
    });

    test('spring forward (2026-03-08) samples the offset at the target', () {
      // 01:00 EST on the transition day (06:00 UTC): the NEXT midnight
      // (Mar 9 00:00 ET) is EDT, so the target is 04:00 UTC — applying the
      // still-EST current offset would say 05:00 and run an hour long.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 3, 8, 6)),
        DateTime.utc(2026, 3, 9, 4),
      );
      // Late Mar 7 EST: the next midnight (Mar 8 00:00 ET) is before the
      // 02:00 jump, so it stays EST-based at 05:00 UTC.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 3, 8, 3)),
        DateTime.utc(2026, 3, 8, 5),
      );
      // After the jump (08:00 EDT): next midnight Mar 9 is EDT.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 3, 8, 12)),
        DateTime.utc(2026, 3, 9, 4),
      );
    });

    test('fall back (2026-11-01) samples the offset at the target', () {
      // 00:00 EDT on the transition day (04:00 UTC): the NEXT midnight
      // (Nov 2 00:00 ET) is EST, so the target is 05:00 UTC — applying the
      // still-EDT current offset would say 04:00 and reveal an hour early.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 11, 1, 4)),
        DateTime.utc(2026, 11, 2, 5),
      );
      // The evening before (Oct 31 EDT): midnight Nov 1 lands before the
      // 02:00 fall-back, so it is still EDT-based at 04:00 UTC.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 10, 31, 12)),
        DateTime.utc(2026, 11, 1, 4),
      );
      // After the fold (01:30 EST = 06:30 UTC): next midnight Nov 2 is EST.
      expect(
        nextEasternMidnightUtc(DateTime.utc(2026, 11, 1, 6, 30)),
        DateTime.utc(2026, 11, 2, 5),
      );
    });
  });

  group('revealLabelFor', () {
    test('diffs against the ET calendar day, not the device-local one', () {
      // 00:00 UTC Jul 15 is still Jul 14 in ET. A reader east of ET (already
      // on Jul 15 locally) must still see the Jul 13 key as yesterday, not
      // as a weekday label.
      expect(
        revealLabelFor('2026-07-13', nowUtc: DateTime.utc(2026, 7, 15)),
        "YESTERDAY'S REVEAL",
      );
    });

    test('weekday and dated labels also diff in ET', () {
      // ET today is Tue Jul 14 → Fri Jul 10 was 4 days ago.
      expect(
        revealLabelFor('2026-07-10', nowUtc: DateTime.utc(2026, 7, 15)),
        "FRIDAY'S REVEAL",
      );
      expect(
        revealLabelFor('2026-06-01', nowUtc: DateTime.utc(2026, 7, 15)),
        'JUN 1 REVEAL',
      );
    });

    test('falls back to yesterday for missing or malformed keys', () {
      expect(revealLabelFor(null), "YESTERDAY'S REVEAL");
      expect(revealLabelFor('not-a-date'), "YESTERDAY'S REVEAL");
    });
  });
}
