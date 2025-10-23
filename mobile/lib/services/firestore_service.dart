import 'package:cloud_firestore/cloud_firestore.dart';
import 'cache_repository.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// Fetch “global/admin” quizzes and persist to local cache.
  /// Tolerates both `deleted: 0` (int) and `deleted: false` (bool).
  static Future<void> fetchGlobalQuizzes() async {
    try {
      // Query set 1: deleted == 0 (int)
      final qInt = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: 0);

      // Query set 2: deleted == false (bool) — for projects that used booleans.
      final qBool = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: false);

      // Run both; some backends will return 0 for one of them depending on data typing.
      final results = await Future.wait([qInt.get(), qBool.get()]);

      // Merge without duplicates (by docId).
      final seen = <String>{};
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        for (final d in snap.docs) {
          if (seen.add(d.id)) allDocs.add(d);
        }
      }

      // Persist to SQLite cache
      for (var doc in allDocs) {
        final data = doc.data();
        final quiz = {
          'quiz_id': doc.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          // tags may be a list or a string; normalize to comma-separated
          'tags': data['tags'] is List
              ? (data['tags'] as List).join(',')
              : (data['tags']?.toString() ?? ''),
          'is_admin_quiz': 1,
          'available_to_all': data['available_to_all'] == true ? 1 : 0,
          'is_approved': data['is_approved'] == true ? 1 : 0,
          'deleted': 0,
          'deleted_at': null,
          'created_at': (data['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          'updated_at': (data['updated_at']?.toString() ??
              DateTime.now().toIso8601String()),
        };
        await CacheRepository.saveAdminQuiz(quiz);
      }

      // Optional: simple console log to help while debugging
      // (Safe to keep; remove later if you want.)
      // ignore: avoid_print
      print(
          'FirestoreService.fetchGlobalQuizzes -> fetched ${allDocs.length} docs and cached them.');
    } catch (e) {
      // We keep this silent for offline-first UX; feel free to log to Crashlytics later.
      // ignore: avoid_print
      print('Firestore fetch failed (will fallback to cache): $e');
    }
  }
}
