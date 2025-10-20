import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ask_psu/user/chatpage.dart';
import 'package:ask_psu/user/profile.dart';
import 'package:ask_psu/user/history.dart';
import 'package:ask_psu/user/notification.dart';
import 'package:ask_psu/user/guest_session_manager.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'package:uuid/uuid.dart';

const primaryColor = Color(0xFFd5891b);
const primaryColorDark = Color(0xFF753a0e);
const secondaryColor = Color(0xFFf4e2c6);
const textDark = Color(0xFF333333);
const textLight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

String capitalizeEachWord(String text) => text
    .toLowerCase()
    .split(' ')
    .map(
      (word) =>
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '',
    )
    .join(' ');

class Homepage extends StatefulWidget {
  final bool isOffline;

  const Homepage({super.key, this.isOffline = false});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  List<Map<String, dynamic>> recentHistories = [];
  int _selectedIndex = 0;
  int _unreadNotifications = 0;
  String? userName;
  String? appName;
  bool isLoading = true;
  final List<bool> _navHovered = [false, false, false, false];

  // Real-time connectivity monitoring
  late StreamSubscription<bool> _connectionSub;
  bool _isCurrentlyOffline = false;

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

        // Refresh data when coming back online
        if (isOnline && !widget.isOffline) {
          fetchAppName();
          fetchRecentHistory();
          fetchUnreadNotifications();
        }
      }
    });

    fetchUserName();
    fetchAppName();
    if (!_isCurrentlyOffline) {
      fetchRecentHistory();
      fetchUnreadNotifications();
    }
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  String sanitizeMessage(String message) {
    final cleaned = message.trim().replaceAll('\n', ' ').replaceAll('\r', '');
    return cleaned.length > 50 ? cleaned.substring(0, 50) : cleaned;
  }

  Future<void> fetchAppName() async {
    if (_isCurrentlyOffline) {
      // For offline mode, use default app name
      if (mounted) {
        setState(() {
          appName = 'Chatbot';
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get();
      if (mounted) {
        setState(() {
          appName = doc.data()?['appName'] ?? 'Chatbot';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          appName = 'Chatbot';
        });
      }
    }
  }

  Future<void> fetchRecentHistory() async {
    if (_isCurrentlyOffline) {
      // For offline mode, show empty or cached data
      if (mounted) {
        setState(() {
          recentHistories = [];
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Guest conversations for THIS session only; filter out empty conversations
      final snapshot = await FirebaseFirestore.instance
          .collection('guest_conversations')
          .where('openId', isEqualTo: GuestSessionManager().openId)
          .orderBy('lastUpdated', descending: true)
          .limit(5)
          .get();

      final messages = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Only include if this conversation has messages
        final messagesSnapshot =
            await doc.reference.collection('messages').limit(1).get();
        if (messagesSnapshot.docs.isNotEmpty) {
          messages.add({
            'id': doc.id,
            'term': data['title'] ?? data['lastMessage'] ?? 'Guest chat',
            'isGuest': true,
          });
        }
      }

      if (mounted) {
        setState(() {
          recentHistories = messages;
        });
      }
    } else {
      // Logged-in user
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('conversations')
          .orderBy('lastTimestamp', descending: true)
          .limit(5)
          .get();

      final userHistoryList = userSnapshot.docs.map((doc) {
        final data = doc.data();
        final rawText =
            data['title'] ?? data['term'] ?? data['firstMessage'] ?? '';
        final sanitized = sanitizeMessage(rawText);
        return {'id': doc.id, 'term': sanitized, 'isGuest': false};
      }).toList();

      if (mounted) {
        setState(() {
          recentHistories = userHistoryList;
        });
      }
    }
  }

  Future<void> fetchUnreadNotifications() async {
    if (_isCurrentlyOffline) {
      // No notifications in offline mode
      if (mounted) {
        setState(() {
          _unreadNotifications = 0;
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('Notifications')
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'unread')
        .get();

    if (mounted) {
      setState(() {
        _unreadNotifications = snapshot.docs.length;
      });
    }
  }

  Future<void> fetchUserName() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          userName = "Guest";
          isLoading = false;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final name = capitalizeEachWord(doc.data()?['name'] ?? "User");
      final firstName = name.split(' ').first;
      if (mounted) {
        setState(() {
          userName = firstName;
          isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          userName = "User";
          isLoading = false;
        });
      }
    }
  }

  Future<void> _createAndOpenChat() async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null;

    String? conversationId;
    if (isGuest) {
      // For guest: only generate the ID, do not create the Firestore doc yet!
      conversationId = const Uuid().v4();
    } else {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('conversations')
          .doc();
      conversationId = docRef.id;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Chatpage(
          conversationId: conversationId,
          isGuest: isGuest,
          isOffline: _isCurrentlyOffline,
        ),
      ),
    );
    if ((result == true || result == null) && !_isCurrentlyOffline) {
      await fetchRecentHistory();
    }
  }

  void _onItemTapped(int index) async {
    if (index == 1) {
      // Always start a new chat for both guest and logged-in user
      await _createAndOpenChat();
      setState(() => _selectedIndex = 0); // Always return to home
    } else if (index == 2) {
      // Double-check connectivity before allowing history access
      final isOnline = ConnectionHandler.instance.isOnline;
      if (!isOnline || _isCurrentlyOffline) {
        // Show offline message for history
        _showOfflineMessage("History is not available in offline mode.");
      } else {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  SearchHistoryPage(isOffline: _isCurrentlyOffline)),
        );
        if (result == true || result == null) {
          await fetchRecentHistory();
        }
      }
      setState(() => _selectedIndex = 0);
    } else if (index == 3) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Profilepage(isOffline: _isCurrentlyOffline),
        ),
      );
      setState(() => _selectedIndex = 0);
    } else {
      setState(() {
        _selectedIndex = index;
      });
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

  Future<void> _openChatFromHistory(Map<String, dynamic> history) async {
    if (_isCurrentlyOffline) {
      _showOfflineMessage("Cannot open previous chats in offline mode.");
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Chatpage(
          conversationId: history['id'],
          historyId: history['id'],
          isGuest: history['isGuest'] ?? false,
          isOffline: _isCurrentlyOffline,
        ),
      ),
    );
    if (result == true || result == null) {
      await fetchRecentHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Offline mode indicator
                      if (_isCurrentlyOffline)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          margin: const EdgeInsets.only(bottom: 16),
                          color: Colors.orange.withOpacity(0.1),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.wifi_off,
                                size: 16,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Offline Mode',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),

                      _buildHeaderRow(),
                      const SizedBox(height: 30),
                      isLoading
                          ? const CircularProgressIndicator(color: primaryColor)
                          : Text(
                              "Hello, ${userName ?? 'Guest'}",
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: primaryColorDark,
                              ),
                            ),
                      const SizedBox(height: 8),
                      Text(
                        _isCurrentlyOffline
                            ? "You're offline. Basic chat features only."
                            : "How can I assist you right now?",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: textLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildChatCard(),
                      const SizedBox(height: 32),
                      _buildRecentChatsHeader(),
                      const SizedBox(height: 16),
                      if (_isCurrentlyOffline)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey[600]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Recent chats are not available in offline mode",
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...recentHistories.map(
                          (history) => _HistoryTile(
                            history: history,
                            onTap: () => _openChatFromHistory(history),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildNavigationBar(),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Profilepage(isOffline: widget.isOffline),
              ),
            );
            setState(() {}); // Refresh on return if needed
          },
          child: const CircleAvatar(
            backgroundImage: AssetImage('assets/images/defaultDP.jpg'),
            radius: 22,
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none,
                color: primaryColorDark,
                size: 28,
              ),
              onPressed: () async {
                if (_isCurrentlyOffline) {
                  _showOfflineMessage(
                    "Notifications are not available offline.",
                  );
                  return;
                }

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationPage()),
                  );
                  final unreadSnap = await FirebaseFirestore.instance
                      .collection('Notifications')
                      .where('email', isEqualTo: user.email)
                      .where('status', isEqualTo: 'unread')
                      .get();
                  final batch = FirebaseFirestore.instance.batch();
                  for (var doc in unreadSnap.docs) {
                    batch.update(doc.reference, {'status': 'read'});
                  }
                  await batch.commit();
                  fetchUnreadNotifications();
                }
              },
            ),
            if (_unreadNotifications > 0 && !_isCurrentlyOffline)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$_unreadNotifications',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatCard() {
    return GestureDetector(
      onTap: _createAndOpenChat,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: primaryColor,
                    radius: 20,
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _isCurrentlyOffline
                        ? "Offline\nChat"
                        : "Chat\nwith ${appName ?? 'ChatBot'}",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/1.png',
                height: 130,
                width: 140,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentChatsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Recent Chats",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textDark,
          ),
        ),
        GestureDetector(
          onTap: () async {
            if (_isCurrentlyOffline) {
              _showOfflineMessage("Cannot view chat history in offline mode.");
              return;
            }

            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchHistoryPage()),
            );
            if (result == true || result == null) {
              await fetchRecentHistory();
            }
          },
          child: Text(
            "View All",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationBar() {
    final navItems = [
      {"icon": Icons.home, "label": "Home"},
      {"icon": Icons.chat, "label": "Chat"},
      {"icon": Icons.history, "label": "History"},
      {"icon": Icons.person, "label": "Account"},
    ];

    return Container(
      decoration: BoxDecoration(
        color: secondaryColor,
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(navItems.length, (index) {
          final isSelected = _selectedIndex == index;
          return MouseRegion(
            onEnter: (_) => setState(() => _navHovered[index] = true),
            onExit: (_) => setState(() => _navHovered[index] = false),
            child: GestureDetector(
              onTap: () => _onItemTapped(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: isSelected || _navHovered[index]
                      ? primaryColor.withOpacity(0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      navItems[index]['icon'] as IconData,
                      color: isSelected ? primaryColorDark : textLight,
                      size: isSelected ? 28 : 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      navItems[index]['label'] as String,
                      style: GoogleFonts.poppins(
                        color: isSelected ? primaryColorDark : textLight,
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
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> history;
  final VoidCallback onTap;

  const _HistoryTile({required this.history, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.history, color: primaryColor),
        title: Text(
          history['term'],
          style: GoogleFonts.poppins(fontSize: 15, color: textDark),
        ),
        onTap: onTap,
      ),
    );
  }
}
