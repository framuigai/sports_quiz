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
      onOpen: (db) async {
        // Day 11: ensure attempts tables exist even if schema.sql wasn't updated yet
        await _ensureMigrations(db);
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

  /// Ensure new tables exist (idempotent) without bumping DB version.
  static Future<void> _ensureMigrations(Database db) async {
    // attempts
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attempts (
        attempt_id   TEXT PRIMARY KEY,
        quiz_id      TEXT NOT NULL,
        quiz_title   TEXT NOT NULL,
        difficulty   TEXT NOT NULL,
        started_at   TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        score        INTEGER NOT NULL,
        num_correct  INTEGER NOT NULL,
        num_total    INTEGER NOT NULL
      );
    ''');

    // attempt_answers
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attempt_answers (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        attempt_id    TEXT NOT NULL,
        question_id   TEXT NOT NULL,
        q_index       INTEGER NOT NULL,
        selected_index INTEGER NOT NULL,
        correct_index  INTEGER NOT NULL,
        is_correct     INTEGER NOT NULL,
        elapsed_ms     INTEGER NULL,
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id) ON DELETE CASCADE
      );
    ''');
  }
}
