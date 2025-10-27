// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart'; // flutterfire-generated
import 'services/sqlite_service.dart'; // creates quiz_cache.db from schema.sql
import 'services/cache_repository.dart'; // local cache helpers
import 'services/firestore_service.dart'; // fetches admin quizzes -> cache
import 'services/auth_service.dart'; // ensure signed-in (per your current flow)
import 'services/firebase_service.dart'; // analytics wrapper
import 'widgets/snackbar_helper.dart'; // reusable snackbars

// 🧩 NEW import for quiz player navigation
import 'pages/quiz_player_page.dart'; // we’ll create this next

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SQLiteService.init();
  await AuthService.ensureSignedIn(); // existing auth flow
  await FirebaseService.I.init(); // make sure analytics is ready
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
  String? _error;
  List<Map<String, dynamic>> _quizzes = [];

  @override
  void initState() {
    super.initState();
    FirebaseService.I.logQuizListViewed();
    _loadQuizzes(firstLoad: true);
  }

  Future<void> _loadQuizzes({bool firstLoad = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final outcome = await FirestoreService.fetchGlobalQuizzes();
    final cached = await CacheRepository.getAdminQuizzes();

    if (!mounted) return;
    setState(() {
      _quizzes = cached;
      _loading = false;
      _error = outcome.status == FetchStatus.error
          ? (outcome.errorMessage ?? 'Failed to load')
          : null;
    });

    if (outcome.status == FetchStatus.successFromServer) {
      if (!firstLoad) SnackbarHelper.showInfo(context, 'Updated from server.');
    } else if (outcome.status == FetchStatus.error) {
      if (cached.isNotEmpty) {
        SnackbarHelper.showInfo(context, 'Showing cached data (offline).');
      } else {
        SnackbarHelper.showError(context, 'Couldn’t load quizzes.');
      }
    } else if (cached.isEmpty) {
      SnackbarHelper.showInfo(context, 'No quizzes yet.');
    }
  }

  Future<void> _insertDummy() async {
    await CacheRepository.insertDummyQuiz();
    final cached = await CacheRepository.getAdminQuizzes();
    if (!mounted) return;
    setState(() => _quizzes = cached);
    SnackbarHelper.showSuccess(context, 'Dummy quiz inserted into SQLite');
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
            onPressed: () async => _loadQuizzes(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _quizzes.isEmpty) {
      return _ErrorState(message: _error!, onRetry: () => _loadQuizzes());
    }
    if (_quizzes.isEmpty) return _EmptyState(onRetry: () => _loadQuizzes());

    // 🧩 MAIN CHANGE → tapping a quiz now navigates to the Player page
    return RefreshIndicator(
      onRefresh: () => _loadQuizzes(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _quizzes.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final q = _quizzes[i];
          return ListTile(
            title: Text(q['title'] ?? 'Untitled'),
            subtitle: Text('Difficulty: ${q['difficulty'] ?? 'N/A'}'),
            onTap: () {
              FirebaseService.I.logQuizTapped(
                quizId: q['quiz_id']?.toString() ?? '',
                title: q['title']?.toString() ?? '',
              );
              // 🧩 Navigate to quiz player page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizPlayerPage(
                    quizId: q['quiz_id']?.toString() ?? '',
                    title: q['title']?.toString() ?? 'Untitled Quiz',
                    difficulty: q['difficulty']?.toString() ?? 'medium',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('No quizzes available', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ]),
    );
  }
}
