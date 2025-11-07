import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sqlite_service.dart';

class CacheRepository {
  /// Cache of existing columns per table to avoid repeated PRAGMA calls.
  static final Map<String, Set<String>> _tableColumnsCache = {};

  /// Returns the set of existing columns for a given table, cached.
  static Future<Set<String>> _existingColumns(String table) async {
    if (_tableColumnsCache.containsKey(table)) {
      return _tableColumnsCache[table]!;
    }
    final rows = await SQLiteService.db.rawQuery('PRAGMA table_info($table);');
    final cols = rows
        .map((r) => (r['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet();
    _tableColumnsCache[table] = cols;
    return cols;
  }

  /// Filters a payload by both an allowed set and the actual existing columns.
  static Future<Map<String, dynamic>> _filterForTable({
    required String table,
    required Map<String, dynamic> data,
    required Set<String> allowed,
  }) async {
    final existing = await _existingColumns(table);
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      if (allowed.contains(e.key) && existing.contains(e.key)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// Ensure a parent user row exists for FK owner_id → users(uid).
  static Future<void> _ensureUserRow(String uid) async {
    if (uid.isEmpty) return; // nothing we can do
    final found = await SQLiteService.db.query(
      'users',
      columns: const ['uid'],
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (found.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();
    // Minimal insert to satisfy FK; other fields can be filled later from Firestore.
    await SQLiteService.db.insert(
      'users',
      {
        'uid': uid,
        'email': null,
        'display_name': null,
        'role': null,
        'current_plan': null,
        'plan_updated_at': null,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
        'deleted_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // -------------------------
  // QUIZZES (ADMIN/GLOBAL)
  // -------------------------
  static Future<void> saveAdminQuiz(Map<String, dynamic> quiz) async {
    const allowedColumns = {
      'quiz_id',
      'title',
      'description',
      'difficulty',
      'tags',
      'is_admin_quiz',
      'available_to_all',
      'is_approved',
      'deleted',
      'deleted_at',
      'created_at',
      'updated_at',
      // optional if present in schema on device:
      'owner_id',
      'source',
      'num_questions',
    };

    final filtered = await _filterForTable(
      table: 'cache_admin_quizzes',
      data: quiz,
      allowed: allowedColumns,
    );

    await SQLiteService.db.insert(
      'cache_admin_quizzes',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getAdminQuizzes() async {
    return SQLiteService.db.query(
      'cache_admin_quizzes',
      orderBy: 'updated_at DESC',
    );
  }

  // Dev helper for testing
  static Future<void> insertDummyQuiz() async {
    await saveAdminQuiz({
      'quiz_id': 'dummy1',
      'title': 'Dev Dummy Quiz',
      'description': 'Inserted from Dev button',
      'difficulty': 'easy',
      'tags': 'dev,offline',
      'is_admin_quiz': 1,
      'available_to_all': 1,
      'is_approved': 1,
      'deleted': 0,
      'deleted_at': null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // -------------------------
  // QUESTIONS (ADMIN/GLOBAL)
  // -------------------------
  static Future<void> saveAdminQuestions(List<Map<String, dynamic>> questions) async {
    final batch = SQLiteService.db.batch();

    const allowedColumns = {
      'question_id',
      'quiz_id',
      'order',
      'index',
      'text',
      'options',
      'correct_index',
      'image_url',
      'created_at',
      'updated_at',
    };
    final existing = await _existingColumns('cache_admin_questions');

    for (final q in questions) {
      final filtered = <String, dynamic>{};
      for (final e in q.entries) {
        if (allowedColumns.contains(e.key) && existing.contains(e.key)) {
          filtered[e.key] = e.value;
        }
      }
      batch.insert(
        'cache_admin_questions',
        filtered,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getAdminQuestionsByQuizId(String quizId) async {
    return SQLiteService.db.query(
      'cache_admin_questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'COALESCE("order","index") ASC',
    );
  }

  // -------------------------
  // 🆕 QUIZZES (USER / MY QUIZZES)
  // -------------------------
  static Future<void> saveUserQuiz(Map<String, dynamic> quiz) async {
    // Resolve owner_id (from payload or current Firebase user)
    String ownerId = (quiz['owner_id']?.toString() ?? '').trim();
    if (ownerId.isEmpty) {
      ownerId = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    }
    // Ensure parent FK row exists (users.uid = ownerId)
    if (ownerId.isNotEmpty) {
      await _ensureUserRow(ownerId);
    }

    // Build filtered map; make sure owner_id is present in the payload we insert.
    final enriched = Map<String, dynamic>.from(quiz);
    enriched['owner_id'] = ownerId;

    const allowedColumns = {
      'quiz_id',
      'title',
      'description',
      'difficulty',
      'owner_id',
      'source',
      'deleted',
      'deleted_at',
      'created_at',
      'updated_at',
      'num_questions', // safely ignored if device schema lacks it
    };

    final filtered = await _filterForTable(
      table: 'user_quizzes',
      data: enriched,
      allowed: allowedColumns,
    );

    // If, for some reason, owner_id is still missing (empty and column exists),
    // set a last-resort placeholder to avoid NOT NULL FK violation in local dev.
    final existingCols = await _existingColumns('user_quizzes');
    if ((filtered['owner_id'] == null || (filtered['owner_id'] as String).isEmpty) &&
        existingCols.contains('owner_id')) {
      // Create a local placeholder user and use it.
      final placeholder = 'local_${DateTime.now().millisecondsSinceEpoch}';
      await _ensureUserRow(placeholder);
      filtered['owner_id'] = placeholder;
    }

    await SQLiteService.db.insert(
      'user_quizzes',
      filtered,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getMyQuizzes(String ownerId) async {
    return SQLiteService.db.query(
      'user_quizzes',
      where: 'owner_id = ? AND (deleted IS NULL OR deleted = 0)',
      whereArgs: [ownerId],
      orderBy: 'updated_at DESC',
    );
  }

  // -------------------------
  // 🆕 QUESTIONS (USER / MY QUIZZES)
  // -------------------------
  static Future<void> saveUserQuestions(List<Map<String, dynamic>> questions) async {
    final batch = SQLiteService.db.batch();

    const allowedColumns = {
      'question_id',
      'quiz_id',
      'order',
      'index',
      'text',
      'options',
      'correct_index',
      'image_url',
      'created_at',
      'updated_at',
    };
    final existing = await _existingColumns('user_questions');

    for (final q in questions) {
      final filtered = <String, dynamic>{};
      for (final e in q.entries) {
        if (allowedColumns.contains(e.key) && existing.contains(e.key)) {
          filtered[e.key] = e.value;
        }
      }
      batch.insert(
        'user_questions',
        filtered,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getUserQuestionsByQuizId(String quizId) async {
    return SQLiteService.db.query(
      'user_questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'COALESCE("order","index") ASC',
    );
  }

  // -------------------------
  // ATTEMPTS (runtime shape)
  // -------------------------
  static Future<String> insertAttempt(Map<String, dynamic> attempt) async {
    String attemptId =
    (attempt['attempt_id'] ?? _pseudoUuid('att_')).toString();

    final data = {
      'attempt_id': attemptId,
      'quiz_id': attempt['quiz_id']?.toString() ?? '',
      'quiz_title': attempt['quiz_title']?.toString() ?? '',
      'difficulty': attempt['difficulty']?.toString() ?? '',
      'started_at': attempt['started_at']?.toString() ?? '',
      'completed_at': attempt['completed_at']?.toString() ?? '',
      'score': attempt['score'] ?? 0,
      'num_correct': attempt['num_correct'] ?? 0,
      'num_total': attempt['num_total'] ?? 0,
    };

    await SQLiteService.db.insert(
      'attempts',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return attemptId;
  }

  static Future<void> insertAttemptAnswers(
      String attemptId, List<Map<String, dynamic>> answers) async {
    final batch = SQLiteService.db.batch();
    for (final a in answers) {
      batch.insert('attempt_answers', {
        'attempt_id': attemptId,
        'question_id': a['question_id']?.toString() ?? '',
        'q_index': a['q_index'] ?? 0,
        'selected_index': a['selected_index'] ?? -1,
        'correct_index': a['correct_index'] ?? -1,
        'is_correct': (a['is_correct'] == true || a['is_correct'] == 1) ? 1 : 0,
        'elapsed_ms': a['elapsed_ms'] ?? null,
      });
    }
    await batch.commit(noResult: true);
  }

  // --- helpers ---
  static String _pseudoUuid(String prefix) {
    final r = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = List.generate(6, (_) => r.nextInt(36))
        .map((n) => '0123456789abcdefghijklmnopqrstuvwxyz'[n])
        .join();
    return '$prefix$ts$rand';
  }
}
