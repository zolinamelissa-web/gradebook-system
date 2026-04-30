import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/painting.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/route_observer.dart';
import 'core/services/data_migration_runner.dart';
import 'core/utils/icon_fix.dart';
import 'data/database/database_helper.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/splash/splash_screen.dart';
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/auth/auth_screen.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/setup_pin_screen.dart';
import 'presentation/student/student_login_screen.dart';
import 'presentation/student/student_registration_screen.dart';
import 'presentation/student/student_home_screen.dart';
import 'presentation/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await IconFix.initialize();
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('[Firebase] Initialized with DefaultFirebaseOptions.currentPlatform');
  } on UnsupportedError catch (e) {
    print(
      '[Firebase] DefaultFirebaseOptions not configured for this platform: $e',
    );
    await Firebase.initializeApp();
    print(
      '[Firebase] Initialized with default options (GoogleService-Info.plist / bundled config)',
    );
  } catch (e) {
    print('[Firebase] Initialization error: $e');
    rethrow;
  }
  if (!kIsWeb) {
    await DatabaseHelper.instance.database;

    await DataMigrationRunner.checkAndRunMigrations();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const GradeBookApp(),
    ),
  );
}

class GradeBookApp extends StatelessWidget {
  const GradeBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        if (themeProvider.isLoading) {
          return MaterialApp(
            title: 'GradeBook',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return MaterialApp(
          title: 'GradeBook',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.getThemeData(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          navigatorObservers: [routeObserver],
          routes: {
            '/auth': (_) => const AuthScreen(),
            '/student-login': (_) => const StudentLoginScreen(),
            '/student-register': (_) => const StudentRegistrationScreen(),
            '/student-dashboard': (_) =>
                const StudentHomeScreen(initialIndex: 0),
          },
          home: const _AppRouter(),
        );
      },
    );
  }
}

class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  bool _isLoading = true;
  _RouteTarget _target = kIsWeb ? _RouteTarget.login : _RouteTarget.onboarding;
  final AuthRepository _authRepo = AuthRepository();

  @override
  void initState() {
    super.initState();
    _determineRoute();
  }

  Future<void> _determineRoute() async {
    var nextTarget = kIsWeb ? _RouteTarget.login : _RouteTarget.onboarding;
    try {
      if (kIsWeb) {
        final user = await _authRepo.getActiveUser();
        if (user == null) {
          nextTarget = _RouteTarget.auth;
        } else {
          final pinHash = await _authRepo.getWebPinHash(
            isStudent: user.userRole == 'student',
          );
          final hasPin = (pinHash ?? '').trim().isNotEmpty;
          print(
            '[AppRouter] Web route check user=${user.email} role=${user.userRole} hasPin=$hasPin',
          );
          if (user.userRole == 'student') {
            nextTarget = hasPin
                ? _RouteTarget.studentLogin
                : _RouteTarget.setupStudentPin;
          } else {
            nextTarget = hasPin ? _RouteTarget.login : _RouteTarget.setupPin;
          }
        }
      } else {
        final db = DatabaseHelper.instance;
        final user = await _authRepo.getActiveUser();
        final onboardingComplete = await db.getSetting('onboarding_complete');
        final pinHash = await db.getSetting('pin_hash');
        final studentPinHash = await db.getSetting('student_pin_hash');

        print(
          '[AppRouter] user=${user?.email} onboardingComplete=$onboardingComplete pinSet=${pinHash != null && pinHash.isNotEmpty}',
        );

        // Always prioritize onboarding if it has not been completed.
        // This is important on app reinstall where iOS may restore a Firebase
        // session, but the local SQLite settings were wiped.
        if (onboardingComplete != 'true') {
          nextTarget = _RouteTarget.onboarding;
        } else if (user == null) {
          // If there is no authenticated user session, use the first-time flow.
          nextTarget = _RouteTarget.auth;
        } else {
          if (user.userRole == 'student') {
            // Student sessions should use their own PIN gate.
            if (studentPinHash == null || studentPinHash.isEmpty) {
              nextTarget = _RouteTarget.setupStudentPin;
            } else {
              nextTarget = _RouteTarget.studentLogin;
            }
          } else {
            // User is already authenticated (including restored Firebase session on a new device).
            // Do not force onboarding again; just ensure PIN is set.
            if (pinHash == null || pinHash.isEmpty) {
              nextTarget = _RouteTarget.setupPin;
            } else {
              nextTarget = _RouteTarget.login;
            }
          }
        }
      }
    } catch (e) {
      print('[AppRouter] Error determining route: $e');
      nextTarget = _RouteTarget.onboarding;
    }

    print('[AppRouter] Route resolved: $nextTarget (was $_target)');

    if (!mounted) return;
    setState(() {
      _target = nextTarget;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    print(
      '[AppRouter] Building screen - target: $_target, isLoading: $_isLoading',
    );
    if (_isLoading) {
      return SplashScreen(nextScreen: _buildTargetScreen());
    }

    return _buildTargetScreen();
  }

  Widget _buildTargetScreen() {
    print('[AppRouter] _buildTargetScreen called with target: $_target');
    switch (_target) {
      case _RouteTarget.onboarding:
        print('[AppRouter] Building OnboardingScreen');
        // First-time experience / welcome flow.
        // After onboarding completes, navigate to auth screen for Google sign-in.
        return OnboardingScreen(
          onComplete: () async {
            if (!kIsWeb) {
              await DatabaseHelper.instance.setSetting(
                'onboarding_complete',
                'true',
              );
            }
            if (!mounted) return;

            // For new users after onboarding, go directly to setup PIN
            // This prevents the routing loop where unauthenticated users
            // get sent back to auth screen instead of setup
            _navigateTo(_RouteTarget.setupPin);
          },
        );
      case _RouteTarget.auth:
        return AuthScreen(
          onAuthSuccess: () => _navigateTo(_RouteTarget.setupPin),
        );
      case _RouteTarget.setupPin:
        return SetupPinScreen(
          isOnboarding: true,
          onComplete: () => _navigateTo(_RouteTarget.home),
        );
      case _RouteTarget.setupStudentPin:
        return SetupPinScreen(
          isOnboarding: true,
          isStudent: true,
          onComplete: () => _navigateTo(_RouteTarget.studentDashboard),
        );
      case _RouteTarget.login:
        print('[AppRouter] Building LoginScreen');
        return LoginScreen(
          onLoginSuccess: () {
            print(
              '[AppRouter] LoginScreen onLoginSuccess called, navigating to home',
            );
            _navigateTo(_RouteTarget.home);
          },
        );
      case _RouteTarget.studentLogin:
        return LoginScreen(
          isStudent: true,
          onLoginSuccess: () => _navigateTo(_RouteTarget.studentDashboard),
        );
      case _RouteTarget.home:
        print('[AppRouter] Building HomeScreen (Dashboard)');
        return const HomeScreen(initialIndex: 0);
      case _RouteTarget.studentDashboard:
        return const StudentHomeScreen(initialIndex: 0);
    }
  }

  void _navigateTo(_RouteTarget target) {
    print(
      '[AppRouter] _navigateTo called with target: $target, mounted: $mounted',
    );
    if (!mounted) {
      print('[AppRouter] Widget not mounted, cannot navigate');
      return;
    }
    print('[AppRouter] Navigating to: $target');
    setState(() {
      _target = target;
      print('[AppRouter] setState completed, new target: $_target');
    });
  }
}

enum _RouteTarget {
  onboarding,
  auth,
  setupPin,
  setupStudentPin,
  login,
  studentLogin,
  home,
  studentDashboard,
}
