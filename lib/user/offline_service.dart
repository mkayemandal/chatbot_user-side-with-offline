import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ask_psu/user/dataset_sync.dart';

// ===== OFFLINE SERVICE (Singleton) =====
class OfflineService {
  // Singleton instance
  static final OfflineService instance = OfflineService._internal();
  OfflineService._internal();

  // ===== FOUL LANGUAGE LOGIC =====
  final List<String> _foulWords = [
    // English
    'fuck', 'fucker', 'fucking', 'motherfucker', 'mf', 'fck', 'fcking',
    'shit', 'bullshit', 'shitty', 'bastard', 'damn', 'dumbass', 'asshole',
    'jerk', 'idiot', 'moron', 'stupid', 'suck', 'sucks', 'retard', 'slut',
    'whore', 'bitch', 'son of a bitch', 'dick', 'cock', 'pussy', 'cunt',
    'wanker', 'bloody', 'bollocks', 'prick', 'twat',

    // Filipino
    'putang ina', 'puta', 'putangina', 'tangina', 'gago', 'ulol', 'tarantado',
    'buwisit', 'lintik', 'leche', 'amp', 'bwisit', 'punyeta', 'gaga',
    'tanga', 'engot', 'bobo', 'ulupong', 'animal', 'pakshet', 'bobita', 'tite',
    'gaga',

    // Variations & slang (English & Filipino)
    'f*ck', 'f**k', 'f@ck', 'f#ck',
    'sh*t', 'sht', 'biatch', 'b1tch',
    'as*hole', 'ass', 'azz',
    'p*ta', 'p*ke', 'p@ke', 'pu\$tang ina', 't@ngina',
    'g@g0', 'uLOL', 't@rantado', 'b0bo', 'eng0t',
  ];

  // ===== FOUL LANGUAGE TRACKING & MUTING =====
  Map<String, int> _foulLanguageViolations = {}; // userId -> violation count
  Map<String, DateTime> _mutedUsers = {}; // userId -> mute timestamp
  static const int _maxViolations = 3; // Mute after 3 violations
  static const Duration _muteDuration =
      Duration(hours: 24); // Mute for 24 hours

  /// Get a unique user identifier (you can modify this based on your user system)
  String _getUserId() {
    // For now, using a simple approach - you might want to use actual user ID
    // This could be based on device ID, user account, or session
    return 'default_user'; // Replace with actual user identification logic
  }

  /// Check if user is currently muted
  bool _isUserMuted(String userId) {
    if (!_mutedUsers.containsKey(userId)) return false;

    final muteTime = _mutedUsers[userId]!;
    final now = DateTime.now();

    // Check if mute period has expired
    if (now.difference(muteTime) > _muteDuration) {
      // Mute expired, remove from muted users and reset violations
      _mutedUsers.remove(userId);
      _foulLanguageViolations.remove(userId);
      return false;
    }

    return true;
  }

  /// Record a foul language violation for the user
  void _recordFoulLanguageViolation(String userId) {
    _foulLanguageViolations[userId] =
        (_foulLanguageViolations[userId] ?? 0) + 1;

    print(
        '⚠️ FOUL LANGUAGE: User $userId has ${_foulLanguageViolations[userId]} violations');

    // Check if user should be muted
    if (_foulLanguageViolations[userId]! >= _maxViolations) {
      _mutedUsers[userId] = DateTime.now();
      print(
          '🔇 MUTED: User $userId has been muted for ${_muteDuration.inHours} hours due to ${_maxViolations} foul language violations');
    }

    // Save violation data to persist across app restarts
    saveViolationData();
  }

  /// Get violation count for a user
  int _getViolationCount(String userId) {
    return _foulLanguageViolations[userId] ?? 0;
  }

  /// Get remaining violations before mute
  int _getRemainingViolations(String userId) {
    return _maxViolations - _getViolationCount(userId);
  }

  /// Manually reset violations for a user (for admin purposes)
  void resetUserViolations(String userId) {
    _foulLanguageViolations.remove(userId);
    _mutedUsers.remove(userId);
    print(
        '✅ VIOLATIONS RESET: User $userId violations and mute status cleared');
  }

  // ===== ABBREVIATION & SYNONYM EXPANSION =====
  final Map<String, List<String>> _synonymMap = {
    // General & Existing
    'dl': ['dean lister', 'dean\'s list'],
    'requirements': ['qualification', 'qualifications', 'criteria'],
    'grades': ['gpa', 'grade point average', 'marks'],
    'cgpa': ['cumulative grade point average'],
    'enroll': [
      'enrollment',
      'enlist',
      'enlistment',
      'register',
      'registration'
    ],
    'subjects': ['courses', 'classes'],
    'id': ['identification card'],
    'scholarship': ['financial aid', 'grant'],
    'dean': ['chair', 'coordinator'],
    'psu': ['pampanga state university'],
    'OCA': ['Office of Culture and the Arts'],
    'VPAS': ['Vice President for Student Affairs and Services'],
    'COR': ['Certificate of Registration'],
    'OTR': ['Transcript of Record'],
    'GPA': ['Grade Point Average'],
    'GWA': ['General Weighted Average'],
    'coe': ['certificate of enrollment'],
    'cog': ['certificate of grades'],
    // Admission-related terms
    'admission': [
      'admissions',
      'pagpasok',
      'pagpasa',
      'enrollment',
      'enlistment',
      'apply',
      'application',
      'applicant',
      'entrance',
      'entry',
      'admit',
      'admitted',
      'admisyon',
      'pagsusumite',
      'paghahain'
    ],
    'director': ['head', 'chief', 'manager', 'supervisor', 'leader'],
    'admission director': [
      'admissions director',
      'head of admissions',
      'admission head',
      'admission chief'
    ],
    'sino': [
      'who',
      'who is',
      'who are',
      'kanino',
      'saan',
      'sini',
      'sina',
      'sinu'
    ],
    'sini': ['sino', 'who', 'who is', 'sina', 'sinu'],
    'sina': ['sino', 'who', 'who are', 'sini', 'sinu'],
    'sinu': ['sino', 'who', 'sini', 'sina'],
    'ang': ['the', 'is', 'are'],
    // Schedule and time-related terms
    'schedule': [
      'kailan',
      'when',
      'time',
      'date',
      'deadline',
      'period',
      'start',
      'begin',
      'open',
      'close',
      'end',
      'semester',
      'term',
      'oras',
      'petsa',
      'panahon'
    ],
    'kailan': [
      'when',
      'schedule',
      'time',
      'date',
      'deadline',
      'period',
      'start',
      'begin',
      'open',
      'close',
      'end',
      'semester',
      'term',
      'oras',
      'petsa',
      'panahon'
    ],
    // First year/freshman terms
    'first year': [
      '1st year',
      'freshman',
      'freshmen',
      'incoming',
      'new student',
      'new students',
      'bagong estudyante',
      'bagong mag-aaral',
      'unang taon'
    ],
    '1st year': [
      'first year',
      'freshman',
      'freshmen',
      'incoming',
      'new student',
      'new students',
      'bagong estudyante',
      'bagong mag-aaral',
      'unang taon'
    ],
    // DHVSU Colleges
    'cea': ['college of engineering and architecture'],
    'cbaa': ['college of business accountancy'],
    'cas': ['college of arts and sciences'],
    'ced': ['college of education'],
    'cit': ['college of industrial technology'],
    'chtm': ['college of hospitality and tourism management'],
    'ccs': ['college of computing studies'],
    'cssp': ['college of social studies and philosophy'],

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

  /// Expands abbreviations and synonyms in the user message for better matching
  String _expandSynonyms(String message) {
    String expandedMessage = message;
    final words = message.toLowerCase().split(RegExp(r'\s+')).toSet();
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

  // ===== AUTOMATED TRUNCATION DETECTION =====

  // Flag to enable/disable auto-fix feature
  bool _autoFixEnabled = true; // Enabled to automatically fix truncated answers

  /// Detects if an answer is likely truncated (ends with colon but no URL/contact info)
  bool _isLikelyTruncated(String answer) {
    final trimmed = answer.trim();

    // Only consider it truncated if:
    // 1. It ends with a colon
    // 2. It's relatively short (less than 50 characters)
    // 3. It doesn't contain contact information
    // 4. It doesn't look like a complete sentence
    return trimmed.endsWith(':') &&
        trimmed.length < 50 &&
        !trimmed.contains('http') &&
        !trimmed.contains('www') &&
        !trimmed.contains('@') &&
        !trimmed.contains('phone') &&
        !trimmed.contains('call') &&
        !trimmed.contains('contact') &&
        !trimmed.contains('.') && // No periods suggests incomplete sentence
        !trimmed.contains('!') && // No exclamation marks
        !trimmed.contains('?'); // No question marks
  }

  /// Finds a more complete answer by looking for similar questions with longer answers
  String? _findCompleteAnswer(
    String truncatedAnswer,
    String userMessage,
    String source,
  ) {
    if (!cachedCsvData.containsKey(source)) return null;

    final collection = cachedCsvData[source]!;
    final truncatedText = truncatedAnswer.trim();

    // Strategy 1: Look for answers that start with the same text but are longer
    // This is the most reliable strategy - only use exact text matches
    for (var item in collection) {
      final answer = item['answer']!;

      if (answer.startsWith(truncatedText) &&
          answer.length > truncatedText.length + 10) {
        print('🔧 AUTO-FIX: Found longer answer starting with truncated text');
        return answer;
      }
    }

    // Strategy 2: Look for the EXACT same question with a complete answer
    // Only use this if we find the exact same question with a longer answer
    for (var item in collection) {
      final answer = item['answer']!;
      final question = item['question']!;

      // Only match if it's the exact same question (case insensitive)
      if (question.toLowerCase().trim() == userMessage.toLowerCase().trim() &&
          answer.length > truncatedText.length + 20 &&
          !_isLikelyTruncated(answer)) {
        print('🔧 AUTO-FIX: Found exact same question with complete answer');
        return answer;
      }
    }

    // Strategy 3: Look for answers that contain key phrases from the truncated answer
    // Only use this for very specific key phrases to avoid false matches
    final keyPhrases = _extractKeyPhrases(truncatedText);
    for (var item in collection) {
      final answer = item['answer']!;

      // Be more strict - require multiple key phrases to match
      final matchingPhrases = keyPhrases
          .where(
            (phrase) => answer.toLowerCase().contains(phrase.toLowerCase()),
          )
          .length;

      if (matchingPhrases >= 2 &&
          answer.length > truncatedText.length + 30 &&
          !_isLikelyTruncated(answer)) {
        print('🔧 AUTO-FIX: Found answer with matching key phrases');
        return answer;
      }
    }

    return null;
  }

  /// Extracts key phrases from truncated text for better matching
  List<String> _extractKeyPhrases(String text) {
    final phrases = <String>[];
    final words = text.toLowerCase().split(RegExp(r'\s+'));

    // Extract 2-3 word phrases
    for (int i = 0; i < words.length - 1; i++) {
      if (words[i].length > 3 && words[i + 1].length > 3) {
        phrases.add('${words[i]} ${words[i + 1]}');
      }
    }

    // Extract 3-word phrases
    for (int i = 0; i < words.length - 2; i++) {
      if (words[i].length > 3 &&
          words[i + 1].length > 3 &&
          words[i + 2].length > 3) {
        phrases.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
      }
    }

    return phrases;
  }

  bool containsBadWord(String message) {
    final lower = message.toLowerCase();

    // Method 1: Check for exact word matches (original method)
    bool hasExactMatch = _foulWords.any(
      (word) => RegExp(
        '\\b${RegExp.escape(word)}\\b',
        caseSensitive: false,
      ).hasMatch(lower),
    );

    if (hasExactMatch) return true;

    // Method 2: Check for foul words embedded in sentences (without word boundaries)
    bool hasEmbeddedMatch = _foulWords.any(
      (word) => lower.contains(word.toLowerCase()),
    );

    if (hasEmbeddedMatch) return true;

    // Method 3: Check for common variations and misspellings
    bool hasVariationMatch = _checkFoulWordVariations(lower);

    return hasVariationMatch;
  }

  /// Check for common variations and misspellings of foul words
  bool _checkFoulWordVariations(String message) {
    // Common variations and misspellings
    final variations = {
      'fuck': [
        'f*ck',
        'f**k',
        'f***',
        'fuk',
        'fuc',
        'fck',
        'f*cking',
        'f**king'
      ],
      'shit': ['sh*t', 'sh**', 'sht', 's**t', 'sh*t', 'shitting', 'sh*tting'],
      'damn': ['d*mn', 'd**n', 'dmn', 'dam*', 'd*amn'],
      'bitch': ['b*tch', 'b**ch', 'btch', 'b*itch', 'b*tch'],
      'asshole': ['a**hole', 'a**h*le', 'ashole', 'a*shole', 'assh*le'],
      'gago': ['g*go', 'g**o', 'gag*', 'g*go'],
      'ulol': ['ul*l', 'u**l', 'ul*', 'u*ol'],
      'tangina': ['tang*na', 'tang**a', 'tang*n*', 't*ngina'],
      'putang ina': ['put*ng ina', 'put*ng *na', 'putang *na', 'p*tang ina'],
    };

    for (var entry in variations.entries) {
      final baseWord = entry.key;
      final wordVariations = entry.value;

      // Check if base word is in message
      if (message.contains(baseWord)) return true;

      // Check variations
      for (var variation in wordVariations) {
        if (message.contains(variation)) return true;
      }
    }

    return false;
  }

  String sanitizeMessage(String message) {
    String sanitized = message;

    // Remove exact word matches
    for (var word in _foulWords) {
      sanitized = sanitized.replaceAll(
        RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false),
        '',
      );
    }

    // Remove embedded matches
    for (var word in _foulWords) {
      sanitized = sanitized.replaceAll(
        RegExp(RegExp.escape(word), caseSensitive: false),
        '',
      );
    }

    // Remove variations and misspellings
    sanitized = _sanitizeFoulWordVariations(sanitized);

    return sanitized.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Remove foul word variations and misspellings
  String _sanitizeFoulWordVariations(String message) {
    String sanitized = message;

    final variations = {
      'fuck': [
        'f*ck',
        'f**k',
        'f***',
        'fuk',
        'fuc',
        'fck',
        'f*cking',
        'f**king'
      ],
      'shit': ['sh*t', 'sh**', 'sht', 's**t', 'sh*t', 'shitting', 'sh*tting'],
      'damn': ['d*mn', 'd**n', 'dmn', 'dam*', 'd*amn'],
      'bitch': ['b*tch', 'b**ch', 'btch', 'b*itch', 'b*tch'],
      'asshole': ['a**hole', 'a**h*le', 'ashole', 'a*shole', 'assh*le'],
      'gago': ['g*go', 'g**o', 'gag*', 'g*go'],
      'ulol': ['ul*l', 'u**l', 'ul*', 'u*ol'],
      'tangina': ['tang*na', 'tang**a', 'tang*n*', 't*ngina'],
      'putang ina': ['put*ng ina', 'put*ng *na', 'putang *na', 'p*tang ina'],
    };

    for (var entry in variations.entries) {
      final baseWord = entry.key;
      final wordVariations = entry.value;

      // Remove base word
      sanitized = sanitized.replaceAll(
        RegExp(RegExp.escape(baseWord), caseSensitive: false),
        '',
      );

      // Remove variations
      for (var variation in wordVariations) {
        sanitized = sanitized.replaceAll(
          RegExp(RegExp.escape(variation), caseSensitive: false),
          '',
        );
      }
    }

    return sanitized;
  }

  // ===== CSV Q&A DATA LOADING =====
  Map<String, List<Map<String, String>>> cachedCsvData = {};

  /// Loads CSV data from documents directory if available, else from assets.
  Future<void> preloadLocalCsvData(List<String> csvFiles) async {
    cachedCsvData.clear();

    // Load violation data first
    await loadViolationData();

    // Load staff database
    await loadStaffDatabase();

    print('🔄 OfflineService: Loading ${csvFiles.length} CSV files...');

    for (final file in csvFiles) {
      String? csvString;

      // Try to load from documents directory
      try {
        final dir = await getApplicationDocumentsDirectory();
        final localFile = File('${dir.path}/$file');
        if (await localFile.exists()) {
          csvString = await localFile.readAsString();
          print('📖 Loaded from documents: $file (${csvString.length} chars)');
        } else {
          print('❌ File not found in documents: ${localFile.path}');
        }
      } catch (e) {
        print('❌ Error loading from documents: $e');
      }

      // Fallback to assets if not found in documents directory
      if (csvString == null) {
        try {
          csvString = await rootBundle.loadString('assets/$file');
          print('📦 Loaded from assets: $file (${csvString.length} chars)');
        } catch (e) {
          print('❌ Error loading from assets: $e');
          continue; // Skip this file if we can't load it
        }
      }

      try {
        // Debug: Show first 500 characters of CSV content
        final preview = csvString.length > 500
            ? csvString.substring(0, 500) + "..."
            : csvString;
        print('📝 CSV content preview:\n$preview');

        // Debug: Look for the specific admissions question in raw CSV
        if (csvString.toLowerCase().contains('pagpasok') ||
            csvString.toLowerCase().contains('admissions')) {
          print('🔍 DEBUG: Found admissions question in raw CSV content');
          final lines = csvString.split('\n');
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].toLowerCase().contains('pagpasok') ||
                lines[i].toLowerCase().contains('admissions')) {
              print('   Line $i: "${lines[i]}"');
              print('   Line length: ${lines[i].length}');
              print('   Contains line breaks: ${lines[i].contains('\n')}');
              print('   Contains carriage returns: ${lines[i].contains('\r')}');
            }
          }
        }

        // Debug: Show line count by splitting manually
        final lines = csvString.split('\n');
        print('📏 Manual line count: ${lines.length} lines');
        print('📋 First 3 lines:');
        for (int i = 0; i < 3 && i < lines.length; i++) {
          print('   Line $i: "${lines[i]}"');
        }

        // Force manual parsing since CsvToListConverter is failing silently
        List<List<dynamic>> rows;

        // Always use manual parsing for better control and debugging
        print(
          '🔧 Using enhanced manual CSV parsing with multi-line support...',
        );
        rows = _parseMultiLineCSV(csvString);
        print('📊 Enhanced manual parsing result: ${rows.length} total rows');

        // Debug: Check if we have the expected number of fields per row
        if (rows.isNotEmpty) {
          final expectedFields = rows[0].length; // Header row field count
          print('📋 Expected fields per row: $expectedFields');

          int malformedRows = 0;
          for (int i = 1; i < rows.length; i++) {
            if (rows[i].length != expectedFields) {
              malformedRows++;
              if (malformedRows <= 3) {
                // Show first 3 malformed rows
                print(
                  '⚠️ Malformed row $i: expected $expectedFields fields, got ${rows[i].length}',
                );
                print('   Content: ${rows[i]}');
              }
            }
          }
          if (malformedRows > 3) {
            print('⚠️ ... and ${malformedRows - 3} more malformed rows');
          }
        }

        List<Map<String, String>> faqs = [];
        for (int i = 1; i < rows.length; i++) {
          if (rows[i].length >= 2) {
            final question = rows[i][0].toString();
            final answer = rows[i][1].toString();

            // Debug: Check for the specific question we're having issues with
            if (question.toLowerCase().contains('school of law') ||
                question.toLowerCase().contains('pagpasok') ||
                question.toLowerCase().contains('admissions')) {
              print('🔍 DEBUG: Found target question during parsing:');
              print('   Raw question: "$question"');
              print('   Raw answer: "$answer"');
              print('   Answer length: ${answer.length}');
              print('   Answer contains line breaks: ${answer.contains('\n')}');
              print(
                '   Answer contains carriage returns: ${answer.contains('\r')}',
              );
              print(
                '   Answer ends with colon: ${answer.trim().endsWith(':')}',
              );
            }

            faqs.add({"question": question, "answer": answer});
          }
        }

        // Use the filename (without extension) as the collection key
        final key = file.replaceAll('.csv', '').replaceAll('faq_', '');
        cachedCsvData[key] = faqs;
        print('✅ Cached $file as key "$key" with ${faqs.length} entries');
      } catch (e) {
        print('❌ Error parsing CSV $file: $e');
      }
    }

    print('🎯 Total cached collections: ${cachedCsvData.length}');
    for (var entry in cachedCsvData.entries) {
      print('   ${entry.key}: ${entry.value.length} entries');

      // Debug: Show first few entries to check for truncation
      if (entry.value.isNotEmpty) {
        print('   📋 Sample entries from ${entry.key}:');

        // Count truncated answers
        int truncatedCount = 0;
        for (var item in entry.value) {
          final answer = item['answer'] ?? '';
          if (_isLikelyTruncated(answer)) {
            truncatedCount++;
          }
        }

        if (truncatedCount > 0) {
          print(
            '   ⚠️ WARNING: Found $truncatedCount potentially truncated answers in ${entry.key}',
          );
        }

        // Show first few entries
        for (int i = 0; i < 3 && i < entry.value.length; i++) {
          final item = entry.value[i];
          final question = item['question'] ?? '';
          final answer = item['answer'] ?? '';
          print('     Q: "$question"');
          print('     A: "$answer"');
          if (_isLikelyTruncated(answer)) {
            print('     ⚠️ TRUNCATED: Answer appears to be cut off!');
          }
        }

        // Show specific truncated entries for debugging
        if (truncatedCount > 0) {
          print('   🔍 All truncated answers in ${entry.key}:');
          for (int i = 0; i < entry.value.length; i++) {
            final item = entry.value[i];
            final question = item['question'] ?? '';
            final answer = item['answer'] ?? '';
            if (_isLikelyTruncated(answer)) {
              print('     [$i] Q: "$question"');
              print('         A: "$answer"');
            }
          }
        }
      }
    }
  }

  /// Parse CSV content that may contain multi-line fields
  List<List<dynamic>> _parseMultiLineCSV(String csvContent) {
    final List<List<dynamic>> rows = [];
    final List<String> fields = [];
    bool inQuotes = false;
    String currentField = '';

    for (int i = 0; i < csvContent.length; i++) {
      final char = csvContent[i];

      if (char == '"') {
        if (inQuotes && i + 1 < csvContent.length && csvContent[i + 1] == '"') {
          // Double quote - add single quote to field
          currentField += '"';
          i++; // Skip next quote
        } else {
          // Toggle quote state
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator outside quotes
        fields.add(currentField.trim());
        currentField = '';
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        // Row separator outside quotes
        fields.add(currentField.trim());
        if (fields.isNotEmpty && fields.any((field) => field.isNotEmpty)) {
          rows.add(fields.toList());
        }
        fields.clear();
        currentField = '';

        // Skip \r\n combinations
        if (char == '\r' &&
            i + 1 < csvContent.length &&
            csvContent[i + 1] == '\n') {
          i++;
        }
      } else {
        // Regular character - include everything inside quotes (including line breaks)
        currentField += char;
      }
    }

    // Add final field and row if there's content
    if (currentField.isNotEmpty || fields.isNotEmpty) {
      fields.add(currentField.trim());
      if (fields.isNotEmpty && fields.any((field) => field.isNotEmpty)) {
        rows.add(fields);
      }
    }

    // Debug: Show parsing results for multi-line content
    if (csvContent.contains('\n') && csvContent.contains('"')) {
      print('🔍 MULTI-LINE CSV PARSING DEBUG:');
      print('   Total rows parsed: ${rows.length}');
      if (rows.isNotEmpty) {
        print('   Header: ${rows[0]}');
        // Show first few data rows
        for (int i = 1; i < 3 && i < rows.length; i++) {
          print('   Row $i: ${rows[i]}');
          if (rows[i].length >= 2) {
            final answer = rows[i][1].toString();
            if (answer.contains('\n')) {
              print(
                '     ⚠️ Row $i answer contains line breaks: ${answer.length} chars',
              );
            }
          }
        }
      }
    }

    // Debug: Look for specific admissions question in parsed data
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].length >= 2) {
        final question = rows[i][0].toString();
        final answer = rows[i][1].toString();
        if (question.toLowerCase().contains('pagpasok') ||
            question.toLowerCase().contains('admissions')) {
          print('🔍 FOUND ADMISSIONS QUESTION IN PARSED DATA:');
          print('   Row $i Question: "$question"');
          print('   Row $i Answer: "$answer"');
          print('   Answer length: ${answer.length}');
          print('   Answer contains line breaks: ${answer.contains('\n')}');
          print(
            '   Answer contains carriage returns: ${answer.contains('\r')}',
          );
        }
      }
    }

    return rows;
  }

  // ===== ENHANCED SIMILARITY LOGIC =====

  // Original Jaccard similarity (kept for reference and hybrid approach)
  double stringSimilarity(String a, String b) {
    final aTokens = a
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    final bTokens = b
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();

    if (aTokens.isEmpty && bTokens.isEmpty) return 0.0;

    final overlap = aTokens.intersection(bTokens).length;
    final union = aTokens.union(bTokens).length;

    return union == 0 ? 0.0 : overlap / union; // Jaccard similarity
  }

  // Levenshtein distance calculation
  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }

    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[a.length][b.length];
  }

  // Levenshtein ratio (0.0 to 1.0)
  double _levenshteinRatio(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final distance = _levenshteinDistance(a, b);
    final maxLength = a.length > b.length ? a.length : b.length;

    return 1.0 - (distance / maxLength);
  }

  // Hybrid similarity - combines Jaccard and Levenshtein with better typo handling
  double enhancedSimilarity(String a, String b) {
    // Quick Jaccard calculation first
    final jaccard = stringSimilarity(a, b);

    // Use Levenshtein even for lower Jaccard scores to catch typos
    if (jaccard < 0.1) {
      return jaccard; // Too different, skip expensive Levenshtein
    }

    final levenshtein = _levenshteinRatio(a.toLowerCase(), b.toLowerCase());

    // Weighted combination - give more weight to Levenshtein for typo detection
    return (jaccard * 0.6) + (levenshtein * 0.4);
  }

  // Keyword-based scoring for better precision with typo handling
  double _calculateKeywordScore(String userInput, String question) {
    final userWords =
        userInput.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final questionWords =
        question.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

    if (userWords.isEmpty || questionWords.isEmpty) return 0.0;

    // Count exact word matches
    final exactMatches = userWords.intersection(questionWords).length;
    final exactScore = exactMatches / userWords.length;

    // Count partial matches (substring matches)
    int partialMatches = 0;
    for (final userWord in userWords) {
      for (final questionWord in questionWords) {
        if (userWord.contains(questionWord) ||
            questionWord.contains(userWord)) {
          partialMatches++;
          break;
        }
      }
    }
    final partialScore = partialMatches / userWords.length;

    // Count typo matches using Levenshtein distance
    int typoMatches = 0;
    for (final userWord in userWords) {
      for (final questionWord in questionWords) {
        if (_isTypoMatch(userWord, questionWord)) {
          typoMatches++;
          break;
        }
      }
    }
    final typoScore = typoMatches / userWords.length;

    // Weight exact matches most heavily, then partial, then typos
    return (exactScore * 0.6) + (partialScore * 0.25) + (typoScore * 0.15);
  }

  // Check if two words are likely typos of each other
  bool _isTypoMatch(String word1, String word2) {
    if (word1.length < 3 || word2.length < 3) return false;

    // Calculate Levenshtein distance
    final distance = _levenshteinDistance(word1, word2);
    final maxLength = word1.length > word2.length ? word1.length : word2.length;

    // Consider it a typo if:
    // 1. Distance is 1-2 characters for short words (3-5 chars)
    // 2. Distance is 1-3 characters for medium words (6-8 chars)
    // 3. Distance is 1-4 characters for long words (9+ chars)
    final maxAllowedDistance = maxLength <= 5
        ? 2
        : maxLength <= 8
            ? 3
            : 4;

    return distance <= maxAllowedDistance && distance > 0;
  }

  // Check if text is admission-related
  bool _isAdmissionRelated(String text) {
    final admissionKeywords = [
      'admission',
      'admissions',
      'pagpasok',
      'pagpasa',
      'enrollment',
      'enlistment',
      'apply',
      'application',
      'applicant',
      'entrance',
      'entry',
      'admit',
      'admitted'
    ];
    return admissionKeywords.any((keyword) => text.contains(keyword));
  }

  // Check if text is schedule/time-related
  bool _isScheduleRelated(String text) {
    final scheduleKeywords = [
      'schedule',
      'kailan',
      'when',
      'time',
      'date',
      'deadline',
      'period',
      'start',
      'begin',
      'open',
      'close',
      'end',
      'semester',
      'term'
    ];
    return scheduleKeywords.any((keyword) => text.contains(keyword));
  }

  // Check if text is first year/freshman-related
  bool _isFirstYearRelated(String text) {
    final firstYearKeywords = [
      'first year',
      '1st year',
      'freshman',
      'freshmen',
      'incoming',
      'new student',
      'new students',
      'bagong estudyante',
      'bagong mag-aaral'
    ];
    return firstYearKeywords.any((keyword) => text.contains(keyword));
  }

  // Check if answer contains only links
  bool _containsOnlyLinks(String answer) {
    final linkPattern =
        RegExp(r'https?://[^\s]+|www\.[^\s]+|facebook\.com/[^\s]+');
    final links = linkPattern.allMatches(answer).toList();

    // If the answer is mostly links (more than 70% of content is links)
    final linkText = links.map((match) => match.group(0)!).join(' ');
    return linkText.length > (answer.length * 0.7);
  }

  // Check if answer contains person names
  bool _containsPersonName(String answer) {
    final personNamePatterns = [
      // Common name patterns
      RegExp(r'\b[A-Z][a-z]+ [A-Z][a-z]+\b'), // First Last
      RegExp(r'\b[A-Z][a-z]+ [A-Z]\. [A-Z][a-z]+\b'), // First M. Last
      RegExp(r'\b[A-Z][a-z]+ [A-Z][a-z]+ [A-Z][a-z]+\b'), // First Middle Last

      // Specific known names
      'Richard N. Briones',
      'RGC',
      'MAGC',
    ];

    return personNamePatterns.any((pattern) {
      if (pattern is RegExp) {
        return pattern.hasMatch(answer);
      } else {
        return answer.contains(pattern);
      }
    });
  }

  // ===== MATCHING LOGIC =====
  Future<Map<String, dynamic>?> matchAndClassify(
    String userMessage,
    String? department,
  ) async {
    if (cachedCsvData.isEmpty) return null;

    // Expand abbreviations and synonyms for better matching
    final expandedMessage = _expandSynonyms(userMessage);
    final normalizedInput = expandedMessage.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9\s]'),
          '',
        );

    print(
      '🔍 DEBUG: Original message: "$userMessage"',
    );
    print(
      '🔍 DEBUG: Expanded message: "$expandedMessage"',
    );
    print(
      '🔍 DEBUG: Normalized input: "$normalizedInput"',
    );
    print('🔍 DEBUG: Available collections: ${cachedCsvData.keys.toList()}');

    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;

    for (var entry in cachedCsvData.entries) {
      final collectionName = entry.key;
      for (var item in entry.value) {
        final question = item['question']!;
        final answer = item['answer']!;
        final qNorm = question.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9\s]'),
              '',
            );

        // Use enhanced similarity instead of basic Jaccard
        final simScore = enhancedSimilarity(normalizedInput, qNorm);
        double score = simScore;

        // Add keyword-based matching for better precision
        final keywordScore = _calculateKeywordScore(normalizedInput, qNorm);
        score =
            (score * 0.5) + (keywordScore * 0.5); // More balanced combination

        // Give extra boost for exact or very close matches
        if (normalizedInput == qNorm) {
          score = 1.0; // Perfect match
        } else if (normalizedInput.contains('admission director') &&
            qNorm.contains('admission director')) {
          score += 0.3; // Boost for admission director questions
        } else if (normalizedInput.contains('sino') ||
            normalizedInput.contains('sini') ||
            normalizedInput.contains('sina') ||
            normalizedInput.contains('sinu')) {
          if (qNorm.contains('sino') || qNorm.contains('director')) {
            score += 0.2; // Boost for "who" questions about directors
          }
        }

        // Enhanced boost for admission-related questions
        if (_isAdmissionRelated(normalizedInput) &&
            _isAdmissionRelated(qNorm)) {
          score += 0.25; // Boost for admission-related matches
        }

        // Boost for schedule/time-related questions
        if (_isScheduleRelated(normalizedInput) && _isScheduleRelated(qNorm)) {
          score += 0.2; // Boost for schedule-related matches
        }

        // Boost for first year/freshman questions
        if (_isFirstYearRelated(normalizedInput) &&
            _isFirstYearRelated(qNorm)) {
          score += 0.15; // Boost for first year-related matches
        }

        // Penalize answers that contain only links for person questions
        if (_isPersonQuestion(normalizedInput) && _containsOnlyLinks(answer)) {
          score -=
              0.4; // Heavy penalty for link-only answers to person questions
        }

        // Boost answers that contain person names for person questions
        if (_isPersonQuestion(normalizedInput) && _containsPersonName(answer)) {
          score += 0.3; // Boost for answers with actual person names
        }

        if (department != null && department.isNotEmpty) {
          bool matchesDept = collectionName.toLowerCase().contains(
                department.toLowerCase(),
              );
          if (matchesDept) {
            score += 0.1; // additive bias for department matches
          }
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = {
            'question': question,
            'answer': answer,
            'score': score,
            'source': collectionName,
          };
        }
      }
    }

    print('🔍 DEBUG: Best match score: $bestScore');
    if (bestMatch != null) {
      print('🔍 DEBUG: Best match question: "${bestMatch['question']}"');
      print('🔍 DEBUG: Best match answer: "${bestMatch['answer']}"');
    } else {
      print('🔍 DEBUG: No match found');
    }

    if (bestMatch == null) return null;

    bestMatch['confidence'] = bestScore >= 0.7
        ? 'high'
        : bestScore >= 0.5
            ? 'medium'
            : 'low';

    print('🔍 DEBUG: Final confidence: ${bestMatch['confidence']}');

    // Only return matches with reasonable confidence to avoid irrelevant responses
    // Lowered threshold from 0.4 to 0.3 to accept more relevant matches
    if (bestScore < 0.3) {
      print('🔍 DEBUG: Match score too low ($bestScore), rejecting match');
      return null;
    }

    return bestMatch;
  }

  // ===== CACHING RESPONSES =====
  Map<String, String> offlineCache = {};

  Future<void> saveOfflineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_cache', jsonEncode(offlineCache));
  }

  Future<void> loadOfflineCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheString = prefs.getString('offline_cache');
    if (cacheString != null) {
      offlineCache = Map<String, String>.from(jsonDecode(cacheString));
    }
  }

  // ===== STAFF DATABASE =====
  Map<String, Map<String, String>> _staffDatabase = {};

  /// Get staff information by role
  Map<String, String>? getStaffInfo(String role) {
    return _staffDatabase[role.toLowerCase()];
  }

  /// Add or update staff information
  Future<void> updateStaffInfo(String role, Map<String, String> info) async {
    _staffDatabase[role.toLowerCase()] = info;
    await saveStaffDatabase();
    print('✅ Updated staff information for: $role');
  }

  /// Get all staff roles
  List<String> getAllStaffRoles() {
    return _staffDatabase.keys.toList();
  }

  /// Remove staff member
  Future<void> removeStaffInfo(String role) async {
    _staffDatabase.remove(role.toLowerCase());
    await saveStaffDatabase();
    print('🗑️ Removed staff information for: $role');
  }

  /// Get staff database as JSON for external management
  Map<String, Map<String, String>> getStaffDatabase() {
    return Map.from(_staffDatabase);
  }

  /// Load staff database from external source
  Future<void> loadStaffDatabaseFromJson(
      Map<String, Map<String, String>> staffData) async {
    _staffDatabase = Map.from(staffData);
    await saveStaffDatabase();
    print(
        '📂 Loaded staff database from external source with ${_staffDatabase.length} staff members');
  }

  /// Identify staff role from subject text
  String? _identifyStaffRole(String subject) {
    final subjectLower = subject.toLowerCase();

    // Map subject patterns to staff roles
    final rolePatterns = {
      'admission_director': [
        'admission director',
        'admissions director',
        'director ng admission',
        'director ng pagpasok',
        'admission head',
        'admission chief'
      ],
      'president': [
        'president',
        'presidente',
        'university president',
        'pangulo'
      ],
      'dean': ['dean', 'dekano', 'college dean', 'school dean'],
      'registrar': ['registrar', 'registro', 'office of registrar'],
    };

    for (final entry in rolePatterns.entries) {
      final role = entry.key;
      final patterns = entry.value;

      if (patterns.any((pattern) => subjectLower.contains(pattern))) {
        return role;
      }
    }

    return null;
  }

  /// Generate dynamic staff response
  String _generateStaffResponse(String role, String? department) {
    final staffInfo = getStaffInfo(role);
    if (staffInfo == null) {
      return _generateGeneralWhoResponse(department);
    }

    final name = staffInfo['name'] ?? 'Unknown';
    final title = staffInfo['title'] ?? 'Staff Member';
    final titleFilipino = staffInfo['title_filipino'] ?? title;
    final credentials = staffInfo['credentials'] ?? '';
    final office = staffInfo['office'] ?? 'University Office';
    final officeFilipino = staffInfo['office_filipino'] ?? office;
    final university = staffInfo['university'] ?? 'Pampanga State University';

    String response = "Ang $titleFilipino ng $university ay si $name";
    if (credentials.isNotEmpty) {
      response += ", $credentials";
    }
    response +=
        ". Para sa karagdagang impormasyon, maaari mong makipag-ugnayan sa $officeFilipino. ";
    response += "(The $title of $university is $name";
    if (credentials.isNotEmpty) {
      response += ", $credentials";
    }
    response += ". For additional information, you can contact the $office.)";

    return response;
  }

  // ===== STAFF DATABASE PERSISTENCE =====
  Future<void> saveStaffDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final staffJson = jsonEncode(_staffDatabase);
    await prefs.setString('staff_database', staffJson);
    print('💾 Saved staff database');
  }

  Future<void> loadStaffDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final staffString = prefs.getString('staff_database');
    if (staffString != null) {
      final staffMap = jsonDecode(staffString) as Map<String, dynamic>;
      _staffDatabase = staffMap.map((key, value) => MapEntry(
          key, Map<String, String>.from(value as Map<String, dynamic>)));
      print(
          '📂 Loaded staff database with ${_staffDatabase.length} staff members');
    } else {
      // If no saved data, try to load from external sources
      await _loadStaffFromExternalSources();
    }
  }

  /// Load staff data from external sources (CSV, API, etc.)
  Future<void> _loadStaffFromExternalSources() async {
    print('🔍 Attempting to load staff data from external sources...');

    // Try to load from CSV file first
    await _loadStaffFromCSV();

    // If still empty, try to load from remote API
    if (_staffDatabase.isEmpty) {
      await _loadStaffFromAPI();
    }

    // If still empty, create a minimal default structure
    if (_staffDatabase.isEmpty) {
      print('⚠️ No staff data found. Please configure staff information.');
      _createDefaultStaffStructure();
    }
  }

  /// Load staff data from CSV file
  Future<void> _loadStaffFromCSV() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final staffFile = File('${dir.path}/staff_database.csv');

      if (await staffFile.exists()) {
        final csvContent = await staffFile.readAsString();
        final rows = _parseMultiLineCSV(csvContent);

        for (int i = 1; i < rows.length; i++) {
          // Skip header
          if (rows[i].length >= 8) {
            final role = rows[i][0].toString().toLowerCase();
            _staffDatabase[role] = {
              'name': rows[i][1].toString(),
              'title': rows[i][2].toString(),
              'title_filipino': rows[i][3].toString(),
              'credentials': rows[i][4].toString(),
              'office': rows[i][5].toString(),
              'office_filipino': rows[i][6].toString(),
              'university': rows[i][7].toString(),
              'university_filipino': rows[i][8].toString(),
            };
          }
        }
        print('📂 Loaded ${_staffDatabase.length} staff members from CSV');
        await saveStaffDatabase();
      }
    } catch (e) {
      print('❌ Error loading staff from CSV: $e');
    }
  }

  /// Load staff data from remote API
  Future<void> _loadStaffFromAPI() async {
    try {
      // This would be implemented to fetch from your API
      // For now, just log that it's not implemented
      print(
          '🌐 API loading not implemented yet. Please use CSV or manual configuration.');
    } catch (e) {
      print('❌ Error loading staff from API: $e');
    }
  }

  /// Create default staff structure (empty but ready for configuration)
  void _createDefaultStaffStructure() {
    print('📝 Creating default staff structure...');
    // Don't add any hard-coded data, just create the structure
    _staffDatabase = {};
    print(
        '✅ Staff database initialized. Use updateStaffInfo() to add staff members.');
  }

  /// Generate a sample CSV file for staff configuration
  Future<void> generateSampleStaffCSV() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final csvFile = File('${dir.path}/staff_database.csv');

      final csvContent =
          '''role,name,title,title_filipino,credentials,office,office_filipino,university,university_filipino
admission_director,Richard N. Briones,Director of Admissions,Direktor ng Tanggapan ng Pagpasok,"RGC, MAGC",Office of Admissions,Tanggapan ng Pagpasok,Pampanga State University,Pampanga State University
president,Dr. [President Name],University President,Pangulo ng Unibersidad,,Office of the President,Tanggapan ng Pangulo,Pampanga State University,Pampanga State University
registrar,Ms. [Registrar Name],University Registrar,Registrar ng Unibersidad,,Office of the Registrar,Tanggapan ng Registrar,Pampanga State University,Pampanga State University
dean,Dr. [Dean Name],College Dean,Dekano ng Kolehiyo,,College Dean's Office,Tanggapan ng Dekano,Pampanga State University,Pampanga State University''';

      await csvFile.writeAsString(csvContent);
      print('📄 Generated sample staff CSV file at: ${csvFile.path}');
      print(
          '💡 Edit this file to configure your staff information, then restart the app.');
    } catch (e) {
      print('❌ Error generating sample CSV: $e');
    }
  }

  // ===== FOUL LANGUAGE VIOLATION PERSISTENCE =====
  Future<void> saveViolationData() async {
    final prefs = await SharedPreferences.getInstance();

    // Save violation counts
    final violationsJson = jsonEncode(_foulLanguageViolations);
    await prefs.setString('foul_language_violations', violationsJson);

    // Save muted users with timestamps
    final mutedUsersJson = jsonEncode(_mutedUsers
        .map((key, value) => MapEntry(key, value.toIso8601String())));
    await prefs.setString('muted_users', mutedUsersJson);

    print('💾 Saved foul language violation data');
  }

  Future<void> loadViolationData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load violation counts
    final violationsString = prefs.getString('foul_language_violations');
    if (violationsString != null) {
      final violationsMap =
          jsonDecode(violationsString) as Map<String, dynamic>;
      _foulLanguageViolations =
          violationsMap.map((key, value) => MapEntry(key, value as int));
    }

    // Load muted users with timestamps
    final mutedUsersString = prefs.getString('muted_users');
    if (mutedUsersString != null) {
      final mutedUsersMap =
          jsonDecode(mutedUsersString) as Map<String, dynamic>;
      _mutedUsers = mutedUsersMap
          .map((key, value) => MapEntry(key, DateTime.parse(value as String)));
    }

    // Clean up expired mutes
    _cleanupExpiredMutes();

    print(
        '📂 Loaded foul language violation data: ${_foulLanguageViolations.length} users with violations, ${_mutedUsers.length} muted users');
  }

  /// Clean up expired mutes and reset violations for expired users
  void _cleanupExpiredMutes() {
    final now = DateTime.now();
    final expiredUsers = <String>[];

    for (var entry in _mutedUsers.entries) {
      if (now.difference(entry.value) > _muteDuration) {
        expiredUsers.add(entry.key);
      }
    }

    for (var userId in expiredUsers) {
      _mutedUsers.remove(userId);
      _foulLanguageViolations.remove(userId);
      print('🔄 Cleaned up expired mute for user: $userId');
    }
  }

  // ===== GREETING DETECTION =====
  bool _isGreeting(String message) {
    final normalizedMessage = message.toLowerCase().trim();

    // Common greeting patterns
    final greetingPatterns = [
      r'^(hi|hello|hey|greetings|good morning|good afternoon|good evening|good night)[\s!.,]*$',
      r'^(kumusta|kamusta|mabuhay|magandang umaga|magandang hapon|magandang gabi)[\s!.,]*$',
      r'^(how are you|how do you do|whats up|sup)[\s!.,]*$',
      r'^(nice to meet you|pleased to meet you)[\s!.,]*$',
      r'^(hi there|hello there|hey there)[\s!.,]*$',
    ];

    for (final pattern in greetingPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(normalizedMessage)) {
        return true;
      }
    }

    return false;
  }

  // ===== SINGLE WORD DETECTION =====
  bool _isSingleWord(String message) {
    final normalizedMessage = message.trim();

    // Split by whitespace and filter out empty strings
    final words = normalizedMessage
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    // Consider it a single word if there's only one word and it's not a greeting
    if (words.length == 1) {
      final word = words.first.toLowerCase();

      // Exclude common single-word greetings and responses
      final singleWordGreetings = [
        'hi',
        'hello',
        'hey',
        'thanks',
        'thank',
        'ok',
        'okay',
        'yes',
        'no',
        'bye',
        'goodbye'
      ];

      // Exclude if it's a greeting
      if (singleWordGreetings.contains(word)) {
        return false;
      }

      // Exclude if it's a question word but still ask for clarification
      final questionWords = [
        'what',
        'who',
        'when',
        'where',
        'why',
        'how',
        'which'
      ];
      if (questionWords.contains(word)) {
        return true; // Still ask for clarification even for question words
      }

      return true;
    }

    return false;
  }

  // ===== INTELLIGENT RESPONSE GENERATION =====

  /// Generate intelligent responses for common question patterns
  String _generateIntelligentResponse(String userMessage, String? department) {
    final normalizedMessage = userMessage.toLowerCase().trim();

    // Pattern 1: "Who is" questions about specific people/roles (HIGHEST PRIORITY)
    if (_isWhoQuestion(normalizedMessage) &&
        _isPersonQuestion(normalizedMessage)) {
      print(
          '🧠 DEBUG: Detected person question, generating person-specific response');
      return _handleWhoQuestion(normalizedMessage, department);
    }

    // Pattern 1b: General "Who is" questions
    if (_isWhoQuestion(normalizedMessage)) {
      return _handleWhoQuestion(normalizedMessage, department);
    }

    // Pattern 2: "What is" questions about definitions
    if (_isWhatQuestion(normalizedMessage)) {
      return _handleWhatQuestion(normalizedMessage, department);
    }

    // Pattern 3: "How to" or "How do I" questions
    if (_isHowToQuestion(normalizedMessage)) {
      return _handleHowToQuestion(normalizedMessage, department);
    }

    // Pattern 4: "When" questions about schedules/deadlines
    if (_isWhenQuestion(normalizedMessage)) {
      return _handleWhenQuestion(normalizedMessage, department);
    }

    // Pattern 5: "Where" questions about locations
    if (_isWhereQuestion(normalizedMessage)) {
      return _handleWhereQuestion(normalizedMessage, department);
    }

    // Pattern 6: Contact information requests
    if (_isContactQuestion(normalizedMessage)) {
      return _handleContactQuestion(normalizedMessage, department);
    }

    return ""; // No intelligent response generated
  }

  /// Check if the message is a "who" question
  bool _isWhoQuestion(String message) {
    final whoPatterns = [
      'sino',
      'sini',
      'sina',
      'sinu',
      'who',
      'who is',
      'who are',
      'kanino',
      'saan',
      'sino ang',
      'who is the',
      'who are the'
    ];
    return whoPatterns.any((pattern) => message.contains(pattern));
  }

  /// Check if the message is asking about a specific person/role
  bool _isPersonQuestion(String message) {
    final personKeywords = [
      'director',
      'president',
      'dean',
      'head',
      'chief',
      'manager',
      'supervisor',
      'leader',
      'chair',
      'coordinator',
      'officer',
      'staff',
      'person',
      'tao',
      'direktor',
      'presidente',
      'dekano',
      'ulo',
      'puno',
      'tagapamahala'
    ];
    return personKeywords
        .any((keyword) => message.toLowerCase().contains(keyword));
  }

  /// Check if the message is a "what" question
  bool _isWhatQuestion(String message) {
    final whatPatterns = [
      'ano',
      'what',
      'what is',
      'what are',
      'ano ang',
      'what is the'
    ];
    return whatPatterns.any((pattern) => message.contains(pattern));
  }

  /// Check if the message is a "how to" question
  bool _isHowToQuestion(String message) {
    final howPatterns = [
      'paano',
      'how',
      'how to',
      'how do',
      'how can',
      'paano mag',
      'paano gumawa'
    ];
    return howPatterns.any((pattern) => message.contains(pattern));
  }

  /// Check if the message is a "when" question
  bool _isWhenQuestion(String message) {
    final whenPatterns = [
      'kailan',
      'when',
      'kailan ang',
      'when is',
      'when are',
      'what time'
    ];
    return whenPatterns.any((pattern) => message.contains(pattern));
  }

  /// Check if the message is a "where" question
  bool _isWhereQuestion(String message) {
    final wherePatterns = [
      'saan',
      'where',
      'saan ang',
      'where is',
      'where are',
      'location'
    ];
    return wherePatterns.any((pattern) => message.contains(pattern));
  }

  /// Check if the message is asking for contact information
  bool _isContactQuestion(String message) {
    final contactPatterns = [
      'contact',
      'phone',
      'email',
      'address',
      'number',
      'tawag',
      'tumawag',
      'makipag-ugnayan',
      'kausapin',
      'tawagan'
    ];
    return contactPatterns.any((pattern) => message.contains(pattern));
  }

  /// Handle "who" questions with dynamic responses
  String _handleWhoQuestion(String message, String? department) {
    // Extract the subject/topic from the question
    final subject = _extractSubjectFromQuestion(message);

    print('🧠 DEBUG: Extracted subject from question: "$subject"');

    // Generate dynamic response based on the subject
    if (subject.isNotEmpty) {
      final response = _generateDynamicWhoResponse(subject, department);
      print('🧠 DEBUG: Generated dynamic response for subject: "$subject"');
      return response;
    }

    // Fallback for general "who" questions
    print('🧠 DEBUG: Using general who response');
    return _generateGeneralWhoResponse(department);
  }

  /// Extract the main subject/topic from a question
  String _extractSubjectFromQuestion(String message) {
    // Remove question words and common words
    final cleanedMessage = message
        .replaceAll(
            RegExp(r'\b(sino|sini|sina|sinu|who|who is|who are|kanino|saan)\b',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\b(ang|the|is|are|ng|of|sa|in|at|for)\b',
                caseSensitive: false),
            '')
        .trim();

    // Check for specific phrases first
    if (cleanedMessage.contains('admission director') ||
        cleanedMessage.contains('admissions director')) {
      return 'admission director';
    }

    if (cleanedMessage.contains('director ng admission') ||
        cleanedMessage.contains('director ng pagpasok')) {
      return 'admission director';
    }

    // Return the first meaningful word or phrase
    final words = cleanedMessage
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toList();
    return words.isNotEmpty ? words.first : '';
  }

  /// Generate dynamic response for "who" questions
  String _generateDynamicWhoResponse(String subject, String? department) {
    // Check for specific staff roles in the database
    final staffRole = _identifyStaffRole(subject);
    if (staffRole != null) {
      return _generateStaffResponse(staffRole, department);
    }

    // Map common subjects to their appropriate offices/contacts
    final subjectOfficeMap = {
      'admission': 'Office of Admissions',
      'admissions': 'Office of Admissions',
      'pagpasok': 'Office of Admissions',
      'director': 'Office of Admissions',
      'president': 'Office of the President',
      'presidente': 'Office of the President',
      'dean': 'College Dean\'s Office',
      'dekano': 'College Dean\'s Office',
      'registrar': 'Office of the Registrar',
      'finance': 'Finance Office',
      'accounting': 'Finance Office',
      'student': 'Student Affairs Office',
      'scholarship': 'Scholarship Office',
      'library': 'Library Office',
      'research': 'Research Office',
      'extension': 'Extension Office',
    };

    final office =
        subjectOfficeMap[subject.toLowerCase()] ?? 'appropriate office';

    return "Para sa impormasyon tungkol sa $subject sa Pampanga State University, maaari mong makipag-ugnayan sa $office. Para sa tiyak na mga detalye at contact information, bisitahin ang opisyal na website ng unibersidad o tumawag sa main office. (For information about $subject at Pampanga State University, you can contact the $office. For specific details and contact information, visit the university's official website or call the main office.)";
  }

  /// Generate general response for "who" questions
  String _generateGeneralWhoResponse(String? department) {
    return "Para sa impormasyon tungkol sa mga tao at staff sa Pampanga State University, maaari mong makipag-ugnayan sa kaukulang tanggapan o bisitahin ang opisyal na website ng unibersidad. Para sa tiyak na contact information, tumawag sa main office. (For information about people and staff at Pampanga State University, you can contact the appropriate office or visit the university's official website. For specific contact information, call the main office.)";
  }

  /// Handle "what" questions with dynamic responses
  String _handleWhatQuestion(String message, String? department) {
    final subject = _extractSubjectFromQuestion(message);

    if (subject.isNotEmpty) {
      return _generateDynamicWhatResponse(subject, department);
    }

    return _generateGeneralWhatResponse(department);
  }

  /// Generate dynamic response for "what" questions
  String _generateDynamicWhatResponse(String subject, String? department) {
    // Map subjects to their relevant information sources
    final subjectInfoMap = {
      'university': 'university information',
      'psu': 'university information',
      'program': 'academic programs',
      'programs': 'academic programs',
      'course': 'academic programs',
      'courses': 'academic programs',
      'kurso': 'academic programs',
      'requirement': 'admission requirements',
      'requirements': 'admission requirements',
      'pangangailangan': 'admission requirements',
      'tuition': 'tuition and fees',
      'fee': 'tuition and fees',
      'fees': 'tuition and fees',
      'scholarship': 'scholarship programs',
      'scholarships': 'scholarship programs',
      'admission': 'admission process',
      'enrollment': 'enrollment process',
    };

    final infoType = subjectInfoMap[subject.toLowerCase()] ?? 'information';

    return "Para sa impormasyon tungkol sa $subject sa Pampanga State University, maaari mong bisitahin ang opisyal na website ng unibersidad o makipag-ugnayan sa kaukulang tanggapan. Para sa tiyak na mga detalye tungkol sa $infoType, tumawag sa main office o bisitahin ang campus. (For information about $subject at Pampanga State University, you can visit the university's official website or contact the appropriate office. For specific details about $infoType, call the main office or visit the campus.)";
  }

  /// Generate general response for "what" questions
  String _generateGeneralWhatResponse(String? department) {
    return "Para sa impormasyon tungkol sa Pampanga State University, maaari mong bisitahin ang opisyal na website ng unibersidad, makipag-ugnayan sa information desk, o tumawag sa main office. Para sa tiyak na mga detalye, bisitahin ang campus o ang website. (For information about Pampanga State University, you can visit the university's official website, contact the information desk, or call the main office. For specific details, visit the campus or the website.)";
  }

  /// Handle "how to" questions with dynamic responses
  String _handleHowToQuestion(String message, String? department) {
    final subject = _extractSubjectFromQuestion(message);

    if (subject.isNotEmpty) {
      return _generateDynamicHowToResponse(subject, department);
    }

    return _generateGeneralHowToResponse(department);
  }

  /// Generate dynamic response for "how to" questions
  String _generateDynamicHowToResponse(String subject, String? department) {
    // Map subjects to their process steps
    final processMap = {
      'enroll': 'enrollment process',
      'enrollment': 'enrollment process',
      'admission': 'admission process',
      'apply': 'application process',
      'application': 'application process',
      'register': 'registration process',
      'registration': 'registration process',
      'graduate': 'graduation process',
      'graduation': 'graduation process',
      'transfer': 'transfer process',
      'withdraw': 'withdrawal process',
      'scholarship': 'scholarship application process',
    };

    final processType = processMap[subject.toLowerCase()] ?? 'process';

    return "Para sa $processType sa Pampanga State University, maaari mong: 1) Bisitahin ang kaukulang tanggapan, 2) Kumpletuhin ang mga kinakailangang dokumento, 3) Sumunod sa mga hakbang na ibinigay. Para sa detalyadong gabay, makipag-ugnayan sa kaukulang tanggapan o bisitahin ang website ng unibersidad. (For the $processType at Pampanga State University, you can: 1) Visit the appropriate office, 2) Complete the required documents, 3) Follow the provided steps. For detailed guidance, contact the appropriate office or visit the university website.)";
  }

  /// Generate general response for "how to" questions
  String _generateGeneralHowToResponse(String? department) {
    return "Para sa detalyadong gabay sa mga proseso sa Pampanga State University, maaari mong makipag-ugnayan sa kaukulang tanggapan, bisitahin ang website ng unibersidad, o tumawag sa main office. Para sa tiyak na mga hakbang, bisitahin ang campus o ang information desk. (For detailed guidance on processes at Pampanga State University, you can contact the appropriate office, visit the university website, or call the main office. For specific steps, visit the campus or the information desk.)";
  }

  /// Handle "when" questions with dynamic responses
  String _handleWhenQuestion(String message, String? department) {
    final subject = _extractSubjectFromQuestion(message);

    if (subject.isNotEmpty) {
      return _generateDynamicWhenResponse(subject, department);
    }

    return _generateGeneralWhenResponse(department);
  }

  /// Generate dynamic response for "when" questions
  String _generateDynamicWhenResponse(String subject, String? department) {
    // Map subjects to their timing information
    final timingMap = {
      'enrollment': 'enrollment period',
      'enroll': 'enrollment period',
      'class': 'class schedule',
      'classes': 'class schedule',
      'klase': 'class schedule',
      'exam': 'examination schedule',
      'examination': 'examination schedule',
      'graduation': 'graduation ceremony',
      'semester': 'semester schedule',
      'break': 'academic break',
      'holiday': 'holiday schedule',
      'deadline': 'application deadline',
      'application': 'application deadline',
    };

    final timingType = timingMap[subject.toLowerCase()] ?? 'schedule';

    return "Para sa tiyak na mga petsa at oras ng $timingType sa Pampanga State University, maaari mong bisitahin ang academic calendar ng unibersidad, makipag-ugnayan sa kaukulang tanggapan, o tumawag sa main office. Para sa updated na mga petsa, bisitahin ang website ng unibersidad. (For specific dates and times of $timingType at Pampanga State University, you can visit the university's academic calendar, contact the appropriate office, or call the main office. For updated dates, visit the university website.)";
  }

  /// Generate general response for "when" questions
  String _generateGeneralWhenResponse(String? department) {
    return "Para sa tiyak na mga petsa at oras sa Pampanga State University, maaari mong bisitahin ang academic calendar ng unibersidad, makipag-ugnayan sa kaukulang tanggapan, o tumawag sa main office. Para sa updated na mga petsa, bisitahin ang website ng unibersidad. (For specific dates and times at Pampanga State University, you can visit the university's academic calendar, contact the appropriate office, or call the main office. For updated dates, visit the university website.)";
  }

  /// Handle "where" questions with dynamic responses
  String _handleWhereQuestion(String message, String? department) {
    final subject = _extractSubjectFromQuestion(message);

    if (subject.isNotEmpty) {
      return _generateDynamicWhereResponse(subject, department);
    }

    return _generateGeneralWhereResponse(department);
  }

  /// Generate dynamic response for "where" questions
  String _generateDynamicWhereResponse(String subject, String? department) {
    return "Para sa tiyak na lokasyon ng $subject sa Pampanga State University, maaari mong bisitahin ang campus map, makipag-ugnayan sa information desk, o tumawag sa main office. Para sa detalyadong direksyon, bisitahin ang website ng unibersidad. (For specific location of $subject at Pampanga State University, you can visit the campus map, contact the information desk, or call the main office. For detailed directions, visit the university website.)";
  }

  /// Generate general response for "where" questions
  String _generateGeneralWhereResponse(String? department) {
    return "Para sa tiyak na lokasyon sa Pampanga State University, maaari mong bisitahin ang campus map, makipag-ugnayan sa information desk, o tumawag sa main office. Para sa detalyadong direksyon at address, bisitahin ang website ng unibersidad. (For specific location at Pampanga State University, you can visit the campus map, contact the information desk, or call the main office. For detailed directions and address, visit the university website.)";
  }

  /// Handle contact information questions with dynamic responses
  String _handleContactQuestion(String message, String? department) {
    final subject = _extractSubjectFromQuestion(message);

    if (subject.isNotEmpty) {
      return _generateDynamicContactResponse(subject, department);
    }

    return _generateGeneralContactResponse(department);
  }

  /// Generate dynamic response for contact questions
  String _generateDynamicContactResponse(String subject, String? department) {
    return "Para sa contact information ng $subject sa Pampanga State University, maaari mong: 1) Bisitahin ang opisyal na website ng unibersidad, 2) Makipag-ugnayan sa information desk, 3) Tawagan ang main office ng unibersidad. Para sa tiyak na mga numero at email address, bisitahin ang website o ang campus. (For contact information of $subject at Pampanga State University, you can: 1) Visit the university's official website, 2) Contact the information desk, 3) Call the university's main office. For specific numbers and email addresses, visit the website or the campus.)";
  }

  /// Generate general response for contact questions
  String _generateGeneralContactResponse(String? department) {
    return "Para sa contact information ng Pampanga State University, maaari mong: 1) Bisitahin ang opisyal na website ng unibersidad, 2) Makipag-ugnayan sa information desk, 3) Tawagan ang main office ng unibersidad. Para sa tiyak na mga numero at email address, bisitahin ang website. (For contact information of Pampanga State University, you can: 1) Visit the university's official website, 2) Contact the information desk, 3) Call the university's main office. For specific numbers and email addresses, visit the website.)";
  }

  /// Check if an intelligent response is actually useful (not just generic)
  bool _isUsefulIntelligentResponse(String response) {
    // Generic responses that should be avoided in favor of CSV data
    final genericPatterns = [
      'Para sa impormasyon tungkol sa mga tao at staff sa Pampanga State University',
      'Para sa impormasyon tungkol sa',
      'Para sa tiyak na mga petsa at oras',
      'Para sa tiyak na lokasyon',
      'Para sa contact information',
      'I couldn\'t find specific information',
      'I couldn\'t find detailed instructions',
      'I couldn\'t find current schedule information',
    ];

    // If response contains any generic patterns, it's not useful
    for (final pattern in genericPatterns) {
      if (response.contains(pattern)) {
        return false;
      }
    }

    // If response contains specific person names or detailed information, it's useful
    final usefulPatterns = [
      'Richard N. Briones',
      'Dr. ',
      'Mr. ',
      'Ms. ',
      'Professor',
      'Director',
      'President',
      'Dean',
      'Registrar',
    ];

    for (final pattern in usefulPatterns) {
      if (response.contains(pattern)) {
        return true;
      }
    }

    // If response is short and generic, it's not useful
    if (response.length < 100) {
      return false;
    }

    return true;
  }

  // ===== MAIN OFFLINE RESPONSE LOGIC =====
  Future<String> fetchOfflineResponse(
    String userMessage,
    String? department,
  ) async {
    final userId = _getUserId();

    // Check if user is muted first
    if (_isUserMuted(userId)) {
      final muteTime = _mutedUsers[userId]!;
      final remainingTime = _muteDuration - DateTime.now().difference(muteTime);
      final hours = remainingTime.inHours;
      final minutes = remainingTime.inMinutes % 60;

      return "You have been temporarily muted due to repeated use of inappropriate language. You can try again in ${hours}h ${minutes}m. Please maintain respectful communication.";
    }

    // Check for foul language and handle violations
    if (containsBadWord(userMessage)) {
      _recordFoulLanguageViolation(userId);
      final violations = _getViolationCount(userId);
      final remaining = _getRemainingViolations(userId);

      if (violations >= _maxViolations) {
        return "You have been muted for 24 hours due to repeated use of inappropriate language. Please maintain respectful communication.";
      } else {
        return "Please avoid using foul language. I can't respond to offensive messages. Warning: ${remaining} more violation${remaining == 1 ? '' : 's'} before temporary mute.";
      }
    }

    // Check if the message is a greeting first
    if (_isGreeting(userMessage)) {
      print('🔍 DEBUG: Detected greeting: "$userMessage"');
      return "You are offline to chat. Please go online for a better experience.";
    }

    // Check if the message is a single word and ask for clarification
    if (_isSingleWord(userMessage)) {
      print('🔍 DEBUG: Detected single word: "$userMessage"');
      return "I need more information to help you better. Could you please expand your question and provide more details?";
    }

    // Expand abbreviations for better matching
    final expandedMessage = _expandSynonyms(userMessage);
    final normalizedKey = userMessage.toLowerCase().trim();
    final expandedKey = expandedMessage.toLowerCase().trim();

    // Check cache for both original and expanded versions
    // But skip cache for person questions to ensure we get the correct person information
    if (!_isPersonQuestion(userMessage)) {
      if (offlineCache.containsKey(normalizedKey)) {
        print('🔍 DEBUG: Using cached response for original: "$userMessage"');
        return offlineCache[normalizedKey]!;
      }
      if (offlineCache.containsKey(expandedKey)) {
        print(
            '🔍 DEBUG: Using cached response for expanded: "$expandedMessage"');
        return offlineCache[expandedKey]!;
      }
    } else {
      print(
          '🔍 DEBUG: Skipping cache for person question to ensure accurate response');
    }

    print(
      '🔍 DEBUG: Searching for: "$userMessage" in ${cachedCsvData.length} collections',
    );
    for (var entry in cachedCsvData.entries) {
      print(
        '🔍 DEBUG: Collection "${entry.key}" has ${entry.value.length} entries',
      );
    }

    // PRIORITY 1: Try intelligent response generation first
    final intelligentResponse =
        _generateIntelligentResponse(userMessage, department);
    if (intelligentResponse.isNotEmpty &&
        _isUsefulIntelligentResponse(intelligentResponse)) {
      print(
          '🧠 DEBUG: Generated useful intelligent response for: "$userMessage"');
      // Cache the intelligent response for future use
      offlineCache[normalizedKey] = intelligentResponse;
      if (expandedKey != normalizedKey) {
        offlineCache[expandedKey] = intelligentResponse;
      }
      await saveOfflineCache();
      return intelligentResponse;
    }

    // PRIORITY 2: Only if no intelligent response, try CSV matching
    print('🔍 DEBUG: Trying CSV matching for: "$userMessage"');
    final match = await matchAndClassify(userMessage, department);
    if (match == null) {
      print('🔍 DEBUG: No CSV match found for: "$userMessage"');

      // Fallback to generic responses if no intelligent response was generated
      final lowerMessage = userMessage.toLowerCase();
      if (lowerMessage.contains('sino') || lowerMessage.contains('who')) {
        return "I couldn't find specific information about that person in my offline knowledge base. For current contact information and staff details, please go online or contact the university directly.";
      } else if (lowerMessage.contains('paano') ||
          lowerMessage.contains('how')) {
        return "I couldn't find detailed instructions for that process in my offline knowledge base. For step-by-step guidance, please go online for more comprehensive information.";
      } else if (lowerMessage.contains('kailan') ||
          lowerMessage.contains('when')) {
        return "I couldn't find current schedule information in my offline knowledge base. For up-to-date dates and deadlines, please go online or check the university website.";
      } else {
        return "I couldn't find this information in my offline knowledge base. For additional information, please go online to get more comprehensive responses.";
      }
    }

    final bestAnswer = match['answer'];
    print(
        '🔍 DEBUG: Found CSV match: "${match['question']}" -> "${bestAnswer}"');

    // AUTOMATED FIX: Detect and fix truncated responses intelligently
    String fixedAnswer = bestAnswer;

    if (_autoFixEnabled && _isLikelyTruncated(bestAnswer)) {
      print('🔧 AUTO-FIX: Detected likely truncated response: "${bestAnswer}"');

      final source = match['source'] ?? '';
      final completeAnswer = _findCompleteAnswer(
        bestAnswer,
        userMessage,
        source,
      );

      if (completeAnswer != null) {
        fixedAnswer = completeAnswer;
        print('🔧 AUTO-FIX: Applied automated fix');
        print('🔧 Original: "${bestAnswer}"');
        print('🔧 Fixed: "${fixedAnswer}"');
      } else {
        print('🔧 AUTO-FIX: No better answer found, keeping original');
      }
    } else if (_isLikelyTruncated(bestAnswer)) {
      print(
        '🔧 AUTO-FIX: Truncated response detected but auto-fix is disabled',
      );
      print(
        '⚠️ WARNING: Answer appears to be truncated in source data: "${bestAnswer}"',
      );
      print(
        '💡 TIP: Use printTruncatedAnswersReport() to see all truncated answers',
      );
    }

    // Cache both original and expanded versions for future queries
    offlineCache[normalizedKey] = fixedAnswer;
    if (expandedKey != normalizedKey) {
      offlineCache[expandedKey] = fixedAnswer;
    }
    await saveOfflineCache();
    return fixedAnswer;
  }

  /// Utility: get all questions (for suggestions)
  Future<List<String>> loadQuestions() async {
    final questions = <String>[];
    for (var entry in cachedCsvData.entries) {
      for (var item in entry.value) {
        if (item['question'] != null && item['question']!.isNotEmpty) {
          questions.add(item['question']!);
        }
      }
    }
    return questions;
  }

  /// Enable or disable the auto-fix feature for truncated responses
  void setAutoFixEnabled(bool enabled) {
    _autoFixEnabled = enabled;
    print('🔧 AUTO-FIX: ${enabled ? "Enabled" : "Disabled"} auto-fix feature');
  }

  /// Get the current auto-fix setting
  bool get autoFixEnabled => _autoFixEnabled;

  /// Get a report of all truncated answers in the cached data
  Map<String, List<Map<String, String>>> getTruncatedAnswersReport() {
    final report = <String, List<Map<String, String>>>{};

    for (var entry in cachedCsvData.entries) {
      final truncatedAnswers = <Map<String, String>>[];

      for (var item in entry.value) {
        final question = item['question'] ?? '';
        final answer = item['answer'] ?? '';

        if (_isLikelyTruncated(answer)) {
          truncatedAnswers.add({
            'question': question,
            'answer': answer,
            'index': entry.value.indexOf(item).toString(),
          });
        }
      }

      if (truncatedAnswers.isNotEmpty) {
        report[entry.key] = truncatedAnswers;
      }
    }

    return report;
  }

  /// Print a detailed report of all truncated answers
  void printTruncatedAnswersReport() {
    final report = getTruncatedAnswersReport();

    if (report.isEmpty) {
      print('✅ No truncated answers found in cached data');
      return;
    }

    print('⚠️ TRUNCATED ANSWERS REPORT:');
    print('=' * 50);

    for (var entry in report.entries) {
      print('📁 Collection: ${entry.key}');
      print('   Found ${entry.value.length} truncated answers:');

      for (var item in entry.value) {
        print('   [${item['index']}] Q: "${item['question']}"');
        print('       A: "${item['answer']}"');
        print('       ⚠️ This answer appears to be cut off!');
        print('');
      }
    }

    print('💡 SOLUTION: The data in your source (Firestore/CSV) is truncated.');
    print('   You need to fix the source data to include complete answers.');
    print(
      '   The auto-fix feature is disabled to prevent incorrect substitutions.',
    );
  }

  /// Clear all cached data and force reload
  Future<void> clearCacheAndReload() async {
    print('🔄 Clearing all cached CSV data...');
    cachedCsvData.clear();
    offlineCache.clear();

    // Clear SharedPreferences cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_cache');

    // Also clear any local CSV files that might contain corrupted data
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir.list().toList();

      for (var file in files) {
        if (file.path.endsWith('.csv') && file.path.contains('dataset')) {
          print('🗑️ Deleting potentially corrupted CSV file: ${file.path}');
          await file.delete();
        }
      }
    } catch (e) {
      print('❌ Error clearing CSV files: $e');
    }

    print('✅ All cached data and CSV files cleared');
  }

  /// Force reload data with detailed debugging
  Future<void> forceReloadWithDebug() async {
    print('🔄 FORCE RELOAD WITH DEBUG - Clearing all data...');
    await clearCacheAndReload();
    print('🔍 Now reload your data to see detailed debugging output');
  }

  /// Test the parsing fix by clearing cache and showing what gets loaded
  Future<void> testParsingFix() async {
    print('🧪 TESTING PARSING FIX');
    print('=' * 50);

    // Clear all cached data
    await clearCacheAndReload();

    print('✅ Cache cleared. Now when you reload your data, you should see:');
    print('   - Enhanced CSV parsing debug output');
    print('   - Detailed field parsing for problematic entries');
    print('   - Complete answers instead of truncated ones');
    print('');
    print('💡 Look for these debug messages:');
    print('   - "🔍 CSV PARSING DEBUG:" - Shows how each line is parsed');
    print('   - "📊 Enhanced manual parsing result" - Shows total rows parsed');
    print('   - "📋 Expected fields per row" - Shows field count validation');
    print('');
    print('🎯 The fix should resolve answers ending with colons like:');
    print('   - "Yes, if they have:" → Complete requirements');
    print('   - "Learners from Grade 11 to 12 who have:" → Complete criteria');
    print('   - "Grade 12 learners who:" → Complete criteria');
  }

  /// Diagnose the root cause of truncated data
  Future<void> diagnoseTruncationIssue() async {
    print('🔍 DIAGNOSING TRUNCATION ISSUE');
    print('=' * 50);

    final report = getTruncatedAnswersReport();

    if (report.isEmpty) {
      print('✅ No truncated answers found - issue may be resolved!');
      return;
    }

    print('⚠️ Found truncated answers in the following collections:');
    for (var entry in report.entries) {
      print('📁 ${entry.key}: ${entry.value.length} truncated answers');
    }

    print('');
    print('🔍 ROOT CAUSE ANALYSIS:');
    print('1. Data in Firestore contains LINE BREAKS (pressed Enter)');
    print('2. CSV parsing was treating line breaks as row separators');
    print('3. This caused multi-line answers to be split into multiple rows');
    print('4. The app only read the first part of the answer');
    print('');
    print('💡 SOLUTION:');
    print('1. Fixed CSV parsing to handle multi-line fields properly');
    print('2. Line breaks within quoted fields are now preserved');
    print('3. Complete answers with line breaks will now be read correctly');
    print('');
    print('🛠️ IMMEDIATE FIX:');
    print('   - Use forceCompleteDataRefresh() to re-sync from Firestore');
    print('   - The new parser will handle line breaks correctly');
    print('   - Complete answers will now be displayed properly');
  }

  /// Force a complete data refresh from Firestore
  Future<void> forceCompleteDataRefresh() async {
    print('🔄 FORCING COMPLETE DATA REFRESH');
    print('=' * 50);

    // Clear all cached data and local CSV files
    await clearCacheAndReload();

    print('✅ Cache and local files cleared');
    print('🔄 Now re-sync data from Firestore...');

    // Force a fresh sync from Firestore
    try {
      final syncResult = await syncDataset(collection: "CsvData");

      if (syncResult.isNotEmpty) {
        print('✅ Successfully synced fresh data from Firestore');
        print('📁 New file: ${syncResult["fileName"]}');
        print('📊 Entries: ${syncResult["entryCount"]}');

        // Load the fresh data
        final fileName = syncResult["fileName"];
        if (fileName != null) {
          await preloadLocalCsvData([fileName]);
        }

        print('🎯 Fresh data loaded successfully!');
        print('💡 The app should now show complete answers');
      } else {
        print('❌ Failed to sync fresh data from Firestore');
      }
    } catch (e) {
      print('❌ Error during data refresh: $e');
    }
  }

  /// Test the line break parsing with detailed debugging
  Future<void> testLineBreakParsing() async {
    print('🧪 TESTING LINE BREAK PARSING');
    print('=' * 50);

    // Clear cache and force fresh data
    await forceCompleteDataRefresh();

    print('');
    print('🔍 Now test the app with the admissions question:');
    print('   "Paano ako makikipag-ugnayan sa Tanggapan ng Pagpasok?"');
    print('');
    print('💡 Look for these debug messages:');
    print('   - "🔍 FIRESTORE LOADING DEBUG - Admissions question"');
    print('   - "🔍 CSV GENERATION DEBUG - Admissions question"');
    print('   - "🔍 DEBUG: Found admissions question in raw CSV content"');
    print('   - "🔍 FOUND ADMISSIONS QUESTION IN PARSED DATA"');
    print('   - "🔍 DEBUG: Found target question during parsing"');
    print('');
    print('🎯 The answer should now be complete with all contact information');
  }

  /// Apply auto-fix to all existing cached data immediately
  Future<void> applyAutoFixToCachedData() async {
    print('🔧 APPLYING AUTO-FIX TO CACHED DATA');
    print('=' * 50);

    if (cachedCsvData.isEmpty) {
      print('❌ No cached data found. Load data first.');
      return;
    }

    int totalFixed = 0;
    int totalTruncated = 0;

    for (var entry in cachedCsvData.entries) {
      final collectionName = entry.key;
      final collection = entry.value;

      print('🔍 Processing collection: $collectionName');

      for (int i = 0; i < collection.length; i++) {
        final item = collection[i];
        final question = item['question'] ?? '';
        final answer = item['answer'] ?? '';

        if (_isLikelyTruncated(answer)) {
          totalTruncated++;
          print('⚠️ Found truncated answer: "$answer"');

          // Try to find a complete answer
          final completeAnswer = _findCompleteAnswer(
            answer,
            question,
            collectionName,
          );

          if (completeAnswer != null) {
            // Update the cached data with the complete answer
            collection[i]['answer'] = completeAnswer;
            totalFixed++;
            print('✅ Fixed: "$answer" → "$completeAnswer"');
          } else {
            print('❌ Could not find complete answer for: "$answer"');
          }
        }
      }
    }

    print('');
    print('📊 AUTO-FIX RESULTS:');
    print('   Total truncated answers found: $totalTruncated');
    print('   Successfully fixed: $totalFixed');
    print('   Failed to fix: ${totalTruncated - totalFixed}');

    if (totalFixed > 0) {
      print('✅ Auto-fix applied successfully!');
      print(
        '💡 The app will now return complete answers instead of truncated ones.',
      );
    } else {
      print(
        '⚠️ No fixes were applied. Check if auto-fix logic needs adjustment.',
      );
    }
  }

  /// Comprehensive test of the entire data pipeline
  Future<void> testCompleteDataPipeline() async {
    print('🧪 TESTING COMPLETE DATA PIPELINE');
    print('=' * 60);

    print('📋 This test will trace data through the entire pipeline:');
    print('   1. Firestore → CSV Generation');
    print('   2. CSV File → Parsing');
    print('   3. Parsed Data → App Response');
    print('');

    // Force a complete refresh to trigger all debugging
    await forceCompleteDataRefresh();

    print('');
    print('✅ Data pipeline test completed!');
    print('🔍 Check the debug output above to see where truncation occurs');
    print('');
    print('💡 If the issue persists, the debug output will show:');
    print('   - Whether Firestore data is complete');
    print('   - Whether CSV generation preserves line breaks');
    print('   - Whether CSV parsing handles multi-line fields');
    print('   - Whether the final answer is complete');
  }

  /// Test abbreviation expansion functionality
  void testAbbreviationExpansion() {
    print('🧪 TESTING ABBREVIATION EXPANSION');
    print('=' * 50);

    final testCases = [
      'PSU requirements',
      'CEA programs',
      'BSA curriculum',
      'enroll in BSCS',
      'dean lister requirements',
      'ID card application',
      'scholarship application',
    ];

    for (final testCase in testCases) {
      final expanded = _expandSynonyms(testCase);
      print('Original: "$testCase"');
      print('Expanded: "$expanded"');
      print('---');
    }

    print('✅ Abbreviation expansion test completed!');
    print(
        '💡 The expanded messages should now match better with questions in the knowledge base.');
  }

  /// Test foul language muting system
  void testFoulLanguageMuting() {
    print('🧪 TESTING FOUL LANGUAGE MUTING SYSTEM');
    print('=' * 50);

    final testUserId = 'test_user';

    // Reset test user
    resetUserViolations(testUserId);

    print('Testing violation tracking...');
    for (int i = 1; i <= 4; i++) {
      _recordFoulLanguageViolation(testUserId);
      final violations = _getViolationCount(testUserId);
      final remaining = _getRemainingViolations(testUserId);
      final isMuted = _isUserMuted(testUserId);

      print(
          'Violation $i: $violations total, $remaining remaining, muted: $isMuted');
    }

    print('✅ Foul language muting test completed!');
    print('💡 User should be muted after 3 violations for 24 hours.');

    // Clean up test data
    resetUserViolations(testUserId);
  }

  /// Test improved foul language detection
  void testImprovedFoulLanguageDetection() {
    print('🧪 TESTING IMPROVED FOUL LANGUAGE DETECTION');
    print('=' * 60);

    final testCases = [
      // Original word boundary tests
      'fuck you',
      'this is shit',
      'damn it',

      // Embedded in sentences
      'what the fuck is this',
      'this is fucking stupid',
      'that shit is broken',
      'damn this thing',
      'you are a bitch',
      'what an asshole',

      // With punctuation
      'fuck!',
      'shit.',
      'damn,',
      'bitch?',

      // Variations and misspellings
      'f*ck you',
      'f**k this',
      'sh*t happens',
      'd*mn it',
      'b*tch please',
      'a**hole',
      'g*go',
      'ul*l',
      'tang*na',
      'put*ng ina',

      // Mixed case
      'FUCK YOU',
      'ShIt happens',
      'DAMN IT',

      // In longer sentences
      'I think this is fucking ridiculous and stupid',
      'What the hell is this shit doing here',
      'Damn, this is really annoying',
      'You are such a bitch sometimes',
      'That guy is a complete asshole',

      // Clean messages (should not be detected)
      'hello world',
      'how are you',
      'what is the weather',
      'can you help me',
      'thank you very much',
    ];

    print('Testing foul language detection...\n');

    int detectedCount = 0;
    int totalCount = testCases.length;

    for (final testCase in testCases) {
      final isDetected = containsBadWord(testCase);
      final sanitized = sanitizeMessage(testCase);

      print('Message: "$testCase"');
      print('Detected: $isDetected');
      if (isDetected) {
        print('Sanitized: "$sanitized"');
        detectedCount++;
      }
      print('---');
    }

    print('📊 DETECTION RESULTS:');
    print('   Total test cases: $totalCount');
    print('   Detected as foul: $detectedCount');
    print(
        '   Detection rate: ${(detectedCount / totalCount * 100).toStringAsFixed(1)}%');

    print('✅ Improved foul language detection test completed!');
    print(
        '💡 The system should now detect foul language even when embedded in sentences.');
  }

  /// Get violation statistics for all users
  Map<String, dynamic> getViolationStatistics() {
    return {
      'totalUsersWithViolations': _foulLanguageViolations.length,
      'totalMutedUsers': _mutedUsers.length,
      'violations': Map.from(_foulLanguageViolations),
      'mutedUsers': _mutedUsers.map((key, value) => MapEntry(key, {
            'mutedAt': value.toIso8601String(),
            'remainingTime': _muteDuration - DateTime.now().difference(value),
          })),
    };
  }

  /// Clear all violation data (for admin purposes)
  Future<void> clearAllViolationData() async {
    _foulLanguageViolations.clear();
    _mutedUsers.clear();
    await saveViolationData();
    print('🗑️ All foul language violation data cleared');
  }

  /// Clear cache for person questions to ensure fresh responses
  Future<void> clearPersonQuestionCache() async {
    print('🧹 CLEARING CACHE FOR PERSON QUESTIONS');
    print('=' * 50);

    final personQuestionKeys = <String>[];

    // Find all cached keys that are person questions
    for (final key in offlineCache.keys) {
      if (_isPersonQuestion(key)) {
        personQuestionKeys.add(key);
      }
    }

    // Remove person question entries from cache
    for (final key in personQuestionKeys) {
      offlineCache.remove(key);
      print('🗑️ Removed cached response for: "$key"');
    }

    // Save the updated cache
    await saveOfflineCache();

    print(
        '✅ Cleared ${personQuestionKeys.length} person question entries from cache');
    print('💡 Person questions will now generate fresh intelligent responses');
  }
}
