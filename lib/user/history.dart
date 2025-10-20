import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ask_psu/user/homepage.dart';
import 'package:ask_psu/user/chatpage.dart';
import 'package:ask_psu/user/profile.dart';
import 'package:ask_psu/user/guest_session_manager.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const secondarycolor = Color(0xFFf4e2c6);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

class SearchHistoryPage extends StatefulWidget {
  final String? historyId;
  final bool isGuest;
  final bool isOffline;

  const SearchHistoryPage({
    super.key,
    this.historyId,
    this.isGuest = false,
    this.isOffline = false,
  });

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  int _selectedIndex = 2;
  final List<bool> _navHovered = [false, false, true, false];
  List<Map<String, dynamic>> userHistory = [];

  bool selectionMode = false;
  Set<String> selectedIds = {};

  // Real-time connectivity monitoring
  late StreamSubscription<bool> _connectionSub;
  bool _isCurrentlyOffline = false;

  @override
  void initState() {
    super.initState();

    // Initialize offline state
    _isCurrentlyOffline = widget.isOffline;

    // Also check current connectivity status directly
    _checkCurrentConnectivity();

    // Listen to real-time connectivity changes
    _connectionSub =
        ConnectionHandler.instance.connectionStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isCurrentlyOffline = !isOnline;
        });

        // If we go offline, show error and redirect
        if (_isCurrentlyOffline) {
          _showOfflineMessageAndReturn();
        }
      }
    });

    // IMMEDIATE OFFLINE CHECK - redirect before any UI is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isOnline = ConnectionHandler.instance.isOnline;
      if (!isOnline || _isCurrentlyOffline) {
        _showOfflineMessageAndReturn();
        return;
      }
    });

    // Check if user is offline and redirect if necessary
    if (_isCurrentlyOffline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showOfflineMessageAndReturn();
      });
      return;
    }

    fetchRecentHistory();
  }

  Future<void> _checkCurrentConnectivity() async {
    final isOnline = ConnectionHandler.instance.isOnline;
    if (mounted) {
      setState(() {
        _isCurrentlyOffline = !isOnline;
      });

      if (_isCurrentlyOffline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showOfflineMessageAndReturn();
        });
      }
    }
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(SearchHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check offline status when widget is updated (e.g., when navigating back)
    final isOnline = ConnectionHandler.instance.isOnline;
    if (!isOnline || widget.isOffline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showOfflineMessageAndReturn();
      });
    }
  }

  void _showOfflineMessageAndReturn() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "History is not available in offline mode.",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    // Navigate back after showing the message
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> fetchRecentHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    List<Map<String, dynamic>> messages = [];
    if (user == null) {
      // Guest conversations for THIS session only
      final snapshot = await FirebaseFirestore.instance
          .collection('guest_conversations')
          .where('openId', isEqualTo: GuestSessionManager().openId)
          .orderBy('lastUpdated', descending: true)
          .limit(50)
          .get();

      // Only include guest conversations that have at least one message
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final messagesSnapshot =
            await doc.reference.collection('messages').limit(1).get();
        if (messagesSnapshot.docs.isNotEmpty) {
          messages.add({
            'id': doc.id,
            'term': data['title'] ?? data['lastMessage'] ?? 'Guest chat',
            'isGuest': true,
            'timestamp': data['lastTimestamp'] ?? data['lastUpdated'],
          });
        }
      }
    } else {
      // User conversations
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('conversations')
          .orderBy('lastTimestamp', descending: true)
          .limit(50)
          .get();

      messages = snapshot.docs.map((doc) {
        final data = doc.data();
        final rawText =
            data['title'] ?? data['term'] ?? data['firstMessage'] ?? '';
        return {
          'id': doc.id,
          'term': sanitizeMessage(rawText),
          'isGuest': false,
          'timestamp': data['lastTimestamp'] ?? data['lastUpdated'],
        };
      }).toList();
    }

    if (mounted) {
      setState(() {
        userHistory = messages;
      });
    }
  }

  String sanitizeMessage(String input) {
    final badWords = ['fuck', 'shit', 'bitch', 'asshole', 'nigger'];
    final pattern = RegExp(
      r'\b(' + badWords.join('|') + r')\b',
      caseSensitive: false,
    );
    final cleaned = input.replaceAllMapped(pattern, (match) => '');
    return cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String? formatTimestamp(dynamic ts) {
    if (ts == null) return null;
    DateTime time;
    if (ts is Timestamp) {
      time = ts.toDate();
    } else if (ts is DateTime) {
      time = ts;
    } else if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      return null;
    }
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    return "${time.month}/${time.day}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}";
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
      // Optionally, you may also set the doc here if you want
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            Chatpage(conversationId: conversationId, isGuest: isGuest),
      ),
    );
    if (result == true || result == null) {
      await fetchRecentHistory();
    }
  }

  void _onItemTapped(int index) async {
    if (index == 1) {
      // Always start a new chat for both guest and logged-in user
      await _createAndOpenChat();
      setState(() => _selectedIndex = 2);
    } else if (index == 0) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Homepage(isOffline: _isCurrentlyOffline)),
      );
      if (result == true || result == null) {
        await fetchRecentHistory();
      }
      setState(() => _selectedIndex = 2);
    } else if (index == 2) {
      // History button clicked - check if offline
      final isOnline = ConnectionHandler.instance.isOnline;
      if (!isOnline || _isCurrentlyOffline) {
        _showOfflineMessageAndReturn();
      } else {
        setState(() {
          _selectedIndex = index;
        });
      }
    } else if (index == 3) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Profilepage(isOffline: _isCurrentlyOffline)),
      );
      setState(() => _selectedIndex = 2);
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null;

    if (selectedIds.isEmpty) return;

    final backupConversations = <String, Map<String, dynamic>>{};
    final backupMessages = <String, List<Map<String, dynamic>>>{};

    for (var id in selectedIds) {
      if (isGuest) {
        final docRef = FirebaseFirestore.instance
            .collection('guest_conversations')
            .doc(id);
        final docSnap = await docRef.get();
        if (docSnap.exists) {
          backupConversations[id] = docSnap.data()!;
        }
      } else {
        final conversationRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('conversations')
            .doc(id);

        final conversationSnapshot = await conversationRef.get();
        if (conversationSnapshot.exists) {
          backupConversations[id] = conversationSnapshot.data()!;
        }

        final messagesSnapshot =
            await conversationRef.collection('messages').get();
        backupMessages[id] = messagesSnapshot.docs
            .map((doc) => {'id': doc.id, 'data': doc.data()})
            .toList();
      }
    }

    for (var id in selectedIds) {
      if (isGuest) {
        await FirebaseFirestore.instance
            .collection('guest_conversations')
            .doc(id)
            .delete();
      } else {
        final conversationRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('conversations')
            .doc(id);

        final messagesSnapshot =
            await conversationRef.collection('messages').get();
        for (var doc in messagesSnapshot.docs) {
          await doc.reference.delete();
        }
        await conversationRef.delete();
      }
    }

    final count = selectedIds.length;
    final deletedIds = Set<String>.from(selectedIds);

    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });

    await fetchRecentHistory();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$count conversation${count > 1 ? 's' : ''} deleted'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () async {
            for (var id in deletedIds) {
              if (isGuest) {
                final convoData = backupConversations[id];
                if (convoData != null) {
                  await FirebaseFirestore.instance
                      .collection('guest_conversations')
                      .doc(id)
                      .set(convoData);
                }
              } else {
                final convoData = backupConversations[id];
                final messageList = backupMessages[id];
                final convoRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('conversations')
                    .doc(id);
                if (convoData != null) {
                  await convoRef.set(convoData);
                }
                if (messageList != null) {
                  for (var msg in messageList) {
                    await convoRef
                        .collection('messages')
                        .doc(msg['id'])
                        .set(msg['data']);
                  }
                }
              }
            }
            await fetchRecentHistory();
          },
        ),
      ),
    );
  }

  void _selectAll() {
    setState(() {
      selectedIds = userHistory.map((e) => e['id'] as String).toSet();
    });
  }

  void _cancelSelection() {
    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });
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
    // TRIPLE-CHECK connectivity status - most aggressive check
    final isOnline = ConnectionHandler.instance.isOnline;
    if (!isOnline || _isCurrentlyOffline) {
      // Immediately redirect without showing any UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "History is not available in offline mode.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      });

      // Return a minimal container while redirecting
      return Scaffold(
        backgroundColor: Colors.white,
        body: Container(),
      );
    }

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: lightBackground,
        elevation: 0,
        title: selectionMode
            ? Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: primarycolordark,
                    ),
                    onPressed: _cancelSelection,
                  ),
                  if (selectedIds.isNotEmpty)
                    Text(
                      '${selectedIds.length}',
                      style: const TextStyle(
                        color: primarycolordark,
                        fontSize: 18,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: primarycolordark,
                    ),
                    onPressed: _deleteSelected,
                    tooltip: 'Delete selected',
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: selectedIds.length == userHistory.length &&
                            userHistory.isNotEmpty,
                        onChanged: (value) {
                          if (value == true) {
                            _selectAll();
                          } else {
                            setState(() {
                              selectedIds.clear();
                            });
                          }
                        },
                        activeColor: primarycolordark,
                        checkColor: Colors.white,
                        side: const BorderSide(
                          color: primarycolordark,
                          width: 2.0,
                        ),
                      ),
                      const Text(
                        "Select all",
                        style: TextStyle(
                          color: primarycolordark,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Center(
                child: Text(
                  'Chat History',
                  style: GoogleFonts.poppins(
                    color: primarycolordark,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
        centerTitle: true,
      ),
      body: userHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/history_empty.png',
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No recent history",
                    style: GoogleFonts.poppins(
                      color: textlight,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: userHistory.length,
                    itemBuilder: (context, index) {
                      final history = userHistory[index];
                      final isSelected = selectedIds.contains(history['id']);
                      final tsStr = formatTimestamp(history['timestamp']);

                      final historyItem = GestureDetector(
                        onLongPress: () {
                          setState(() {
                            selectionMode = true;
                            selectedIds.add(history['id']);
                          });
                        },
                        onTap: () async {
                          if (selectionMode) {
                            _toggleSelection(history['id']);
                          } else {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Chatpage(
                                  historyId: history["id"],
                                  conversationId: history["id"],
                                  isGuest: history['isGuest'] ?? false,
                                  isOffline: _isCurrentlyOffline,
                                ),
                              ),
                            );
                            await fetchRecentHistory();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 18,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? secondarycolor.withOpacity(0.4)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: primarycolor.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              if (selectionMode)
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (_) =>
                                      _toggleSelection(history['id']),
                                  activeColor: primarycolordark,
                                )
                              else
                                const Icon(
                                  Icons.history,
                                  size: 22,
                                  color: primarycolordark,
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  sanitizeMessage(history["term"]),
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: textdark,
                                  ),
                                ),
                              ),
                              if (tsStr != null) ...[
                                const SizedBox(width: 10),
                                Text(
                                  tsStr,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: textlight,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );

                      if (!selectionMode) {
                        return Dismissible(
                          key: Key(history['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          onDismissed: (direction) async {
                            final user = FirebaseAuth.instance.currentUser;
                            final isGuest = user == null;
                            final deletedItem = userHistory[index];
                            final conversationId = deletedItem['id'];

                            Map<String, dynamic>? conversationData;
                            List<Map<String, dynamic>> backedUpMessages = [];

                            if (isGuest) {
                              final docRef = FirebaseFirestore.instance
                                  .collection('guest_conversations')
                                  .doc(conversationId);
                              final docSnap = await docRef.get();
                              if (docSnap.exists) {
                                conversationData = docSnap.data();
                              }
                              await docRef.delete();
                            } else {
                              final conversationRef = FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('conversations')
                                  .doc(conversationId);

                              final messagesRef = conversationRef.collection(
                                'messages',
                              );
                              final conversationSnapshot =
                                  await conversationRef.get();
                              conversationData = conversationSnapshot.data();

                              final messagesSnapshot = await messagesRef.get();
                              backedUpMessages = messagesSnapshot.docs.map((
                                doc,
                              ) {
                                return {
                                  'messageId': doc.id,
                                  'messageData': doc.data(),
                                };
                              }).toList();

                              for (var doc in messagesSnapshot.docs) {
                                await doc.reference.delete();
                              }
                              await conversationRef.delete();
                            }

                            await fetchRecentHistory();

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Conversation deleted'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () async {
                                    if (isGuest) {
                                      if (conversationData != null) {
                                        await FirebaseFirestore.instance
                                            .collection('guest_conversations')
                                            .doc(conversationId)
                                            .set(conversationData);
                                      }
                                    } else {
                                      if (conversationData != null) {
                                        final user =
                                            FirebaseAuth.instance.currentUser;
                                        if (user != null) {
                                          final conversationRef =
                                              FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(user.uid)
                                                  .collection('conversations')
                                                  .doc(conversationId);
                                          await conversationRef.set(
                                            conversationData,
                                          );
                                          for (var msg in backedUpMessages) {
                                            final messageId =
                                                msg['messageId'] as String;
                                            final messageData =
                                                msg['messageData']
                                                    as Map<String, dynamic>;
                                            await conversationRef
                                                .collection('messages')
                                                .doc(messageId)
                                                .set(messageData);
                                          }
                                        }
                                      }
                                    }
                                    await fetchRecentHistory();
                                  },
                                ),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                          child: historyItem,
                        );
                      } else {
                        return historyItem;
                      }
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildNavigationBar(context),
    );
  }
}
