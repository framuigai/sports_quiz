import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/cache_repository.dart';
import '../services/firestore_service.dart';
import '../services/firebase_service.dart';
import '../widgets/snackbar_helper.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? FirebaseService.I.currentUser?.uid ?? '';
    _loadFromCache();
    _refreshFromServer();
  }

  Future<void> _loadFromCache() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await CacheRepository.getMyAttempts();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load attempts: $e';
      });
    }
  }

  Future<void> _refreshFromServer() async {
    if (_uid.isEmpty) {
      return;
    }
    try {
      await FirestoreService.fetchMyAttempts(_uid);
    } catch (_) {
      // ignore; still show cache
    } finally {
      await _loadFromCache();
    }
  }

  void _openDetails(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Attempt Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quiz: ${a['quiz_title'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Difficulty: ${a['difficulty'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Score: ${a['num_correct'] ?? 0}/${a['num_total'] ?? 0}'),
            const SizedBox(height: 8),
            Text('Started: ${a['started_at'] ?? ''}'),
            const SizedBox(height: 4),
            Text('Completed: ${a['completed_at'] ?? ''}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _refreshFromServer);
    }
    if (_items.isEmpty) {
      return _EmptyState(onRetry: _refreshFromServer);
    }

    return RefreshIndicator(
      onRefresh: _refreshFromServer,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final a = _items[i];
          final title = (a['quiz_title']?.toString().isNotEmpty ?? false)
              ? a['quiz_title'].toString()
              : a['quiz_id']?.toString() ?? 'Quiz';
          final score = '${a['num_correct'] ?? 0}/${a['num_total'] ?? 0}';
          final started = a['started_at']?.toString() ?? '';
          return ListTile(
            title: Text(title),
            subtitle: Text('Score: $score • ${a['difficulty'] ?? ''}'),
            trailing: Text(
              started.isNotEmpty ? started.substring(0, 19).replaceFirst('T', ' ') : '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            onTap: () => _openDetails(a),
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
        const Text('No attempts yet. Play a quiz!', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
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
