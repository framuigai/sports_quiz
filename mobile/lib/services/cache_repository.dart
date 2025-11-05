import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'sqlite_service.dart';

class CacheRepository {
  // -------------------------
  // QUIZZES (ADMIN/GLOBAL)
  // -------------------------
  static Future<void> saveAdminQuiz(Map<String, dynamic> quiz) async {
    await SQLiteService.db.insert(
      'cache_admin_quizzes',
      quiz,
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
    for (final q in questions) {
      batch.insert(
        'cache_admin_questions',
        q,
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
      // Prefer "order", fallback to legacy "index"
      orderBy: 'COALESCE("order","index") ASC',
    );
  }

  // -------------------------
  // 🆕 QUIZZES (USER / MY QUIZZES)
  // -------------------------
  static Future<void> saveUserQuiz(Map<String, dynamic> quiz) async {
    await SQLiteService.db.insert(
      'user_quizzes',
      quiz,
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
    for (final q in questions) {
      batch.insert(
        'user_questions',
        q,
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

  /// Inserts a completed attempt into the `attempts` table.
  /// Returns the generated attempt_id (UUID-ish string).
  static Future<String> insertAttempt(Map<String, dynamic> attempt) async {
    // attempt should contain:
    // quiz_id, quiz_title, difficulty, started_at, completed_at,
    // score, num_correct, num_total
    // We'll generate attempt_id if not provided.
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

  /// Bulk-insert child answers into `attempt_answers`.
  /// Each map should include: question_id, q_index, selected_index, correct_index, is_correct
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
