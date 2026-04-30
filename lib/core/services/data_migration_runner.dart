import 'package:flutter/foundation.dart';
import 'data_migration_service.dart';

/// Runner to check and execute data migrations on app startup
class DataMigrationRunner {
  static bool _hasCheckedMigration = false;
  
  /// Check if migration is needed and run it if necessary
  /// This should be called once during app initialization
  static Future<void> checkAndRunMigrations() async {
    // Prevent multiple checks in the same session
    if (_hasCheckedMigration) return;
    _hasCheckedMigration = true;
    
    try {
      if (kDebugMode) {
        debugPrint('[DataMigrationRunner] Checking if migration is needed...');
      }
      
      final isNeeded = await DataMigrationService.isMigrationNeeded();
      
      if (isNeeded) {
        debugPrint('[DataMigrationRunner] Migration is needed, running...');
        await DataMigrationService.runAllMigrations();
        debugPrint('[DataMigrationRunner] Migration completed successfully!');
      } else {
        debugPrint('[DataMigrationRunner] No migration needed');
      }
    } catch (e) {
      debugPrint('[DataMigrationRunner] Migration failed: $e');
      // Don't rethrow - migration failure shouldn't crash the app
      // The app will continue to work with the existing invalid data
      // but with validation in place to prevent new invalid data
    }
  }
  
  /// Force run migration regardless of check
  /// Useful for debugging or manual fixes
  static Future<void> forceRunMigration() async {
    debugPrint('[DataMigrationRunner] Force running migration...');
    await DataMigrationService.runAllMigrations();
    debugPrint('[DataMigrationRunner] Force migration completed!');
  }
}
