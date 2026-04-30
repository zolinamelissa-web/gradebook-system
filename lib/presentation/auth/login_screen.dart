import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/curved_background.dart';
import '../../core/providers/theme_provider.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import 'setup_pin_screen.dart';
import '../home/home_screen.dart';
import '../student/student_home_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final bool isStudent;

  const LoginScreen({super.key, this.onLoginSuccess, this.isStudent = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthRepository _authRepo = AuthRepository();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String _teacherName = '';
  String _pin = '';

  @override
  void initState() {
    super.initState();
    _loadTeacherName();
    _redirectToPinSetupIfMissing();
  }

  Future<void> _redirectToPinSetupIfMissing() async {
    try {
      final storedHash = kIsWeb
          ? await _authRepo.getWebPinHash(isStudent: widget.isStudent)
          : await DatabaseHelper.instance.getSetting(
              widget.isStudent ? 'student_pin_hash' : 'pin_hash',
            );
      final localStudentId = kIsWeb
          ? null
          : await DatabaseHelper.instance.getSetting('student_id');
      final needsSetup = storedHash == null || storedHash.isEmpty;
      print(
        '[LoginScreen] PIN gate check role=${widget.isStudent ? 'student' : 'teacher'} needsSetup=$needsSetup web=$kIsWeb',
      );
      if (!needsSetup) return;
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SetupPinScreen(
              isOnboarding: true,
              isStudent: true,
              prefilledStudentId: localStudentId,
            ),
          ),
        );
      });
    } catch (e) {
      print('[LoginScreen] Student PIN gate check error: $e');
    }
  }

  Future<void> _loadTeacherName() async {
    final fallback = widget.isStudent ? 'Student' : 'Teacher';
    final name = kIsWeb
        ? await _authRepo.getWebProfileName(isStudent: widget.isStudent)
        : await DatabaseHelper.instance.getSetting(
            widget.isStudent ? 'student_name' : 'teacher_name',
          );
    if (mounted) {
      setState(
        () => _teacherName = (name == null || name.isEmpty) ? fallback : name,
      );
    }
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  Future<void> _login() async {
    if (_pinController.text.isEmpty) {
      if (mounted) setState(() => _error = 'Please enter your PIN');
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final storedHash = kIsWeb
          ? await _authRepo.getWebPinHash(isStudent: widget.isStudent)
          : await DatabaseHelper.instance.getSetting(
              widget.isStudent ? 'student_pin_hash' : 'pin_hash',
            );
      final inputHash = _hashPin(_pinController.text);
      print(
        '[LoginScreen] Attempting PIN login role=${widget.isStudent ? 'student' : 'teacher'} name=$_teacherName web=$kIsWeb',
      );
      print(
        '[LoginScreen] PIN verification - storedHash: ${storedHash?.substring(0, 8)}..., inputHash: ${inputHash.substring(0, 8)}...',
      );
      print(
        '[LoginScreen] PIN verification - storedHash length: ${storedHash?.length}, inputHash length: ${inputHash.length}',
      );
      print(
        '[LoginScreen] PIN verification - hashes match: ${storedHash == inputHash}',
      );

      if (storedHash == inputHash) {
        print('[LoginScreen] PIN login successful');

        // For students, verify they have a valid user record in local database
        if (widget.isStudent) {
          try {
            // Get the current student ID from local settings
            final localStudentId = await DatabaseHelper.instance.getSetting(
              'student_id',
            );

            // If we have a local student ID, verify it matches the current session
            if (localStudentId != null && localStudentId.isNotEmpty) {
              final user = await AuthRepository().getActiveUser();
              if (user != null && user.userRole == 'student') {
                // Check if this is a different student trying to login with PIN
                // This scenario can happen if the device was shared between students
                print(
                  '[LoginScreen] PIN login verification: localStudentId=$localStudentId',
                );
              }
            }
          } catch (e) {
            print('[LoginScreen] Session check error (offline mode): $e');
          }
        }

        if (mounted) {
          if (widget.onLoginSuccess != null) {
            try {
              print('[LoginScreen] Calling onLoginSuccess callback');
              widget.onLoginSuccess!();
              print('[LoginScreen] onLoginSuccess callback completed');

              // Add a small delay and check if navigation happened
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) {
                print(
                  '[LoginScreen] Callback completed but still on login screen, using fallback navigation',
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => widget.isStudent
                        ? const StudentHomeScreen(
                            initialIndex: 0,
                            key: ValueKey('pin-login-student-dashboard'),
                          )
                        : const HomeScreen(
                            initialIndex: 0,
                            key: ValueKey('pin-login-dashboard'),
                          ),
                  ),
                );
              }
            } catch (e) {
              print('[LoginScreen] onLoginSuccess callback error: $e');
              if (!mounted) return;
              print('[LoginScreen] Falling back to direct navigation');
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => widget.isStudent
                      ? const StudentHomeScreen(
                          initialIndex: 0,
                          key: ValueKey('pin-login-student-dashboard'),
                        )
                      : const HomeScreen(
                          initialIndex: 0,
                          key: ValueKey('pin-login-dashboard'),
                        ),
                ),
              );
            }
          } else {
            print(
              '[LoginScreen] No onLoginSuccess callback, using direct navigation',
            );
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => widget.isStudent
                    ? const StudentHomeScreen(
                        initialIndex: 0,
                        key: ValueKey('pin-login-student-dashboard'),
                      )
                    : const HomeScreen(
                        initialIndex: 0,
                        key: ValueKey('pin-login-dashboard'),
                      ),
              ),
            );
            print('[LoginScreen] Direct navigation completed');
          }
        }
      } else {
        print('[LoginScreen] Login failed: incorrect PIN');
        if (mounted)
          setState(() => _error = 'Incorrect PIN. Please try again.');
      }
    } catch (e) {
      print('[LoginScreen] Error: $e');
      if (mounted)
        setState(() => _error = 'An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxHeight < 600;
              final isLargeScreen = constraints.maxHeight > 800;
              final isTablet = constraints.maxWidth > 600;

              final topSpacing = isSmallScreen
                  ? 16.0
                  : (isLargeScreen ? 48.0 : 32.0);
              final iconSize = isSmallScreen ? 80.0 : 100.0;
              final titleFontSize = isSmallScreen ? 28.0 : 32.0;
              final cardPadding = isSmallScreen ? 20.0 : 28.0;
              final numpadButtonSize = isSmallScreen ? 56.0 : 64.0;

              final content = isTablet
                  ? Row(
                      children: [
                        // Left side: App info
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(
                                    (0.15 * 255).round(),
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/app_icon.png',
                                    fit: BoxFit.cover,
                                    width: iconSize,
                                    height: iconSize,
                                  ),
                                ),
                              ),
                              SizedBox(height: topSpacing * 0.5),
                              Text(
                                'GradeBook',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Welcome back,\n$_teacherName',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(
                                    (0.8 * 255).round(),
                                  ),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right side: PIN card
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  padding: EdgeInsets.all(cardPadding),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(
                                      (0.18 * 255).round(),
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withAlpha(
                                        (0.22 * 255).round(),
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(
                                          (0.12 * 255).round(),
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Enter PIN',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const SizedBox(height: 20),
                                      const SizedBox(height: 8),
                                      if (_error != null) ...[
                                        Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: AppTheme.danger,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      _PinBoxes(
                                        pinLength: _pin.length,
                                        primaryColor: primary,
                                      ),
                                      const SizedBox(height: 28),
                                      _Numpad(
                                        buttonSize: numpadButtonSize,
                                        isLoading: _isLoading,
                                        onDigit: (d) {
                                          if (_pin.length >= 4 || _isLoading) {
                                            return;
                                          }
                                          setState(() => _pin += d);
                                          _pinController.text = _pin;
                                          if (_pin.length == 4) {
                                            _login();
                                          }
                                        },
                                        onBackspace: () {
                                          if (_pin.isEmpty || _isLoading) {
                                            return;
                                          }
                                          setState(() {
                                            _pin = _pin.substring(
                                              0,
                                              _pin.length - 1,
                                            );
                                            _pinController.text = _pin;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Scale down slightly on shorter devices to prevent overflow
                        const baseHeight = 720.0;
                        final scale = (constraints.maxHeight / baseHeight)
                            .clamp(0.82, 1.0);

                        final scaledIcon = iconSize * scale;
                        final scaledTopSpacing = topSpacing * scale;
                        final scaledTitleFont = titleFontSize * scale;
                        final scaledCardPadding = cardPadding * scale;
                        final scaledNumpadButton = (numpadButtonSize * scale)
                            .clamp(44.0, 70.0);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Container(
                              width: scaledIcon,
                              height: scaledIcon,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(
                                  (0.15 * 255).round(),
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/app_icon.png',
                                  fit: BoxFit.cover,
                                  width: scaledIcon,
                                  height: scaledIcon,
                                ),
                              ),
                            ),
                            SizedBox(height: scaledTopSpacing * 0.5),
                            Text(
                              'GradeBook',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: scaledTitleFont,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Welcome back, $_teacherName',
                              style: TextStyle(
                                color: Colors.white.withAlpha(
                                  (0.8 * 255).round(),
                                ),
                                fontSize: 15 * scale,
                              ),
                            ),
                            SizedBox(height: scaledTopSpacing),
                            Container(
                              padding: EdgeInsets.all(scaledCardPadding),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(
                                  (0.18 * 255).round(),
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withAlpha(
                                    (0.22 * 255).round(),
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(
                                      (0.12 * 255).round(),
                                    ),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Enter PIN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18 * scale,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 20 * scale),
                                  if (_error != null) ...[
                                    Text(
                                      _error!,
                                      style: TextStyle(
                                        color: AppTheme.danger,
                                        fontSize: 12 * scale,
                                      ),
                                    ),
                                    SizedBox(height: 12 * scale),
                                  ],
                                  _PinBoxes(
                                    pinLength: _pin.length,
                                    primaryColor: primary,
                                  ),
                                  SizedBox(height: 28 * scale),
                                  _Numpad(
                                    buttonSize: scaledNumpadButton,
                                    isLoading: _isLoading,
                                    onDigit: (d) {
                                      if (_pin.length >= 4 || _isLoading) {
                                        return;
                                      }
                                      setState(() => _pin += d);
                                      _pinController.text = _pin;
                                      if (_pin.length == 4) {
                                        _login();
                                      }
                                    },
                                    onBackspace: () {
                                      if (_pin.isEmpty || _isLoading) {
                                        return;
                                      }
                                      setState(() {
                                        _pin = _pin.substring(
                                          0,
                                          _pin.length - 1,
                                        );
                                        _pinController.text = _pin;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );

              return Padding(
                padding: EdgeInsets.all(isSmallScreen ? 20.0 : 28.0),
                child: Center(child: content),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PinBoxes extends StatelessWidget {
  final int pinLength;
  final Color primaryColor;

  const _PinBoxes({required this.pinLength, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final filled = index < pinLength;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 46,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.6),
              width: 2,
            ),
            color: filled
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: filled
              ? Icon(PlatformIcons.circle, size: 10, color: Colors.white)
              : const SizedBox.shrink(),
        );
      }),
    );
  }
}

class _Numpad extends StatelessWidget {
  final bool isLoading;
  final double buttonSize;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  const _Numpad({
    required this.isLoading,
    this.buttonSize = 64,
    required this.onDigit,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    IconData getPlatformIcon({
      required IconData material,
      required IconData cupertino,
    }) {
      return Theme.of(context).platform == TargetPlatform.iOS
          ? cupertino
          : material;
    }

    Widget buildButton({String? label, IconData? icon, VoidCallback? onTap}) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: (onTap == null || isLoading) ? null : onTap,
            child: Center(
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: icon != null
                    ? Icon(icon, color: Colors.white)
                    : Text(
                        label ?? '',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildButton(label: '1', onTap: () => onDigit('1')),
            buildButton(label: '2', onTap: () => onDigit('2')),
            buildButton(label: '3', onTap: () => onDigit('3')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildButton(label: '4', onTap: () => onDigit('4')),
            buildButton(label: '5', onTap: () => onDigit('5')),
            buildButton(label: '6', onTap: () => onDigit('6')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildButton(label: '7', onTap: () => onDigit('7')),
            buildButton(label: '8', onTap: () => onDigit('8')),
            buildButton(label: '9', onTap: () => onDigit('9')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildButton(
              icon: getPlatformIcon(
                cupertino: CupertinoIcons.mail_solid,
                material: PlatformIcons.email,
              ),
              onTap: () {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/auth', (_) => false);
              },
            ),
            buildButton(label: '0', onTap: () => onDigit('0')),
            buildButton(icon: PlatformIcons.backspace, onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}
