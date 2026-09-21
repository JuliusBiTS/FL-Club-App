import 'package:intl/intl.dart';

/// Europe/London wall-clock time without a timezone database.
///
/// Every event happens in London, and the club's staff may not be — the
/// editor is used from wherever a producer happens to be (this project's own
/// developer works from a German-locale machine). So event times must never
/// be read or written in the *device's* timezone: 19:00 on the poster is
/// 19:00 London whether the phone is in Paddington or Berlin (briefing §7.3:
/// "venue timezone, never device timezone").
///
/// UK rule: BST (UTC+1) runs from 01:00 UTC on the last Sunday of March to
/// 01:00 UTC on the last Sunday of October; otherwise GMT (UTC+0). That rule
/// has been stable since 1996 and is what `Europe/London` implements.
abstract final class LondonTime {
  static DateTime _lastSunday(int year, int month) {
    final DateTime lastDay = DateTime.utc(year, month + 1, 0);
    return lastDay.subtract(Duration(days: lastDay.weekday % 7)); // Sunday == 7 → 0
  }

  /// Whether London is on British Summer Time at this instant.
  static bool isBst(DateTime instant) {
    final DateTime utc = instant.toUtc();
    final DateTime start = _lastSunday(utc.year, 3).add(const Duration(hours: 1));
    final DateTime end = _lastSunday(utc.year, 10).add(const Duration(hours: 1));
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  /// A UTC instant → London wall-clock time, as a plain (non-UTC) [DateTime]
  /// whose fields read exactly what a clock in London shows. It is a
  /// "floating" value: never call `.toUtc()`/`.toLocal()` on it — use
  /// [toUtc] to go back.
  static DateTime fromUtc(DateTime instant) {
    final DateTime utc = instant.toUtc();
    final DateTime shifted = utc.add(Duration(hours: isBst(utc) ? 1 : 0));
    return DateTime(shifted.year, shifted.month, shifted.day, shifted.hour, shifted.minute, shifted.second);
  }

  /// London wall-clock time (fields read as London time) → the UTC instant.
  ///
  /// At the autumn change the hour 01:00–02:00 happens twice; this picks the
  /// first (BST) reading. At the spring change 01:00–02:00 doesn't exist;
  /// such a time resolves to 02:xx BST. Neither matters for evening events.
  static DateTime toUtc(DateTime wallClock) {
    final DateTime asUtc = DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
    );
    final DateTime ifBst = asUtc.subtract(const Duration(hours: 1));
    return isBst(ifBst) ? ifBst : asUtc;
  }

  /// "Wed 9 Sep 2026, 19:00" — the club's house date style, in London time.
  static String format(DateTime instant, {String pattern = 'EEE d MMM yyyy, HH:mm'}) {
    return DateFormat(pattern).format(fromUtc(instant));
  }
}
