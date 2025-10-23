// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';                      // flutterfire-generated
import 'services/sqlite_service.dart';               // creates quiz_cache.db from schema.sql
import 'services/cache_repository.dart';             // local cache helpers
import 'services/firestore_service.dart';            // fetches admin quizzes -> cache
import 'services/auth_service.dart';                 // ✅ ensure signed-in for Firestore rules

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SQLiteService.init();
  // ✅ Make sure we are authenticated before hitting Firestore
  await AuthService.ensureSignedIn();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const GlobalQuizzesPage(),
    );
  }
}

class GlobalQuizzesPage extends StatefulWidget {
  const GlobalQuizzesPage({super.key});

  @override
  State<GlobalQuizzesPage> createState() => _GlobalQuizzesPageState();
}

class _GlobalQuizzesPageState extends State<GlobalQuizzesPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _quizzes = [];

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    try {
      // Try Firestore → cache; always read from cache after
      await FirestoreService.fetchGlobalQuizzes();
    } catch (_) {
      // ignore; we always read cache below
    }
    final cached = await CacheRepository.getAdminQuizzes();
    if (!mounted) return;
    setState(() {
      _quizzes = cached;
      _loading = false;
    });
    if (cached.isEmpty) {
      // Optional UX hint
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No quizzes in cache yet. Add a dummy or seed Firestore.')),
      );
    }
  }

  Future<void> _insertDummy() async {
    await CacheRepository.insertDummyQuiz();
    final cached = await CacheRepository.getAdminQuizzes();
    if (!mounted) return;
    setState(() => _quizzes = cached);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dummy quiz inserted into SQLite')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Quizzes'),
        actions: [
          IconButton(
            tooltip: 'Dev: Insert Dummy',
            onPressed: _insertDummy,
            icon: const Icon(Icons.bug_report),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              setState(() => _loading = true);
              await _loadQuizzes();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quizzes.isEmpty
          ? const Center(child: Text('No quizzes available'))
          : ListView.separated(
        itemCount: _quizzes.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final q = _quizzes[i];
          return ListTile(
            title: Text(q['title'] ?? 'Untitled'),
            subtitle: Text('Difficulty: ${q['difficulty'] ?? 'N/A'}'),
          );
        },
      ),
    );
  }
}
