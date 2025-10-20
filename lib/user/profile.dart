import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ask_psu/user/homepage.dart';
import 'package:ask_psu/user/chatpage.dart';
import 'package:ask_psu/user/myaccount.dart';
import 'package:ask_psu/user/helpsupport.dart';
import 'package:ask_psu/user/aboutapp.dart';
import 'package:ask_psu/user/login.dart';
import 'package:ask_psu/user/history.dart';
import 'package:ask_psu/user/ws2.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'dart:async';

const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const secondarycolor = Color(0xFFf4e2c6);
const dark = Color(0xFF17110d);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

String capitalizeEachWord(String input) {
  return input
      .split(' ')
      .map(
        (word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '',
      )
      .join(' ');
}

class Profilepage extends StatefulWidget {
  final bool isOffline;

  const Profilepage({super.key, this.isOffline = false});

  @override
  State<Profilepage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<Profilepage>
    with TickerProviderStateMixin {
  final int _selectedIndex = 3;
  String fullName = "Loading...";
  String email = "Loading...";
  bool isGuest = false;

  final List<bool> _navHovered = [false, false, false, true];

  // Real-time connectivity monitoring
  late StreamSubscription<bool> _connectionSub;
  bool _isCurrentlyOffline = false;

  @override
  void initState() {
    super.initState();

    // Initialize offline state
    _isCurrentlyOffline = widget.isOffline;

    // Listen to real-time connectivity changes
    _connectionSub =
        ConnectionHandler.instance.connectionStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isCurrentlyOffline = !isOnline;
        });
      }
    });

    fetchUserDetails();
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  Future<void> fetchUserDetails() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        setState(() {
          isGuest = false;
        });
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data();
          setState(() {
            fullName = capitalizeEachWord(data?['name'] ?? 'No Name');
            email = data?['email'] ?? user.email ?? 'No Email';
          });
        } else {
          setState(() {
            fullName = 'User not found';
            email = user.email ?? 'No Email';
          });
        }
      } else {
        // Guest
        setState(() {
          isGuest = true;
          fullName = "Guest";
          email = "Not logged in";
        });
      }
    } catch (e) {
      setState(() {
        fullName = 'Error loading name';
        email = 'Error loading email';
        isGuest = true;
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => Homepage(isOffline: _isCurrentlyOffline),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else if (index == 1) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              Chatpage(isGuest: isGuest, isOffline: _isCurrentlyOffline),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else if (index == 2) {
      // Double-check connectivity before allowing history access
      final isOnline = ConnectionHandler.instance.isOnline;
      if (!isOnline || _isCurrentlyOffline) {
        // Show offline message for history
        _showOfflineMessage("History is not available in offline mode.");
      } else {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                SearchHistoryPage(isOffline: _isCurrentlyOffline),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    }
  }

  void _showOfflineMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Colors.orange,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.orange[700],
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Color _navItemColor(int idx, {bool selected = false}) {
    if (_navHovered[idx]) return primarycolordark;
    return selected ? primarycolor : textlight;
  }

  Widget _buildNavigationBar(BuildContext context) {
    final navItems = [
      {"icon": Icons.home, "label": "Home"},
      {"icon": Icons.chat, "label": "Chat"},
      {"icon": Icons.history, "label": "History"},
      {"icon": Icons.person, "label": "Account"},
    ];

    return Container(
      decoration: BoxDecoration(
        color: secondarycolor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (idx) {
          final isSelected = _selectedIndex == idx;
          return MouseRegion(
            onEnter: (_) => setState(() => _navHovered[idx] = true),
            onExit: (_) => setState(() => _navHovered[idx] = false),
            child: GestureDetector(
              onTap: () => _onItemTapped(idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 26,
                ),
                decoration: BoxDecoration(
                  color: (isSelected || _navHovered[idx])
                      ? primarycolor.withOpacity(0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      navItems[idx]["icon"] as IconData,
                      color: _navItemColor(idx, selected: isSelected),
                      size: isSelected ? 28 : 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      navItems[idx]["label"] as String,
                      style: GoogleFonts.poppins(
                        color: _navItemColor(idx, selected: isSelected),
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: isSelected ? 14 : 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Your Profile',
          style: GoogleFonts.poppins(
            color: primarycolordark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primarycolor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: primarycolor.withOpacity(0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundImage: AssetImage(
                        'assets/images/defaultDP.jpg',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: GoogleFonts.poppins(
                              color: textdark,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: GoogleFonts.poppins(
                              color: textlight,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _loadingCard(
                title: 'My Account',
                icon: Icons.account_circle_outlined,
                onTap: isGuest
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const MyAccountPage(),
                            transitionsBuilder: (_, animation, __, child) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                          ),
                        );
                      },
              ),
              _loadingCard(
                title: 'Help & Support',
                icon: Icons.help_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const HelpSupportPage(),
                      transitionsBuilder: (_, animation, __, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                },
              ),
              _loadingCard(
                title: 'About App',
                icon: Icons.info_outline,
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const AboutAppPage(),
                      transitionsBuilder: (_, animation, __, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                },
              ),
              _loadingCard(
                title: isGuest ? 'Sign In' : 'Logout',
                icon: isGuest ? Icons.login : Icons.logout,
                onTap: () async {
                  if (isGuest) {
                    // ✅ Guests go directly to the login page
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const UserLogin()),
                      (route) => false,
                    );
                  } else {
                    // Logout for logged-in users
                    await FirebaseAuth.instance.signOut();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('isFirstTime', true); // reset onboarding if needed
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatWithAIApp()),
                      (route) => false,
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildNavigationBar(context),
    );
  }

  Widget _loadingCard({
    required String title,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDisabled ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: primarycolor.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: lightBackground,
              child: Icon(icon, color: primarycolordark, size: 27),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: isDisabled ? textlight : textdark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (title != 'Logout' && title != 'Sign In')
              const Icon(
                Icons.chevron_right,
                color: primarycolordark,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
