import 'package:intl/intl.dart';
import 'salah_calendar_model.dart';
import '../models/prayer_time_data.dart';

class SalahTimeUtils {
  /// Parse a time string like "5:30 AM" using a base date
  static DateTime parse(String time, DateTime baseDate) {
    try {
      final format = DateFormat('h:mm a');
      final parsed = format.parse(time);
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        parsed.hour,
        parsed.minute,
      );
    } catch (e) {
      // fallback to midnight if parsing fails
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 0, 0);
    }
  }

  /// Subtract N minutes
  static DateTime subtractMinutes(DateTime time, int mins) {
    return time.subtract(Duration(minutes: mins));
  }

  /// Convert a SalahCalendarModel entry to PrayerTimeData list
  static List<PrayerTimeData> fromSalahCalendarModel(SalahCalendarModel day) {
    final date = DateTime(DateTime.now().year, day.month, day.day);

    // ---------------- START TIMES ----------------
    final fajrStart = parse(day.fajrAzan, date);
    final dhuhrStart = parse(day.dhuhrAzan, date);
    final asrStart = parse(day.asrAzan, date);
    final maghribStart = parse(day.maghribAzan, date);
    final ishaStart = parse(day.ishaAzan, date);

    // ---------------- END TIMES ----------------
    final fajrEnd = parse(day.fajrJamat, date);
    final dhuhrEnd = subtractMinutes(asrStart, 5);
    final asrEnd = subtractMinutes(maghribStart, 5);
    final maghribEnd = subtractMinutes(ishaStart, 5);

    // Isha end = next day's Fajr start - 5 minutes
    final nextDay = date.add(const Duration(days: 1));
    final nextFajrStart = parse(day.fajrAzan, nextDay);
    final ishaEnd = subtractMinutes(nextFajrStart, 5);

    return [
      PrayerTimeData(name: 'Fajr', startTime: fajrStart, endTime: fajrEnd),
      PrayerTimeData(name: 'Dhuhr', startTime: dhuhrStart, endTime: dhuhrEnd),
      PrayerTimeData(name: 'Asr', startTime: asrStart, endTime: asrEnd),
      PrayerTimeData(
        name: 'Maghrib',
        startTime: maghribStart,
        endTime: maghribEnd,
      ),
      PrayerTimeData(name: 'Isha', startTime: ishaStart, endTime: ishaEnd),
    ];
  }

  /// Returns index of current prayer based on now
  static int getCurrentPrayerIndex(List<PrayerTimeData> prayers) {
    final now = DateTime.now();
    for (int i = 0; i < prayers.length; i++) {
      final p = prayers[i];
      if (now.isAfter(p.startTime) && now.isBefore(p.endTime)) {
        return i;
      }
      // Special case: Isha crossing midnight
      if (p.name.toLowerCase() == 'isha' &&
          now.isAfter(p.startTime) &&
          now.isBefore(p.endTime.add(const Duration(days: 1)))) {
        return i;
      }
    }
    return -1;
  }
}
