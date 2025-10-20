import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ask_psu/user/guest_session_manager.dart';
import 'package:ask_psu/user/ws1.dart'; // OnboardingScreen
import 'package:ask_psu/user/ws2.dart'; // LoginPage / choice screen
import 'package:ask_psu/user/homepage.dart'; // Homepage after login
import 'package:ask_psu/user/connection_handler.dart';
import 'package:ask_psu/user/dataset_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up global error handling for Firestore internal assertion failures
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('INTERNAL ASSERTION FAILED') ||
        details.exception.toString().contains('Unexpected state')) {
      print(
          '🚨 Caught Firestore internal assertion failure: ${details.exception}');
      // Don't crash the app, just log the error
      return;
    }
    // Let other errors be handled normally
    FlutterError.presentError(details);
  };

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    print('✅ Firebase initialized successfully');

    // Configure Firestore with minimal settings to prevent internal assertion failures
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled:
          false, // Temporarily disable persistence to prevent state issues
      cacheSizeBytes: 10 * 1024 * 1024, // Reduced cache size to 10MB
    );
    print('✅ Firestore settings configured');

    // Always create a new guest session on app start
    GuestSessionManager().initialize();
    print('✅ Guest session manager initialized');

    // Initialize datasets (sync from Firestore if online, load local if offline)
    print('🚀 MAIN: Starting dataset initialization...');
    await DatasetManager.instance.initializeDatasets();
    print('🚀 MAIN: Dataset initialization completed');

    runApp(const ChatBotApp());
  } catch (e, stackTrace) {
    print('❌ Error during app initialization: $e');
    print('Stack trace: $stackTrace');

    // Still run the app even if initialization fails
    runApp(const ChatBotApp());
  }
}

class ChatBotApp extends StatefulWidget {
  const ChatBotApp({super.key});

  @override
  State<ChatBotApp> createState() => _ChatBotAppState();
}

class _ChatBotAppState extends State<ChatBotApp> {
  late final ConnectionHandler _connectionHandler;
  bool _isLoading = true;
  bool _isFirstTime = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _connectionHandler = ConnectionHandler.instance;
    _checkStartupState();
  }

  Future<void> _checkStartupState() async {
    final prefs = await SharedPreferences.getInstance();
    final firstTime = prefs.getBool('isFirstTime') ?? true;
    final currentUser = FirebaseAuth.instance.currentUser;

    setState(() {
      _isFirstTime = firstTime;
      _isLoggedIn = currentUser != null;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _connectionHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    Widget startScreen;

    if (_isLoggedIn) {
      // ✅ User already logged in → go straight to Homepage
      startScreen = const Homepage();
    } else if (_isFirstTime) {
      // ✅ First time opening → show onboarding (ws1)
      startScreen = const OnboardingScreen();
    } else {
      // ✅ Already opened, not logged in → show login / choice screen (ws2)
      startScreen = const ChatWithAIApp(); // or ChatWithAIApp depending on your ws2
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AskPSU',
      theme: ThemeData.light(),
      home: startScreen,
    );
  }
}
