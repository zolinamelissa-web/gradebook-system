import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../core/providers/theme_provider.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user_model.dart' as user_model;
import '../../data/models/grading_system_config.dart';
import '../auth/setup_pin_screen.dart';
import 'sync_modal.dart';
import 'clear_data_dialog.dart';
import 'grade_equivalency_config_screen.dart';
import 'table_selection_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({super.key, this.onSettingsChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthRepository _authRepo = AuthRepository();
  String _teacherName = '';
  String _schoolName = '';
  String _gradeThreshold = '75';
  String _attendanceThreshold = '80';
  user_model.User? _currentUser;
  bool _isLoading = true;
  GradingSystemConfig _gradingSystem = GradingSystemConfig.percentage100;
  bool _hasPasswordProvider = false;
  bool _hasGoogleProvider = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) {
      await _loadWebData();
      return;
    }

    final db = DatabaseHelper.instance;
    final teacher = await db.getSetting('teacher_name');
    final school = await db.getSetting('school_name');
    final grade = await db.getSetting('grade_threshold');
    final att = await db.getSetting('attendance_threshold');
    final gradingSystemJson = await db.getSetting('grading_system');
    final user = await _authRepo.getActiveUser();

    GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
    if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
      try {
        gradingSystem = GradingSystemConfig.fromJson(
          jsonDecode(gradingSystemJson) as Map<String, dynamic>,
        );
      } catch (e) {
        print('[SettingsScreen] Error parsing grading system: $e');
      }
    }

    print(
      '[SettingsScreen] Loaded: teacher=$teacher school=$school gradeThreshold=$grade attThreshold=$att gradingSystem=${gradingSystem.displayName} user=${user?.email}',
    );
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final providers =
        firebaseUser?.providerData
            .map((p) => p.providerId)
            .where((p) => p.trim().isNotEmpty)
            .toSet()
            .toList() ??
        <String>[];
    print('[SettingsScreen] Auth providers loaded providers=$providers');
    if (mounted) {
      setState(() {
        _teacherName = teacher ?? '';
        _schoolName = school ?? '';
        _gradeThreshold = grade ?? '75';
        _attendanceThreshold = att ?? '80';
        _gradingSystem = gradingSystem;
        _currentUser = user;
        _hasPasswordProvider = providers.contains('password');
        _hasGoogleProvider = providers.contains('google.com');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWebData() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      print('[SettingsScreen] Web data load skipped: no Firebase user');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final uid = firebaseUser.uid;
    print(
      '[SettingsScreen] Loading web settings data for uid=$uid email=${firebaseUser.email}',
    );

    try {
      final teacherDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userFuture = _authRepo.getActiveUser();

      final teacherDoc = await teacherDocFuture;
      final user = await userFuture;

      final teacherData = teacherDoc.data();
      final teacher = teacherData?['teacher_name'] as String?;
      final school = teacherData?['school_name'] as String?;
      final grade = teacherData?['grade_threshold'] as String?;
      final att = teacherData?['attendance_threshold'] as String?;
      final gradingSystemJson = teacherData?['grading_system'] as String?;

      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
        try {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gradingSystemJson) as Map<String, dynamic>,
          );
        } catch (e) {
          print('[SettingsScreen] Error parsing grading system: $e');
        }
      }

      final providers = firebaseUser.providerData
          .map((p) => p.providerId)
          .where((p) => p.trim().isNotEmpty)
          .toSet()
          .toList();

      print(
        '[SettingsScreen] Web data loaded: teacher=$teacher school=$school gradeThreshold=$grade attThreshold=$att gradingSystem=${gradingSystem.displayName} user=${user?.email}',
      );

      if (mounted) {
        setState(() {
          _teacherName = teacher ?? '';
          _schoolName = school ?? '';
          _gradeThreshold = grade ?? '75';
          _attendanceThreshold = att ?? '80';
          _gradingSystem = gradingSystem;
          _currentUser = user;
          _hasPasswordProvider = providers.contains('password');
          _hasGoogleProvider = providers.contains('google.com');
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[SettingsScreen] Error loading web data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _sha256Hash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Future<void> _saveWebThresholds(
    String gradeThreshold,
    String attendanceThreshold,
  ) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      print('[SettingsScreen] Cannot save web thresholds: no Firebase user');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .update({
            'grade_threshold': gradeThreshold,
            'attendance_threshold': attendanceThreshold,
          });
      print('[SettingsScreen] Web thresholds saved successfully');
    } catch (e) {
      print('[SettingsScreen] Error saving web thresholds: $e');
    }
  }

  Future<void> _saveWebGradingSystem(GradingSystemConfig gradingSystem) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      print(
        '[SettingsScreen] Cannot save web grading system: no Firebase user',
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .update({'grading_system': jsonEncode(gradingSystem.toJson())});
      print('[SettingsScreen] Web grading system saved successfully');
    } catch (e) {
      print('[SettingsScreen] Error saving web grading system: $e');
    }
  }

  Future<void> _editProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SetupPinScreen(isOnboarding: false),
      ),
    );
    _load();
    widget.onSettingsChanged?.call();
  }

  Future<void> _editThresholds() async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => _ThresholdsDialog(
        gradeThreshold: _gradeThreshold,
        attendanceThreshold: _attendanceThreshold,
      ),
    );

    if (result != null && mounted) {
      if (kIsWeb) {
        await _saveWebThresholds(result['grade']!, result['attendance']!);
      } else {
        await DatabaseHelper.instance.setSetting(
          'grade_threshold',
          result['grade']!,
        );
        await DatabaseHelper.instance.setSetting(
          'attendance_threshold',
          result['attendance']!,
        );
      }
      print(
        '[SettingsScreen] Updated thresholds grade=${result['grade']} att=${result['attendance']}',
      );
      if (mounted) {
        setState(() {
          _gradeThreshold = result['grade']!;
          _attendanceThreshold = result['attendance']!;
        });
      }
    }
  }

  Future<void> _configureGradingSystem() async {
    GradingSystemConfig selected = _gradingSystem;

    final result = await showDialog<GradingSystemConfig?>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Grading System'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the grading system used in your institution:',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ...GradingSystemConfig.presets.map((config) {
                final isSelected = selected.type == config.type;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.divider,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.05)
                        : Colors.transparent,
                  ),
                  child: RadioListTile<GradingSystemConfig>(
                    value: config,
                    groupValue: selected,
                    onChanged: (val) {
                      Navigator.pop(context, val);
                    },
                    title: Text(
                      config.displayName,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      _getGradingSystemDescription(config),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    dense: true,
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (kIsWeb) {
        await _saveWebGradingSystem(result);
      } else {
        await DatabaseHelper.instance.setSetting(
          'grading_system',
          jsonEncode(result.toJson()),
        );
      }
      print('[SettingsScreen] Updated grading system to ${result.displayName}');
      if (mounted) {
        setState(() {
          _gradingSystem = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grading system updated to ${result.displayName}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  String _getGradingSystemDescription(GradingSystemConfig config) {
    switch (config.type) {
      case GradingSystemType.depedPercentage:
        return 'Raw score 60-100%, transmuted to 75-100% (DepEd K-12)';
      case GradingSystemType.college1to5:
        return '1.00 (highest) to 5.00 (failing), 3.00 passing';
      case GradingSystemType.college4point0:
        return '4.0 (highest) to 0.0 (failing), 1.0 passing';
      case GradingSystemType.percentage100:
        return '0-100%, zero-based, 60% passing';
      case GradingSystemType.custom:
        return 'Custom configuration';
    }
  }

  Future<void> _changePin() async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => _ChangePinDialog(),
    );

    if (result != null && mounted) {
      final storedHash = kIsWeb
          ? await _authRepo.getWebPinHash(isStudent: false)
          : await DatabaseHelper.instance.getSetting('pin_hash');
      final inputHash = _sha256Hash(result['current']!);
      if (storedHash != null &&
          storedHash.isNotEmpty &&
          storedHash != inputHash) {
        print('[SettingsScreen] Change PIN failed: incorrect current PIN');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Current PIN is incorrect.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      } else {
        if (kIsWeb) {
          await _authRepo.saveWebPinProfile(
            isStudent: false,
            name: _teacherName,
            schoolName: _schoolName,
            pinHash: _sha256Hash(result['new']!),
          );
        } else {
          await DatabaseHelper.instance.setSetting(
            'pin_hash',
            _sha256Hash(result['new']!),
          );
        }
        print('[SettingsScreen] PIN changed successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN changed successfully.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    }
  }

  Future<void> _manageAccountPassword() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not logged in.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final email = firebaseUser.email?.trim() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email found for this account.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    try {
      if (_hasPasswordProvider) {
        final result = await showDialog<Map<String, String>?>(
          context: context,
          builder: (_) => _ChangeAccountPasswordDialog(),
        );

        if (result == null || !mounted) return;

        final credential = firebase_auth.EmailAuthProvider.credential(
          email: email,
          password: result['current']!,
        );
        await firebaseUser.reauthenticateWithCredential(credential);
        await firebaseUser.updatePassword(result['new']!);
        print(
          '[SettingsScreen] Account password changed uid=${firebaseUser.uid} email=$email',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully.'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else if (_hasGoogleProvider) {
        final result = await showDialog<Map<String, String>?>(
          context: context,
          builder: (_) => _CreateAccountPasswordDialog(email: email),
        );

        if (result == null || !mounted) return;

        await _authRepo.linkEmailPasswordToCurrentUser(
          email: email,
          password: result['new']!,
        );
        print(
          '[SettingsScreen] Email/password linked to Google account uid=${firebaseUser.uid} email=$email',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password created successfully. You can now sign in using email and password.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password management is not available for this account.',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[SettingsScreen] Manage account password FirebaseAuthException code=${e.code} message=${e.message}',
      );
      String message = 'Failed to update account password.';
      if (e.code == 'wrong-password') {
        message = 'Current password is incorrect.';
      } else if (e.code == 'weak-password') {
        message = 'Password should be at least 6 characters.';
      } else if (e.code == 'requires-recent-login') {
        message =
            'Please sign in again with Google, then retry creating your email password.';
      } else if (e.code == 'provider-already-linked') {
        message = 'Email/password is already linked to this account.';
      } else if (e.code == 'email-already-in-use' ||
          e.code == 'credential-already-in-use') {
        message =
            'This email/password is already linked to another account. Sign in with the correct method first.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
      );
    } catch (e) {
      print('[SettingsScreen] Manage account password error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update account password: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _showThemeColorPicker() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentScheme = themeProvider.getCurrentSchemeName();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Choose Theme Color'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: ThemeProvider.colorSchemes.entries.map((entry) {
              final isSelected = entry.key == currentScheme;
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        entry.value['primary']!,
                        entry.value['secondary']!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                ),
                title: Text(
                  entry.key,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: isSelected
                    ? Icon(PlatformIcons.checkCircle, color: Colors.green)
                    : null,
                onTap: () async {
                  await themeProvider.setColorScheme(entry.key);
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? You will need to sign in again with Google or Email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.signOutAndGoToLogin(context);
    }
  }

  Future<void> _syncNow() async {
    final confirm = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                PlatformIcons.cloudSync,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Sync Data'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will sync all your data with Firebase cloud storage.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'The sync process will:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(PlatformIcons.upload, size: 16, color: AppTheme.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upload local changes to cloud',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Icon(PlatformIcons.download, size: 16, color: AppTheme.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Download cloud updates to device',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Do you want to continue?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0891B2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                  ),
                  child: const Text('Upload', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                  ),
                  child: const Text('Download', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == null) {
      print('[SettingsScreen] Sync cancelled by user');
      return;
    }

    print(
      '[SettingsScreen] Opening table selection dialog with direction: $confirm',
    );

    // Show table selection dialog
    final selectedTables = await showDialog<List<String>>(
      context: context,
      builder: (context) => TableSelectionDialog(syncDirection: confirm),
    );

    if (selectedTables == null || selectedTables.isEmpty) {
      print('[SettingsScreen] Table selection cancelled or no tables selected');
      return;
    }

    print(
      '[SettingsScreen] Opening sync modal with ${selectedTables.length} selected tables',
    );

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          SyncModal(syncDirection: confirm, selectedTables: selectedTables),
    );

    print('[SettingsScreen] Sync modal closed, success: $success');

    if (success == true && mounted) {
      _load();
      widget.onSettingsChanged?.call();
      print('[SettingsScreen] Notified parent to refresh after sync');
    }
  }

  Future<void> _clearData() async {
    print('[SettingsScreen] Opening clear data dialog...');

    final cleared = await showDialog<bool>(
      context: context,
      builder: (context) => const ClearDataDialog(),
    );

    print('[SettingsScreen] Clear data dialog closed, cleared: $cleared');

    // Optionally reload after clearing
    if (cleared == true && mounted) {
      _load();
    }
  }

  Future<void> _backupDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final dbFile = File('$dbPath/gradebook.db');
      if (!await dbFile.exists()) {
        print('[SettingsScreen] Backup: database file not found at $dbPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database file not found.')),
          );
        }
        return;
      }
      final appDir = await getApplicationDocumentsDirectory();
      final backupPath =
          '${appDir.path}/gradebook_backup_${DateTime.now().millisecondsSinceEpoch}.db';
      await dbFile.copy(backupPath);
      print('[SettingsScreen] Database backed up to $backupPath');
      await Share.shareXFiles([
        XFile(backupPath),
      ], text: 'GradeBook Database Backup');
    } catch (e) {
      print('[SettingsScreen] Backup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _migrateStudentEmails() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Migrate Student Emails'),
        content: const Text(
          'This will copy existing student emails from student accounts to '
          'the synced students collection. Internet connection is required. '
          'Run this once for students who already signed up before the fix.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Run Migration'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting student email migration...')),
    );

    try {
      final result = await _authRepo.migrateStudentEmails();
      if (!mounted) return;

      print('[SettingsScreen] Student email migration result: $result');

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Migration Complete'),
          content: Text(
            'Updated: ${result['updated']}\n'
            'Skipped: ${result['skipped']}\n'
            'Errors: ${result['errors']}\n\n'
            '${result['message']}',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('[SettingsScreen] Student email migration error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Migration failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Fixed Header with Wave
                WaveHeader(
                  title: 'Settings',
                  subtitle: 'App configuration & preferences',
                  gradientColors: gradientColors,
                  actions: [
                    IconButton(
                      tooltip: 'Logout',
                      icon: Icon(PlatformIcons.logout, color: Colors.white),
                      onPressed: () => AuthService.signOutAndGoToLogin(context),
                    ),
                  ],
                ),
                // Scrollable Settings Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SettingsSection(
                          title: 'PROFILE',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.person,
                              color: AppTheme.primary,
                              title: 'Teacher Name',
                              subtitle: _teacherName.isNotEmpty
                                  ? _teacherName
                                  : 'Not set',
                              onTap: _editProfile,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.school,
                              color: AppTheme.secondary,
                              title: 'School Name',
                              subtitle: _schoolName.isNotEmpty
                                  ? _schoolName
                                  : 'Not set',
                              onTap: _editProfile,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'GRADING SYSTEM',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.calculate,
                              color: const Color(0xFF8B5CF6),
                              title: 'Grading Scale',
                              subtitle: _gradingSystem.displayName,
                              onTap: _configureGradingSystem,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.tableChart,
                              color: const Color(0xFF10B981),
                              title: 'Grade Equivalency Table',
                              subtitle:
                                  'Configure percentage to numerical conversion',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const GradeEquivalencyConfigScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'RISK MONITORING',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.tune,
                              color: AppTheme.danger,
                              title: 'Grade Threshold',
                              subtitle:
                                  '$_gradeThreshold% — Below this is flagged',
                              onTap: _editThresholds,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.eventAvailable,
                              color: AppTheme.warning,
                              title: 'Attendance Threshold',
                              subtitle:
                                  '$_attendanceThreshold% — Below this is flagged',
                              onTap: _editThresholds,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'APPEARANCE',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.palette,
                              color: AppTheme.primary,
                              title: 'Theme Color',
                              subtitle: 'Customize app accent colors',
                              onTap: _showThemeColorPicker,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'ACCOUNT',
                          items: [
                            if (_currentUser != null)
                              _SettingsTile(
                                icon: PlatformIcons.email,
                                color: AppTheme.primary,
                                title: 'Signed in as',
                                subtitle: _currentUser!.email ?? 'No email',
                                onTap: null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'SECURITY',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.lock,
                              color: const Color(0xFF7C3AED),
                              title: 'Change PIN',
                              subtitle: 'Update your app access PIN',
                              onTap: _changePin,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.lockReset,
                              color: const Color(0xFF2563EB),
                              title: _hasPasswordProvider
                                  ? 'Change Account Password'
                                  : 'Create Email Password',
                              subtitle: _hasPasswordProvider
                                  ? 'Use email and password to sign in'
                                  : _hasGoogleProvider
                                  ? 'Add email/password login to your Google account'
                                  : 'Set up password-based login',
                              onTap: _manageAccountPassword,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.logout,
                              color: AppTheme.danger,
                              title: 'Sign Out',
                              subtitle: 'Sign out from your account',
                              onTap: _signOut,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: 'DATA MANAGEMENT',
                          items: [
                            _SettingsTile(
                              icon: PlatformIcons.cloudSync,
                              color: const Color(0xFF0891B2),
                              title: 'Sync Now',
                              subtitle: 'Backup & restore data with Firebase',
                              onTap: _syncNow,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.email,
                              color: const Color(0xFFF59E0B),
                              title: 'Migrate Student Emails',
                              subtitle:
                                  'Fix existing student emails before download sync',
                              onTap: _migrateStudentEmails,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.deleteSweep,
                              color: const Color(0xFFEF4444),
                              title: 'Clear Data',
                              subtitle: 'Select offline tables to clear',
                              onTap: _clearData,
                            ),
                            _SettingsTile(
                              icon: PlatformIcons.backup,
                              color: AppTheme.success,
                              title: 'Backup Database',
                              subtitle: 'Export and share your database file',
                              onTap: _backupDatabase,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                PlatformIcons.school,
                                size: 40,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'GradeBook',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Version 1.0.0',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Developed by MTZ-CodeCollective ITS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChangeAccountPasswordDialog extends StatefulWidget {
  @override
  State<_ChangeAccountPasswordDialog> createState() =>
      _ChangeAccountPasswordDialogState();
}

class _ChangeAccountPasswordDialogState
    extends State<_ChangeAccountPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _currentController;
  late final TextEditingController _newController;
  late final TextEditingController _confirmController;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _currentController = TextEditingController();
    _newController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'current': _currentController.text.trim(),
        'new': _newController.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change Account Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Current password',
                prefixIcon: Icon(PlatformIcons.lock),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                  icon: Icon(
                    _obscureCurrent
                        ? PlatformIcons.eye
                        : PlatformIcons.eyeSlash,
                  ),
                ),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Current password is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(PlatformIcons.lockReset),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  icon: Icon(
                    _obscureNew ? PlatformIcons.eye : PlatformIcons.eyeSlash,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'New password is required';
                }
                if (value.trim().length < 6) {
                  return 'Password should be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: Icon(PlatformIcons.verified),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(
                    _obscureConfirm
                        ? PlatformIcons.eye
                        : PlatformIcons.eyeSlash,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please confirm the new password';
                }
                if (value.trim() != _newController.text.trim()) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Update')),
      ],
    );
  }
}

class _CreateAccountPasswordDialog extends StatefulWidget {
  final String email;

  const _CreateAccountPasswordDialog({required this.email});

  @override
  State<_CreateAccountPasswordDialog> createState() =>
      _CreateAccountPasswordDialogState();
}

class _CreateAccountPasswordDialogState
    extends State<_CreateAccountPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _newController;
  late final TextEditingController _confirmController;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _newController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({'new': _newController.text.trim()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Create Email Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a password for ${widget.email}. You can continue using Google, and this will also enable email/password sign-in.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(PlatformIcons.lockReset),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  icon: Icon(
                    _obscureNew ? PlatformIcons.eye : PlatformIcons.eyeSlash,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Password is required';
                }
                if (value.trim().length < 6) {
                  return 'Password should be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(PlatformIcons.verified),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(
                    _obscureConfirm
                        ? PlatformIcons.eye
                        : PlatformIcons.eyeSlash,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please confirm your password';
                }
                if (value.trim() != _newController.text.trim()) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsTile> items;

  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: items
                .asMap()
                .entries
                .map(
                  (e) => Column(
                    children: [
                      e.value,
                      if (e.key < items.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PlatformIcons.chevronRight,
              color: AppTheme.textLight,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// Custom dialog widget that properly manages TextEditingController lifecycle
class _ThresholdsDialog extends StatefulWidget {
  final String gradeThreshold;
  final String attendanceThreshold;

  const _ThresholdsDialog({
    required this.gradeThreshold,
    required this.attendanceThreshold,
  });

  @override
  State<_ThresholdsDialog> createState() => _ThresholdsDialogState();
}

class _ThresholdsDialogState extends State<_ThresholdsDialog> {
  late final TextEditingController _gradeController;
  late final TextEditingController _attendanceController;

  @override
  void initState() {
    super.initState();
    _gradeController = TextEditingController(text: widget.gradeThreshold);
    _attendanceController = TextEditingController(
      text: widget.attendanceThreshold,
    );
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _attendanceController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop({
      'grade': _gradeController.text.trim(),
      'attendance': _attendanceController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Risk Thresholds'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _gradeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Grade Threshold (%)',
              suffixText: '%',
              helperText: 'Students below this are flagged',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _attendanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Attendance Threshold (%)',
              suffixText: '%',
              helperText: 'Students below this are flagged',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  late final TextEditingController _currentController;
  late final TextEditingController _newController;
  late final TextEditingController _confirmController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _currentController = TextEditingController();
    _newController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _changePin() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(
        context,
      ).pop({'current': _currentController.text, 'new': _newController.text});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change PIN'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _newController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'New PIN (4-6 digits)',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 4) return 'At least 4 digits';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirm New PIN',
                counterText: '',
              ),
              validator: (v) =>
                  v != _newController.text ? 'PINs do not match' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _changePin, child: const Text('Change')),
      ],
    );
  }
}
