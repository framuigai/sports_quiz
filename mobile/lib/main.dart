// lib/main.dart
//
// PURPOSE:
//  - Minimal demonstration of Firebase Auth with Flutter.
//  - Allows sign-up, sign-in, and sign-out using email/password.
//  - Automatically reacts to auth changes and shows the correct screen.
//
// NEXT STEPS (future days):
//  - Add Firestore and tie quizzes to logged-in users.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // ✅ Initialize Firebase before the UI starts.
    await FirebaseService.I.init();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Quiz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      // ✅ Automatically switch UI based on sign-in state.
      home: StreamBuilder<User?>(
        stream: FirebaseService.I.authState(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // While checking auth state, show a spinner.
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final user = snapshot.data;
          if (user == null) {
            return const AuthScreen(); // Not signed in → show login form.
          } else {
            return HomeScreen(userEmail: user.email ?? 'No Email');
          }
        },
      ),
    );
  }
}

// ✅ Login/Signup Screen
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignIn = true;
  bool _busy = false;
  String? _error;

  // ✅ Handles login/signup based on _isSignIn flag.
  Future<void> _submit() async {
    // Close keyboard before submitting
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isSignIn) {
        await FirebaseService.I.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await FirebaseService.I.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (e) {
      // TODO: map FirebaseAuthException to friendly messages later
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignIn ? 'Sign In' : 'Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ Show error banner when any auth error occurs.
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // ✅ Email Field
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),

            // ✅ Password Field
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // ✅ Sign-in / Sign-up button
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isSignIn ? 'Sign In' : 'Create Account'),
            ),

            // ✅ Toggle between Sign In and Sign Up.
            TextButton(
              onPressed: _busy ? null : () => setState(() => _isSignIn = !_isSignIn),
              child: Text(
                _isSignIn
                    ? 'Need an account? Sign Up'
                    : 'Have an account? Sign In',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ Home Screen (shown after login)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.userEmail});
  final String userEmail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Signed in as $userEmail'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseService.I.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: const Center(
        child: Text(
          '✅ Day 2 Complete — Firebase Auth is working!',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
