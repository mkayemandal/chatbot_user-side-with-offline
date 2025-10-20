import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// = GUEST FOUL LOGIC STATE =
int guestFoulStrikes = 0;
DateTime? guestMuteUntil;

void resetGuestFoulPenalty() {
  guestFoulStrikes = 0;
  guestMuteUntil = null;
}

bool isGuestMuted() =>
    guestMuteUntil != null && DateTime.now().isBefore(guestMuteUntil!);

// = [BAGONG HELPER] Para sa UI check =
int? getGuestMuteSeconds() {
  if (isGuestMuted()) {
    return guestMuteUntil!.difference(DateTime.now()).inSeconds;
  }
  return null;
}
// ==========

// = [UPDATED] GUEST FOUL WORD LOGIC =
String handleGuestFoulWord(String message) {
  final now = DateTime.now();

  if (guestMuteUntil != null && now.difference(guestMuteUntil!).inHours >= 24) {
    guestFoulStrikes = 0;
    guestMuteUntil = null;
  }
  if (isGuestMuted()) {
    guestMuteUntil = now.add(const Duration(minutes: 1));
    return "Mute timer has been reset to 1 minute.";
  }
  guestFoulStrikes++;
  String reply;
  if (guestFoulStrikes <= 3) {
    reply =
        "Please avoid using foul language. Continued use of foul words will lead to a temporary mute.";
  } else {
    guestMuteUntil = now.add(const Duration(minutes: 1));
    reply = "You’ve been muted for 1 minute due to continued foul language.";
  }
  return reply;
}
// ============

Map<String, String> guestLLMCache = {};

// 🔁 Levenshtein Distance Calculator
int levenshteinDistance(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  List<List<int>> matrix =
      List.generate(s.length + 1, (_) => List.filled(t.length + 1, 0));
  for (int i = 0; i <= s.length; i++) matrix[i][0] = i;
  for (int j = 0; j <= t.length; j++) matrix[0][j] = j;
  for (int i = 1; i <= s.length; i++) {
    for (int j = 1; j <= t.length; j++) {
      int cost = s[i - 1] == t[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return matrix[s.length][t.length];
}

// In-memory CSV cache
Map<String, List<Map<String, String>>> cachedCsvData = {};

// = [NEW] ABBREVIATION & SYNONYM EXPANSION =
final Map<String, List<String>> _synonymMap = {
  // General & Existing
  'dl': ['dean lister', 'dean\'s list'],
  'requirements': ['qualification', 'qualifications', 'criteria'],
  'grades': ['gpa', 'grade point average', 'marks'],
  'cgpa': ['cumulative grade point average'],
  'enroll': ['enrollment', 'enlist', 'enlistment', 'register', 'registration'],
  'subjects': ['courses', 'classes'],
  'id': ['identification card'],
  'scholarship': ['financial aid', 'grant'],
  'dean': ['chair', 'coordinator'],
  'psu': ['pampanga state university'],

  // DHVSU Colleges

  'cea': ['college of engineering and architecture'],
  'cbaa': ['college of business administration and accountancy'],
  'cas': ['college of arts and sciences'],
  'ced': ['college of education'],
  'cit': ['college of industrial technology'],
  'chtm': ['college of hospitality and tourism management'],
  'ccs': ['college of computing studies'],
  'ccs': ['college of computing studies'],

  // DHVSU Programs (Acronyms)
  'bsa': ['bachelor of science in architecture'],
  'bsce': ['bachelor of science in civil engineering'],
  'bsee': ['bachelor of science in electrical engineering'],
  'bsece': ['bachelor of science in electronics engineering'],
  'bsie': ['bachelor of science in industrial engineering'],
  'bsme': ['bachelor of science in mechanical engineering'],
  'bs-arch': ['bachelor of science in architecture'],
  'bca': ['bachelor of science in accountancy'],
  'bsba': ['bachelor of science in business administration'],
  'bsentrep': ['bachelor of science in entrepreneurship'],
  'bshm': ['bachelor of science in hospitality management'],
  'bstm': ['bachelor of science in tourism management'],
  'bscs': ['bachelor of science in computer science'],
  'bsinfotech': ['bachelor of science in information technology'],
  'bsit': ['bachelor of science in information technology'],
  'blis': ['bachelor of library and information science'],
  'bpa': ['bachelor of public administration'],
  'bs-math': ['bachelor of science in mathematics'],
  'bs-psych': ['bachelor of science in psychology'],
  'bmm': ['bachelor of multimedia arts'],
  'bfa': ['bachelor of fine arts'],
  'bsed': ['bachelor of secondary education'],
  'beed': ['bachelor of elementary education'],
  'btvted': ['bachelor of technical-vocational teacher education'],
  'bped': ['bachelor of physical education'],
  'bsned': ['bachelor of special needs education'],
  'bat': ['bachelor of automotive technology'],
  'bet': ['bachelor of engineering technology'],
};

String _expandSynonyms(String message) {
  String expandedMessage = message;
  final words = message.toLowerCase().split(RegExp(r'\\s+')).toSet();
  for (var word in words) {
    if (_synonymMap.containsKey(word)) {
      for (var synonym in _synonymMap[word]!) {
        if (!expandedMessage.toLowerCase().contains(synonym)) {
          expandedMessage += ' $synonym';
        }
      }
    }
  }
  return expandedMessage;
}
// = END OF SYNONYM LOGIC =

void watchForCsvUpdates() {
  FirebaseFirestore.instance
      .collection('metadata')
      .doc('dataset')
      .snapshots()
      .listen((snapshot) async {
    if (snapshot.exists) {
      print('🔁 CSV updated, reloading cache...');
      await preloadAllCsvData();
    }
  });
}

final RegExp _greetingOnlyPattern = RegExp(
    r'^(hi|hello|greetings|kumusta|kamusta|good (morning|afternoon|evening))[\\s!.,]*$',
    caseSensitive: false);

bool isGreetingOnly(String message) =>
    _greetingOnlyPattern.hasMatch(message.trim().toLowerCase());

// ❌ Foul word filtering (with regex support)
final List<String> foulWords = [
  'fuck',
  'shit',
  'asshole',
  'bitch',
  'mother fucker',
  'damn',
  'putang ina',
  'tangina',
  'gago',
  'ulol',
  'tarantado',
  'gaga'
];
final List<RegExp> foulPatterns = [
  RegExp(r'f[\\W_]*u[\\W_]*c[\\W_]*k', caseSensitive: false),
  RegExp(r's[\\W_]*h[\\W_]*i[\\W_]*t', caseSensitive: false),
  RegExp(r'b[\\W_]*i[\\W_]*t[\\W_]*c[\\W_]*h', caseSensitive: false),
  RegExp(r'a[\\W_]*s[\\W_]*s[\\W_]*h[\\W_]*o[\\W_]*l[\\W_]*e',
      caseSensitive: false),
  RegExp(r'p[\\W_]*u[\\W_]*t[\\W_]*a[\\W_]*n[\\W_]*g', caseSensitive: false),
  RegExp(r'g[\\W_]*a[\\W_]*g[\\W_]*o', caseSensitive: false)
];

// Foul word removal
String removeFoulWords(String text) {
  String sanitized = text;
  for (var pattern in foulPatterns) {
    sanitized = sanitized.replaceAll(pattern, '');
  }
  for (var word in foulWords) {
    sanitized = sanitized.replaceAll(
      RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false),
      '',
    );
  }
  return sanitized.replaceAll(RegExp(r'\\s{2,}'), ' ').trim();
}

// Helper: true if message is only foul words (after removal nothing left)
bool isFoulWordOnly(String message) {
  String cleaned = message.trim();
  if (cleaned.isEmpty) return false;
  foulPatterns.forEach((p) => cleaned = cleaned.replaceAll(p, ''));
  foulWords.forEach((w) => cleaned = cleaned.replaceAll(
      RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ''));
  return cleaned.replaceAll(RegExp(r'\\s+'), '').isEmpty;
}

// Get clean, real user message (skip greetings, handle foul word only)
String getCleanHistoryTitle(List<String> userMessages) {
  for (final msg in userMessages) {
    if (isGreetingOnly(msg)) continue;
    if (isFoulWordOnly(msg)) return "foul word";
    final cleaned = removeFoulWords(msg.trim());
    if (cleaned.isNotEmpty) return cleaned;
  }
  return "Greetings";
}

// = [BAGONG FALLBACK] Keyword Extraction Logic =
String _createFallbackTitleFromKeywords(String message) {
  const stopWords = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'was',
    'were',
    'what',
    'when',
    'where',
    'why',
    'how',
    'who',
    'i',
    'me',
    'my',
    'to',
    'for',
    'of',
    'in',
    'on',
    'with',
    'and',
    'or',
    'but',
    'po',
    'opo',
    'ano',
    'paano',
    'saan',
    'kailan',
    'sino',
    'ang',
    'mga',
    'sa',
    'para',
    'lang',
    'naman'
  };

  List<String> words = message
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zA-Z0-9\\s]'), '')
      .split(' ');
  List<String> keywords = words
      .where((word) => !stopWords.contains(word) && word.isNotEmpty)
      .toList();

  if (keywords.isEmpty) {
    return message.length > 30 ? '${message.substring(0, 27)}...' : message;
  }

  String title = keywords
      .map((kw) => kw.isNotEmpty ? kw[0].toUpperCase() + kw.substring(1) : '')
      .join(' ');

  var titleWords = title.split(' ');
  if (titleWords.length > 5) {
    title = titleWords.sublist(0, 5).join(' ');
  }
  return title;
}
// ============

// = [IN-UPDATE] Title Generation with Intelligent Fallback =
Future<String> generateChatHistoryTitle(
    List<String> userMessages, String uid) async {
  final preview = getCleanHistoryTitle(userMessages);

  if (preview == "Greetings" || preview == "foul word") {
    return preview;
  }

  try {
    final rephrased = await fetchLlamaTitle(preview, uid);

    if (rephrased != null &&
        rephrased.trim().isNotEmpty &&
        !rephrased.toLowerCase().contains("sorry") &&
        !rephrased.toLowerCase().contains("trouble")) {
      return removeFoulWords(rephrased.trim());
    } else {
      return _createFallbackTitleFromKeywords(preview);
    }
  } catch (e) {
    print(
        "Could not generate title with Llama, using keyword fallback. Error: $e");
    return _createFallbackTitleFromKeywords(preview);
  }
}
// ============

Future<void> preloadAllCsvData() async {
  final snapshot = await FirebaseFirestore.instance.collection('CsvData').get();
  for (var doc in snapshot.docs) {
    final dataList = doc.data()['data'];
    if (dataList is List) {
      cachedCsvData[doc.id] = dataList
          .whereType<Map>()
          .map((entry) => {
                'question': entry['question']?.toString() ?? '',
                'answer': entry['answer']?.toString() ?? ''
              })
          .where((qa) => qa['question']!.isNotEmpty && qa['answer']!.isNotEmpty)
          .toList();
    }
  }
}

// = [BAGONG LOGIC] Smarter Search Functions =
String? _findDepartmentFromQuery(String userMessage) {
  final words = userMessage.toLowerCase().split(RegExp(r'\\s+'));
  for (var word in words) {
    for (var key in cachedCsvData.keys) {
      if (word.replaceAll(RegExp(r'[^a-z0-9]'), '') ==
          key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')) {
        print('✅ Department keyword detected: $key');
        return key;
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> _searchKnowledgeBase(
    String userMessage, String? detectedDepartment) {
  List<Map<String, dynamic>> allMatches = [];
  final normalizedInput =
      userMessage.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\\s]'), '');
  final searchKeys =
      detectedDepartment != null ? [detectedDepartment] : cachedCsvData.keys;

  print('🧠 Searching in departments: $searchKeys');

  for (var key in searchKeys) {
    final qaList = cachedCsvData[key];
    if (qaList != null) {
      for (var item in qaList) {
        final question = item['question']!;
        final qNorm =
            question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\\s]'), '');
        final simScore =
            StringSimilarity.compareTwoStrings(normalizedInput, qNorm);

        allMatches.add({
          'question': question,
          'answer': item['answer']!,
          'score': simScore,
          'source': key,
        });
      }
    }
  }
  allMatches
      .sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
  return allMatches;
}
// ===========

// 🧠 Message memory
List<Map<String, String>> messageHistory = [
  {"role": "system", "content": '''...'''},
];

void trimMessageHistory() {
  const int maxHistory = 6;
  if (messageHistory.length > maxHistory + 2) {
    messageHistory = [
      messageHistory.first,
      ...messageHistory.sublist(messageHistory.length - maxHistory)
    ];
  }
}

String generateFriendlyGreeting() {
  final greetings = [
    "Hello! How can I help you today?",
    "Hi there! What can I do for you?",
    "Hey! What question do you have for me?",
    "Greetings! I'm here to help with your questions."
  ];
  return greetings[Random().nextInt(greetings.length)];
}

bool containsBadWord(String message) {
  final lower = message.toLowerCase();
  return foulWords.any((word) => lower.contains(word)) ||
      foulPatterns.any((pattern) => pattern.hasMatch(lower));
}

String sanitizeMessage(String message) {
  String sanitized = message;
  for (var pattern in foulPatterns) {
    sanitized = sanitized.replaceAll(pattern, '');
  }
  for (var word in foulWords) {
    sanitized = sanitized.replaceAll(
        RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false), '');
  }
  return sanitized.replaceAll(RegExp(r'\\s{2,}'), ' ').trim();
}

bool isValidQuestion(String message) {
  final lower = message.toLowerCase();
  return message.contains("?") ||
      lower.contains("ano") ||
      lower.contains("what") ||
      lower.contains("paano");
}

// = [BAGONG HELPER] Para sa UI check ng Logged-in User=
Future<int?> getLoggedInUserMuteSeconds(String uid) async {
  if (uid.isEmpty) return null;
  try {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null && data.containsKey('muteUntil')) {
      final muteUntil = (data['muteUntil'] as Timestamp).toDate();
      final now = DateTime.now();
      if (now.isBefore(muteUntil)) {
        return muteUntil.difference(now).inSeconds;
      }
    }
  } catch (e) {
    print("Error getting mute status: $e");
  }
  return null;
}
// ============

// = [UPDATED] LOGGED-IN FOUL WORD LOGIC =
Future<String?> handleFoulWord(String uid, String message) async {
  final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final doc = await docRef.get();
  final now = DateTime.now();
  final data = doc.data();

  // 1. Suriin muna kung may active mute.
  final existingMuteUntil = (data?['muteUntil'] as Timestamp?)?.toDate();
  if (existingMuteUntil != null && now.isBefore(existingMuteUntil)) {
    final newMuteTime = now.add(const Duration(minutes: 1));
    await docRef.update({'muteUntil': Timestamp.fromDate(newMuteTime)});
    return "Mute timer has been reset to 1 minute.";
  }

  // 2. Kung walang active mute, gawin ang strike counting.
  int strikes =
      data != null && data.containsKey('strikes') ? data['strikes'] : 0;
  final lastOffense = (data?['lastOffense'] as Timestamp?)?.toDate();

  if (lastOffense != null && now.difference(lastOffense).inHours >= 24) {
    strikes = 0;
  }
  strikes++;

  DateTime? newMuteUntil;
  String reply;

  if (strikes <= 3) {
    reply =
        "Please avoid using foul language. Continued use of foul words will lead to a temporary mute.";
  } else {
    newMuteUntil = now.add(const Duration(minutes: 1));
    reply = "You’ve been muted for 1 minute due to continued foul language.";
  }

  await docRef.set({
    'strikes': strikes,
    'lastOffense': Timestamp.fromDate(now),
    if (newMuteUntil != null) 'muteUntil': Timestamp.fromDate(newMuteUntil),
  }, SetOptions(merge: true));

  return reply;
}
// ============

Future<String?> fetchLlamaTitle(String message, String uid) async {
  try {
    final prompt =
        "Rephrase this user question into a concise title: \"$message\"";
    final fetchUid = (uid == 'preview') ? '' : uid;
    final title = await fetchLlamaResponse(prompt, "general", uid: fetchUid);
    return title;
  } catch (e) {
    print('⚠️ Error in fetchLlamaTitle: $e');
    return null;
  }
}

// = [IMPROVED] MAIN FETCH LOGIC WITH TYPO HANDLING & BETTER PROMPT =
Future<String> fetchLlamaResponse(String userMessage, String? department,
    {required String uid}) async {
  if (uid.isNotEmpty && uid != 'preview') {
    final muteSeconds = await getLoggedInUserMuteSeconds(uid);
    if (muteSeconds != null) return '';
  } else if (uid.isEmpty) {
    if (isGuestMuted()) return '';
  }

  if (containsBadWord(userMessage)) {
    String? foulReply;
    if (uid.isEmpty) {
      foulReply = handleGuestFoulWord(userMessage);
    } else if (uid != 'preview') {
      foulReply = await handleFoulWord(uid, userMessage);
    }
    if (foulReply != null) {
      if (isFoulWordOnly(userMessage)) {
        return foulReply;
      }
      final isStrikeStop =
          (foulReply.contains("muted") || foulReply.contains("reset"));
      if (isStrikeStop) {
        return foulReply;
      }
      messageHistory
          .add({"role": "assistant", "content": sanitizeMessage(foulReply)});
    }
  }

  if (isGreetingOnly(userMessage)) {
    return generateFriendlyGreeting();
  }

  if (uid == 'preview') {
    return await sendToTogether([
      {
        "role": "system",
        "content": "Rephrase the following message into a concise title."
      },
      {"role": "user", "content": userMessage}
    ]);
  }

  // --- SMART SEARCH EXECUTION ---
  final expandedUserMessage = _expandSynonyms(userMessage);
  final detectedDepartment = _findDepartmentFromQuery(expandedUserMessage);
  final allMatches =
      _searchKnowledgeBase(expandedUserMessage, detectedDepartment);

  // --- NEW: TYPO-HANDLING & CONFIDENCE LOGIC ---
  if (allMatches.isNotEmpty) {
    final bestMatch = allMatches.first;
    final bestScore = bestMatch['score'] as double;

    if (bestScore > 0.85) {
      // HIGH confidence: Return direct answer
      final response =
          "Of course! Here is the information I found:\n\n${bestMatch['answer']}";
      print(
          '✅ High confidence match (score: ${bestMatch['score']}). Returning direct answer.');
      return response;
    } else if (bestScore > 0.70) {
      // MEDIUM confidence: It might be a typo. Ask the user for confirmation.
      final suggestedQuestion = bestMatch['question'] as String;
      print(
          '🤔 Medium confidence match (score: ${bestMatch['score']}). Asking for clarification.');
      // NOTE: Your UI will need to handle the user's "yes/no" response to this question.
      return 'I found something similar. Did you mean: "$suggestedQuestion"?';
    }
  }
  // LOW confidence or NO matches will fall through to the RAG logic below.

  // --- RAG Fallback ---
  print(allMatches.isEmpty
      ? '🤔 No matches found. Using general knowledge.'
      : '🤔 Low confidence (score: ${allMatches.first['score']}). Using top matches as context for Llama.');
  final relevantDocs = allMatches.take(5).toList();

  String contextBlock;
  if (relevantDocs.isEmpty) {
    contextBlock =
        "No specific information was found in the school's database related to your question.";
  } else {
    contextBlock = relevantDocs
        .map((doc) => 'Q: ${doc['question']}\nA: ${doc['answer']}')
        .join('\\n\\n---\\n\\n');
  }

  final sanitizedUserMessage = sanitizeMessage(userMessage);

  // ===== [IMPROVED, CONVERSATIONAL PROMPT] =====
  final systemPrompt = '''
You are PSUBot, a friendly and expert assistant for the university. Your goal is to help students and visitors by answering their questions accurately.

- **Respond in the same language the user is writing in (e.g., English, Tagalog, Kapampangan, or Taglish). Match their tone and style.
- *Use the Database First:* Always rely on the [DATABASE INFORMATION] provided. It is your single source of truth.
- *Be Conversational:* Talk like a helpful guide, not a robot. Be direct, but polite. For example, instead of saying "The data indicates...", say "I found that...".
- *Handle Keywords:* If the user just types a keyword (like "cics" or "enrollment"), summarize the key information you have about it from the database and ask a clarifying question to help them. Example: "The College of Information and Computing Sciences (CICS) offers programs like BS in Computer Science and BS in Information Technology. Are you interested in admission requirements, the curriculum, or something else?"
- *Answer Specific Questions:* If the user asks a clear question, provide a direct and concise answer from the database.
- *Never Mention the Database:* Do not say things like "Based on the provided context..." or "The database says...". You are the expert.
- *If You Don't Know:* If the database does not contain the answer, say "I don't have information on that topic right now, but I can help with other questions about the university."

The user asked: "$sanitizedUserMessage"

[DATABASE INFORMATION]
$contextBlock
[END OF DATABASE INFORMATION]
''';
  // ===================================

  messageHistory.add({"role": "system", "content": systemPrompt});
  messageHistory.add({"role": "user", "content": sanitizedUserMessage});
  trimMessageHistory();
  final aiReply = await sendToTogether(messageHistory);
  return aiReply;
}
// ==========

// 📡 Send to Together AI (no fallback model)
Future<String> sendToTogether(List<Map<String, String>> messages) async {
  const apiKey =
      'b6fb486bed0f7dd40d075871dff0255716a06afba510bcb04357d737ac5a6e42';
  const apiUrl = 'https://api.together.xyz/v1/chat/completions';
  const primaryModel = "meta-llama/Llama-3.3-70B-Instruct-Turbo";

  try {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "model": primaryModel,
        "messages": messages,
        "temperature": 0.4,
        "max_tokens": 1024,
        "stop": ["\\nUser", "\\nSystem"]
      }),
    );
    if (response.statusCode == 200) {
      final reply =
          jsonDecode(response.body)['choices'][0]['message']['content'].trim();
      messageHistory
          .add({"role": "assistant", "content": sanitizeMessage(reply)});
      return reply;
    }
    print('❌ Llama API failed: ${response.body}');
    return "Sorry, I'm having trouble accessing the answer right now. Please try again in a moment.";
  } catch (e) {
    print('❌ Llama API connection error: $e');
    return "Sorry, I'm having trouble connecting to the server. Please check your internet connection.";
  }
}

// Generate a clean, friendly preview title from first message
Future<String> generatePreviewText(String message) async {
  try {
    final prompt =
        'Rephrase this message clearly and grammatically:\\n"$message"';
    final rephrased = await fetchLlamaResponse(prompt, null, uid: 'preview');
    if (rephrased == null ||
        rephrased.trim().isEmpty ||
        rephrased.toLowerCase().contains("sorry")) {
      return _createFallbackTitleFromKeywords(message);
    }
    return rephrased.trim();
  } catch (e) {
    return _createFallbackTitleFromKeywords(message);
  }
}

String basicClean(String text) {
  final cleaned = text
      .replaceAll(RegExp(r'\\s+'), ' ')
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .trim();
  return cleaned.length > 40 ? '${cleaned.substring(0, 37)}...' : cleaned;
}

Future<void> saveGuestCacheToDisk() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('guest_llm_cache', jsonEncode(guestLLMCache));
}

Future<void> loadGuestCacheFromDisk() async {
  final prefs = await SharedPreferences.getInstance();
  final cacheString = prefs.getString('guest_llm_cache');
  if (cacheString != null) {
    guestLLMCache = Map<String, String>.from(jsonDecode(cacheString));
  }
}

Future<void> clearGuestCacheFromDisk() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('guest_llm_cache');
}
