// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cache_repository.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // Helper to coerce Firestore value into a bool (accepts true/false, 1/0, "true"/"false")
  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  // Helper to stringify tags
  static String _tagsToCsv(dynamic v) {
    if (v is List) return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join(',');
    if (v is String) return v; // already a CSV/one tag string
    return '';
  }

  static Future<void> fetchGlobalQuizzes() async {
    try {
      // NOTE: rules expect booleans; query matches rules
      final snapshot = await _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: false)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Be defensive about older docs (0/1 or strings)
        final quiz = {
          'quiz_id'        : doc.id,
          'title'          : (data['title'] ?? 'Untitled Quiz').toString(),
          'description'    : (data['description'] ?? '').toString(),
          'difficulty'     : (data['difficulty'] ?? 'medium').toString(),
          'tags'           : _tagsToCsv(data['tags']),
          'is_admin_quiz'  : _toBool(data['is_admin_quiz']) ? 1 : 0,
          'available_to_all': _toBool(data['available_to_all']) ? 1 : 0,
          'is_approved'    : _toBool(data['is_approved']) ? 1 : 0,
          'deleted'        : 0,                       // we only cached visible docs
          'deleted_at'     : null,
          'created_at'     : DateTime.now().toIso8601String(),
          'updated_at'     : DateTime.now().toIso8601String(),
        };

        await CacheRepository.saveAdminQuiz(quiz);
      }
      // success → nothing else to do
    } catch (e) {
      // Silent failure: UI falls back to cache.
      // Consider logging to Crashlytics later.
      // debugPrint('Firestore fetch failed: $e');
    }
  }
}
