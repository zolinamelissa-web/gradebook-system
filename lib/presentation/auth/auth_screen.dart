import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/curved_background.dart';
import '../../core/providers/theme_provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_account_repository.dart';
import '../../data/database/database_helper.dart';
import '../home/home_screen.dart';
import 'setup_pin_screen.dart';
import 'login_screen.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const AuthScreen({super.key, this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthRole { teacher, student }

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final AuthRepository _authRepo = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _studentFirstNameController = TextEditingController();
  final _studentLastNameController = TextEditingController();
  final _schoolController = TextEditingController();

  String? _selectedTeacherUid;

  // Entrance animation
  late AnimationController _entranceController;
  late Animation<double> _entranceFade;
  late Animation<Offset> _entranceSlide;

  // Book flip animation
  late AnimationController _flipController;
  late Animation<double> _flipAnim;

  // Role switcher animation
  late AnimationController _roleController;
  late Animation<double> _roleFade;

  bool _isLogin = true; // the TARGET state (updated immediately on tap)
  bool _displayedIsLogin =
      true; // what is VISUALLY shown (flips at animation midpoint)
  bool _isFlipping = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  _AuthRole _role = _AuthRole.teacher;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _isMissingStudentPinHash(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return true;
    if (s.toLowerCase() == 'null') return true;
    if (s.toLowerCase() == 'undefined') return true;
    return false;
  }

  Future<void> _routeStudentAfterAuth() async {
    try {
      final pinHash = kIsWeb
          ? await _authRepo.getWebPinHash(isStudent: true)
          : await DatabaseHelper.instance.getSetting('student_pin_hash');
      final needsSetup = _isMissingStudentPinHash(pinHash);
      print(
        '[AuthScreen] Student post-auth route check needsSetup=$needsSetup student_pin_hash=${pinHash ?? 'null'} web=$kIsWeb',
      );
      if (!mounted) return;

      if (needsSetup) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SetupPinScreen(isOnboarding: true, isStudent: true),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => LoginScreen(isStudent: true)),
        );
      }
    } catch (e) {
      print('[AuthScreen] Student post-auth route error: $e');
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/student-dashboard');
    }
  }

  IconData _platformIcon({
    required IconData cupertino,
    required IconData material,
  }) {
    return PlatformIcons.adaptive(cupertino: cupertino, material: material);
  }

  @override
  void initState() {
    super.initState();

    // Entrance
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
        );
    _entranceController.forward();

    // Flip
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutCubic),
    );
    _flipController.addListener(() {
      // Swap the displayed content exactly at the visual midpoint (card is edge-on)
      if (_flipController.value >= 0.5 && _displayedIsLogin != _isLogin) {
        setState(() => _displayedIsLogin = _isLogin);
      }
    });
    _flipController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isFlipping = false);
        _flipController.reset();
      }
    });

    // Role fade
    _roleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _roleFade = CurvedAnimation(parent: _roleController, curve: Curves.easeOut);
    _roleController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _flipController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _studentIdController.dispose();
    _studentFirstNameController.dispose();
    _studentLastNameController.dispose();
    _schoolController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (_isFlipping) return;
    setState(() {
      _isFlipping = true;
      _isLogin = !_isLogin; // target state (used by logic/handlers)
      // _displayedIsLogin swaps at the animation midpoint via the listener
      _errorMessage = null;
      _selectedTeacherUid = null;
      _studentIdController.clear();
      _studentFirstNameController.clear();
      _studentLastNameController.clear();
      _schoolController.clear();
      _confirmPasswordController.clear();
      _emailController.clear();
      _passwordController.clear();
    });
    _flipController.forward();
  }

  void _setRole(_AuthRole role) {
    if (_role == role) return;
    _roleController.reset();
    setState(() {
      _role = role;
      _errorMessage = null;
      _selectedTeacherUid = null;
      _studentIdController.clear();
      _studentFirstNameController.clear();
      _studentLastNameController.clear();
      _schoolController.clear();
      _confirmPasswordController.clear();
    });
    _roleController.forward();
  }

  String _normalizeName(String v) {
    return v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<StudentTeacherLinkInfo?> _showTeacherPicker(
    List<StudentTeacherLinkInfo> links,
  ) async {
    if (links.isEmpty) return null;

    print('[AuthScreen] Showing teacher picker links=${links.length}');

    return showDialog<StudentTeacherLinkInfo>(
      context: context,
      builder: (context) {
        final list = SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: links.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final l = links[index];
              return ListTile(
                title: Text(l.teacherName),
                subtitle: Text(l.teacherUid),
                onTap: () => Navigator.of(context).pop(l),
              );
            },
          ),
        );

        if (_isIOS) {
          return CupertinoAlertDialog(
            title: const Text('Select Teacher'),
            content: Material(color: Colors.transparent, child: list),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: const Text('Select Teacher'),
          content: list,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_role == _AuthRole.teacher) {
        final user = await _authRepo.signInWithGoogle();
        if (user != null && mounted) {
          _navigateToSetupPin(user.displayName ?? user.email ?? 'User');
        }
      } else {
        try {
          final user = await _authRepo.signInStudentWithGoogle();
          if (user != null && mounted) {
            await _routeStudentAfterAuth();
          }
        } on MultiTeacherSelectionRequired catch (e) {
          print('[AuthScreen] Multi-teacher Google login: ${e.links.length}');
          final selected = await _showTeacherPicker(e.links);
          if (!mounted) return;
          if (selected == null) {
            setState(() => _errorMessage = 'Teacher selection is required.');
            return;
          }
          final user = await _authRepo.signInStudentWithGoogleAndTeacher(
            teacherUid: selected.teacherUid,
          );
          if (user != null && mounted) {
            await _routeStudentAfterAuth();
          }
        }
      }
    } on PlatformException catch (e) {
      print(
        '[AuthScreen] PlatformException (Google) code=${e.code} message=${e.message} details=${e.details}',
      );
      setState(
        () => _errorMessage = e.message?.trim().isNotEmpty == true
            ? e.message
            : 'Google sign-in failed. Please try again.',
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[AuthScreen] FirebaseAuthException (Google) code=${e.code} message=${e.message}',
      );
      setState(() => _errorMessage = _getErrorMessage(e.code));
    } catch (e) {
      print('[AuthScreen] Google sign-in unexpected error: $e');
      setState(() => _errorMessage = 'An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_role == _AuthRole.teacher) {
        final user = _isLogin
            ? await _authRepo.signInWithEmailPassword(
                email,
                _passwordController.text,
              )
            : await _authRepo.signUpWithEmailPassword(
                email,
                _passwordController.text,
                '', // No name required
              );
        if (user != null && mounted) {
          _navigateToSetupPin(
            user.displayName ?? user.email ?? 'User',
            schoolName: _schoolController.text.trim(),
          );
        }
      } else {
        if (_isLogin) {
          try {
            final user = await _authRepo.signInStudentWithEmailPassword(
              _emailController.text.trim(),
              _passwordController.text,
              studentId: _studentIdController.text.trim(),
            );
            if (user != null && mounted) {
              await _routeStudentAfterAuth();
            }
          } on MultiTeacherSelectionRequired catch (e) {
            print('[AuthScreen] Multi-teacher email login: ${e.links.length}');
            final selected = await _showTeacherPicker(e.links);
            if (!mounted) return;
            if (selected == null) {
              setState(() => _errorMessage = 'Teacher selection is required.');
              return;
            }
            final user = await _authRepo.signInStudentWithEmailPassword(
              _emailController.text.trim(),
              _passwordController.text,
              teacherUid: selected.teacherUid,
              studentId: _studentIdController.text.trim(),
            );
            if (user != null && mounted) {
              await _routeStudentAfterAuth();
            }
          }
        } else {
          final studentId = _studentIdController.text.trim();
          final firstName = _studentFirstNameController.text.trim();
          final lastName = _studentLastNameController.text.trim();

          final resolved =
              await StudentAccountRepository.resolveTeacherLinkByName(
                studentId: studentId,
                firstName: firstName,
                lastName: lastName,
              );
          print(
            '[AuthScreen] Student signup submit resolveTeacherLinkByName studentId=$studentId firstName=${_normalizeName(firstName)} lastName=${_normalizeName(lastName)} result=${resolved == null ? 'null' : 'teacherUid=${resolved.teacherUid}'}',
          );

          if (!mounted) return;
          if (resolved == null) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Invalid Student ID + Name combination.';
            });
            return;
          }

          final info =
              await StudentAccountRepository.getStudentAccountInfoForTeacher(
                studentId: studentId,
                teacherUid: resolved.teacherUid,
              );
          print(
            '[AuthScreen] Student signup submit getStudentAccountInfoForTeacher studentId=$studentId teacherUid=${resolved.teacherUid} result=${info == null ? 'null' : 'ok registered=${info.isRegistered}'}',
          );

          if (!mounted) return;
          if (info == null) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Student record not found. Please contact your teacher.';
            });
            return;
          }

          if (info.isRegistered) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'This Student ID is already registered. Please sign in instead.';
            });
            return;
          }

          final confirm = _confirmPasswordController.text;
          if (confirm != _passwordController.text) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Passwords do not match.';
            });
            return;
          }

          final displayName = 'Student $studentId';
          final selectedTeacherUid = resolved.teacherUid.trim();
          _selectedTeacherUid = selectedTeacherUid;

          final user = await _authRepo.registerStudentAccount(
            studentId: studentId,
            teacherUid: _selectedTeacherUid!,
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: displayName,
          );

          if (user != null && mounted) {
            final verifiedStudentId = studentId;
            final verifiedName = displayName;

            if (kIsWeb) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (newContext) => SetupPinScreen(
                    isOnboarding: true,
                    isStudent: true,
                    prefilledStudentId: verifiedStudentId,
                    prefilledName: verifiedName,
                    onComplete: () {
                      Navigator.of(
                        newContext,
                      ).pushReplacementNamed('/student-dashboard');
                    },
                  ),
                ),
              );
            } else {
              try {
                await DatabaseHelper.instance.setSetting(
                  'student_id',
                  verifiedStudentId,
                );
                if (verifiedName.trim().isNotEmpty) {
                  await DatabaseHelper.instance.setSetting(
                    'student_name',
                    verifiedName.trim(),
                  );
                }
                print(
                  '[AuthScreen] Student signup saved local settings student_id=$verifiedStudentId student_name=$verifiedName',
                );
              } catch (e) {
                print('[AuthScreen] Failed saving local student settings: $e');
              }

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (newContext) => SetupPinScreen(
                    isOnboarding: true,
                    isStudent: true,
                    prefilledStudentId: verifiedStudentId,
                    prefilledName: verifiedName,
                    onComplete: () {
                      Navigator.of(
                        newContext,
                      ).pushReplacementNamed('/student-dashboard');
                    },
                  ),
                ),
              );
            }
          }
        }
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[AuthScreen] FirebaseAuthException (Email) code=${e.code} message=${e.message}',
      );
      final message = _role == _AuthRole.teacher
          ? await _getTeacherEmailAuthErrorMessage(
              code: e.code,
              email: email,
              isLogin: _isLogin,
            )
          : _getErrorMessage(e.code);
      setState(() => _errorMessage = message);
    } catch (e) {
      setState(() => _errorMessage = 'An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _getTeacherEmailAuthErrorMessage({
    required String code,
    required String email,
    required bool isLogin,
  }) async {
    final fallback = _getErrorMessage(code);
    if (email.isEmpty) return fallback;

    try {
      final methods = await _authRepo.fetchSignInMethodsForEmail(email);
      final hasGoogle = methods.contains('google.com');
      final hasPassword = methods.contains('password');
      print(
        '[AuthScreen] Teacher email auth guidance code=$code email=$email methods=$methods isLogin=$isLogin',
      );
      if (hasGoogle && !hasPassword) {
        return isLogin
            ? 'This email uses Google sign-in only right now. Use Continue with Google first, then open Settings > Security to create an email password.'
            : 'This email already exists as a Google account. Sign in with Google first, then open Settings > Security to create an email password.';
      }
    } catch (e) {
      print(
        '[AuthScreen] Teacher email auth guidance lookup failed email=$email error=$e',
      );
    }

    return fallback;
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'invalid-login-credentials':
        return 'Invalid email or password.';
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password.';
      case 'invalid-password':
        return 'Invalid email or password.';
      case 'INVALID_PASSWORD':
        return 'Invalid email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'account-exists-with-different-credential':
        return 'This email is already registered with a different sign-in method.';
      case 'credential-already-in-use':
        return 'This credential is already linked to another account.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'provider-already-linked':
        return 'This sign-in method is already linked to your account.';
      case 'requires-recent-login':
        return 'Please sign in again and retry.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  void _navigateToSetupPin(String userName, {String? schoolName}) {
    Future<void>(() async {
      if (!mounted) return;
      if (kIsWeb) {
        final pinHash = await _authRepo.getWebPinHash(isStudent: false);
        final needsSetup = (pinHash ?? '').trim().isEmpty;
        print(
          '[AuthScreen] Teacher post-auth route check needsSetup=$needsSetup web=$kIsWeb',
        );
        if (!mounted) return;
        if (needsSetup) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SetupPinScreen(
                isOnboarding: true,
                prefilledName: userName,
                prefilledSchool: schoolName,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => LoginScreen(
                onLoginSuccess: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(initialIndex: 0),
                    ),
                  );
                },
              ),
            ),
          );
        }
        return;
      }

      if (widget.onAuthSuccess != null) {
        widget.onAuthSuccess!();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SetupPinScreen(
              isOnboarding: true,
              prefilledName: userName,
              prefilledSchool: schoolName,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.primaryColor;
    final secondary = themeProvider.secondaryColor;

    return Scaffold(
      body: FullCurvedBackground(
        colors: [
          primary,
          Color.lerp(primary, secondary, 0.45) ?? primary,
          secondary,
        ],
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: kIsWeb ? 480 : double.infinity,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _entranceFade,
                      child: SlideTransition(
                        position: _entranceSlide,
                        child: _buildHeader(primary, secondary),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Book flip card
                    FadeTransition(
                      opacity: _entranceFade,
                      child: SlideTransition(
                        position: _entranceSlide,
                        child: _buildFlipBook(primary, secondary),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeTransition(
                      opacity: _entranceFade,
                      child: _buildFooterToggle(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(Color primary, Color secondary) {
    return Column(
      children: [
        // Layered glowing icon badge
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // Middle ring
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
            ),
            // Inner badge
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Icon(PlatformIcons.school, size: 32, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'GradeBook',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey('${_role.name}_${_isLogin ? 'in' : 'up'}'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _role == _AuthRole.teacher
                      ? _platformIcon(
                          cupertino: CupertinoIcons.person_2,
                          material: Icons.person,
                        )
                      : _platformIcon(
                          cupertino: CupertinoIcons.book,
                          material: Icons.school,
                        ),
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  _role == _AuthRole.teacher
                      ? (_isLogin ? 'Teacher Sign In' : 'Teacher Sign Up')
                      : (_isLogin ? 'Student Sign In' : 'Student Sign Up'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Book Flip ─────────────────────────────────────────────────────────────

  Widget _buildFlipBook(Color primary, Color secondary) {
    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, child) {
        final double progress = _flipAnim.value; // 0.0 → 1.0

        // First half  (0.0→0.5): current face sweeps from 0 to π/2 (edge-on)
        // Second half (0.5→1.0): new face sweeps from -π/2 back to 0 (flat)
        final double angle = progress < 0.5
            ? progress *
                  math
                      .pi // 0 → π/2
            : (progress - 1.0) * math.pi; // -π/2 → 0

        final Matrix4 transform = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle);

        // Shadow peaks at midpoint
        final double shadowOpacity = (math.sin(progress * math.pi) * 0.22)
            .clamp(0.0, 0.22);

        return Stack(
          alignment: Alignment.center,
          children: [
            if (_isFlipping)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: shadowOpacity),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                        stops: const [0.35, 0.5, 0.65],
                      ),
                    ),
                  ),
                ),
              ),
            Transform(
              alignment: Alignment.center,
              transform: transform,
              // _displayedIsLogin flips at the midpoint — always shows correct face,
              // text is never rotated past π/2 so it never mirrors
              child: _buildCardFace(
                primary,
                secondary,
                isSignIn: _displayedIsLogin,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCardFace(
    Color primary,
    Color secondary, {
    required bool isSignIn,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Subtle top gradient accent
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 5,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, secondary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            // Decorative corner circles
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      primary.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -30,
              left: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      secondary.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mode indicator pill
                    _buildModePill(primary, isSignIn: isSignIn),
                    const SizedBox(height: 18),
                    // Role switcher
                    _buildRoleSwitcher(primary),
                    const SizedBox(height: 20),
                    // Error — only show on the active face
                    if (_errorMessage != null &&
                        isSignIn == _displayedIsLogin) ...[
                      _buildErrorBanner(),
                      const SizedBox(height: 14),
                    ],
                    // Fields
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOut,
                      child: Column(
                        children: [
                          // Student sign-up: ID verify row
                          if (_role == _AuthRole.student && !isSignIn) ...[
                            _buildField(
                              controller: _studentIdController,
                              label: 'Student ID',
                              icon: _platformIcon(
                                cupertino: CupertinoIcons.number,
                                material: Icons.confirmation_number,
                              ),
                              primary: primary,
                              validator: (v) {
                                if (_role != _AuthRole.student || _isLogin)
                                  return null;
                                if (v == null || v.trim().isEmpty)
                                  return 'Student ID is required';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _studentFirstNameController,
                              label: 'Firstname',
                              icon: _platformIcon(
                                cupertino: CupertinoIcons.person,
                                material: Icons.person,
                              ),
                              primary: primary,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z\s]'),
                                ),
                                UpperCaseTextFormatter(),
                              ],
                              validator: (v) {
                                if (_role != _AuthRole.student || _isLogin)
                                  return null;
                                if (v == null || v.trim().isEmpty)
                                  return 'Firstname is required';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _studentLastNameController,
                              label: 'Lastname',
                              icon: _platformIcon(
                                cupertino: CupertinoIcons.person,
                                material: Icons.person,
                              ),
                              primary: primary,
                              enabled: !_isLoading,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z\s]'),
                                ),
                                UpperCaseTextFormatter(),
                              ],
                              validator: (v) {
                                if (_role != _AuthRole.student || _isLogin)
                                  return null;
                                if (v == null || v.trim().isEmpty)
                                  return 'Lastname is required';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          // Student sign-in: require Student ID (School ID)
                          if (_role == _AuthRole.student && isSignIn) ...[
                            _buildField(
                              controller: _studentIdController,
                              label: 'Student ID',
                              icon: _platformIcon(
                                cupertino: CupertinoIcons.number,
                                material: Icons.confirmation_number,
                              ),
                              primary: primary,
                              validator: (v) {
                                if (_role != _AuthRole.student || !_isLogin)
                                  return null;
                                if (v == null || v.trim().isEmpty)
                                  return 'Student ID is required';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          // School field (teacher sign-up only)
                          if (_role == _AuthRole.teacher && !isSignIn) ...[
                            _buildField(
                              controller: _schoolController,
                              label: 'School *',
                              icon: _platformIcon(
                                cupertino: CupertinoIcons.building_2_fill,
                                material: Icons.school,
                              ),
                              primary: primary,
                              validator: (v) {
                                return v == null || v.trim().isEmpty
                                    ? 'School name is required'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          // Email (always)
                          _buildField(
                            controller: _emailController,
                            label: 'Email address',
                            icon: _platformIcon(
                              cupertino: CupertinoIcons.mail,
                              material: Icons.email,
                            ),
                            primary: primary,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Email is required';
                              if (!v.contains('@')) return 'Invalid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          // Password (always)
                          _buildPasswordField(primary),
                          // Confirm password (student sign-up only)
                          if (_role == _AuthRole.student && !isSignIn) ...[
                            const SizedBox(height: 14),
                            _buildConfirmPasswordField(primary),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildPrimaryButton(primary, secondary, isSignIn: isSignIn),
                    const SizedBox(height: 18),
                    if (!(_role == _AuthRole.student && !isSignIn)) ...[
                      _buildDivider(),
                      const SizedBox(height: 18),
                      _buildGoogleButton(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModePill(Color primary, {required bool isSignIn}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primary.withValues(alpha: 0.12),
                primary.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: primary.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _platformIcon(
                  cupertino: isSignIn
                      ? CupertinoIcons.arrow_right_to_line
                      : CupertinoIcons.person_badge_plus,
                  material: isSignIn ? Icons.login : Icons.person_add,
                ),
                color: primary,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                isSignIn ? 'Sign In' : 'Create Account',
                style: TextStyle(
                  color: primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Page indicator dots
        Row(
          children: [
            _pageDot(active: isSignIn, primary: primary),
            const SizedBox(width: 5),
            _pageDot(active: !isSignIn, primary: primary),
          ],
        ),
      ],
    );
  }

  Widget _pageDot({required bool active, required Color primary}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 18 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? primary : primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ── Role Switcher ─────────────────────────────────────────────────────────

  Widget _buildRoleSwitcher(Color primary) {
    return FadeTransition(
      opacity: _roleFade,
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _roleTabItem(
              label: 'Teacher',
              selected: _role == _AuthRole.teacher,
              primary: primary,
              icon: _platformIcon(
                cupertino: CupertinoIcons.person_2,
                material: Icons.person,
              ),
              onTap: () => _setRole(_AuthRole.teacher),
            ),
            _roleTabItem(
              label: 'Student',
              selected: _role == _AuthRole.student,
              primary: primary,
              icon: _platformIcon(
                cupertino: CupertinoIcons.book,
                material: Icons.school,
              ),
              onTap: () => _setRole(_AuthRole.student),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleTabItem({
    required String label,
    required bool selected,
    required Color primary,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      primary,
                      Color.lerp(primary, Colors.white, 0.15) ?? primary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF9098A3),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF9098A3),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmPasswordField(Color primary) {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: _fieldDecoration(
        label: 'Confirm Password',
        icon: _platformIcon(
          cupertino: CupertinoIcons.lock,
          material: Icons.lock_outline,
        ),
        primary: primary,
        suffix: IconButton(
          icon: Icon(
            _platformIcon(
              cupertino: _obscureConfirmPassword
                  ? CupertinoIcons.eye_slash
                  : CupertinoIcons.eye,
              material: _obscureConfirmPassword
                  ? Icons.visibility_off
                  : Icons.visibility,
            ),
            size: 19,
            color: const Color(0xFF9098A3),
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
          },
        ),
      ),
      validator: (v) {
        if (_role != _AuthRole.student || _isLogin) return null;
        if (v == null || v.isEmpty) return 'Please confirm your password';
        if (v != _passwordController.text) return 'Passwords do not match';
        return null;
      },
    );
  }

  // ── Error Banner ──────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF5F5), Color(0xFFFFF0F0)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: Color(0xFFE53935),
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFB71C1C),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(
              _platformIcon(
                cupertino: CupertinoIcons.xmark,
                material: Icons.close,
              ),
              color: const Color(0xFFE53935),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ── Input Fields ──────────────────────────────────────────────────────────

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required Color primary,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF9098A3),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF9098A3)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEAECF0), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.8),
      ),
      errorStyle: const TextStyle(fontSize: 11.5),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color primary,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: _fieldDecoration(label: label, icon: icon, primary: primary),
      validator: validator,
    );
  }

  Widget _buildPasswordField(Color primary) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: _fieldDecoration(
        label: 'Password',
        icon: _platformIcon(
          cupertino: CupertinoIcons.lock,
          material: Icons.lock_outline,
        ),
        primary: primary,
        suffix: IconButton(
          icon: Icon(
            _platformIcon(
              cupertino: _obscurePassword
                  ? CupertinoIcons.eye_slash
                  : CupertinoIcons.eye,
              material: _obscurePassword
                  ? Icons.visibility_off
                  : Icons.visibility,
            ),
            size: 19,
            color: const Color(0xFF9098A3),
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required';
        if (!_isLogin && v.length < 6)
          return 'Password must be at least 6 characters';
        return null;
      },
    );
  }

  // ── Primary Button ────────────────────────────────────────────────────────

  Widget _buildPrimaryButton(
    Color primary,
    Color secondary, {
    required bool isSignIn,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [primary, Color.lerp(primary, secondary, 0.55) ?? secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.40),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: primary.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _isLoading ? null : _handleEmailAuth,
          splashColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _platformIcon(
                          cupertino: isSignIn
                              ? CupertinoIcons.arrow_right_to_line
                              : CupertinoIcons.person_badge_plus,
                          material: isSignIn ? Icons.login : Icons.person_add,
                        ),
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSignIn ? 'Sign In' : 'Create Account',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Divider ───────────────────────────────────────────────────────────────

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: const Color(0xFFEAECF0), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(child: Divider(color: const Color(0xFFEAECF0), thickness: 1)),
      ],
    );
  }

  // ── Google Button ─────────────────────────────────────────────────────────

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        style:
            OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFDDE1E7), width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(const Color(0xFFF5F5F5)),
            ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GoogleLogo(size: 20),
            const SizedBox(width: 10),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: Color(0xFF3C4043),
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer Toggle ─────────────────────────────────────────────────────────

  Widget _buildFooterToggle() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _displayedIsLogin
                  ? "Don't have an account?"
                  : 'Already have an account?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _isFlipping ? null : _toggleMode,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _displayedIsLogin ? 'Sign Up' : 'Sign In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _platformIcon(
                        cupertino: CupertinoIcons.arrow_right,
                        material: Icons.arrow_forward,
                      ),
                      color: Colors.white,
                      size: 13,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Flip hint
        AnimatedOpacity(
          opacity: _isFlipping ? 0.0 : 0.55,
          duration: const Duration(milliseconds: 300),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _platformIcon(
                  cupertino: CupertinoIcons.arrow_left_right,
                  material: Icons.swap_horiz,
                ),
                color: Colors.white.withValues(alpha: 0.7),
                size: 12,
              ),
              const SizedBox(width: 6),
              Text(
                _isLogin ? 'Need an account?' : 'Already have an account?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11.5,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Google Logo Widget ────────────────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/google_logo.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GoogleGPainter()),
      ),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final double sw = s * 0.195;
    final double arcR = (s - sw) / 2;
    final Offset c = Offset(s / 2, s / 2);
    final Rect rect = Rect.fromCircle(center: c, radius: arcR);
    const double gap = 0.07;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      rect,
      -1.50,
      1.85 - gap,
      false,
      arcPaint..color = const Color(0xFFEA4335),
    );
    canvas.drawArc(
      rect,
      0.38,
      1.57 - gap,
      false,
      arcPaint..color = const Color(0xFFFBBC05),
    );
    canvas.drawArc(
      rect,
      1.98,
      1.57 - gap,
      false,
      arcPaint..color = const Color(0xFF34A853),
    );
    canvas.drawArc(
      rect,
      3.58,
      1.57 + gap * 2,
      false,
      arcPaint..color = const Color(0xFF4285F4),
    );

    final double midY = s / 2;
    final double crossLeft = s / 2 - sw * 0.08;
    final double rightEdge = s - sw * 0.1;
    canvas.drawRect(
      Rect.fromLTRB(crossLeft, midY - sw / 2, rightEdge, midY + sw / 2),
      Paint()..color = const Color(0xFF4285F4),
    );
    canvas.drawRect(
      Rect.fromLTRB(
        crossLeft - sw * 0.5,
        midY - sw / 2 - 1,
        crossLeft,
        midY + sw / 2 + 1,
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final String formattedText = newValue.text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
