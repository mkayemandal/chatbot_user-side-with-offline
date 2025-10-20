import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:ask_psu/user/llama_service.dart';
import 'package:ask_psu/user/guest_session_manager.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'package:ask_psu/user/offline_service.dart'; 


const primarycolor = Color(0xFFE6B24A);
const primarycolordark = Color(0xFF7A4F22);
const secondarycolor = Color(0xFFF7D9B9);
const textdark = Color(0xFF312B20);
const textlight = Color(0xFF948D7C);
const lightBackground = Color(0xFFFFFAF3);
const customBeige = Color(0xFFF5F5DC);

class Chatpage extends StatefulWidget {
  final String? department;
  final String? historyId;
  final String? conversationId;
  final String? sessionId;
  final bool isGuest;
  final bool isOffline;

  const Chatpage({
    super.key,
    this.department,
    this.sessionId,
    this.historyId,
    this.conversationId,
    this.isGuest = false,
    this.isOffline = false,
  });

  @override
  State<Chatpage> createState() => _ChatpageState();
}

class _ChatpageState extends State<Chatpage> with TickerProviderStateMixin {
  String? userName;
  String appName = "AskPSU"; 
  bool isLoading = true;
  late AnimationController _controller;
  late Animation<double> _animation;
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, dynamic>> messages = [];
  final ScrollController _scrollController = ScrollController();
  bool isMuted = false;
  int muteSecondsLeft = 0;
  Timer? muteTimer;
  List<String> suggestionPool = [];
  List<String> liveSuggestions = [];
  String? guestSessionId;
  String displayedBotMessage = '';
  bool isTyping = false;
  bool isThinking = false;
  bool hasSentMessage = false;
  Timer? typingTimer;
  Timer? refreshTimer;
  int charIndex = 0;
  String activeConversationId = '';
  final List<String> userMessagesForTitle = [];
  // 🔑 NEW: Connection handling
  late StreamSubscription<bool> _connectionSub;
  bool isOnline = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();

    // 🔑 NEW: Listen to connection state
    _connectionSub = ConnectionHandler.instance.connectionStream.listen((
      online,
    ) {
      setState(() => isOnline = online);
    });

    loadSuggestions();

    if (widget.isGuest) {
      guestSessionId = widget.historyId ??
          widget.conversationId ??
          GuestSessionManager().sessionId;
      if (widget.historyId != null || widget.conversationId != null) {
        loadChatHistory();
      }
    }

    fetchAppName().then((_) {
      fetchUserName().then((_) {
        setState(() {
          final displayName = userName ?? "Guest";
          messages.add({
            'text':
                "Hi, $displayName! Welcome to $appName.\nHow can I help you today?",
            'isSender': false,
            'timestamp': DateTime.now(),
          });
        });

        if (!widget.isGuest &&
            (widget.historyId != null || widget.conversationId != null)) {
          activeConversationId =
              widget.historyId ?? widget.conversationId ?? '';
          loadChatHistory();
        } else if (!widget.isGuest) {
          _createNewConversation();
        }
      });
    });

    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    typingTimer?.cancel();
    muteTimer?.cancel();
    refreshTimer?.cancel();
    _connectionSub.cancel(); // 🔑 NEW
    super.dispose();
  }

  Future<void> fetchAppName() async {
    try {
      if (!isOnline) {
        setState(() {
          appName = "AskPSU";
        });
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get();
      final data = doc.data();
      setState(() {
        appName = data?['appName'] ?? "AskPSU";
      });
    } catch (e) {
      // fallback remains AskPSU
    }
  }

  Future<void> fetchUserName() async {
    try {
      if (!isOnline) {
        setState(() {
          userName = "User";
          isLoading = false;
        });
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = doc.data()?['name'] ?? "User";
      setState(() {
        userName = name.split(' ').first;
        isLoading = false;
      });
    } catch (_) {
      setState(() {
        userName = "User";
        isLoading = false;
      });
    }
  }

  /// Always creates a new conversation for logged-in user or guest.
  /// For guest: Only creates the guest conversation when the user sends their first message!
  Future<void> _createNewConversation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && isOnline) {
      // Create a new conversation for the logged-in user (only if online)
      final newDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('conversations')
          .doc();
      await newDoc.set({
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      setState(() {
        activeConversationId = newDoc.id;
      });
    } else {
      // For guest or offline: Do NOT create Firestore doc yet! Only set guestSessionId for now.
      final conversationId = const Uuid().v4();
      setState(() {
        guestSessionId = conversationId;
      });
    }
  }

  /// For guests, only creates the conversation doc in Firestore when the first message is sent.
  Future<void> saveGuestMessage(String message, String role) async {
    if (!isOnline) return; // Don't save to Firestore when offline

    final conversationId = guestSessionId ??
        widget.conversationId ??
        widget.historyId ??
        GuestSessionManager().sessionId;
    final docRef = FirebaseFirestore.instance
        .collection('guest_conversations')
        .doc(conversationId);

    // Only create doc if it doesn't exist and only for the first user message (NOT for bot greeting)
    final docSnap = await docRef.get();
    if (!docSnap.exists) {
      await docRef.set({
        'openId': GuestSessionManager().openId,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastTimestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await docRef.collection('messages').add({
      'text': message,
      'role': role,
      'isSender': role == 'user',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void applyMute(int seconds) {
    setState(() {
      isMuted = true;
      muteSecondsLeft = seconds;
    });
    muteTimer?.cancel();
    muteTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          muteSecondsLeft--;
          if (muteSecondsLeft <= 0) {
            timer.cancel();
            isMuted = false;
          }
        });
      }
    });
  }

  /// This is called by the "new chat" icon in the AppBar.
  /// It will create a new conversation for both user and guest and reset the UI.
  Future<void> startNewChat() async {
    await _createNewConversation();
    setState(() {
      messages.clear();
      displayedBotMessage = '';
      hasSentMessage = false;
      isTyping = false;
      isThinking = false;
      userMessagesForTitle.clear();
    });
    final displayName = userName ?? "Guest";
    messages.add({
      'text':
          "Hi, $displayName! Welcome to $appName.\nHow can I help you today?",
      'isSender': false,
      'timestamp': DateTime.now(),
    });
    scrollToBottom();
  }

  Future<void> saveMessageToConversation({
    required String conversationId,
    required String message,
    required bool isSender,
    required String role,
  }) async {
    if (!isOnline) return; // Don't save to Firestore when offline
    final timestamp = Timestamp.now();
    final messageData = {
      'role': role,
      'text': message,
      'timestamp': timestamp,
      'isSender': isSender,
    };

    if (widget.isGuest) {
      final guestRef = FirebaseFirestore.instance
          .collection('guest_conversations')
          .doc(conversationId);
      await guestRef.collection('messages').add(messageData);
      await guestRef.set({
        'lastMessage': message,
        'lastTimestamp': timestamp,
      }, SetOptions(merge: true));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('conversations')
        .doc(conversationId);

    await userRef.collection('messages').add(messageData);

    final snapshot = await userRef.get();
    if (!snapshot.exists ||
        !(snapshot.data()?['firstMessage']?.isNotEmpty ?? false)) {
      await userRef.set({'firstMessage': message}, SetOptions(merge: true));
    }
    await userRef.set({
      'lastMessage': message,
      'lastTimestamp': timestamp,
    }, SetOptions(merge: true));
  }

  void scrollToBottom({Duration delay = const Duration(milliseconds: 100)}) {
    Future.delayed(delay, () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 🔹 SIMPLIFIED: Only use offline service when truly offline
  Future<String?> getCsvBasedReply(String input) async {
    try {
      // Only use offline service when device is actually offline
      if (isOnline && ConnectionHandler.instance.isOnline) {
        print(
          '🔍 DEBUG: Device is online, skipping offline service for "$input"',
        );
        return null; // Let the online LLM handle it
      }

      // Only try offline service when offline
      final offlineResponse = await OfflineService.instance
          .fetchOfflineResponse(input, widget.department);

      print('🔍 DEBUG: Offline response for "$input": "$offlineResponse"');

      // Return the offline response if it's meaningful
      // Allow our new offline messages to be shown
      if (offlineResponse.isNotEmpty &&
          !offlineResponse.contains("I'm sorry, but I couldn't find") &&
          !offlineResponse.contains("Please try asking more clearly") &&
          !offlineResponse.contains("Please try rephrasing your question")) {
        print('🔍 DEBUG: Using offline response as real answer');
        return offlineResponse;
      }

      print('🔍 DEBUG: No meaningful offline response found');
      return null;
    } catch (e) {
      print("Error in getCsvBasedReply: $e");
    }
    return null; // no match found
  }

  void handleUserTyping(String value) {
    final query = value.toLowerCase().trim();
    final greetingPattern = RegExp(
      r'^(hi|hello|greetings|kumusta|kamusta|good (morning|afternoon|evening))[\s!.,]*$',
      caseSensitive: false,
    );
    if (query.isEmpty || greetingPattern.hasMatch(query)) {
      setState(() {
        liveSuggestions.clear();
      });
      return;
    }
    final fuzzyMatches = suggestionPool
        .where((q) {
          final qLower = q.toLowerCase();
          final levDist = levenshteinDistance(query, qLower);
          final maxLen =
              query.length > qLower.length ? query.length : qLower.length;
          final levRatio =
              maxLen == 0 ? 0.0 : 1.0 - (levDist / maxLen.toDouble());
          return levRatio >= 0.8 || qLower.contains(query);
        })
        .take(5)
        .toList();
    setState(() {
      liveSuggestions = fuzzyMatches;
    });
  }

  // 🔹 SIMPLIFIED: Load suggestions based on connection status
  Future<void> loadSuggestions() async {
    try {
      if (isOnline && ConnectionHandler.instance.isOnline) {
        // When online, try to fetch from Firestore first
        try {
          final snapshot =
              await FirebaseFirestore.instance.collection('CsvData').get();
          final allQuestions = <String>{};

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final csvData = data['data'];
            if (csvData is List) {
              for (var item in csvData) {
                if (item is Map && item.containsKey('question')) {
                  final question = item['question']?.toString() ?? '';
                  if (question.isNotEmpty) allQuestions.add(question);
                }
              }
            }
          }
          setState(() => suggestionPool = allQuestions.toList());
          print(
            '🔍 DEBUG: Loaded ${allQuestions.length} suggestions from Firestore',
          );
        } catch (e) {
          print("Firestore error in loadSuggestions: $e");
          // Fallback to offline suggestions
          await _loadOfflineSuggestions();
        }
      } else {
        // When offline, use offline suggestions
        await _loadOfflineSuggestions();
      }
    } catch (e) {
      print("Error loading suggestions: $e");
    }
  }

  Future<void> _loadOfflineSuggestions() async {
    try {
      final offlineQs = await OfflineService.instance.loadQuestions();
      if (offlineQs.isNotEmpty) {
        setState(() => suggestionPool = offlineQs);
        print('🔍 DEBUG: Loaded ${offlineQs.length} offline suggestions');
      }
    } catch (e) {
      print("Error loading offline suggestions: $e");
    }
  }

  Future<void> handleUserMessage(String message) async {
    if (message.trim().isEmpty || isTyping || isThinking || isMuted) return;
    if (!mounted) return;
    setState(() {
      hasSentMessage = true;
      isThinking = true;
      liveSuggestions.clear();
      messages.add({
        'text': message,
        'isSender': true,
        'timestamp': DateTime.now(),
      });
    });

    // Only save to Firestore if online
    if (isOnline && ConnectionHandler.instance.isOnline) {
      final user = FirebaseAuth.instance.currentUser;
      userMessagesForTitle.add(message);
      final uid = user?.uid ?? guestSessionId ?? '';
      String title = await generateChatHistoryTitle(userMessagesForTitle, uid);

      if (widget.isGuest && guestSessionId != null) {
        await FirebaseFirestore.instance
            .collection('guest_conversations')
            .doc(guestSessionId)
            .set({
          'title': title,
          'lastUpdated': Timestamp.now(),
          'openId': GuestSessionManager().openId,
        }, SetOptions(merge: true));
      } else if ((activeConversationId.isNotEmpty) && user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('conversations')
            .doc(activeConversationId)
            .set({
          'title': title,
          'lastUpdated': Timestamp.now(),
        }, SetOptions(merge: true));
      }

      if (widget.isGuest && guestSessionId != null) {
        await saveGuestMessage(message, 'user');
      } else if ((activeConversationId.isNotEmpty) && user != null) {
        await saveMessageToConversation(
          conversationId: activeConversationId,
          role: 'user',
          message: message,
          isSender: true,
        );
      }
    }

    _textController.clear();
    scrollToBottom();

    String? csvReply = await getCsvBasedReply(message);
    String aiReply;

    print('🔍 DEBUG: csvReply is ${csvReply != null ? "not null" : "null"}');
    print(
      '🔍 DEBUG: isOnline: $isOnline, ConnectionHandler.isOnline: ${ConnectionHandler.instance.isOnline}',
    );

    if (csvReply != null) {
      // Use CSV-based reply (works both online and offline)
      print('🔍 DEBUG: Using CSV-based reply: "$csvReply"');
      aiReply = csvReply;
    } else if (isOnline && ConnectionHandler.instance.isOnline) {
      // Only try LLM if online
      print('🔍 DEBUG: Using online LLM for message: "$message"');
      final uid2 = FirebaseAuth.instance.currentUser?.uid ?? '';
      aiReply = await fetchLlamaResponse(message, widget.department, uid: uid2);
      print('🔍 DEBUG: LLM response: "$aiReply"');
    } else {
      // Offline fallback when no CSV match found
      print('🔍 DEBUG: Using offline fallback - no internet connection');
      aiReply =
          "I'm sorry, I couldn't find a relevant answer in my offline knowledge base. Please try rephrasing your question or check your internet connection for more comprehensive responses.";
    }

    if (aiReply.startsWith('⏳ You’re muted for')) {
      if (!mounted) return;
      setState(() {
        isThinking = false;
        isTyping = false;
        isMuted = true;
        displayedBotMessage = '';
        messages.add({
          'text': aiReply,
          'isSender': false,
          'timestamp': DateTime.now(),
        });
        liveSuggestions.clear();
      });

      // Only save bot message to Firestore if online
      if (isOnline && ConnectionHandler.instance.isOnline) {
        final user = FirebaseAuth.instance.currentUser;
        if (widget.isGuest && guestSessionId != null) {
          await saveGuestMessage(aiReply, 'bot');
        } else if ((activeConversationId.isNotEmpty) && user != null) {
          await saveMessageToConversation(
            conversationId: activeConversationId,
            role: 'bot',
            message: aiReply,
            isSender: false,
          );
        }
      }

      final secondsMatch = RegExp(r'Please wait (\d+)s').firstMatch(aiReply);
      final muteSecs =
          secondsMatch != null ? int.parse(secondsMatch.group(1)!) : 60;
      applyMute(muteSecs);
      return;
    }

    if (!mounted) return;
    setState(() {
      isThinking = false;
      isTyping = true;
    });
    startTypingEffect(aiReply);
  }

  void startTypingEffect(String fullMessage) {
    displayedBotMessage = '';
    charIndex = 0;
    typingTimer?.cancel();
    typingTimer = Timer.periodic(const Duration(milliseconds: 15), (
      timer,
    ) async {
      if (charIndex < fullMessage.length) {
        setState(() {
          displayedBotMessage += fullMessage[charIndex];
          charIndex++;
        });
        scrollToBottom();
      } else {
        timer.cancel();
        setState(() {
          isTyping = false;
          messages.add({
            'text': fullMessage,
            'isSender': false,
            'timestamp': DateTime.now(),
          });
        });

        final user = FirebaseAuth.instance.currentUser;

        // Only save bot message to Firestore if online
        if (isOnline && ConnectionHandler.instance.isOnline) {
          if (widget.isGuest && guestSessionId != null) {
            await saveGuestMessage(fullMessage, 'bot');
          } else if ((activeConversationId.isNotEmpty) && user != null) {
            await saveMessageToConversation(
              conversationId: activeConversationId,
              role: 'bot',
              message: fullMessage,
              isSender: false,
            );
          }
        }

        if (fullMessage.contains('🚫 You’ve been muted for 1 minute')) {
          applyMute(60);
        }
        scrollToBottom();
      }
    });
  }

  Future<void> loadChatHistory() async {
    if (!isOnline || !ConnectionHandler.instance.isOnline) {
      // Cannot load chat history when offline
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = user != null && !widget.isGuest;
    final String? historyId = widget.historyId ?? widget.conversationId;
    if (historyId == null) return;
    final CollectionReference chatRef = isLoggedIn
        ? FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('conversations')
            .doc(historyId)
            .collection('messages')
        : FirebaseFirestore.instance
            .collection('guest_conversations')
            .doc(historyId)
            .collection('messages');
    final snapshot = await chatRef.orderBy('timestamp').get();
    final loadedMessages = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'text': data['text'] ?? '',
        'isSender': data['isSender'] ?? false,
        'timestamp': (data['timestamp'] as Timestamp).toDate(),
      };
    }).toList();
    setState(() {
      messages.addAll(loadedMessages);
    });
    scrollToBottom(delay: const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: textdark),
        elevation: 0,
        title: Text(appName,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: primarycolordark,
                fontSize: 22)),
        centerTitle: true,
        leading: Tooltip(
          message: 'Back',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          // Offline indicator
          if (!isOnline || !ConnectionHandler.instance.isOnline)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'OFFLINE',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.forum),
            tooltip: "New Chat",
            onPressed: () async {
              await startNewChat();
            },
            color: primarycolordark,
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _animation,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: messages.length + (isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < messages.length) {
                    final msg = messages[index];
                    return MessageBubble(
                      message: msg['text'],
                      isSender: msg['isSender'],
                      timestamp: msg['timestamp'],
                      isOnline: isOnline,
                    );
                  } else {
                    return MessageBubble(
                      message: displayedBotMessage,
                      isSender: false,
                      timestamp: DateTime.now(),
                      isOnline: isOnline,
                    );
                  }
                },
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: liveSuggestions.isNotEmpty
                  ? Container(
                      key: const ValueKey('suggestions'),
                      height: 48,
                      padding: const EdgeInsets.only(left: 12, right: 12),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: liveSuggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final suggestion = liveSuggestions[index];
                          return GestureDetector(
                            onTap: isMuted
                                ? null
                                : () => handleUserMessage(suggestion),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: primarycolordark),
                                borderRadius: BorderRadius.circular(20),
                                color: primarycolordark.withOpacity(0.05),
                              ),
                              child: Center(
                                child: Text(
                                  suggestion,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: primarycolordark,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no_suggestions')),
            ),
            if (hasSentMessage && (isThinking || isTyping))
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 6),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 10,
                      backgroundColor: primarycolor,
                      child: Icon(
                        Icons.smart_toy,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    isThinking
                        ? const TypingDotsStatic()
                        : Text(
                            "$appName is typing...",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: textlight,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ],
                ),
              ),
            ChatInputField(
              textController: _textController,
              onMessageSent: handleUserMessage,
              isTyping: isTyping || isThinking,
              isMuted: isMuted,
              muteSecondsLeft: muteSecondsLeft,
              onInputChanged: handleUserTyping,
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isSender,
    required this.timestamp,
    required this.isOnline,
  });

  final String message;
  final bool isSender;
  final DateTime timestamp;
  final bool isOnline;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool liked = false;
  bool disliked = false;

  @override
  Widget build(BuildContext context) {
    final formatted = formatTimestamp(widget.timestamp);
    return Align(
      alignment: widget.isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.isSender
              ? primarycolor.withOpacity(0.95)
              : secondarycolor.withOpacity(0.12),
          border: widget.isSender
              ? null
              : Border.all(color: primarycolordark.withOpacity(0.18)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isSender ? 16 : 0),
            bottomRight: Radius.circular(widget.isSender ? 0 : 16),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Linkify(
              text: widget.message,
              style: GoogleFonts.poppins(
                color: widget.isSender ? Colors.white : textdark,
                fontSize: 15,
              ),
              linkStyle: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.none, // no underline
              ),
              // NOTE: PhoneNumberLinkifier removed so phone numbers are not detected/clickable
              linkifiers: const [
                UrlLinkifier(),
                EmailLinkifier(),
              ],
              onOpen: (link) async {
                String raw = link.url.trim();

                // Basic cleanup
                raw = raw.replaceFirst(RegExp(r'^[\u2022\-\•\s]+'), ''); // remove bullets
                raw = raw.replaceFirst(RegExp(r'^(Email:|E-mail:)\s*', caseSensitive: false), '');
                raw = raw.replaceFirst(RegExp(r'^(Facebook:|Facebook Page:)\s*', caseSensitive: false), '');

                // Quick invalid check
                if (raw.isEmpty || raw.contains('  ')) raw = raw.replaceAll(RegExp(r'\s+'), ' ');
                if (raw.isEmpty) return;

                Uri uriCandidate;

                final emailReg = RegExp(r'^[\w\.\-+%]+@[\w\.\-]+\.[A-Za-z]{2,}$');

                try {
                  if (raw.toLowerCase().startsWith('mailto:')) {
                    uriCandidate = Uri.parse(raw);
                  } else if (emailReg.hasMatch(raw)) {
                    uriCandidate = Uri(scheme: 'mailto', path: raw);
                  } else {
                    // URL normalization for scheme-less values like "facebook.com/..."
                    String candidate = raw;
                    if (candidate.startsWith('www.')) candidate = 'https://$candidate';
                    else if (!candidate.contains('://') && candidate.contains('.')) candidate = 'https://$candidate';
                    uriCandidate = Uri.parse(candidate);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invalid link: $raw')),
                  );
                  return;
                }

                // If somehow a tel: scheme appears, do not open; inform the user instead.
                if (uriCandidate.scheme == 'tel') {
                  showCustomSnackBar(
                    context,
                    message: "Phone numbers are not clickable.",
                    backgroundColor: Colors.orange,
                    icon: Icons.phone_disabled,
                    iconColor: Colors.white,
                    borderColor: Colors.orangeAccent,
                    seconds: 2,
                  );
                  return;
                }

                // Confirm before opening
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Open Link'),
                    content: Text('Do you want to open this link?\n${uriCandidate.toString()}'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Open')),
                    ],
                  ),
                );
                if (confirm != true) return;

                final isMailTo = uriCandidate.scheme == 'mailto';
                final mode = isMailTo ? LaunchMode.platformDefault : LaunchMode.externalApplication;

                try {
                  final can = await canLaunchUrl(uriCandidate);
                  print('DEBUG: open ${uriCandidate.toString()} (canLaunch=$can)');

                  if (can) {
                    final launched = await launchUrl(uriCandidate, mode: mode);
                    if (!launched) {
                      final fallback = await launchUrlString(uriCandidate.toString(), mode: mode);
                      if (!fallback) {
                        showCustomSnackBar(
                          context,
                          message: "Could not open ${uriCandidate.toString()}",
                          backgroundColor: Colors.redAccent,
                          icon: Icons.error,
                          iconColor: Colors.white,
                          borderColor: Colors.red,
                          seconds: 3,
                        );
                      }
                    }
                  } else {
                    final fallback = await launchUrlString(uriCandidate.toString(), mode: mode);
                    if (!fallback) {
                      showCustomSnackBar(
                        context,
                        message: "Could not launch ${uriCandidate.toString()}",
                        backgroundColor: Colors.redAccent,
                        icon: Icons.error,
                        iconColor: Colors.white,
                        borderColor: Colors.red,
                        seconds: 3,
                      );
                    }
                  }
                } catch (e) {
                  print('ERROR launching url: $e');
                  showCustomSnackBar(
                    context,
                    message: "Error opening link: ${e.toString()}",
                    backgroundColor: Colors.redAccent,
                    icon: Icons.error,
                    iconColor: Colors.white,
                    borderColor: Colors.red,
                    seconds: 3,
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.isSender) ...[
                  Text(
                    formatted,
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "Copy",
                    icon: const Icon(
                      Icons.copy,
                      size: 18,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.message));
                      showCustomSnackBar(
                        context,
                        message: "Copied to clipboard",
                        backgroundColor: primarycolordark,
                        icon: Icons.check_circle,
                        iconColor: Colors.white,
                        borderColor: primarycolor,
                        seconds: 2,
                      );
                    },
                  ),
                ] else ...[
                  IconButton(
                    tooltip: "Copy",
                    icon: Icon(
                      Icons.copy,
                      size: 18,
                      color: primarycolor.withOpacity(0.7),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.message));
                      showCustomSnackBar(
                        context,
                        message: "Copied to clipboard",
                        backgroundColor: primarycolordark,
                        icon: Icons.check_circle,
                        iconColor: Colors.white,
                        borderColor: primarycolor,
                        seconds: 2,
                      );
                    },
                  ),
                  IconButton(
                    tooltip: "Good Response",
                    icon: Icon(
                      liked ? Icons.thumb_up_alt : Icons.thumb_up,
                      size: 18,
                      color: primarycolor.withOpacity(0.7),
                    ),
                    onPressed: () {
                      setState(() {
                        liked = true;
                        disliked = false;
                      });
                      _showFeedbackDialog(
                          context, 'positive', widget.message, widget.isOnline);
                    },
                  ),
                  IconButton(
                    tooltip: "Bad Response",
                    icon: Icon(
                      disliked ? Icons.thumb_down_alt : Icons.thumb_down,
                      size: 18,
                      color: primarycolor.withOpacity(0.7),
                    ),
                    onPressed: () {
                      setState(() {
                        disliked = true;
                        liked = false;
                      });
                      _showFeedbackDialog(
                          context, 'negative', widget.message, widget.isOnline);
                    },
                  ),
                  const Spacer(),
                  Text(
                    formatted,
                    style: GoogleFonts.poppins(color: textlight, fontSize: 10),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackDialog(
    BuildContext context,
    String sentiment,
    String botMessage,
    bool isOnline,
  ) {
    final TextEditingController feedbackController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'Give Feedback',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: feedbackController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Your Message...',
                    hintStyle: GoogleFonts.poppins(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.grey,
                      ), // Default border color
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: primarycolordark,
                        width: 2,
                      ), // Focused color
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: primarycolor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.poppins(color: primarycolor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primarycolor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final feedback = feedbackController.text.trim();
                          if (feedback.isNotEmpty) {
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              print(
                                  '🔍 DEBUG: User authentication status: ${user != null ? "Authenticated" : "Guest user"}');

                              // Check if we're online before attempting Firestore operations
                              if (!isOnline ||
                                  !ConnectionHandler.instance.isOnline) {
                                print(
                                    '⚠️ DEBUG: App is offline, cannot submit feedback to Firestore');
                                Navigator.of(dialogContext).pop();
                                showCustomSnackBar(
                                  context,
                                  message: "Cannot submit feedback while offline. Please go online and try again.",
                                  backgroundColor: Colors.orange,
                                  icon: Icons.warning,
                                  iconColor: Colors.white,
                                  borderColor: Colors.yellow,
                                  seconds: 3,
                                );
                                return;
                              }

                              String userName = 'Guest User';
                              String userEmail = '';

                              if (user != null) {
                                // Authenticated user
                                print('🔍 DEBUG: User UID: ${user.uid}');
                                print('🔍 DEBUG: User email: ${user.email}');

                                final userDoc = await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .get();
                                userName = userDoc.data()?['name'] ??
                                    'Authenticated User';
                                userEmail = user.email ?? '';
                              } else {
                                // Guest user
                                print(
                                    '🔍 DEBUG: Guest user submitting feedback');
                                userName = 'Guest User';
                                userEmail = '';
                              }

                              print(
                                  '🔍 DEBUG: Submitting feedback to Firestore...');
                              print(
                                  '🔍 DEBUG: Feedback data: name=$userName, email=$userEmail, sentiment=$sentiment');

                              await FirebaseFirestore.instance
                                  .collection('Feedbacks')
                                  .add({
                                'name': userName,
                                'email': userEmail,
                                'message': feedback,
                                'sentiment': sentiment,
                                'status': 'new',
                                'timestamp': Timestamp.now(),
                                'botResponse': botMessage,
                                'userType':
                                    user != null ? 'authenticated' : 'guest',
                                'userId': user?.uid ?? 'guest',
                              });

                              print(
                                  '✅ DEBUG: Feedback successfully submitted to Firestore');

                              Navigator.of(dialogContext).pop();
                              showCustomSnackBar(
                                context,
                                message: "Feedback submitted successfully!",
                                backgroundColor: primarycolordark,
                                icon: Icons.check_circle,
                                iconColor: Colors.white,
                                borderColor: primarycolor,
                                seconds: 2,
                              );
                            } catch (e) {
                              print('❌ ERROR: Failed to submit feedback: $e');
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Failed to submit feedback. Please try again.",
                                    style: GoogleFonts.poppins(),
                                  ),
                                  duration: const Duration(seconds: 3),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.only(
                                    bottom: 80,
                                    left: 20,
                                    right: 20,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            }
                          } else {
                            print('⚠️ DEBUG: Feedback text is empty');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Please enter your feedback before submitting.",
                                  style: GoogleFonts.poppins(),
                                ),
                                duration: const Duration(seconds: 2),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.only(
                                  bottom: 80,
                                  left: 20,
                                  right: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          }
                        },
                        child: Text("Submit", style: GoogleFonts.poppins()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.textController,
    required this.onMessageSent,
    required this.isTyping,
    required this.isMuted,
    required this.muteSecondsLeft,
    required this.onInputChanged,
  });

  final TextEditingController textController;
  final ValueChanged<String> onMessageSent;
  final bool isTyping;
  final bool isMuted;
  final int muteSecondsLeft;
  final ValueChanged<String> onInputChanged;

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  bool _sendHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.textController,
              enabled: !widget.isTyping && !widget.isMuted,
              decoration: InputDecoration(
                hintText: widget.isMuted
                    ? "You are muted for ${widget.muteSecondsLeft}s"
                    : (widget.isTyping
                        ? "Please wait..."
                        : "Type your message..."),
                hintStyle: GoogleFonts.poppins(color: textlight),
                filled: true,
                fillColor: widget.isMuted || widget.isTyping
                    ? Colors.grey.shade200
                    : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              style: GoogleFonts.poppins(color: textdark),
              onSubmitted: widget.isTyping || widget.isMuted
                  ? null
                  : (msg) => widget.onMessageSent(msg),
              onChanged: widget.onInputChanged,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.isTyping || widget.isMuted
                ? null
                : () => widget.onMessageSent(widget.textController.text),
            onTapDown: (_) => setState(() => _sendHovered = true),
            onTapUp: (_) => setState(() => _sendHovered = false),
            onTapCancel: () => setState(() => _sendHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isTyping
                    ? customBeige
                    : (_sendHovered ? primarycolordark : primarycolor),
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(Icons.send, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class TypingDotsStatic extends StatefulWidget {
  const TypingDotsStatic({super.key});
  @override
  State<TypingDotsStatic> createState() => _TypingDotsStaticState();
}

class _TypingDotsStaticState extends State<TypingDotsStatic>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int dotCount = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        dotCount = (dotCount % 3) + 1;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '.' * dotCount,
      style: const TextStyle(
        fontSize: 12,
        fontStyle: FontStyle.italic,
        color: textlight,
      ),
    );
  }
}

String formatTimestamp(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} hr ago';
  return '${time.month}/${time.day}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}

void showCustomSnackBar(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  IconData? icon,
  Color? iconColor,
  Color? borderColor,
  int seconds = 2,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (icon != null)
            Icon(icon, color: iconColor ?? Colors.white),
          if (icon != null)
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      duration: Duration(seconds: seconds),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(
        bottom: 100,
        left: 20,
        right: 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        // side: BorderSide(color: borderColor ?? backgroundColor, width: 2),
      ),
      elevation: 8,
    ),
  );
}