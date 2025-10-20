import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ask_psu/user/ws2.dart';
import 'package:ask_psu/user/homepage.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; 

const primaryColor = Color(0xFFd5891b);
const primaryColorDark = Color(0xFF753a0e);
const secondaryColor = Color(0xFF542409);
const dark = Color(0xFF17110d);
const textDark = Color(0xFF333333);
const textLight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Future<Map<String, dynamic>> fetchSystemSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get();
      return doc.data() ?? _getDefaultSettings();
    } catch (e) {
      print('Error fetching system settings: $e');
      return _getDefaultSettings();
    }
  }

  Map<String, dynamic> _getDefaultSettings() {
    return {
      'appName': 'AskPSU',
      'tagline1': 'Welcome to AskPSU',
      'description1': 'Your intelligent assistant for all your questions.',
    };
  }

  // Save flag so next time app skips onboarding
  Future<void> _completeOnboarding(bool isOnline) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstTime', false);

    // If offline → go to Homepage
    if (!isOnline) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const Homepage()),
      );
    } 
    // If online → go to login choice (ws2)
    else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatWithAIApp(isOffline: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    double scale = screenWidth / 375;
    scale = scale.clamp(0.85, 1.2);

    return SafeArea(
      child: Scaffold(
        backgroundColor: lightBackground,
        body: StreamBuilder<ConnectivityResult>(
          stream: ConnectionHandler.instance.connectivityStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primaryColor),
              );
            }

            final isOnline = snapshot.data != ConnectivityResult.none;

            return FutureBuilder<Map<String, dynamic>>(
              future: fetchSystemSettings(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }

                if (!snapshot.hasData || snapshot.data == null) {
                  return const Center(
                    child: Text("Failed to load app settings"),
                  );
                }

                final settings = snapshot.data!;
                final appName = settings['appName'] ?? 'AppName';
                final tagline = settings['tagline1'] ?? 'Welcome!';
                final description = settings['description1'] ??
                    'Your app description goes here.';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: Center(
                        child: Text(
                          appName,
                          style: GoogleFonts.poppins(
                            fontSize: 32 * scale,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/2.png',
                                height: screenHeight * 0.35,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                tagline,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 26 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30.0,
                                ),
                                child: Text(
                                  description,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16 * scale,
                                    fontWeight: FontWeight.w500,
                                    color: textLight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 50.0),
                      child: GestureDetector(
                        onTap: () => _completeOnboarding(isOnline), // ✅ updated
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [primaryColor, primaryColorDark],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.3),
                                blurRadius: 16,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (!isOnline)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'You are offline. Only offline chat is available.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}