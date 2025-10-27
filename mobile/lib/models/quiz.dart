// mobile/lib/models/quiz.dart
//
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
//  - created_at / updated_at (string; iso8601 or epoch-as-string)
//    We keep them as String for now since the cache stores strings.

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
}
