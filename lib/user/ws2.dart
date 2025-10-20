import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ask_psu/user/homepage.dart';
import 'package:ask_psu/user/login.dart';
import 'package:ask_psu/user/connection_handler.dart';

const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const secondarycolor = Color(0xFF542409);
const dark = Color(0xFF17110d);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

class ChatWithAIApp extends StatefulWidget {
  final bool isOffline;

  const ChatWithAIApp({super.key, this.isOffline = false});

  @override
  State<ChatWithAIApp> createState() => _ChatWithAIAppState();
}

class _ChatWithAIAppState extends State<ChatWithAIApp> {
  bool _isGuestHovered = false;
  bool _isLoginHovered = false;

  // Real-time connectivity monitoring
  late StreamSubscription<bool> _connectionSub;
  bool _isCurrentlyOffline = false;

  Future<Map<String, dynamic>> fetchSettings() async {
    try {
      // Only fetch from Firestore if online
      if (!_isCurrentlyOffline) {
        final doc = await FirebaseFirestore.instance
            .collection('SystemSettings')
            .doc('global')
            .get();
        return doc.data() ?? _getDefaultSettings();
      } else {
        // Use default settings when offline
        return _getDefaultSettings();
      }
    } catch (e) {
      print('Error fetching settings: $e');
      return _getDefaultSettings();
    }
  }

  Map<String, dynamic> _getDefaultSettings() {
    return {
      'appName': 'AskPSU',
      'tagline2': 'Ask Me Anything',
      'description2': 'Support at your fingertips.',
    };
  }

  @override
  void initState() {
    super.initState();

    // Initialize offline state
    _isCurrentlyOffline = widget.isOffline;

    // Listen to real-time connectivity changes
    _connectionSub = ConnectionHandler.instance.connectionStream.listen((
      isOnline,
    ) {
      if (mounted) {
        setState(() {
          _isCurrentlyOffline = !isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 375).clamp(0.85, 1.2);

    return Scaffold(
      backgroundColor: lightBackground,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: fetchSettings(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: primarycolor),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(child: Text("Failed to load settings"));
            }

            final data = snapshot.data!;
            final appName = data['appName'] ?? 'AppName';
            final tagline = data['tagline2'] ?? 'Ask Me Anything';
            final description =
                data['description2'] ?? 'Support at your fingertips.';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24.0, bottom: 10),
                  child: Center(
                    child: Text(
                      appName,
                      style: GoogleFonts.poppins(
                        fontSize: 32 * scale,
                        fontWeight: FontWeight.bold,
                        color: primarycolor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/3.png', height: 210),
                          const SizedBox(height: 36),
                          Text(
                            tagline,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 26 * scale,
                              fontWeight: FontWeight.bold,
                              color: primarycolor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Text(
                              description,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16 * scale,
                                fontWeight: FontWeight.w500,
                                color: textlight,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildAnimatedButton(
                                label: 'Guest',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Homepage(
                                      isOffline: _isCurrentlyOffline,
                                    ),
                                  ),
                                ),
                                hovered: _isGuestHovered,
                                onHoverChanged: (hovered) {
                                  if (mounted) {
                                    setState(() => _isGuestHovered = hovered);
                                  }
                                },
                                isFilled: false,
                                scaleFactor: scale,
                              ),
                              const SizedBox(width: 20),
                              _buildAnimatedButton(
                                label: 'Login',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const UserLogin(),
                                  ),
                                ),
                                hovered: _isLoginHovered,
                                onHoverChanged: (hovered) {
                                  if (mounted) {
                                    setState(() => _isLoginHovered = hovered);
                                  }
                                },
                                isFilled: true,
                                scaleFactor: scale,
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Divider(
                            thickness: 1,
                            color: secondarycolor.withOpacity(0.1),
                            height: 40,
                            indent: 40,
                            endIndent: 40,
                          ),
                          Text(
                            'By continuing, you agree to our Terms and Privacy Policy.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 12 * scale,
                              color: textlight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedButton({
    required String label,
    required VoidCallback onTap,
    required bool hovered,
    required Function(bool) onHoverChanged,
    required bool isFilled,
    required double scaleFactor,
  }) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onTap: () async {
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isFilled
                ? null
                : Border.all(
                    color: hovered ? primarycolordark : primarycolor,
                    width: 2,
                  ),
            gradient: isFilled
                ? LinearGradient(
                    colors: hovered
                        ? [primarycolordark, primarycolor]
                        : [primarycolor, primarycolordark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isFilled
                ? null
                : hovered
                    ? primarycolor.withOpacity(0.08)
                    : Colors.transparent,
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: primarycolor.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 50 * scaleFactor,
            vertical: 14 * scaleFactor,
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: isFilled
                  ? Colors.white
                  : (hovered ? primarycolordark : primarycolor),
              fontWeight: FontWeight.w600,
              fontSize: 16 * scaleFactor,
            ),
          ),
        ),
      ),
    );
  }
}
