//lib/models/quiz.dart
// Domain model for a Quiz used by UI and services.
// Maps cleanly to our cache_admin_quizzes table and Firestore docs.
//
// Fields align with our current schema:
//  - quiz_id (string)        => id
//  - title (string)
//  - description (string)
//  - difficulty (string: easy|medium|hard)
//  - tags (string: "a,b,c" | may be empty)
//  - is_admin_quiz (int 0/1) => isAdminQuiz (bool)
//  - available_to_all (int 0/1) => availableToAll (bool)
//  - is_approved (int 0/1) => isApproved (bool)
//  - deleted (int 0/1) => deleted (bool)
//  - owner_id (string) => ownerId (user's private quizzes)
//  - source (string)   => e.g., "ai", "manual"
//  - num_questions (int) => optional
//  - created_at / updated_at (string; iso8601 or epoch-as-string)
//
// NOTE: We keep strings for created/updated to match local cache.

class Quiz {
  final String id;
  final String title;
  final String description;
  final String difficulty;
  final List<String> tags;
  final bool isAdminQuiz;
  final bool availableToAll;
  final bool isApproved;
  final bool deleted;
  final String createdAt; // stored as string to align with cache
  final String updatedAt; // stored as string to align with cache

  // 🆕 user/private quiz-specific
  final String ownerId;     // empty for admin/global
  final String source;      // "ai"/"manual"/"import"
  final int? numQuestions;  // optional

  const Quiz({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.tags,
    required this.isAdminQuiz,
    required this.availableToAll,
    required this.isApproved,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
    this.ownerId = '',
    this.source = '',
    this.numQuestions,
  });

  factory Quiz.fromCacheMap(Map<String, dynamic> m) {
    return Quiz(
      id: (m['quiz_id'] ?? m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      difficulty: (m['difficulty'] ?? 'medium').toString(),
      tags: _splitTags(m['tags']),
      isAdminQuiz: _asBool(m['is_admin_quiz']),
      availableToAll: _asBool(m['available_to_all']),
      isApproved: _asBool(m['is_approved']),
      deleted: _asBool(m['deleted']),
      createdAt: (m['created_at'] ?? '').toString(),
      updatedAt: (m['updated_at'] ?? '').toString(),
      ownerId: (m['owner_id'] ?? '').toString(),
      source: (m['source'] ?? '').toString(),
      numQuestions: _asNullableInt(m['num_questions']),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'quiz_id': id,
      'title': title,
      'description': description,
      'difficulty': difficulty,
      'tags': tags.join(','),
      'is_admin_quiz': isAdminQuiz ? 1 : 0,
      'available_to_all': availableToAll ? 1 : 0,
      'is_approved': isApproved ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'owner_id': ownerId,
      'source': source,
      if (numQuestions != null) 'num_questions': numQuestions,
    };
  }

  static List<String> _splitTags(dynamic raw) {
    if (raw == null) return const [];
    final s = raw.toString().trim();
    if (s.isEmpty) return const [];
    // Accept both comma and pipe separators (defensive)
    final sep = s.contains('|') ? '|' : ',';
    return s.split(sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase() ?? 'false';
    return s == 'true' || s == '1';
  }

  static int? _asNullableInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
