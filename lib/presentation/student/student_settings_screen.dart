import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';
import 'dart:convert';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/student_sync_service.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_data_repository.dart';
import '../../data/repositories/student_account_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/student_model.dart';
import '../auth/login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class StudentSettingsScreen extends StatefulWidget {
  const StudentSettingsScreen({super.key});

  @override
  State<StudentSettingsScreen> createState() => _StudentSettingsScreenState();
}

class _StudentSyncModal extends StatefulWidget {
  final String firebaseUid;
  final String syncDirection; // 'upload' or 'download'
  final StudentDataRepository studentRepo;

  const _StudentSyncModal({
    required this.firebaseUid,
    required this.syncDirection,
    required this.studentRepo,
  });

  @override
  State<_StudentSyncModal> createState() => _StudentSyncModalState();
}

class _StudentSyncModalState extends State<_StudentSyncModal>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _status = 'Initializing sync...';
  StudentSyncResult? _result;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();

    _status = widget.syncDirection == 'upload'
        ? 'Uploading to cloud...'
        : 'Downloading from cloud...';
    _startSync();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    try {
      final result = await widget.studentRepo.syncStudentData(
        firebaseUid: widget.firebaseUid,
        direction: widget.syncDirection,
        onStatusUpdate: (s) {
          if (mounted) {
            setState(() {
              _status = s;
            });
          }
          print('[StudentSyncModal] Status update: $s');
        },
      );

      final ok = result.error == null || result.error!.trim().isEmpty;
      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
          if (ok) {
            _status = widget.syncDirection == 'upload'
                ? 'Upload completed successfully!'
                : 'Download completed successfully!';
          } else {
            final error = result.error ?? '';
            if (error.contains('No internet connection')) {
              _status = 'No internet connection. Sync cancelled.';
            } else {
              _status = widget.syncDirection == 'upload'
                  ? 'Upload failed'
                  : 'Download failed';
            }
          }
        });
      }

      print('[StudentSyncModal] Sync result: ${result.summary()}');
      if (result.error != null && result.error!.isNotEmpty) {
        print('[StudentSyncModal] Sync returned error: ${result.error}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = StudentSyncResult(uploaded: 0, downloaded: 0, error: '$e');
          _isLoading = false;
          _status = 'Sync failed';
        });
      }
      print('[StudentSyncModal] Sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    final ok =
        (_result?.error == null) || (_result?.error?.trim().isEmpty ?? false);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: _isLoading
                      ? LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : ok
                      ? const LinearGradient(
                          colors: [AppTheme.success, Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [AppTheme.danger, Color(0xFFEF4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  shape: BoxShape.circle,
                ),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        ok ? PlatformIcons.checkCircle : PlatformIcons.error,
                        color: Colors.white,
                        size: 48,
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                _isLoading
                    ? 'Syncing...'
                    : ok
                    ? 'Success!'
                    : 'Error',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              if (!_isLoading && _result != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ok
                      ? Column(
                          children: [
                            if (widget.syncDirection != 'download')
                              _StudentSyncStatRow(
                                icon: PlatformIcons.cloudUpload,
                                label: 'Uploaded',
                                value: '${_result!.uploaded}',
                                color: const Color(0xFF0891B2),
                              ),
                            if (widget.syncDirection != 'upload') ...[
                              const SizedBox(height: 8),
                              _StudentSyncStatRow(
                                icon: PlatformIcons.cloudDownload,
                                label: 'Downloaded',
                                value: '${_result!.downloaded}',
                                color: const Color(0xFF8B5CF6),
                              ),
                            ],
                          ],
                        )
                      : Row(
                          children: [
                            Icon(
                              PlatformIcons.warning,
                              color: AppTheme.danger,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _result!.error ?? 'Unknown error',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
              if (!_isLoading) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(ok),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ok ? AppTheme.success : AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      ok ? 'Done' : 'Close',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentSyncStatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StudentSyncStatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StudentSettingsScreenState extends State<StudentSettingsScreen>
    with SingleTickerProviderStateMixin {
  final StudentDataRepository _studentRepo = StudentDataRepository();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  String? _error;
  String _studentName = '';
  String _studentId = '';
  String _email = '';
  String? _photoPath;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeCtrl.reset();

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) throw Exception('Not logged in');

      final student = await _studentRepo.getCurrentStudentProfile(
        firebaseUser.uid,
      );
      final accountInfo = student == null
          ? await StudentAccountRepository.getStudentAccountByUid(
              firebaseUser.uid,
            )
          : null;

      setState(() {
        _studentName = student != null
            ? '${student.firstName} ${student.lastName}'.trim()
            : (accountInfo?.displayName ?? '').trim();
        _studentId = student?.studentId ?? accountInfo?.studentId ?? '';
        // Prioritize Firebase Auth email since it's the login credential
        _email =
            firebaseUser.email ?? student?.email ?? accountInfo?.email ?? '';
        _photoPath = student?.photoPath;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _fadeCtrl.forward();
    }
  }

  Future<void> _syncNow() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _showSnack('Not logged in', backgroundColor: AppTheme.danger);
      return;
    }

    final confirm = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0891B2),
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
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how you want to sync your student data.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            SizedBox(height: 12),
            Text(
              'Upload: send your local data to the cloud\nDownload: restore cloud data to this device',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          OverflowBar(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('upload'),
                icon: Icon(PlatformIcons.cloudUpload, size: 16),
                label: const Text('Upload', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('download'),
                icon: Icon(PlatformIcons.cloudDownload, size: 16),
                label: const Text('Download', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirm == null) {
      print('[StudentSettings] Sync cancelled by user');
      return;
    }

    print(
      '[StudentSettings] Opening student sync modal direction=$confirm uid=${user.uid}',
    );

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StudentSyncModal(
        firebaseUid: user.uid,
        syncDirection: confirm,
        studentRepo: _studentRepo,
      ),
    );

    if (!mounted) return;

    print('[StudentSettings] Student sync modal closed, success=$success');
    if (success == true) {
      await _load();
    }
  }

  // ── Theme picker ────────────────────────────────────────────────────────────

  Future<void> _showThemeColorPicker() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentScheme = themeProvider.getCurrentSchemeName();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ThemePickerSheet(
        currentScheme: currentScheme,
        themeProvider: themeProvider,
      ),
    );
  }

  // ── Sign-out confirm ────────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _SignOutDialog(),
    );
    if (ok == true && mounted) {
      try {
        await StudentAccountRepository.clearActiveTeacherContext();
        print('[StudentSettingsScreen] Cleared active teacher context');
      } catch (e) {
        print('[StudentSettingsScreen] Clear teacher context error: $e');
      }
      if (!mounted) return;

      final pinHash = await DatabaseHelper.instance.getSetting(
        'student_pin_hash',
      );
      final hasPin = pinHash != null && pinHash.trim().isNotEmpty;
      print(
        '[StudentSettingsScreen] Logout lock redirect hasStudentPin=$hasPin',
      );

      if (hasPin) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen(isStudent: true)),
          (_) => false,
        );
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    }
  }

  Future<void> _showSnack(String message, {Color? backgroundColor}) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor:
            backgroundColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _changePassword() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _showSnack('Not logged in', backgroundColor: AppTheme.danger);
      return;
    }

    final providers = user.providerData.map((p) => p.providerId).toList();
    if (!providers.contains('password')) {
      await _showSnack(
        'Password change is only available for email/password accounts.',
        backgroundColor: AppTheme.danger,
      );
      return;
    }

    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) {
          return _ChangePasswordDialog();
        },
      );

      if (result == null) return;
      final currentPassword = result['current'] ?? '';
      final nextPassword = result['next'] ?? '';

      print(
        '[StudentSettings] ChangePassword start uid=${user.uid} email=${user.email} providers=$providers',
      );

      final email = user.email;
      if (email == null || email.trim().isEmpty) {
        await _showSnack(
          'No email found for this account.',
          backgroundColor: AppTheme.danger,
        );
        return;
      }

      await _showSnack('Updating password...');

      final credential = firebase_auth.EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(nextPassword);

      print('[StudentSettings] ChangePassword success uid=${user.uid}');
      await _showSnack(
        'Password updated successfully.',
        backgroundColor: AppTheme.success,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[StudentSettings] ChangePassword FirebaseAuthException code=${e.code} message=${e.message}',
      );

      String message = 'Failed to update password.';
      if (e.code == 'wrong-password') {
        message = 'Current password is incorrect.';
      } else if (e.code == 'weak-password') {
        message = 'New password is too weak.';
      } else if (e.code == 'requires-recent-login') {
        message = 'Please log in again and retry.';
      }

      await _showSnack(message, backgroundColor: AppTheme.danger);
    } catch (e) {
      print('[StudentSettings] ChangePassword error: $e');
      await _showSnack(
        'Failed to update password: $e',
        backgroundColor: AppTheme.danger,
      );
    }
  }

  Future<void> _editProfilePicture() async {
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        await _showSnack('Not logged in', backgroundColor: AppTheme.danger);
        return;
      }

      // Show image source selection dialog
      final imageSource = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change Profile Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PlatformIcons.camera),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: Icon(PlatformIcons.photoLibrary),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (imageSource == null) return;

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: imageSource,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Convert image to base64 for storage
      final bytes = await pickedFile.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';

      // Update student profile picture in database
      await _updateStudentProfilePicture(firebaseUser.uid, dataUri);

      setState(() {
        _photoPath = dataUri;
      });

      await _showSnack(
        'Profile picture updated successfully!',
        backgroundColor: AppTheme.success,
      );
    } catch (e) {
      print('[StudentSettings] Edit profile picture error: $e');
      await _showSnack(
        'Failed to update profile picture: $e',
        backgroundColor: AppTheme.danger,
      );
    }
  }

  Future<void> _updateStudentProfilePicture(
    String firebaseUid,
    String photoPath,
  ) async {
    try {
      // Get current student profile
      final student = await _studentRepo.getCurrentStudentProfile(firebaseUid);

      if (student == null) {
        // Student doesn't exist locally, try to get student info and create record
        final studentInfo =
            await StudentAccountRepository.getStudentAccountByUid(firebaseUid);
        if (studentInfo == null) {
          throw Exception('Student account not found');
        }

        // Create a minimal student record for profile picture update
        final now = DateTime.now().toIso8601String();
        final displayName = studentInfo.displayName;
        final nameParts = displayName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : 'Student';
        final lastName = nameParts.length > 1 ? nameParts.last : 'User';

        final newStudent = Student(
          id: null, // Will be assigned by database
          studentId: studentInfo.studentId,
          firstName: firstName,
          lastName: lastName,
          email: studentInfo.email,
          photoPath: photoPath,
          createdAt: now,
          updatedAt: now,
        );

        // Insert the student record
        final studentRepo = StudentRepository();
        final studentId = await studentRepo.insertStudent(newStudent);
        print(
          '[StudentSettings] Created student record with id=$studentId for profile picture update',
        );
      } else {
        // Update existing student record
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'students',
          {
            'photo_path': photoPath,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [student.id],
        );
        print(
          '[StudentSettings] Profile picture updated locally for student ${student.id}',
        );
      }
    } catch (e) {
      print('[StudentSettings] Update profile picture error: $e');
      rethrow;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        color: primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SettingsHeader(
                studentName: _studentName,
                isLoading: _isLoading,
                onLogout: _confirmSignOut,
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 24 : 16,
                0,
                isTablet ? 24 : 16,
                40,
              ),
              sliver: _isLoading
                  ? const SliverToBoxAdapter(child: _SettingsShimmer())
                  : _error != null
                  ? SliverToBoxAdapter(child: _ErrorCard(error: _error!))
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Profile card
                              _ProfileCard(
                                name: _studentName,
                                studentId: _studentId,
                                email: _email,
                                photoPath: _photoPath,
                                onEditPhoto: _editProfilePicture,
                              ),
                              const SizedBox(height: 20),

                              // Appearance section
                              _SectionLabel(label: 'Appearance'),
                              const SizedBox(height: 10),
                              _SettingsGroup(
                                children: [
                                  _SettingsTile(
                                    icon: PlatformIcons.palette,
                                    iconColor: const Color(0xFF9C6FE4),
                                    title: 'Theme Color',
                                    subtitle: 'Customize app appearance',
                                    onTap: _showThemeColorPicker,
                                    trailing: _ColorDot(color: primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Account section
                              _SectionLabel(label: 'Account'),
                              const SizedBox(height: 10),
                              _SettingsGroup(
                                children: [
                                  _SettingsTile(
                                    icon: PlatformIcons.lock,
                                    iconColor: const Color(0xFF5B8AF5),
                                    title: 'Change Password',
                                    subtitle: 'Update your credentials',
                                    onTap: _changePassword,
                                  ),
                                  _SettingsDivider(),
                                  _SettingsTile(
                                    icon: PlatformIcons.logout,
                                    iconColor: const Color(0xFFFF5C72),
                                    title: 'Sign Out',
                                    subtitle: 'Log out of your account',
                                    onTap: _confirmSignOut,
                                    titleColor: const Color(0xFFFF5C72),
                                    showChevron: false,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),
                              _SectionLabel(label: 'Data Management'),
                              const SizedBox(height: 10),
                              _SettingsGroup(
                                children: [
                                  _SettingsTile(
                                    icon: PlatformIcons.cloudSync,
                                    iconColor: const Color(0xFF0891B2),
                                    title: 'Sync Data',
                                    subtitle: 'Upload or download your data',
                                    onTap: _syncNow,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 28),
                              _AppVersionBadge(),
                            ],
                          ),
                        ),
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Change Password Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  late final TextEditingController _currentCtrl;
  late final TextEditingController _newCtrl;
  late final TextEditingController _confirmCtrl;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _currentCtrl = TextEditingController();
    _newCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.trim().isEmpty ||
        next.trim().isEmpty ||
        confirm.trim().isEmpty) {
      print('[StudentSettings] ChangePassword validation failed: empty fields');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (next.trim().length < 6) {
      print(
        '[StudentSettings] ChangePassword validation failed: weak password length=${next.trim().length}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (next != confirm) {
      print('[StudentSettings] ChangePassword validation failed: mismatch');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop({'current': current, 'next': next});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentCtrl,
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
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
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
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
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
            ),
            const SizedBox(height: 8),
            const Text(
              'Password must be at least 6 characters.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Update')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Settings Header
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsHeader extends StatelessWidget {
  final String studentName;
  final bool isLoading;
  final VoidCallback? onLogout;

  const _SettingsHeader({
    required this.studentName,
    required this.isLoading,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientColors.first, gradientColors.last, primary],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -30,
            right: -30,
            child: _Circle(size: 160, opacity: 0.06),
          ),
          Positioned(
            bottom: -20,
            left: 40,
            child: _Circle(size: 100, opacity: 0.05),
          ),
          Positioned(
            top: 70,
            right: 90,
            child: _Circle(size: 50, opacity: 0.08),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Manage your account',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onLogout != null)
                      _HeaderIconButton(
                        icon: PlatformIcons.logout,
                        tooltip: 'Logout',
                        onTap: () {
                          print('[StudentSettingsHeader] Logout pressed');
                          onLogout?.call();
                        },
                      ),
                  ],
                ),

                if (!isLoading && studentName.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  // Greeting chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5B8AF5), Color(0xFF9C6FE4)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              studentName.isNotEmpty
                                  ? studentName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const Text(
                              'Student Account',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double opacity;
  const _Circle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A237E),
          letterSpacing: 0.3,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String name;
  final String studentId;
  final String email;
  final String? photoPath;
  final VoidCallback onEditPhoto;

  const _ProfileCard({
    required this.name,
    required this.studentId,
    required this.email,
    this.photoPath,
    required this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar + name block
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                // Avatar with gradient ring and edit capability
                GestureDetector(
                  onTap: onEditPhoto,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3949AB), Color(0xFF5B8AF5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF3949AB,
                          ).withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Profile picture or initials
                        Center(child: _buildProfileImage()),
                        // Edit overlay icon
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF3949AB),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              PlatformIcons.edit,
                              size: 12,
                              color: Color(0xFF3949AB),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : '—',
                        style: const TextStyle(
                          color: Color(0xFF1A237E),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _ProfileBadge(
                            icon: PlatformIcons.badge,
                            label: studentId.isNotEmpty ? studentId : '—',
                            color: const Color(0xFF5B8AF5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: const Color(0xFFEEF1F6),
          ),

          // Info rows
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              children: [
                _ProfileInfoRow(
                  icon: PlatformIcons.person,
                  label: 'Full Name',
                  value: name.isNotEmpty ? name : '—',
                  color: const Color(0xFF5B8AF5),
                  onCopy: name.isNotEmpty ? () => _copy(context, name) : null,
                ),
                const SizedBox(height: 10),
                _ProfileInfoRow(
                  icon: PlatformIcons.badge,
                  label: 'Student ID',
                  value: studentId.isNotEmpty ? studentId : '—',
                  color: const Color(0xFF9C6FE4),
                  onCopy: studentId.isNotEmpty
                      ? () => _copy(context, studentId)
                      : null,
                ),
                const SizedBox(height: 10),
                _ProfileInfoRow(
                  icon: PlatformIcons.email,
                  label: 'Email',
                  value: email.isNotEmpty ? email : '—',
                  color: const Color(0xFF26C6DA),
                  onCopy: email.isNotEmpty ? () => _copy(context, email) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: const Color(0xFF1A237E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildProfileImage() {
    if (photoPath != null && photoPath!.isNotEmpty) {
      // Check if it's a base64 image
      if (photoPath!.startsWith('data:image/')) {
        try {
          final base64String = photoPath!.split(',').last;
          final bytes = base64Decode(base64String);
          return ClipOval(
            child: Image.memory(
              bytes,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildInitials();
              },
            ),
          );
        } catch (e) {
          return _buildInitials();
        }
      }
    }

    // Fallback to initials
    return _buildInitials();
  }

  Widget _buildInitials() {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 26,
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ProfileBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onCopy;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF1F6)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF9AA3B0),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1A237E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            GestureDetector(
              onTap: onCopy,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(PlatformIcons.copy, color: color, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Settings Group + Tile
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1A237E).withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(children: children),
  );
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: const Color(0xFFEEF1F6),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? titleColor;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.titleColor,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor ?? const Color(0xFF1A237E),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Trailing
            if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
            if (showChevron)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(PlatformIcons.forward, color: iconColor, size: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.4),
          blurRadius: 6,
          spreadRadius: 1,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  App Version Badge
// ─────────────────────────────────────────────────────────────────────────────

class _AppVersionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(
      children: [
        Icon(PlatformIcons.school, size: 40, color: AppTheme.primary),
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
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Theme Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ThemePickerSheet extends StatelessWidget {
  final String currentScheme;
  final ThemeProvider themeProvider;

  const _ThemePickerSheet({
    required this.currentScheme,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF9C6FE4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  PlatformIcons.palette,
                  color: Color(0xFF9C6FE4),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Color',
                    style: TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Choose your preferred color',
                    style: TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFEEF1F6)),
          const SizedBox(height: 14),

          // Color options
          ...ThemeProvider.colorSchemes.entries.map((entry) {
            final isSelected = entry.key == currentScheme;
            final color = entry.value['primary'] as Color;

            return GestureDetector(
              onTap: () async {
                await themeProvider.setColorScheme(entry.key);
                if (context.mounted) Navigator.pop(context);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.08)
                      : const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.35)
                        : const Color(0xFFEEF1F6),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Color swatch
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: isSelected ? color : const Color(0xFF1A237E),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PlatformIcons.check,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sign Out Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SignOutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PlatformIcons.logout,
                color: Color(0xFFFF5C72),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign Out?',
              style: TextStyle(
                color: Color(0xFF1A237E),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You will be returned to the login screen. Any unsaved data may be lost.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9AA3B0),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF1A237E),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5C72),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF5C72,
                            ).withValues(alpha: 0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsShimmer extends StatefulWidget {
  const _SettingsShimmer();

  @override
  State<_SettingsShimmer> createState() => _SettingsShimmerState();
}

class _SettingsShimmerState extends State<_SettingsShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final opacity = 0.5 + 0.5 * math.sin(_anim.value * math.pi);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error Card
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFD6DA)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFFF5C72).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEF0),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            PlatformIcons.errorOutline,
            color: Color(0xFFFF5C72),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Color(0xFF2E3A5C),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                error,
                style: const TextStyle(color: Color(0xFF9AA3B0), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
