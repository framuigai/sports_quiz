// lib/services/sqlite_service.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;

class SQLiteService {
  static Database? _db;

  /// Enable to print each statement executed from schema.sql on first boot.
  static const bool debugLogging = false;

  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'quiz_cache.db');

    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Ensure FKs are enforced for this connection.
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await _runSchema(db);
      },
    );
  }

  static Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('SQLiteService.init() not called before use.');
    }
    return d;
  }

  /// Loads lib/db/schema.sql (declared in pubspec) and executes it safely.
  static Future<void> _runSchema(Database db) async {
    // Keep this path in sync with pubspec.yaml
    final rawSchema = await rootBundle.loadString('lib/db/schema.sql');

    // 1) Remove block comments: /* ... */
    String cleaned = rawSchema.replaceAll(
      RegExp(r'/\*[\s\S]*?\*/', multiLine: true),
      '',
    );

    // 2) Remove line comments starting with -- or //
    final sb = StringBuffer();
    for (final line in const LineSplitter().convert(cleaned)) {
      final l = line.trimLeft();
      if (l.startsWith('--')) continue;
      if (l.startsWith('//')) continue;
      sb.writeln(line);
    }
    cleaned = sb.toString();

    // 3) Split by semicolon; ignore empty statements.
    final statements = cleaned
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // 4) Execute inside a transaction for atomic setup.
    await db.transaction((txn) async {
      for (final stmt in statements) {
        if (debugLogging) {
          // ignore: avoid_print
          print('🟦 SQL: $stmt;');
        }
        await txn.execute(stmt);
      }
    });
  }
}
