import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/cache_repository.dart';
import '../services/sqlite_service.dart';
import '../services/firebase_service.dart';
import '../widgets/snackbar_helper.dart';
import 'quiz_player_page.dart';
import 'generate_quiz_page.dart';
import 'history_page.dart';
import '../main.dart' show appRouteObserver;

/// Home with two tabs: Admin Quizzes & My Quizzes.
/// - Admin tab: mirrors global/admin quizzes from cache (refreshed via FirestoreService).
/// - My tab: loads from local cache; pull-to-refresh -> Firestore -> cache -> reload.
/// - Auto-refresh when returning from Generate page using RouteAware.didPopNext.
class QuizzesPage extends StatefulWidget {
  const QuizzesPage({super.key});

  @override
  State<QuizzesPage> createState() => _QuizzesPageState();
}

class _QuizzesPageState extends State<QuizzesPage> with SingleTickerProviderStateMixin {
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
    final shouldRefreshMy = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const GenerateQuizPage()),
    );
    if (shouldRefreshMy == true) {
      _tab.index = 1; // switch to My Quizzes
      // Ask MyQuizzesTab to refresh from server then cache via inherited lookup.
      _MyQuizzesTabState.requestExternalRefresh();
      setState(() {}); // ensure TabBarView rebuilds
    }
  }

  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Quiz'),
        actions: [
          IconButton(
            tooltip: 'History',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
        ],
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

/// ADMIN (global) tab — mirrors existing global list behavior.
class _AdminQuizzesTab extends StatefulWidget {
  const _AdminQuizzesTab();

  @override
  State<_AdminQuizzesTab> createState() => _AdminQuizzesTabState();
}

class _AdminQuizzesTabState extends State<_AdminQuizzesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _quizzes = [];
  String _filter = 'all'; // all | easy | medium | hard

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

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _quizzes;
    return _quizzes.where((q) {
      final d = (q['difficulty'] ?? '').toString().toLowerCase();
      return d == _filter;
    }).toList();
  }

  Widget _buildFilters() {
    Widget chip(String key, String label) {
      final selected = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        chip('all', 'All'),
        chip('easy', 'Easy'),
        chip('medium', 'Medium'),
        chip('hard', 'Hard'),
      ]),
    );
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

    final items = _filtered;

    return RefreshIndicator(
      onRefresh: () => _loadQuizzes(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) return _buildFilters();
          final q = items[i - 1];
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
                    isAdmin: true,
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

/// USER (My Quizzes) tab — local-first with server refresh.
/// Uses RouteAware to auto-refresh when returning from Generate page.
class _MyQuizzesTab extends StatefulWidget {
  const _MyQuizzesTab();

  @override
  State<_MyQuizzesTab> createState() => _MyQuizzesTabState();
}

class _MyQuizzesTabState extends State<_MyQuizzesTab> with RouteAware {
  static _MyQuizzesTabState? _lastMountedInstance; // simple external refresh hook
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _mine = [];
  String _uid = '';

  // External trigger to force a refresh from server.
  static void requestExternalRefresh() {
    _lastMountedInstance?._refreshFromServer();
  }

  @override
  void initState() {
    super.initState();
    _uid = FirebaseService.I.currentUser?.uid ?? '';
    _loadFromCache();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appRouteObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
    _lastMountedInstance = this;
  }

  @override
  void dispose() {
    if (mounted) {
      appRouteObserver.unsubscribe(this);
    }
    if (identical(_lastMountedInstance, this)) {
      _lastMountedInstance = null;
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returning to this tab (e.g., after Generate dialog closed) → refresh.
    _refreshFromServer();
  }

  Future<void> _loadFromCache() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await CacheRepository.getMyQuizzes(_uid);
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

  Future<void> _refreshFromServer() async {
    if (_uid.isEmpty) {
      await _loadFromCache();
      return;
    }
    try {
      await FirestoreService.fetchMyQuizzes(_uid); // fetch -> write cache
    } catch (_) {
      // ignore; we still show cache
    } finally {
      await _loadFromCache(); // always re-read cache afterward
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _mine.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _refreshFromServer);
    }
    if (_mine.isEmpty) {
      return _MyEmptyState(onGenerate: () async {
        final shouldRefresh = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const GenerateQuizPage()),
        );
        if (shouldRefresh == true) {
          await _refreshFromServer();
        }
      });
    }

    return RefreshIndicator(
      onRefresh: _refreshFromServer,
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
                    isAdmin: false,
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

class _MyEmptyState extends StatelessWidget {
  final VoidCallback onGenerate;
  const _MyEmptyState({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('No quizzes yet. Generate one.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generate AI Quiz'),
        ),
      ]),
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
