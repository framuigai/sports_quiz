// lib/services/firebase_service.dart
//
// PURPOSE:
//  - Centralized service to handle Firebase initialization, authentication, and analytics.
//  - Also logs quiz gameplay events: quiz_started, quiz_completed, question_answered.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../firebase_options.dart';

class FirebaseService {
  static final FirebaseService I = FirebaseService._();
  FirebaseService._();

  FirebaseAnalytics? _analytics;

  Future<void> init() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _analytics = FirebaseAnalytics.instance;
  }

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------

  Stream<User?> authState() => FirebaseAuth.instance.authStateChanges();

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential?> signInAnonymously() async {
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      await logLoginAnonymous();
      return credential;
    } catch (e) {
      print('Anonymous login failed: $e');
      return null;
    }
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  User? get currentUser => FirebaseAuth.instance.currentUser;

  // ---------------------------------------------------------------------------
  // ANALYTICS
  // ---------------------------------------------------------------------------

  Future<void> logQuizListViewed() async {
    try {
      await _analytics?.logEvent(name: 'quiz_list_viewed');
    } catch (e) {
      print('Analytics logQuizListViewed failed: $e');
    }
  }

  Future<void> logQuizTapped({
    required String quizId,
    required String title,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'quiz_tapped',
        parameters: {
          'quiz_id': quizId,
          'title': title,
        },
      );
    } catch (e) {
      print('Analytics logQuizTapped failed: $e');
    }
  }

  Future<void> logQuizStarted({
    required String quizId,
    required String title,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'quiz_started',
        parameters: {
          'quiz_id': quizId,
          'title': title,
        },
      );
    } catch (e) {
      print('Analytics logQuizStarted failed: $e');
    }
  }

  // ✅ NEW: log per-question answer event
  Future<void> logQuestionAnswered({
    required String quizId,
    required String questionId,
    required bool isCorrect,
    required int selectedIndex,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'question_answered',
        parameters: {
          'quiz_id': quizId,
          'question_id': questionId,
          'is_correct_i': isCorrect ? 1:0,
          'selected_index_i': selectedIndex,
        },
      );
    } catch (e) {
      print('Analytics logQuestionAnswered failed: $e');
    }
  }

  // ✅ NEW: log final quiz completion
  Future<void> logQuizCompleted({
    required String quizId,
    required String title,
    required int score,
    required int total,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'quiz_completed',
        parameters: {
          'quiz_id': quizId,
          'title': title,
          'score': score,
          'total': total,
        },
      );
    } catch (e) {
      print('Analytics logQuizCompleted failed: $e');
    }
  }

  // ✅ Optional but recommended: when viewing summary screen
  Future<void> logQuizSummaryViewed({
    required String quizId,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'quiz_summary_viewed',
        parameters: {
          'quiz_id': quizId,
        },
      );
    } catch (e) {
      print('Analytics logQuizSummaryViewed failed: $e');
    }
  }

  Future<void> logLoginAnonymous() async {
    try {
      await _analytics?.logEvent(name: 'login_anonymous');
    } catch (e) {
      print('Analytics logLoginAnonymous failed: $e');
    }
  }

  Future<void> logCustomEvent({
    required String name,
    Map<String, Object?>? parameters,
  }) async {
    try {
      final sanitized = _sanitizeParams(parameters);
      await _analytics?.logEvent(name: name, parameters: sanitized);
    } catch (e) {
      print('Analytics custom log failed: $e');
    }
  }

  Future<void> flushAnalytics() async {
    try {
      await _analytics?.logEvent(name: 'flush_triggered');
    } catch (_) {}
  }

  Map<String, Object>? _sanitizeParams(Map<String, Object?>? src) {
    if (src == null) return null;
    final out = <String, Object>{};
    src.forEach((key, value) {
      if (value == null) return;
      if (value is bool) {
        out[key] = value ? 1 : 0;        // <-- convert bools to ints
      } else if (value is num || value is String) {
        out[key] = value;
      } else {
        out[key] = value.toString();
      }
    });
    return out;
  }
}
