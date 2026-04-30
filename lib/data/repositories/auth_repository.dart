import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../../core/services/auto_sync_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/student_sync_service.dart';
import 'student_account_repository.dart';

class MultiTeacherSelectionRequired implements Exception {
  final List<StudentTeacherLinkInfo> links;
  final String message;

  MultiTeacherSelectionRequired({required this.links, required this.message});

  @override
  String toString() => message;
}

class AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _webUserDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  Future<String?> getWebPinHash({required bool isStudent}) async {
    if (!kIsWeb) return null;
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    try {
      final doc = await _webUserDoc(firebaseUser.uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final key = isStudent ? 'student_pin_hash' : 'pin_hash';
      final value = settings[key]?.toString().trim();
      print(
        '[AuthRepository] Web PIN hash loaded role=${isStudent ? 'student' : 'teacher'} uid=${firebaseUser.uid} hasPin=${value != null && value.isNotEmpty}',
      );
      return value;
    } catch (e) {
      print(
        '[AuthRepository] Web PIN hash load error role=${isStudent ? 'student' : 'teacher'} uid=${firebaseUser.uid} error=$e',
      );
      rethrow;
    }
  }

  Future<String?> getWebProfileName({required bool isStudent}) async {
    if (!kIsWeb) return null;
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    try {
      final doc = await _webUserDoc(firebaseUser.uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final key = isStudent ? 'student_name' : 'teacher_name';
      final value = settings[key]?.toString().trim();
      final fallback = data['display_name']?.toString().trim();
      final resolved = value != null && value.isNotEmpty
          ? value
          : (fallback != null && fallback.isNotEmpty
                ? fallback
                : firebaseUser.displayName);
      print(
        '[AuthRepository] Web profile name loaded role=${isStudent ? 'student' : 'teacher'} uid=${firebaseUser.uid} name=${resolved ?? 'null'}',
      );
      return resolved;
    } catch (e) {
      print(
        '[AuthRepository] Web profile name load error role=${isStudent ? 'student' : 'teacher'} uid=${firebaseUser.uid} error=$e',
      );
      return firebaseUser.displayName;
    }
  }

  Future<void> saveWebPinProfile({
    required bool isStudent,
    required String name,
    String? schoolName,
    String? studentId,
    String? pinHash,
  }) async {
    if (!kIsWeb) return;
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      throw Exception('No authenticated Firebase user found for web PIN save.');
    }

    final trimmedName = name.trim();
    final trimmedSchool = (schoolName ?? '').trim();
    final trimmedStudentId = (studentId ?? '').trim();
    final payload = <String, dynamic>{
      'email': firebaseUser.email,
      'display_name': trimmedName.isNotEmpty
          ? trimmedName
          : (firebaseUser.displayName ?? ''),
      'photo_url': firebaseUser.photoURL,
      'user_role': isStudent ? 'student' : 'teacher',
      'updated_at': DateTime.now().toIso8601String(),
      'settings': <String, dynamic>{
        if (isStudent) 'student_name': trimmedName,
        if (!isStudent) 'teacher_name': trimmedName,
        if (!isStudent) 'school_name': trimmedSchool,
        if (isStudent) 'student_id': trimmedStudentId,
        (isStudent ? 'student_pin_hash' : 'pin_hash'): pinHash,
        'onboarding_complete': 'true',
      },
    };

    await _webUserDoc(firebaseUser.uid).set(payload, SetOptions(merge: true));
    if (trimmedName.isNotEmpty && firebaseUser.displayName != trimmedName) {
      await firebaseUser.updateDisplayName(trimmedName);
    }
    print(
      '[AuthRepository] Web PIN/profile saved role=${isStudent ? 'student' : 'teacher'} uid=${firebaseUser.uid} name=$trimmedName school=$trimmedSchool studentId=$trimmedStudentId hasPin=${pinHash != null && pinHash.isNotEmpty}',
    );
  }

  Future<firebase_auth.UserCredential> _signInWithGoogleOnWeb() async {
    print('[AuthRepository] Starting web Google Sign-In via Firebase popup');
    final provider = firebase_auth.GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    final credential = await _firebaseAuth.signInWithPopup(provider);
    print(
      '[AuthRepository] Web Google Sign-In popup completed email=${credential.user?.email}',
    );
    return credential;
  }

  Future<firebase_auth.User> _getWebGoogleUser() async {
    final currentUser = _firebaseAuth.currentUser;
    final hasGoogleProvider =
        currentUser?.providerData.any((p) => p.providerId == 'google.com') ??
        false;
    if (currentUser != null && hasGoogleProvider) {
      print(
        '[AuthRepository] Reusing existing web Google session uid=${currentUser.uid} email=${currentUser.email}',
      );
      return currentUser;
    }

    final userCredential = await _signInWithGoogleOnWeb();
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'null-user',
        message: 'Google Sign-In succeeded but Firebase returned a null user.',
      );
    }
    return firebaseUser;
  }

  Future<StudentTeacherLinkInfo?> _pickBestTeacherLinkByEnrollment(
    List<StudentTeacherLinkInfo> links,
  ) async {
    try {
      if (links.isEmpty) return null;
      if (links.length == 1) return links.first;

      print(
        '[AuthRepository] Selecting best teacher link by enrollments links=${links.length}',
      );

      for (final l in links) {
        final teacherUid = l.teacherUid.trim();
        final studentRemoteId = l.studentRemoteId.trim();
        if (teacherUid.isEmpty || studentRemoteId.isEmpty) continue;

        try {
          final snap = await _firestore
              .collection('users/$teacherUid/class_students')
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            print(
              '[AuthRepository] Selected teacherUid=$teacherUid by class_students enrollment match for studentRemoteId=$studentRemoteId',
            );
            return l;
          }
        } catch (e) {
          print(
            '[AuthRepository] Enrollment check failed teacherUid=$teacherUid studentRemoteId=$studentRemoteId: $e',
          );
        }
      }

      print(
        '[AuthRepository] No teacher link had enrollments; defaulting to first link teacherUid=${links.first.teacherUid}',
      );
      return links.first;
    } catch (e) {
      print('[AuthRepository] Error selecting best teacher link: $e');
      return links.isNotEmpty ? links.first : null;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      print('[AuthRepository] Starting Google Sign-In');

      if (kIsWeb) {
        final userCredential = await _signInWithGoogleOnWeb();
        final firebaseUser = userCredential.user;
        if (firebaseUser == null) {
          throw firebase_auth.FirebaseAuthException(
            code: 'null-user',
            message:
                'Google Sign-In succeeded but Firebase returned a null user.',
          );
        }
        await _checkTeacherAccountConflict(firebaseUser);
        final localUser = await _saveUserToDatabase(firebaseUser, 'google');
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
        print(
          '[AuthRepository] Web Google Sign-In successful isNewUser=$isNewUser localUserId=${localUser.id}',
        );
        return localUser;
      } else {
        print('[AuthRepository] Using mobile platform Google Sign-In');
        print('[AuthRepository] Attempting silent Google Sign-In...');
        GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
        print(
          '[AuthRepository] Silent Google Sign-In result: ${googleUser?.email ?? 'null'}',
        );

        print('[AuthRepository] Attempting interactive Google Sign-In...');
        googleUser ??= await _googleSignIn.signIn();
        if (googleUser == null) {
          print('[AuthRepository] Google Sign-In cancelled by user');
          return null;
        }

        return await _handleGoogleSignIn(googleUser);
      }
    } catch (e) {
      print('[AuthRepository] Google Sign-In error: $e');
      rethrow;
    }
  }

  Future<User?> _handleGoogleSignIn(GoogleSignInAccount googleUser) async {
    try {
      print('[AuthRepository] Google user selected: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      print(
        '[AuthRepository] Google auth tokens received: accessToken=${googleAuth.accessToken != null} idToken=${googleAuth.idToken != null}',
      );

      if ((googleAuth.accessToken == null || googleAuth.accessToken!.isEmpty) &&
          (googleAuth.idToken == null || googleAuth.idToken!.isEmpty)) {
        print(
          '[AuthRepository] Google Sign-In failed: missing both accessToken and idToken',
        );
        throw PlatformException(
          code: 'missing_google_auth_token',
          message:
              'Google Sign-In did not return authentication tokens (accessToken/idToken).',
        );
      }

      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase_auth.UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        print(
          '[AuthRepository] Student Google Sign-In failed: firebase user is null',
        );
        throw firebase_auth.FirebaseAuthException(
          code: 'null-user',
          message:
              'Google Sign-In succeeded but Firebase returned a null user.',
        );
      }

      print(
        '[AuthRepository] Google Sign-In successful: ${userCredential.user?.email}',
      );

      // Check for teacher account conflict before proceeding
      await _checkTeacherAccountConflict(firebaseUser);

      final localUser = await _saveUserToDatabase(firebaseUser, 'google');
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      print(
        '[AuthRepository] New user status: $isNewUser, Local user ID: ${localUser.id}',
      );

      return localUser;
    } on PlatformException catch (e) {
      print(
        '[AuthRepository] Google Sign-In PlatformException: code=${e.code} message=${e.message} details=${e.details}',
      );
      rethrow;
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[AuthRepository] Google Sign-In FirebaseAuthException: code=${e.code} message=${e.message}',
      );
      rethrow;
    } catch (e) {
      print('[AuthRepository] Google Sign-In error: $e');
      rethrow;
    }
  }

  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      print('[AuthRepository] Starting Email/Password Sign-In');
      final firebase_auth.UserCredential userCredential = await _firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password);

      print(
        '[AuthRepository] Email Sign-In successful: ${userCredential.user?.email}',
      );

      // Check for teacher account conflict before proceeding
      await _checkTeacherAccountConflict(userCredential.user!);

      return await _saveUserToDatabase(userCredential.user!, 'email');
    } catch (e) {
      print('[AuthRepository] Email Sign-In error: $e');
      rethrow;
    }
  }

  Future<User?> signUpWithEmailPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      print('[AuthRepository] Starting Email/Password Sign-Up');
      final firebase_auth.UserCredential userCredential = await _firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      await userCredential.user?.updateDisplayName(displayName);
      await userCredential.user?.reload();
      final updatedUser = _firebaseAuth.currentUser;
      if (updatedUser == null) {
        throw firebase_auth.FirebaseAuthException(
          code: 'null-user',
          message: 'Email sign-up succeeded but Firebase returned a null user.',
        );
      }

      print('[AuthRepository] Email Sign-Up successful: ${updatedUser.email}');

      // Check for teacher account conflict before proceeding
      await _checkTeacherAccountConflict(updatedUser);

      return await _saveUserToDatabase(updatedUser, 'email');
    } catch (e) {
      print('[AuthRepository] Email Sign-Up error: $e');
      rethrow;
    }
  }

  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    try {
      final methods = await _firebaseAuth.fetchSignInMethodsForEmail(email);
      print(
        '[AuthRepository] fetchSignInMethodsForEmail email=$email methods=$methods',
      );
      return methods;
    } catch (e) {
      print(
        '[AuthRepository] fetchSignInMethodsForEmail error email=$email error=$e',
      );
      rethrow;
    }
  }

  Future<void> linkEmailPasswordToCurrentUser({
    required String email,
    required String password,
  }) async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) {
        throw firebase_auth.FirebaseAuthException(
          code: 'no-current-user',
          message: 'No authenticated user found.',
        );
      }

      final credential = firebase_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await currentUser.linkWithCredential(credential);
      await currentUser.reload();
      final refreshedUser = _firebaseAuth.currentUser;

      if (refreshedUser == null) {
        throw firebase_auth.FirebaseAuthException(
          code: 'null-user',
          message: 'Account linking succeeded but the refreshed user is null.',
        );
      }

      print(
        '[AuthRepository] linkEmailPasswordToCurrentUser success uid=${refreshedUser.uid} email=${refreshedUser.email}',
      );

      // Check for teacher account conflict before proceeding
      await _checkTeacherAccountConflict(refreshedUser);

      await _saveUserToDatabase(refreshedUser, 'email');
    } catch (e) {
      print(
        '[AuthRepository] linkEmailPasswordToCurrentUser error email=$email error=$e',
      );
      rethrow;
    }
  }

  Future<User> _saveUserToDatabase(
    firebase_auth.User firebaseUser,
    String provider,
  ) async {
    if (kIsWeb) {
      final now = DateTime.now().toIso8601String();
      print(
        '[AuthRepository] Web platform detected, using Firebase user without SQLite save: ${firebaseUser.email}',
      );
      return User(
        uid: firebaseUser.uid,
        email: firebaseUser.email,
        displayName: firebaseUser.displayName,
        photoUrl: firebaseUser.photoURL,
        provider: provider,
        createdAt: now,
        updatedAt: now,
      );
    }

    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    final user = User(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      displayName: firebaseUser.displayName,
      photoUrl: firebaseUser.photoURL,
      provider: provider,
      createdAt: now,
      updatedAt: now,
    );

    final existing = await db.query(
      'users',
      where: 'uid = ?',
      whereArgs: [firebaseUser.uid],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'users',
        {
          'email': user.email,
          'display_name': user.displayName,
          'photo_url': user.photoUrl,
          'provider': provider,
          'is_active': 1,
          'updated_at': now,
        },
        where: 'uid = ?',
        whereArgs: [firebaseUser.uid],
      );
      print('[AuthRepository] Updated existing user in SQLite: ${user.email}');
      return user.copyWith(id: existing.first['id'] as int);
    } else {
      final id = await db.insert(
        'users',
        user.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[AuthRepository] Saved new user to SQLite: ${user.email}');
      return user.copyWith(id: id);
    }
  }

  Future<User?> getActiveUser() async {
    if (kIsWeb) {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) return null;

      print(
        '[AuthRepository] Web platform detected, resolving active user from Firebase only: ${firebaseUser.email}',
      );

      try {
        final studentInfo =
            await StudentAccountRepository.getStudentAccountByUid(
              firebaseUser.uid,
            );
        if (studentInfo != null) {
          final now = DateTime.now().toIso8601String();
          return User(
            uid: firebaseUser.uid,
            email: firebaseUser.email,
            displayName: firebaseUser.displayName ?? studentInfo.displayName,
            photoUrl: firebaseUser.photoURL,
            provider: firebaseUser.providerData.isNotEmpty
                ? firebaseUser.providerData.first.providerId
                : 'google',
            userRole: 'student',
            createdAt: now,
            updatedAt: now,
          );
        }
      } catch (e) {
        print('[AuthRepository] Web student account lookup error: $e');
      }

      final now = DateTime.now().toIso8601String();
      return User(
        uid: firebaseUser.uid,
        email: firebaseUser.email,
        displayName: firebaseUser.displayName,
        photoUrl: firebaseUser.photoURL,
        provider: firebaseUser.providerData.isNotEmpty
            ? firebaseUser.providerData.first.providerId
            : 'google',
        userRole: 'teacher',
        createdAt: now,
        updatedAt: now,
      );
    }

    final db = await _db.database;
    final maps = await db.query('users', where: 'is_active = 1', limit: 1);
    if (maps.isNotEmpty) return User.fromMap(maps.first);

    // If the device has a persisted Firebase session (common on a new device
    // after Google sign-in or app reinstall), the local SQLite may not yet have a user row.
    // In that case, check if this is a student account and mirror appropriately.
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    print(
      '[AuthRepository] No active local user found; checking if Firebase user is student: ${firebaseUser.email}',
    );

    // Check if this user is a student by looking up in student_accounts
    try {
      final studentInfo = await StudentAccountRepository.getStudentAccountByUid(
        firebaseUser.uid,
      );

      if (studentInfo != null) {
        print(
          '[AuthRepository] Firebase user is a student: ${studentInfo.studentId}',
        );

        // Reset database if different student is detected
        await _resetDatabaseForDifferentStudent(studentInfo.studentId);

        // Save as student user
        final localUser = await _saveStudentUserToDatabase(
          firebaseUser,
          firebaseUser.providerData.isNotEmpty
              ? (firebaseUser.providerData.first.providerId)
              : 'google',
          studentInfo,
        );
        return localUser;
      }
    } catch (e) {
      print('[AuthRepository] Error checking student account: $e');
    }

    // Not a student, save as teacher
    print('[AuthRepository] Firebase user is a teacher: ${firebaseUser.email}');

    // Check for teacher account conflict before proceeding
    await _checkTeacherAccountConflict(firebaseUser);

    final localUser = await _saveUserToDatabase(
      firebaseUser,
      firebaseUser.providerData.isNotEmpty
          ? (firebaseUser.providerData.first.providerId)
          : 'google',
    );
    return localUser;
  }

  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
      await _googleSignIn.signOut();

      await StudentAccountRepository.clearActiveTeacherContext();

      if (kIsWeb) {
        print('[AuthRepository] Signed out successfully');
        return;
      }

      final db = await _db.database;
      await db.update('users', {'is_active': 0}, where: 'is_active = 1');

      print('[AuthRepository] Signed out successfully');
    } catch (e) {
      print('[AuthRepository] Sign-out error: $e');
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        await user.delete();
      }

      if (kIsWeb) {
        print('[AuthRepository] Account deleted');
        return;
      }

      final db = await _db.database;
      await db.delete('users', where: 'uid = ?', whereArgs: [user?.uid]);

      print('[AuthRepository] Account deleted');
    } catch (e) {
      print('[AuthRepository] Delete account error: $e');
      rethrow;
    }
  }

  firebase_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser;

  Future<firebase_auth.User>
  _ensureTeacherAuthenticatedForRemoteAction() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser != null) {
      print(
        '[AuthRepository] Remote action using existing Firebase user: ${currentUser.email}',
      );
      return currentUser;
    }

    final activeUser = await getActiveUser();
    if (activeUser == null) {
      throw Exception('No active teacher session found. Please sign in again.');
    }

    if (activeUser.userRole != 'teacher') {
      throw Exception('Teacher account is required to reset student password.');
    }

    print(
      '[AuthRepository] No Firebase user for remote action. Attempting restore for provider=${activeUser.provider} email=${activeUser.email}',
    );

    if (activeUser.provider == 'google') {
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;
        if ((googleAuth.accessToken != null &&
                googleAuth.accessToken!.isNotEmpty) ||
            (googleAuth.idToken != null && googleAuth.idToken!.isNotEmpty)) {
          final credential = firebase_auth.GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          final userCredential = await _firebaseAuth.signInWithCredential(
            credential,
          );
          final restoredUser = userCredential.user;
          if (restoredUser != null) {
            print(
              '[AuthRepository] Restored Firebase teacher session via Google: ${restoredUser.email}',
            );
            return restoredUser;
          }
        }
      }
    }

    throw Exception(
      'Teacher must be authenticated online to reset student password. Please sign in again with your teacher account.',
    );
  }

  // ────────────────────────────────────────────────────────────
  // STUDENT AUTHENTICATION
  // ────────────────────────────────────────────────────────────

  /// Register a student account using Student ID and Firebase Auth
  Future<User?> registerStudentAccount({
    required String studentId,
    String? teacherUid,
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      print('[AuthRepository] Starting student registration for: $studentId');

      final links = await StudentAccountRepository.getTeacherLinksForStudentId(
        studentId,
      );
      if (links.isEmpty) {
        print('[AuthRepository] Student ID not found: $studentId');
        throw Exception('Student ID not found. Please contact your teacher.');
      }

      if (teacherUid == null || teacherUid.isEmpty) {
        if (links.length == 1) {
          teacherUid = links.first.teacherUid;
        } else {
          final best = await _pickBestTeacherLinkByEnrollment(links);
          teacherUid = (best?.teacherUid ?? links.first.teacherUid).trim();
          print(
            '[AuthRepository] Multi-teacher registration auto-selected teacherUid=$teacherUid studentId=$studentId links=${links.length}',
          );
        }
      }

      final String resolvedTeacherUid = teacherUid.trim();
      if (resolvedTeacherUid.isEmpty) {
        throw Exception('Teacher selection is required.');
      }

      final studentInfo =
          await StudentAccountRepository.getStudentAccountInfoForTeacher(
            studentId: studentId,
            teacherUid: resolvedTeacherUid,
          );
      if (studentInfo == null) {
        print(
          '[AuthRepository] Student info not found for teacher selection studentId=$studentId teacherUid=$teacherUid',
        );
        throw Exception('Student record not found for selected teacher.');
      }

      if (studentInfo.isRegistered) {
        print('[AuthRepository] Student ID already registered: $studentId');
        throw Exception(
          'This Student ID is already registered. Please login instead.',
        );
      }

      // Create Firebase Auth account
      final firebase_auth.UserCredential userCredential = await _firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      // Update display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await userCredential.user?.updateDisplayName(displayName);
        await userCredential.user?.reload();
      }

      final updatedUser = _firebaseAuth.currentUser;
      print(
        '[AuthRepository] Firebase Auth account created: ${updatedUser?.email}',
      );

      // Register the student account (link Firebase UID to Student ID)
      final registrationSuccess =
          await StudentAccountRepository.registerStudentAccount(
            studentId: studentId,
            teacherUid: teacherUid,
            firebaseUid: updatedUser!.uid,
            email: email,
          );

      if (!registrationSuccess) {
        print(
          '[AuthRepository] Failed to register student account in Firestore',
        );
        throw Exception('Failed to complete registration. Please try again.');
      }

      // Reset database if different student is signing in
      await _resetDatabaseForDifferentStudent(studentId);

      // Save user to local database with student role
      final localUser = await _saveStudentUserToDatabase(
        updatedUser,
        'email',
        studentInfo,
      );

      // Ensure the student session is locked to the selected teacher.
      await StudentAccountRepository.setActiveTeacherContext(
        studentId: studentId,
        teacherUid: resolvedTeacherUid,
      );

      try {
        if (kIsWeb) {
          print(
            '[AuthRepository] Web platform detected, skipping local student settings save after registration student_id=$studentId',
          );
        } else {
          await DatabaseHelper.instance.setSetting('student_id', studentId);
          if ((studentInfo.displayName).trim().isNotEmpty) {
            await DatabaseHelper.instance.setSetting(
              'student_name',
              studentInfo.displayName.trim(),
            );
          }
        }
        print(
          '[AuthRepository] Saved local student settings after registration student_id=$studentId student_name=${studentInfo.displayName.trim()}',
        );
      } catch (e) {
        print(
          '[AuthRepository] Save local student settings after registration error: $e',
        );
      }

      print('[AuthRepository] Student registration complete: $studentId');
      return localUser;
    } catch (e) {
      print('[AuthRepository] Student registration error: $e');
      rethrow;
    }
  }

  /// Sign in student with email/password
  Future<User?> signInStudentWithEmailPassword(
    String email,
    String password, {
    String? teacherUid,
    String? studentId,
  }) async {
    try {
      print('[AuthRepository] Starting student email sign-in');

      final firebase_auth.UserCredential userCredential = await _firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password);

      print(
        '[AuthRepository] Student email sign-in successful: ${userCredential.user?.email}',
      );

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw firebase_auth.FirebaseAuthException(
          code: 'null-user',
          message: 'Email sign-in succeeded but Firebase returned a null user.',
        );
      }

      // Get student account info from Firestore
      final uid = firebaseUser.uid;
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        uid,
      );
      if (links.isEmpty) {
        // Primary fallback: use provided Student ID (School ID) to resolve the
        // student_account doc and rebuild teacher links with this firebase uid.
        final providedStudentId = (studentId ?? '').trim();
        if (providedStudentId.isNotEmpty) {
          print(
            '[AuthRepository] No teacher links by uid=$uid; attempting fallback by studentId=$providedStudentId',
          );
          final byIdLinks =
              await StudentAccountRepository.getTeacherLinksForStudentId(
                providedStudentId,
                firebaseUid: uid,
              );
          links.addAll(byIdLinks);
          print(
            '[AuthRepository] Fallback by studentId completed uid=$uid links=${byIdLinks.length}',
          );
        }

        // Fallback: attempt to resolve studentId from legacy root-doc mapping
        // then rebuild teacher links by scanning users/*/students.
        final legacyStudentId =
            await StudentAccountRepository.getStudentIdForFirebaseUid(uid);
        if (legacyStudentId.isNotEmpty && links.isEmpty) {
          final fallbackLinks =
              await StudentAccountRepository.getTeacherLinksForStudentId(
                legacyStudentId,
                firebaseUid: uid,
              );
          links.addAll(fallbackLinks);
        }

        // Recovery: if mappings were wiped (firebase_uid removed), attempt to
        // rebuild teacher links by scanning teacher student collections using
        // the login email.
        if (links.isEmpty) {
          print(
            '[AuthRepository] No teacher links for uid=$uid; attempting recovery by email=$email',
          );
          final recovered =
              await StudentAccountRepository.recoverTeacherLinksByEmail(
                firebaseUid: uid,
                email: email,
              );
          links.addAll(recovered);
          print(
            '[AuthRepository] Recovery by email completed uid=$uid recoveredLinks=${recovered.length}',
          );
        }
        if (links.isEmpty) {
          throw Exception(
            'No student account found. Please contact your teacher.',
          );
        }
      }

      if (teacherUid == null || teacherUid.isEmpty) {
        if (links.length == 1) {
          teacherUid = links.first.teacherUid;
        } else {
          final best = await _pickBestTeacherLinkByEnrollment(links);
          if (best != null) {
            teacherUid = best.teacherUid;
          } else {
            print(
              '[AuthRepository] Multi-teacher login requires selection uid=$uid links=${links.length}',
            );
            throw MultiTeacherSelectionRequired(
              links: links,
              message: 'Multiple teachers found. Please select your teacher.',
            );
          }
        }
      }

      final String resolvedTeacherUid = teacherUid;

      final resolvedStudentId = links
          .firstWhere(
            (l) => l.teacherUid == resolvedTeacherUid,
            orElse: () => links.first,
          )
          .studentId;

      final studentInfo =
          await StudentAccountRepository.getStudentAccountInfoForTeacher(
            studentId: resolvedStudentId,
            teacherUid: resolvedTeacherUid,
          );

      if (studentInfo == null) {
        print(
          '[AuthRepository] No student info found for selected teacher uid=$uid teacherUid=$teacherUid',
        );
        throw Exception('Student record not found for selected teacher.');
      }

      // Reset database if different student is signing in
      await _resetDatabaseForDifferentStudent(resolvedStudentId);

      await StudentAccountRepository.setActiveTeacherContext(
        studentId: resolvedStudentId,
        teacherUid: resolvedTeacherUid,
      );

      try {
        if (kIsWeb) {
          print(
            '[AuthRepository] Web platform detected, skipping local student settings save after email login student_id=$resolvedStudentId',
          );
        } else {
          await DatabaseHelper.instance.setSetting(
            'student_id',
            resolvedStudentId,
          );
          if ((studentInfo.displayName).trim().isNotEmpty) {
            await DatabaseHelper.instance.setSetting(
              'student_name',
              studentInfo.displayName.trim(),
            );
          }
        }
        print(
          '[AuthRepository] Saved local student settings after email login student_id=$resolvedStudentId student_name=${studentInfo.displayName.trim()}',
        );
      } catch (e) {
        print(
          '[AuthRepository] Save local student settings after email login error: $e',
        );
      }

      // Save user to local database with student role
      final localUser = await _saveStudentUserToDatabase(
        firebaseUser,
        'email',
        studentInfo,
      );

      // Trigger student data sync
      _triggerStudentDataSync(studentInfo);

      return localUser;
    } catch (e) {
      print('[AuthRepository] Student email sign-in error: $e');
      rethrow;
    }
  }

  /// Sign in student with Google
  Future<User?> signInStudentWithGoogle() async {
    return signInStudentWithGoogleAndTeacher();
  }

  Future<User?> signInStudentWithGoogleAndTeacher({String? teacherUid}) async {
    try {
      print('[AuthRepository] Starting student Google Sign-In');
      late final firebase_auth.User firebaseUser;

      if (kIsWeb) {
        firebaseUser = await _getWebGoogleUser();
      } else {
        GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
        print(
          '[AuthRepository] Silent Google Sign-In result: ${googleUser?.email ?? 'null'}',
        );

        googleUser ??= await _googleSignIn.signIn();
        if (googleUser == null) {
          print('[AuthRepository] Google Sign-In cancelled by user');
          return null;
        }

        print('[AuthRepository] Google user selected: ${googleUser.email}');

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        if ((googleAuth.accessToken == null ||
                googleAuth.accessToken!.isEmpty) &&
            (googleAuth.idToken == null || googleAuth.idToken!.isEmpty)) {
          print(
            '[AuthRepository] Student Google Sign-In failed: missing both accessToken and idToken',
          );
          throw PlatformException(
            code: 'missing_google_auth_token',
            message:
                'Google Sign-In did not return authentication tokens (accessToken/idToken).',
          );
        }

        final credential = firebase_auth.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _firebaseAuth.signInWithCredential(
          credential,
        );
        final signedInUser = userCredential.user;
        if (signedInUser == null) {
          print(
            '[AuthRepository] Student Google Sign-In failed: firebase user is null',
          );
          throw firebase_auth.FirebaseAuthException(
            code: 'null-user',
            message:
                'Google Sign-In succeeded but Firebase returned a null user.',
          );
        }
        firebaseUser = signedInUser;
      }

      print(
        '[AuthRepository] Student Google Sign-In successful: ${firebaseUser.email}',
      );

      // Get student account info from Firestore
      final uid = firebaseUser.uid;
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        uid,
      );
      if (links.isEmpty) {
        // Fallback: attempt to resolve studentId from legacy root-doc mapping
        // then rebuild teacher links by scanning users/*/students.
        final studentId =
            await StudentAccountRepository.getStudentIdForFirebaseUid(uid);
        if (studentId.isNotEmpty) {
          final fallbackLinks =
              await StudentAccountRepository.getTeacherLinksForStudentId(
                studentId,
                firebaseUid: uid,
              );
          links.addAll(fallbackLinks);
        }
        if (links.isEmpty) {
          throw Exception(
            'No student account found. Please contact your teacher.',
          );
        }
      }

      if (teacherUid == null || teacherUid.isEmpty) {
        if (links.length == 1) {
          teacherUid = links.first.teacherUid;
        } else {
          print(
            '[AuthRepository] Multi-teacher Google login requires selection uid=$uid links=${links.length}',
          );
          throw MultiTeacherSelectionRequired(
            links: links,
            message: 'Multiple teachers found. Please select your teacher.',
          );
        }
      }

      if (teacherUid == null || teacherUid.isEmpty) {
        throw Exception('Teacher selection is required.');
      }
      final String resolvedTeacherUid = teacherUid;

      final studentId = links
          .firstWhere(
            (l) => l.teacherUid == resolvedTeacherUid,
            orElse: () => links.first,
          )
          .studentId;

      final studentInfo =
          await StudentAccountRepository.getStudentAccountInfoForTeacher(
            studentId: studentId,
            teacherUid: resolvedTeacherUid,
          );

      if (studentInfo == null) {
        print(
          '[AuthRepository] No student info found for selected teacher uid=$uid teacherUid=$teacherUid',
        );
        throw Exception('Student record not found for selected teacher.');
      }

      // Reset database if different student is signing in
      await _resetDatabaseForDifferentStudent(studentId);

      await StudentAccountRepository.setActiveTeacherContext(
        studentId: studentId,
        teacherUid: resolvedTeacherUid,
      );

      // Save user to local database with student role
      final localUser = await _saveStudentUserToDatabase(
        firebaseUser,
        'google',
        studentInfo,
      );

      // Trigger student data sync
      _triggerStudentDataSync(studentInfo);

      return localUser;
    } on PlatformException catch (e) {
      print('[AuthRepository] Student Google Sign-In PlatformException: $e');
      rethrow;
    } on firebase_auth.FirebaseAuthException catch (e) {
      print(
        '[AuthRepository] Student Google Sign-In FirebaseAuthException: $e',
      );
      rethrow;
    } catch (e) {
      print('[AuthRepository] Student Google Sign-In error: $e');
      rethrow;
    }
  }

  /// Check if a different teacher account is trying to sign in/sign up
  /// Blocks the operation to prevent data leakage between teacher accounts
  Future<void> _checkTeacherAccountConflict(
    firebase_auth.User firebaseUser,
  ) async {
    if (kIsWeb) {
      print(
        '[AuthRepository] Web platform detected, skipping local teacher account conflict check uid=${firebaseUser.uid}',
      );
      return;
    }

    try {
      final db = await _db.database;
      final existingUsers = await db.query(
        'users',
        where: 'userRole = ? AND is_active = 1',
        whereArgs: ['teacher'],
        limit: 1,
      );

      if (existingUsers.isNotEmpty) {
        final existingTeacher = existingUsers.first;
        final existingTeacherEmail = existingTeacher['email'] as String?;
        final existingTeacherUid = existingTeacher['uid'] as String?;

        print(
          '[AuthRepository] Existing teacher account found: email=$existingTeacherEmail uid=$existingTeacherUid',
        );
        print(
          '[AuthRepository] New teacher attempting to sign in: email=${firebaseUser.email} uid=${firebaseUser.uid}',
        );

        // Check if this is a different teacher account
        if (existingTeacherUid != firebaseUser.uid) {
          print(
            '[AuthRepository] Teacher account conflict detected - blocking sign-in',
          );
          throw Exception(
            'This device already has a teacher account registered ($existingTeacherEmail). '
            'For security reasons, only one teacher account can be used per device. '
            'Please use the existing account or contact support for assistance.',
          );
        } else {
          print('[AuthRepository] Same teacher account - allowing sign-in');
        }
      } else {
        print(
          '[AuthRepository] No existing teacher account found - allowing sign-in',
        );
      }
    } catch (e) {
      if (e.toString().contains('This device already has a teacher account')) {
        rethrow; // Re-throw our custom exception
      }
      print('[AuthRepository] Error during teacher account conflict check: $e');
      // Don't block sign-in due to check errors, but log the issue
    }
  }

  /// Reset local database if a different student account is detected
  Future<void> _resetDatabaseForDifferentStudent(String newStudentId) async {
    if (kIsWeb) {
      print(
        '[AuthRepository] Web platform detected, skipping local database reset for student_id=$newStudentId',
      );
      return;
    }

    try {
      final currentStudentId = await _db.getSetting('student_id');

      if (currentStudentId != null &&
          currentStudentId.isNotEmpty &&
          currentStudentId != newStudentId) {
        print(
          '[AuthRepository] Different student detected: current=$currentStudentId, new=$newStudentId',
        );
        print(
          '[AuthRepository] Resetting local database to prevent data leakage',
        );

        // Reset the entire database
        await _db.resetDatabase();

        print(
          '[AuthRepository] Database reset completed for student account switch',
        );
      } else {
        print(
          '[AuthRepository] Same student or no previous student: current=$currentStudentId, new=$newStudentId',
        );
      }
    } catch (e) {
      print('[AuthRepository] Error during database reset check: $e');
      // Don't throw error to prevent login failure, but log the issue
    }
  }

  /// Save student user to local database
  Future<User> _saveStudentUserToDatabase(
    firebase_auth.User firebaseUser,
    String provider,
    StudentAccountInfo studentInfo,
  ) async {
    if (kIsWeb) {
      final now = DateTime.now().toIso8601String();
      print(
        '[AuthRepository] Web platform detected, using Firebase student user without SQLite save: ${firebaseUser.email}',
      );
      return User(
        uid: firebaseUser.uid,
        email: firebaseUser.email,
        displayName: firebaseUser.displayName ?? studentInfo.displayName,
        photoUrl: firebaseUser.photoURL,
        provider: provider,
        userRole: 'student',
        createdAt: now,
        updatedAt: now,
      );
    }

    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    final user = User(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      displayName: firebaseUser.displayName ?? studentInfo.displayName,
      photoUrl: firebaseUser.photoURL,
      provider: provider,
      userRole: 'student',
      linkedStudentId:
          null, // We'll link this after getting the local student ID
      createdAt: now,
      updatedAt: now,
    );

    final existing = await db.query(
      'users',
      where: 'uid = ?',
      whereArgs: [firebaseUser.uid],
    );

    if (existing.isNotEmpty) {
      final updateMap = user.toMap()..remove('id');
      await db.update(
        'users',
        updateMap,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      print('[AuthRepository] Updated existing student user in database');
      return user.copyWith(id: existing.first['id'] as int);
    } else {
      final insertMap = user.toMap()..remove('id');
      final id = await db.insert('users', insertMap);
      print(
        '[AuthRepository] Inserted new student user to database with id: $id',
      );
      return user.copyWith(id: id);
    }
  }

  /// Trigger student data sync after login
  void _triggerStudentDataSync(StudentAccountInfo studentInfo) {
    AutoSyncService.hasInternetConnection()
        .then((hasInternet) {
          if (!hasInternet) {
            print('[AuthRepository] Student data sync skipped: no internet');
            return;
          }
          print(
            '[AuthRepository] Starting student data sync for firebaseUid...',
          );

          // Get the current Firebase user UID
          final firebaseUser = _firebaseAuth.currentUser;
          if (firebaseUser == null) {
            print(
              '[AuthRepository] Student data sync failed: no Firebase user',
            );
            return;
          }

          print(
            '[AuthRepository] Student data sync direction=download firebaseUid=${firebaseUser.uid}',
          );
          StudentSyncService.syncStudentData(
                firebaseUid: firebaseUser.uid,
                direction: 'download',
                onStatusUpdate: (status) {
                  print('[AuthRepository] Student sync status: $status');
                },
              )
              .then((result) {
                print(
                  '[AuthRepository] Student data sync finished: uploaded=${result.uploaded} downloaded=${result.downloaded}',
                );
              })
              .catchError((e) {
                print('[AuthRepository] Student data sync failed: $e');
              });
        })
        .catchError((e) {
          print(
            '[AuthRepository] Student data sync connectivity check failed: $e',
          );
        });
  }

  /// Reset student password to temporary password "TempPassword123"
  /// Requires internet connection and student's email
  /// Uses Firebase Cloud Functions to reset password via Admin SDK
  Future<void> resetStudentPassword(String studentEmail) async {
    try {
      print('[AuthRepository] Resetting password for student: $studentEmail');

      final currentUser = await _ensureTeacherAuthenticatedForRemoteAction();
      print(
        '[AuthRepository] Reset password teacher auth verified: uid=${currentUser.uid} email=${currentUser.email}',
      );

      // Call Cloud Function to reset password
      // The Cloud Function should be deployed with this code:
      // exports.resetStudentPassword = functions.https.onCall(async (data, context) => {
      //   if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
      //   const email = data.email;
      //   const user = await admin.auth().getUserByEmail(email);
      //   await admin.auth().updateUser(user.uid, { password: 'TempPassword123' });
      //   return { success: true };
      // });

      final callable = FirebaseFunctions.instance.httpsCallable(
        'resetStudentPassword',
      );
      final result = await callable.call({'email': studentEmail});

      if (result.data['success'] == true) {
        print('[AuthRepository] Password reset successful for: $studentEmail');
      } else {
        throw Exception('Password reset failed');
      }
    } on FirebaseFunctionsException catch (e) {
      print('[AuthRepository] Cloud Function error: ${e.code} - ${e.message}');
      if (e.code == 'not-found') {
        throw Exception(
          'Cloud Function not deployed. Please deploy the resetStudentPassword function.',
        );
      }
      rethrow;
    } catch (e) {
      print('[AuthRepository] Reset student password error: $e');
      rethrow;
    }
  }

  /// Migrate existing student emails from student_accounts to students collection
  /// This fixes students who signed up before the email sync fix
  Future<Map<String, dynamic>> migrateStudentEmails() async {
    try {
      print('[AuthRepository] Starting student email migration');

      // Call Cloud Function to migrate emails
      final callable = FirebaseFunctions.instance.httpsCallable(
        'migrateStudentEmails',
      );
      final result = await callable.call({});

      final data = result.data as Map<String, dynamic>;
      print('[AuthRepository] Migration complete: ${data['message']}');

      return data;
    } on FirebaseFunctionsException catch (e) {
      print('[AuthRepository] Cloud Function error: ${e.code} - ${e.message}');
      if (e.code == 'not-found') {
        throw Exception(
          'Cloud Function not deployed. Please deploy the migrateStudentEmails function.',
        );
      }
      rethrow;
    } catch (e) {
      print('[AuthRepository] Migration error: $e');
      rethrow;
    }
  }
}
