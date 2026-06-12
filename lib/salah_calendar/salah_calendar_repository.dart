import 'package:sqflite/sqflite.dart';
import 'salah_calendar_model.dart';

class SalahCalendarRepository {
  final Database _db;

  SalahCalendarRepository(this._db);

  /// Get the Salah row for a particular date
  Future<SalahCalendarModel?> getByDate(DateTime date) async {
    try {
      final day = date.day;
      final month = date.month;

      // Correct WHERE clause
      final List<Map<String, dynamic>> result = await _db.query(
        'salah_calendar',
        where: 'start_day <= ? AND end_day >= ? AND month = ?',
        whereArgs: [day, day, month],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final row = result.first;

        // DEBUG: print the fetched row
        print('SalahCalendar fetched row: $row');

        return SalahCalendarModel.fromMap(row);
      } else {
        print('SalahCalendar: No row found for $date');
        return null;
      }
    } catch (e) {
      print('SalahCalendar: Error in getByDate → $e');
      return null;
    }
  }
}
