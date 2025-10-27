// mobile/lib/models/question.dart
//
// Domain model for a Question used by the Player.
// Matches cache_admin_questions table and Firestore subcollection fields.
//
// Cache fields:
//  - question_id (string)   => id
//  - quiz_id (string)       => quizId
//  - index (int)            => index (question order)
//  - text (string)
//  - options (string)       => "A|B|C|D" (we store as List<String> in memory)
//  - correct_index (int)
//  - image_url (string)
//  - created_at / updated_at (string)

class Question {
  final String id;
  final String quizId;
  final int index;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String imageUrl;
  final String createdAt;
  final String updatedAt;

  const Question({
    required this.id,
    required this.quizId,
    required this.index,
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Question.fromCacheMap(Map<String, dynamic> m) {
    return Question(
      id: (m['question_id'] ?? m['id'] ?? '').toString(),
      quizId: (m['quiz_id'] ?? '').toString(),
      index: _asInt(m['index'], fallback: 0),
      text: (m['text'] ?? '').toString(),
      options: _splitOptions(m['options']),
      correctIndex: _asInt(m['correct_index'], fallback: 0),
      imageUrl: (m['image_url'] ?? '').toString(),
      createdAt: (m['created_at'] ?? '').toString(),
      updatedAt: (m['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'question_id': id,
      'quiz_id': quizId,
      'index': index,
      'text': text,
      'options': options.join('|'),
      'correct_index': correctIndex,
      'image_url': imageUrl,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  static int _asInt(dynamic v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return n;
    }
    return fallback;
  }

  static List<String> _splitOptions(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return const [];
    // Accept both pipe and comma separators (defensive)
    final sep = s.contains('|') ? '|' : ',';
    return s.split(sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
}
