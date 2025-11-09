import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart'; // flutterfire-generated
import 'services/sqlite_service.dart'; // creates quiz_cache.db from schema.sql
import 'services/auth_service.dart'; // ensure signed-in (per your current flow)
import 'services/firebase_service.dart'; // analytics wrapper

// Home: consolidated Admin/My tabs page (contains the tabs & logic)
import 'pages/quizzes_page.dart';

// Global RouteObserver so child pages (e.g., My Quizzes tab) can subscribe to didPopNext.
final RouteObserver<PageRoute<dynamic>> appRouteObserver = RouteObserver<PageRoute<dynamic>>();

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
      navigatorObservers: [appRouteObserver],
      home: const QuizzesPage(),
    );
  }
}
