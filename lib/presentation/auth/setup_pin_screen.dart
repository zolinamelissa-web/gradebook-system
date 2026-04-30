import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/curved_background.dart';
import '../../core/providers/theme_provider.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_account_repository.dart';
import '../home/home_screen.dart';
import '../student/student_home_screen.dart';

class SetupPinScreen extends StatefulWidget {
  final bool isOnboarding;
  final VoidCallback? onComplete;
  final bool isStudent;
  final String? prefilledStudentId;
  final String? prefilledName;
  final String? prefilledSchool;

  const SetupPinScreen({
    super.key,
    this.isOnboarding = false,
    this.onComplete,
    this.isStudent = false,
    this.prefilledStudentId,
    this.prefilledName,
    this.prefilledSchool,
  });

  @override
  State<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<SetupPinScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthRepository _authRepo = AuthRepository();
  late final TextEditingController _nameController;
  final _schoolController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    print(
      '[SetupPinScreen] init isStudent=${widget.isStudent} isOnboarding=${widget.isOnboarding} prefilledStudentId=${widget.prefilledStudentId}',
    );
    _nameController = TextEditingController(text: widget.prefilledName ?? '');
    _schoolController.text = widget.prefilledSchool ?? '';
    _studentIdController.text = widget.prefilledStudentId ?? '';
    _loadLocalStudentPrefill();
    _loadGoogleUserName();
  }

  Future<void> _loadLocalStudentPrefill() async {
    if (!widget.isStudent) return;
    try {
      if (kIsWeb) {
        if (_studentIdController.text.trim().isEmpty) {
          try {
            final user = await _authRepo.getActiveUser();
            final uid = user?.uid ?? '';
            if (uid.isNotEmpty) {
              final remoteStudentId =
                  await StudentAccountRepository.getStudentIdForFirebaseUid(
                    uid,
                  );
              if (remoteStudentId.trim().isNotEmpty && mounted) {
                _studentIdController.text = remoteStudentId.trim();
                print(
                  '[SetupPinScreen] Auto-filled student_id from Firestore mapping uid=$uid student_id=${remoteStudentId.trim()}',
                );
              }
            }
          } catch (inner) {
            print('[SetupPinScreen] Student ID remote prefill error: $inner');
          }
        }

        if (_nameController.text.trim().isEmpty) {
          final name = await _authRepo.getWebProfileName(isStudent: true);
          if (name != null && name.trim().isNotEmpty && mounted) {
            _nameController.text = name.trim();
          }
        }
        return;
      }

      final db = DatabaseHelper.instance;
      if (_studentIdController.text.trim().isEmpty) {
        final sid = await db.getSetting('student_id');
        if (sid != null && sid.trim().isNotEmpty && mounted) {
          _studentIdController.text = sid.trim();
          print(
            '[SetupPinScreen] Auto-filled student_id from local settings student_id=${sid.trim()}',
          );
        }
      }

      // Fallback: resolve student_id from Firestore mapping using current UID.
      // This is important on a new device where local settings are empty.
      if (_studentIdController.text.trim().isEmpty) {
        try {
          final authRepo = AuthRepository();
          final user = await authRepo.getActiveUser();
          final uid = user?.uid ?? '';
          if (uid.isNotEmpty) {
            final remoteStudentId =
                await StudentAccountRepository.getStudentIdForFirebaseUid(uid);
            if (remoteStudentId.trim().isNotEmpty && mounted) {
              _studentIdController.text = remoteStudentId.trim();
              print(
                '[SetupPinScreen] Auto-filled student_id from Firestore mapping uid=$uid student_id=${remoteStudentId.trim()}',
              );
            }
          }
        } catch (inner) {
          print('[SetupPinScreen] Student ID remote prefill error: $inner');
        }
      }

      if (_nameController.text.trim().isEmpty) {
        final name = await db.getSetting('student_name');
        if (name != null && name.trim().isNotEmpty && mounted) {
          _nameController.text = name.trim();
        }
      }
    } catch (e) {
      print('[SetupPinScreen] Error loading local student prefill: $e');
    }
  }

  Future<void> _loadGoogleUserName() async {
    // Only auto-fill teacher name for teacher accounts
    if (widget.isStudent) return;

    // If no prefilled name, try to get it from the active user (Google sign-in)
    if (widget.prefilledName == null || widget.prefilledName!.isEmpty) {
      try {
        final authRepo = AuthRepository();
        final user = await authRepo.getActiveUser();
        if (user?.displayName != null &&
            user!.displayName!.isNotEmpty &&
            mounted) {
          _nameController.text = user.displayName!;
          print(
            '[SetupPinScreen] Auto-filled teacher name from Google: ${user.displayName}',
          );
        }
      } catch (e) {
        print('[SetupPinScreen] Error loading Google user name: $e');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _schoolController.dispose();
    _studentIdController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      if (kIsWeb) {
        await _authRepo.saveWebPinProfile(
          isStudent: widget.isStudent,
          name: _nameController.text.trim(),
          schoolName: widget.isStudent ? null : _schoolController.text.trim(),
          studentId: widget.isStudent ? _studentIdController.text.trim() : null,
          pinHash: _pinController.text.isNotEmpty
              ? _hashPin(_pinController.text)
              : null,
        );
      } else {
        final db = DatabaseHelper.instance;

        if (widget.isStudent) {
          await db.setSetting('student_name', _nameController.text.trim());
          await db.setSetting('student_id', _studentIdController.text.trim());
          if (_pinController.text.isNotEmpty) {
            await db.setSetting(
              'student_pin_hash',
              _hashPin(_pinController.text),
            );
          }
        } else {
          await db.setSetting('teacher_name', _nameController.text.trim());
          await db.setSetting('school_name', _schoolController.text.trim());
          if (_pinController.text.isNotEmpty) {
            await db.setSetting('pin_hash', _hashPin(_pinController.text));
          }
        }

        await db.setSetting('onboarding_complete', 'true');
      }
      print(
        '[SetupPinScreen] Setup complete: role=${widget.isStudent ? 'student' : 'teacher'} name=${_nameController.text.trim()}',
      );

      // Navigate immediately while context is still valid
      if (widget.onComplete != null) {
        try {
          widget.onComplete!();
        } catch (e) {
          print('[SetupPinScreen] onComplete callback error: $e');
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => widget.isStudent
                    ? const StudentHomeScreen(initialIndex: 0)
                    : const HomeScreen(initialIndex: 0),
              ),
              (_) => false,
            );
          }
        }
      } else {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => widget.isStudent
                  ? const StudentHomeScreen(initialIndex: 0)
                  : const HomeScreen(initialIndex: 0),
            ),
            (_) => false,
          );
        }
      }
    } catch (e) {
      print('[SetupPinScreen] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.primaryColor;
    final secondary = themeProvider.secondaryColor;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      body: FullCurvedBackground(
        colors: [
          primary,
          Color.lerp(primary, secondary, 0.45) ?? primary,
          secondary,
        ],
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive padding based on screen size
              final horizontalPadding = constraints.maxWidth > 600
                  ? 40.0
                  : 28.0;
              final verticalPadding = constraints.maxHeight > 800 ? 28.0 : 20.0;

              return SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: kIsWeb ? 480 : double.infinity,
                      minHeight:
                          constraints.maxHeight -
                          (isKeyboardVisible ? keyboardHeight : 0),
                    ),
                    child: IntrinsicHeight(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (Navigator.of(context).canPop()) ...[
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(PlatformIcons.back),
                                color: Colors.white,
                                splashRadius: 22,
                              ),
                              SizedBox(height: verticalPadding * 0.2),
                            ],
                            SizedBox(height: verticalPadding),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                PlatformIcons.person,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                            SizedBox(height: verticalPadding * 0.8),
                            const Text(
                              'Setup Your\nProfile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isStudent
                                  ? 'Setup your student profile and PIN security'
                                  : 'Configure your teacher profile and optional PIN security',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: verticalPadding * 1.2),
                            _buildCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label(
                                    widget.isStudent
                                        ? 'Student Name *'
                                        : 'Teacher Name *',
                                  ),
                                  TextFormField(
                                    controller: _nameController,
                                    decoration: InputDecoration(
                                      hintText: widget.isStudent
                                          ? 'e.g. Juan Dela Cruz'
                                          : 'e.g. Melissa Zolina',
                                      prefixIcon: Icon(
                                        PlatformIcons.personOutline,
                                      ),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'Name is required'
                                        : null,
                                  ),
                                  if (widget.isStudent) ...[
                                    const SizedBox(height: 16),
                                    _label('Student ID *'),
                                    TextFormField(
                                      controller: _studentIdController,
                                      decoration: InputDecoration(
                                        hintText: 'e.g. 2026-0001',
                                        prefixIcon: Icon(
                                          PlatformIcons.idNumber,
                                        ),
                                      ),
                                      enabled: false,
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'Student ID is required'
                                          : null,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  if (!widget.isStudent) ...[
                                    _label('School Name *'),
                                    TextFormField(
                                      controller: _schoolController,
                                      decoration: InputDecoration(
                                        hintText:
                                            'e.g. San Pedro National High School',
                                        prefixIcon: Icon(PlatformIcons.school),
                                      ),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'School is required'
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        PlatformIcons.lock,
                                        size: 18,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'PIN Security',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'Optional',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Leave blank to skip PIN protection',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _label('PIN (4 digits)'),
                                  TextFormField(
                                    controller: _pinController,
                                    obscureText: _obscurePin,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    decoration: InputDecoration(
                                      hintText: '••••',
                                      prefixIcon: Icon(PlatformIcons.key),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePin
                                              ? PlatformIcons.eyeSlash
                                              : PlatformIcons.eye,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePin = !_obscurePin,
                                        ),
                                      ),
                                      counterText: '',
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return null;
                                      if (v.length != 4) {
                                        return 'PIN must be exactly 4 digits';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _label('Confirm PIN'),
                                  TextFormField(
                                    controller: _confirmController,
                                    obscureText: _obscureConfirm,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    decoration: InputDecoration(
                                      hintText: '••••',
                                      prefixIcon: Icon(PlatformIcons.key),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirm
                                              ? PlatformIcons.eyeSlash
                                              : PlatformIcons.eye,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscureConfirm =
                                              !_obscureConfirm,
                                        ),
                                      ),
                                      counterText: '',
                                    ),
                                    validator: (v) {
                                      if (_pinController.text.isEmpty) {
                                        return null;
                                      }
                                      if (v != _pinController.text) {
                                        return 'PINs do not match';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSaving ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: primary,
                                  textStyle: const TextStyle(
                                    inherit: false,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Continue'),
                              ),
                            ),
                            SizedBox(height: verticalPadding * 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
