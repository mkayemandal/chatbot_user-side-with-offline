import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ask_psu/user/firestore_error_handler.dart';

class Log {
  static void i(String message) {
    print('ℹ️ INFO: $message');
  }

  static void w(String message) {
    print('⚠️ WARN: $message');
  }

  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    print('❌ ERROR: $message');
    if (error != null) {
      print('   Error: $error');
    }
    if (stackTrace != null) {
      print('   StackTrace: $stackTrace');
    }
  }

  static void d(String message) {
    print('🐛 DEBUG: $message');
  }
}

/// Model class for FAQ entries
class FAQEntry {
  final String question;
  final String answer;
  final String language;

  FAQEntry({
    required this.question,
    required this.answer,
    required this.language,
  });

  factory FAQEntry.fromFirestore(Map<String, dynamic> data) {
    final question = data['question']?.toString() ?? '';
    final answer = data['answer']?.toString() ?? '';
    final language = data['language']?.toString() ?? '';

    // Log warning for invalid entries but don't throw to avoid breaking entire sync
    if (question.isEmpty || answer.isEmpty) {
      Log.w('Invalid FAQ entry: question or answer is empty');
    }

    return FAQEntry(question: question, answer: answer, language: language);
  }

  // Add equality for better testing and comparison
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FAQEntry &&
          runtimeType == other.runtimeType &&
          question == other.question &&
          answer == other.answer &&
          language == other.language;

  @override
  int get hashCode => Object.hash(question, answer, language);

  @override
  String toString() => 'FAQEntry(question: $question, language: $language)';

  Map<String, dynamic> toJson() => {
        "question": question,
        "answer": answer,
        "language": language,
      };

  /// CSV-safe row (escapes quotes/commas and preserves line breaks)
  String toCsvRow() {
    String escape(String val) {
      // Replace quotes with double quotes for CSV escaping
      final escaped = val.replaceAll('"', '""');
      // Wrap in quotes to preserve line breaks and special characters
      return '"$escaped"';
    }

    return "${escape(question)},${escape(answer)},${escape(language)}";
  }
}

/// Sync dataset from Firestore into local CSV file
/// Returns map with file path and metadata or empty map on failure
Future<Map<String, String>> syncDataset({String collection = "CsvData"}) async {
  if (collection.trim().isEmpty) {
    Log.e("Collection name cannot be empty");
    return {};
  }

  try {
    final firestore = FirebaseFirestore.instance;
    Log.i("Fetching data from Firestore collection: '$collection'");

    // Add timeout and retry logic for Firestore operations
    final snapshot = await firestore
        .collection(collection)
        .get()
        .timeout(const Duration(seconds: 30))
        .catchError((error) {
      Log.e("Firestore timeout or error: $error");
      throw error;
    });

    if (snapshot.docs.isEmpty) {
      Log.w("No documents found in Firestore collection '$collection'");
      return {};
    }

    Log.i("Retrieved ${snapshot.docs.length} documents from Firestore");

    // Debug: Print the structure of the first document
    if (snapshot.docs.isNotEmpty) {
      final firstDoc = snapshot.docs.first;
      Log.d("First document structure: ${firstDoc.data()}");
    }

    // Process and filter entries
    final entries = <FAQEntry>[];
    for (var doc in snapshot.docs) {
      final data = doc.data();

      // Check if this document has a 'data' field (like CsvData collection)
      if (data.containsKey('data') && data['data'] is List) {
        Log.d("Found nested data structure in document ${doc.id}");
        final List<dynamic> nestedData = data['data'];

        for (var item in nestedData) {
          if (item is Map<String, dynamic>) {
            try {
              final entry = FAQEntry.fromFirestore(item);
              if (entry.question.isNotEmpty && entry.answer.isNotEmpty) {
                // Debug: Check for admissions question during Firestore loading
                if (entry.question.toLowerCase().contains('pagpasok') ||
                    entry.question.toLowerCase().contains('admissions')) {
                  Log.d("🔍 FIRESTORE LOADING DEBUG - Admissions question:");
                  Log.d("   Question: ${entry.question}");
                  Log.d("   Answer: ${entry.answer}");
                  Log.d("   Answer length: ${entry.answer.length}");
                  Log.d(
                    "   Answer contains line breaks: ${entry.answer.contains('\n')}",
                  );
                }
                entries.add(entry);
              }
            } catch (e) {
              Log.w("Error parsing nested entry: $e");
            }
          }
        }
      } else {
        // Direct document structure
        try {
          final entry = FAQEntry.fromFirestore(data);
          if (entry.question.isNotEmpty && entry.answer.isNotEmpty) {
            entries.add(entry);
          }
        } catch (e) {
          Log.w("Error parsing document ${doc.id}: $e");
        }
      }
    }

    if (entries.isEmpty) {
      Log.w(
        "No valid FAQ entries found after filtering empty questions/answers",
      );
      return {};
    }

    Log.i("Processing ${entries.length} valid FAQ entries");

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = "${collection}_dataset_$timestamp.csv";

    // --- Save CSV ---
    final csvBuffer = StringBuffer()..writeln("question,answer,language");
    for (final entry in entries) {
      final csvRow = entry.toCsvRow();

      // Debug: Check for admissions question during CSV generation
      if (entry.question.toLowerCase().contains('pagpasok') ||
          entry.question.toLowerCase().contains('admissions')) {
        Log.d("🔍 CSV GENERATION DEBUG - Admissions question:");
        Log.d("   Question: ${entry.question}");
        Log.d("   Answer: ${entry.answer}");
        Log.d("   Answer length: ${entry.answer.length}");
        Log.d("   Answer contains line breaks: ${entry.answer.contains('\n')}");
        Log.d("   CSV Row: $csvRow");
        Log.d("   CSV Row length: ${csvRow.length}");
      }

      csvBuffer.writeln(csvRow);
    }

    final csvFile = File("${dir.path}/$filename");
    await csvFile.writeAsString(csvBuffer.toString());

    // Verify file was written successfully
    final fileStats = await csvFile.stat();
    Log.i(
      "CSV dataset saved successfully at ${csvFile.path} "
      "(${fileStats.size} bytes, ${entries.length} entries)",
    );

    return {
      "filePath": csvFile.path,
      "fileName": filename,
      "entryCount": entries.length.toString(),
      "timestamp": timestamp.toString(),
      "fileSize": fileStats.size.toString(),
    };
  } on FirebaseException catch (e, stack) {
    FirestoreErrorHandler.handleError(e, 'syncDataset - FirebaseException');
    Log.e(
      "Firestore error syncing dataset from collection '$collection'",
      error: e,
      stackTrace: stack,
    );
  } on IOException catch (e, stack) {
    Log.e(
      "I/O error saving CSV file for collection '$collection'",
      error: e,
      stackTrace: stack,
    );
  } catch (e, stack) {
    FirestoreErrorHandler.handleError(e, 'syncDataset - Unexpected error');
    Log.e(
      "Unexpected error syncing dataset from collection '$collection'",
      error: e,
      stackTrace: stack,
    );
  }

  return {};
}

/// Check if local dataset files exist for a collection
Future<bool> localDatasetExists({String collection = "CsvData"}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final files = await dir.list().toList();

    final datasetFiles = files.where((file) {
      final filename = file.uri.pathSegments.last;
      return filename.startsWith("${collection}_dataset_") &&
          filename.endsWith('.csv');
    }).toList();

    return datasetFiles.isNotEmpty;
  } catch (e) {
    Log.e(
      "Error checking local dataset existence for collection '$collection'",
      error: e,
    );
    return false;
  }
}

/// Get the most recent local dataset file path for a collection
Future<String?> getLatestLocalDatasetPath({
  String collection = "CsvData",
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final files = await dir.list().toList();

    final datasetFiles = files.where((file) {
      final filename = file.uri.pathSegments.last;
      return filename.startsWith("${collection}_dataset_") &&
          filename.endsWith('.csv');
    }).toList();

    if (datasetFiles.isEmpty) {
      return null;
    }

    // Sort by modification time to get the most recent
    datasetFiles.sort((a, b) {
      final statA = a.statSync();
      final statB = b.statSync();
      return statB.modified.compareTo(statA.modified);
    });

    return datasetFiles.first.path;
  } catch (e) {
    Log.e(
      "Error getting latest local dataset path for collection '$collection'",
      error: e,
    );
    return null;
  }
}

/// Get all local dataset file paths for a collection with metadata
Future<List<Map<String, String>>> getAllLocalDatasets({
  String collection = "CsvData",
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final files = await dir.list().toList();

    final datasetFiles = files.where((file) {
      final filename = file.uri.pathSegments.last;
      return filename.startsWith("${collection}_dataset_") &&
          filename.endsWith('.csv');
    }).toList();

    final datasets = <Map<String, String>>[];

    for (final file in datasetFiles) {
      final stat = file.statSync();
      datasets.add({
        "filePath": file.path,
        "fileName": file.uri.pathSegments.last,
        "fileSize": stat.size.toString(),
        "modified": stat.modified.toIso8601String(),
      });
    }

    // Sort by modification time (newest first)
    datasets.sort((a, b) => b["modified"]!.compareTo(a["modified"]!));

    return datasets;
  } catch (e) {
    Log.e(
      "Error getting all local datasets for collection '$collection'",
      error: e,
    );
    return [];
  }
}

/// Delete old dataset files, keeping only the most recent N files
Future<bool> cleanupOldDatasets({
  String collection = "CsvData",
  int keepRecent = 3,
}) async {
  try {
    final datasets = await getAllLocalDatasets(collection: collection);

    if (datasets.length <= keepRecent) {
      Log.i(
        "No cleanup needed for collection '$collection'. Found ${datasets.length} files, keeping $keepRecent",
      );
      return true;
    }

    final filesToDelete = datasets.sublist(keepRecent);

    for (final dataset in filesToDelete) {
      final file = File(dataset["filePath"]!);
      if (await file.exists()) {
        await file.delete();
        Log.i("Deleted old dataset file: ${dataset["fileName"]}");
      }
    }

    Log.i(
      "Cleanup completed for collection '$collection'. "
      "Deleted ${filesToDelete.length} old files, kept $keepRecent recent files",
    );
    return true;
  } catch (e) {
    Log.e(
      "Error cleaning up old datasets for collection '$collection'",
      error: e,
    );
    return false;
  }
}

/// Get dataset statistics
Future<Map<String, dynamic>> getDatasetStats({
  String collection = "CsvData",
}) async {
  try {
    final datasets = await getAllLocalDatasets(collection: collection);
    final latestPath = await getLatestLocalDatasetPath(collection: collection);

    int totalEntries = 0;
    Set<String> categories = {};

    if (latestPath != null) {
      final file = File(latestPath);
      final content = await file.readAsLines();

      // Skip header and count entries
      totalEntries = content.length - 1;

      // Extract languages from CSV (skip header)
      for (int i = 1; i < content.length && i < 100; i++) {
        // Sample first 100 entries for languages
        final parts = _parseCsvLine(content[i]);
        if (parts.length >= 3) {
          categories.add(parts[2]); // language is 3rd column
        }
      }
    }

    return {
      "totalFiles": datasets.length,
      "latestFile": latestPath,
      "totalEntries": totalEntries,
      "languages": categories.toList(),
      "collection": collection,
    };
  } catch (e) {
    Log.e("Error getting dataset stats for collection '$collection'", error: e);
    return {};
  }
}

/// Helper function to parse CSV line (handles quoted fields properly)
List<String> _parseCsvLine(String line) {
  final List<String> fields = [];
  bool inQuotes = false;
  String currentField = '';

  for (int i = 0; i < line.length; i++) {
    final char = line[i];

    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
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
    } else {
      // Regular character
      currentField += char;
    }
  }

  // Add final field
  fields.add(currentField.trim());

  return fields;
}
