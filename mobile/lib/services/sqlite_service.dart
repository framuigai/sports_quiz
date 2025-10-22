import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;

class SQLiteService {
  static Database? _db;

  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'quiz_cache.db');

    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('PRAGMA foreign_keys = ON;');

      // Load schema.sql bundled in assets
      final schema = await rootBundle.loadString('lib/db/schema.sql');
      // Execute statements; simple split by ';' works for our schema
      for (final stmt in schema.split(';')) {
        final s = stmt.trim();
        if (s.isNotEmpty) {
          await db.execute(s);
        }
      }
    });
  }

  static Database get db {
    if (_db == null) {
      throw StateError('SQLiteService.init() not called before use.');
    }
    return _db!;
  }
}
