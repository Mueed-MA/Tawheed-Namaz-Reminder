import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class SalahDatabaseHelper {
  SalahDatabaseHelper._privateConstructor();
  static final SalahDatabaseHelper instance =
      SalahDatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'salah_calendar.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _executeScript(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS salah_calendar');
        await _executeScript(db);
      },
    );
  }

  Future<void> _executeScript(Database db) async {
    String script = await rootBundle.loadString(
      'lib/salah_calendar/salah_calendar.sql',
    );
    List<String> statements = script.split(';');

    for (var statement in statements) {
      if (statement.trim().isNotEmpty) {
        await db.execute(statement);
      }
    }
  }

  // ==========================================================
  // NEW: Get salah calendar row for a specific date
  // ==========================================================
  Future<Map<String, dynamic>?> getRowForDate(DateTime date) async {
    final db = await database;

    final result = await db.query(
      'salah_calendar',
      where: 'month = ? AND start_day <= ? AND end_day >= ?',
      whereArgs: [date.month, date.day, date.day],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }
}
