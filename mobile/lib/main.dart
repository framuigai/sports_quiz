import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart'; // flutterfire-generated
import 'services/sqlite_service.dart'; // creates quiz_cache.db from schema.sql
import 'services/cache_repository.dart'; // local cache helpers (admin cache)
import 'services/firestore_service.dart'; // fetches admin quizzes -> cache
import 'services/auth_service.dart'; // ensure signed-in (per your current flow)
import 'services/firebase_service.dart'; // analytics wrapper
import 'widgets/snackbar_helper.dart'; // reusable snackbars

// Player + Generate pages
import 'pages/quiz_player_page.dart';
import 'pages/generate_quiz_page.dart';

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
      home: const HomeTabsPage(),
    );
  }
}

/// The new two-tab home: Admin Quizzes (global) + My Quizzes (user-generated).
class HomeTabsPage extends StatefulWidget {
  const HomeTabsPage({super.key});

  @override
  State<HomeTabsPage> createState() => _HomeTabsPageState();
}

class _HomeTabsPageState extends State<HomeTabsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _openGenerator() async {
    // Navigate to Generate AI Quiz page.
    // The page returns true when the user taps "My Quizzes" on success dialog.
    final shouldRefreshMy = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const GenerateQuizPage()),
    );

    // If user chose to go to My Quizzes, switch tab and ping a refresh via an inherited lookup.
    if (shouldRefreshMy == true) {
      _tab.index = 1; // My Quizzes tab
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Quiz'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Admin Quizzes'),
            Tab(text: 'My Quizzes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _AdminQuizzesTab(),
          _MyQuizzesTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGenerator,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Generate AI Quiz'),
      ),
    );
  }
}

/// ADMIN (global) tab — this preserves your existing logic for global/admin quizzes.
class _AdminQuizzesTab extends StatefulWidget {
  const _AdminQuizzesTab();

  @override
  State<_AdminQuizzesTab> createState() => _AdminQuizzesTabState();
}

class _AdminQuizzesTabState extends State<_AdminQuizzesTab> {
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _quizzes.isEmpty) {
      return _ErrorState(message: _error!, onRetry: () => _loadQuizzes());
    }
    if (_quizzes.isEmpty) {
      return _EmptyState(onRetry: () => _loadQuizzes());
    }

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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizPlayerPage(
                    quizId: q['quiz_id']?.toString() ?? '',
                    title: q['title']?.toString() ?? 'Untitled Quiz',
                    difficulty: q['difficulty']?.toString() ?? 'medium',
                    isAdmin: true, // ✅ important
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

/// USER (My Quizzes) tab — loads from local SQLite user_quizzes.
/// This keeps things working even before you finish Firestore pull functions.
class _MyQuizzesTab extends StatefulWidget {
  const _MyQuizzesTab();

  @override
  State<_MyQuizzesTab> createState() => _MyQuizzesTabState();
}

class _MyQuizzesTabState extends State<_MyQuizzesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _mine = [];

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Direct SQLite read (avoids needing extra repo methods right now).
      final rows = await SQLiteService.db.query(
        'user_quizzes',
        orderBy: 'updated_at DESC',
      );
      if (!mounted) return;
      setState(() {
        _mine = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load My Quizzes: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _mine.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _loadMine);
    }
    if (_mine.isEmpty) {
      return _EmptyState(
        onRetry: _loadMine,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _mine.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final q = _mine[i];
          return ListTile(
            title: Text(q['title']?.toString().isNotEmpty == true
                ? q['title'].toString()
                : 'Untitled'),
            subtitle: Text('Difficulty: ${q['difficulty'] ?? 'N/A'}'),
            onTap: () {
              final id = q['quiz_id']?.toString() ?? '';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizPlayerPage(
                    quizId: id,
                    title: q['title']?.toString() ?? 'Untitled Quiz',
                    difficulty: q['difficulty']?.toString() ?? 'medium',
                    isAdmin: false, // ✅ important
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
