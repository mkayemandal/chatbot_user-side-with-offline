import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ask_psu/user/dataset_sync.dart';
import 'package:ask_psu/user/offline_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Manages dataset synchronization and offline data initialization
class DatasetManager {
  static final DatasetManager instance = DatasetManager._internal();
  DatasetManager._internal();

  bool _isInitialized = false;

  /// Initialize datasets - sync from Firestore if online, load local if offline
  Future<void> initializeDatasets() async {
    if (_isInitialized) return;

    try {
      // Add a small delay to let Firebase fully initialize
      await Future.delayed(const Duration(milliseconds: 500));

      final isOnline = await _checkConnectivity();

      if (isOnline) {
        print('🌐 Online: Syncing datasets from Firestore...');
        await _syncAndLoadDatasets();
      } else {
        print('📱 Offline: Loading local datasets...');
        await _loadLocalDatasets();
      }

      _isInitialized = true;
      print('✅ Dataset initialization complete');
    } catch (e) {
      print('❌ Dataset initialization failed: $e');
      // Try to load any existing local data as fallback
      await _loadLocalDatasets();
    }
  }

  /// Check if device has internet connectivity
  Future<bool> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.first != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  /// Sync datasets from Firestore and load them into OfflineService
  Future<void> _syncAndLoadDatasets() async {
    try {
      // Sync main dataset from Firestore
      final syncResult = await syncDataset(collection: "CsvData");

      if (syncResult.isNotEmpty) {
        print(
          '📥 Synced dataset: ${syncResult["fileName"]} (${syncResult["entryCount"]} entries)',
        );

        // Load the synced data into OfflineService
        await _loadLocalDatasets();

        // Clean up old files
        await cleanupOldDatasets(collection: "CsvData", keepRecent: 3);
      } else {
        print('⚠️ No data synced, loading existing local datasets');
        await _loadLocalDatasets();
      }
    } catch (e) {
      print('❌ Sync failed: $e, falling back to local data');
      await _loadLocalDatasets();
    }
  }

  /// Load local CSV datasets into OfflineService
  Future<void> _loadLocalDatasets() async {
    print('🔄 DatasetManager: Starting _loadLocalDatasets()');
    try {
      // Get all available local dataset files
      print('🔍 Getting local dataset files...');
      final localFiles = await _getLocalDatasetFiles();
      print('📋 Local files result: $localFiles');

      if (localFiles.isNotEmpty) {
        print('📂 Found ${localFiles.length} local dataset files: $localFiles');

        // Load them into OfflineService
        print('📤 Calling OfflineService.preloadLocalCsvData()...');
        await OfflineService.instance.preloadLocalCsvData(localFiles);

        // Also load the offline cache
        print('📥 Loading offline cache...');
        await OfflineService.instance.loadOfflineCache();

        print('✅ Local datasets loaded successfully');
      } else {
        print('⚠️ No local datasets found, using fallback data');
        await _loadFallbackData();
      }
    } catch (e) {
      print('❌ Failed to load local datasets: $e');
      await _loadFallbackData();
    }
  }

  /// Get list of local dataset CSV files
  Future<List<String>> _getLocalDatasetFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir.list().toList();

      final csvFiles = files
          .where(
            (file) =>
                file.path.endsWith('.csv') && file.path.contains('dataset'),
          )
          .map((file) => file.uri.pathSegments.last)
          .toList();

      print('📂 Found dataset files: $csvFiles');
      return csvFiles;
    } catch (e) {
      print('❌ Error getting local files: $e');
      return [];
    }
  }
  
  // Future<List<String>> _getLocalDatasetFiles() async {
  //   try {
  //     // 🧠 Skip local file handling on web
  //     if (kIsWeb) {
  //       print('🌐 Running on web — skipping local dataset file check.');
  //       return [];
  //     }

  //     // Also skip if running on a platform that doesn’t support file storage
  //     if (!(Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS)) {
  //       print('⚙️ Platform not supported for local file access.');
  //       return [];
  //     }

  //     final dir = await getApplicationDocumentsDirectory();
  //     final files = await dir.list().toList();

  //     final csvFiles = files
  //         .where((file) =>
  //             file.path.endsWith('.csv') && file.path.contains('dataset'))
  //         .map((file) => file.uri.pathSegments.last)
  //         .toList();

  //     print('📂 Found dataset files: $csvFiles');
  //     return csvFiles;
  //   } catch (e) {
  //     print('❌ Error getting local files: $e');
  //     return [];
  //   }
  // }

  /// Load basic fallback data if no datasets are available
  Future<void> _loadFallbackData() async {
    try {
      // Try to load from assets as last resort
      await OfflineService.instance.preloadLocalCsvData(['faq_general.csv']);
      print('📦 Loaded fallback data from assets');
    } catch (e) {
      print('❌ No fallback data available: $e');
    }
  }

  /// Force refresh datasets (useful for manual sync)
  Future<void> refreshDatasets() async {
    _isInitialized = false;
    await initializeDatasets();
  }

  /// Clear all cached data and force reload (fixes parsing issues)
  Future<void> clearCacheAndReload() async {
    print('🔄 DatasetManager: Clearing cache and forcing reload...');

    // Clear OfflineService cache
    await OfflineService.instance.clearCacheAndReload();

    // Reset initialization state
    _isInitialized = false;

    // Reinitialize datasets
    await initializeDatasets();

    print('✅ DatasetManager: Cache cleared and datasets reloaded');
  }

  /// Check if datasets are initialized
  bool get isInitialized => _isInitialized;

  /// Get dataset statistics
  Future<Map<String, dynamic>> getDatasetInfo() async {
    return await getDatasetStats(collection: "CsvData");
  }

  /// Force a complete data refresh from Firestore (fixes truncated data issues)
  Future<void> forceCompleteDataRefresh() async {
    print('🔄 DatasetManager: Forcing complete data refresh...');

    // Use the OfflineService method
    await OfflineService.instance.forceCompleteDataRefresh();

    print('✅ DatasetManager: Complete data refresh finished');
  }
}
