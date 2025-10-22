import 'package:sqflite/sqflite.dart';
import 'sqlite_service.dart';

class CacheRepository {
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

  // Dev helper for Day 4 acceptance
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
}
