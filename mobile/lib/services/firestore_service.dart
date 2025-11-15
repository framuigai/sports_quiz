import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cache_repository.dart';

enum FetchStatus { successFromServer, error }

class FetchOutcome {
  final FetchStatus status;
  final int fetchedCount;
  final String? errorMessage;
  const FetchOutcome.success(this.fetchedCount)
      : status = FetchStatus.successFromServer,
        errorMessage = null;
  const FetchOutcome.error(this.errorMessage)
      : status = FetchStatus.error,
        fetchedCount = 0;
}

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// Fetch global/admin quizzes and persist to local cache.
  static Future<FetchOutcome> fetchGlobalQuizzes() async {
    try {
      final qInt = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: 0);
      final qBool = _db
          .collection('quizzes')
          .where('is_admin_quiz', isEqualTo: true)
          .where('available_to_all', isEqualTo: true)
          .where('is_approved', isEqualTo: true)
          .where('deleted', isEqualTo: false);

      final results = await Future.wait([qInt.get(), qBool.get()]);
      final seen = <String>{};
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        for (final d in snap.docs) {
          if (seen.add(d.id)) allDocs.add(d);
        }
      }

      for (var doc in allDocs) {
        final data = doc.data();
        final quiz = {
          'quiz_id': doc.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          'tags': data['tags'] is List
              ? (data['tags'] as List).join(',')
              : (data['tags']?.toString() ?? ''),
          'is_admin_quiz': 1,
          'available_to_all': data['available_to_all'] == true ? 1 : 0,
          'is_approved': data['is_approved'] == true ? 1 : 0,
          'deleted': 0,
          'deleted_at': null,
          'created_at': data['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': data['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          // admin/global → user-specific fields empty
          'owner_id': '',
          'source': (data['source'] ?? '').toString(),
          if (data['num_questions'] != null)
            'num_questions': data['num_questions'],
        };
        await CacheRepository.saveAdminQuiz(quiz);
      }
      return FetchOutcome.success(allDocs.length);
    } catch (e) {
      return FetchOutcome.error(e.toString());
    }
  }

  // 🧩 NEW: Fetch *my* (owner) quizzes and persist to local user cache.
  static Future<FetchOutcome> fetchMyQuizzes(String ownerId) async {
    try {
      final q1 = _db
          .collection('quizzes')
          .where('owner_id', isEqualTo: ownerId)
          .where('deleted', isEqualTo: 0);
      final q2 = _db
          .collection('quizzes')
          .where('owner_id', isEqualTo: ownerId)
          .where('deleted', isEqualTo: false);

      final results = await Future.wait([q1.get(), q2.get()]);
      final seen = <String>{};
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in results) {
        for (final d in snap.docs) {
          if (seen.add(d.id)) allDocs.add(d);
        }
      }

      for (var doc in allDocs) {
        final data = doc.data();
        final quiz = {
          'quiz_id': doc.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          'owner_id': (data['owner_id'] ?? '').toString(),
          'source': (data['source'] ?? '').toString(),
          'deleted': (data['deleted'] == true) ? 1 : 0,
          'deleted_at': data['deleted_at']?.toString(),
          'created_at': data['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': data['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          if (data['num_questions'] != null)
            'num_questions': data['num_questions'],
        };
        await CacheRepository.saveUserQuiz(quiz);
      }

      return FetchOutcome.success(allDocs.length);
    } catch (e) {
      return FetchOutcome.error('Error fetching my quizzes: $e');
    }
  }

  // 🧩 NEW: Fetch a quiz by id and cache it into the correct table (admin or user),
  // used immediately after AI generation when we only know quiz_id.
  static Future<FetchOutcome> fetchQuizById(String quizId) async {
    try {
      final snap = await _db.collection('quizzes').doc(quizId).get();
      if (!snap.exists) {
        return const FetchOutcome.error('Quiz not found');
      }
      final data = snap.data() as Map<String, dynamic>;
      final isAdmin = data['is_admin_quiz'] == true;

      if (isAdmin) {
        await CacheRepository.saveAdminQuiz({
          'quiz_id': snap.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          'tags': data['tags'] is List
              ? (data['tags'] as List).join(',')
              : (data['tags']?.toString() ?? ''),
          'is_admin_quiz': 1,
          'available_to_all': data['available_to_all'] == true ? 1 : 0,
          'is_approved': data['is_approved'] == true ? 1 : 0,
          'deleted': 0,
          'deleted_at': null,
          'created_at': data['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': data['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'owner_id': '',
          'source': (data['source'] ?? '').toString(),
          if (data['num_questions'] != null)
            'num_questions': data['num_questions'],
        });
      } else {
        await CacheRepository.saveUserQuiz({
          'quiz_id': snap.id,
          'title': data['title'] ?? 'Untitled Quiz',
          'description': data['description'] ?? '',
          'difficulty': (data['difficulty'] ?? 'medium').toString(),
          'owner_id': (data['owner_id'] ?? '').toString(),
          'source': (data['source'] ?? '').toString(),
          'deleted': (data['deleted'] == true) ? 1 : 0,
          'deleted_at': data['deleted_at']?.toString(),
          'created_at': data['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': data['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          if (data['num_questions'] != null)
            'num_questions': data['num_questions'],
        });
      }

      return const FetchOutcome.success(1);
    } catch (e) {
      return FetchOutcome.error('Error fetching quiz by id: $e');
    }
  }

  // 🧩 UPDATED: Fetch questions by quizId and save to either admin or user cache.
  static Future<FetchOutcome> fetchQuestionsByQuizId(
      String quizId, {
        required bool isAdmin,
      }) async {
    try {
      final query = await _db
          .collection('quizzes')
          .doc(quizId)
          .collection('questions')
          .get();

      final questions = query.docs.map((d) {
        final q = d.data();
        return {
          'question_id': d.id,
          'quiz_id': quizId,
          // prefer explicit 'order'; keep legacy 'index'
          'order': q['order'] ?? q['index'] ?? 0,
          'index': q['index'] ?? q['order'] ?? 0,
          'text': q['text'] ?? '',
          'options': q['options'] is List
              ? (q['options'] as List).join('|')
              : q['options']?.toString() ?? '',
          'correct_index': q['correct_index'] ?? 0,
          'image_url': q['image_url'] ?? '',
          'created_at': q['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': q['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
        };
      }).toList();

      if (isAdmin) {
        await CacheRepository.saveAdminQuestions(questions);
      } else {
        await CacheRepository.saveUserQuestions(questions);
      }
      return FetchOutcome.success(questions.length);
    } catch (e) {
      return FetchOutcome.error('Error fetching questions: $e');
    }
  }

  // =========================
  // 🆕 Attempts APIs (Day B)
  // =========================

  /// Create an attempt document in Firestore for the current user.
  /// Returns the generated attemptId.
  static Future<String> createAttempt({
    required String quizId,
    required String quizTitle,
    required String difficulty,
    required DateTime startedAt,
    required DateTime completedAt,
    required int score,
    required int numCorrect,
    required int numTotal,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Must be signed in to create an attempt');
    }

    final ref = _db.collection('attempts').doc();
    await ref.set({
      'attempt_id': ref.id,
      'user_id': uid,
      'quiz_id': quizId,
      'quiz_title': quizTitle,
      'difficulty': difficulty,
      'started_at': Timestamp.fromDate(startedAt),
      'completed_at': Timestamp.fromDate(completedAt),
      'score': score,
      'num_correct': numCorrect,
      'num_total': numTotal,
      'deleted': false,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    // Mirror locally (best effort)
    await CacheRepository.insertAttempt({
      'attempt_id': ref.id,
      'quiz_id': quizId,
      'quiz_title': quizTitle,
      'difficulty': difficulty,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'score': score,
      'num_correct': numCorrect,
      'num_total': numTotal,
    });

    return ref.id;
  }

  /// Write answers under attempts/{id}/answers.
  /// `answers` is a list of maps with:
  ///  question_id, q_index, selected_index, correct_index, is_correct, elapsed_ms (optional)
  static Future<void> createAttemptAnswers(
      String attemptId,
      List<Map<String, dynamic>> answers,
      ) async {
    final col = _db.collection('attempts').doc(attemptId).collection('answers');
    final batch = _db.batch();

    for (final a in answers) {
      final doc = col.doc();
      batch.set(doc, {
        'question_id': a['question_id']?.toString() ?? '',
        'q_index': a['q_index'] ?? 0,
        'selected_index': a['selected_index'] ?? -1,
        'correct_index': a['correct_index'] ?? -1,
        'is_correct': a['is_correct'] == true,
        'elapsed_ms': a['elapsed_ms'],
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // Mirror locally (best effort)
    await CacheRepository.insertAttemptAnswers(attemptId, answers);
  }

  /// Download my attempts and cache to SQLite.
  static Future<FetchOutcome> fetchMyAttempts(String uid) async {
    try {
      final q = _db
          .collection('attempts')
          .where('user_id', isEqualTo: uid)
          .where('deleted', isEqualTo: false)
          .orderBy('started_at', descending: true);

      final snaps = await q.get();
      int count = 0;
      for (final d in snaps.docs) {
        final data = d.data();
        final startedAt = _tsToIso(data['started_at']);
        final completedAt = _tsToIso(data['completed_at']);
        await CacheRepository.insertAttempt({
          'attempt_id': d.id,
          'quiz_id': data['quiz_id']?.toString() ?? '',
          'quiz_title': data['quiz_title']?.toString() ?? '',
          'difficulty': data['difficulty']?.toString() ?? 'medium',
          'started_at': startedAt,
          'completed_at': completedAt,
          'score': (data['score'] ?? 0) as int,
          'num_correct': (data['num_correct'] ?? 0) as int,
          'num_total': (data['num_total'] ?? 0) as int,
        });
        count++;
      }
      return FetchOutcome.success(count);
    } catch (e) {
      return FetchOutcome.error('Error fetching attempts: $e');
    }
  }

  static String _tsToIso(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    return DateTime.now().toIso8601String();
  }
}
