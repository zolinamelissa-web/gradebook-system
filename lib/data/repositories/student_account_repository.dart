import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

class StudentAccountRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool _effectiveIsRegistered(Map<String, dynamic> d) {
    final isReg = (d['is_registered'] as int?) == 1;
    final firebaseUid = (d['firebase_uid']?.toString() ?? '').trim();
    return isReg && firebaseUid.isNotEmpty;
  }

  static String _normalizeName(String v) {
    return v.toLowerCase().trim();
  }

  static const String _activeTeacherUidKey = 'active_student_teacher_uid';
  static const String _activeStudentRemoteIdKey = 'active_student_remote_id';
  static const String _activeStudentIdKey = 'active_student_id';

  static Future<String> getStudentIdForFirebaseUid(String firebaseUid) async {
    try {
      final legacy = await _firestore
          .collection('student_accounts')
          .where('firebase_uid', isEqualTo: firebaseUid)
          .limit(1)
          .get();
      if (legacy.docs.isEmpty) return '';
      return legacy.docs.first.id;
    } catch (e) {
      print('[StudentAccountRepo] Error resolving studentId for uid: $e');
      return '';
    }
  }

  /// Recovery path: rebuild teacher links by scanning teacher student collections
  /// using the student's login email.
  ///
  /// This is used when firebase_uid mappings were lost (e.g., overwritten during sync)
  /// and collectionGroup indexes are missing.
  static Future<List<StudentTeacherLinkInfo>> recoverTeacherLinksByEmail({
    required String firebaseUid,
    required String email,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      if (normalizedEmail.isEmpty) return [];

      print(
        '[StudentAccountRepo] Recover teacher links by email=$normalizedEmail firebaseUid=$firebaseUid',
      );

      final matches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        final cg = await _firestore
            .collectionGroup('students')
            .where('email', isEqualTo: normalizedEmail)
            .get();
        matches.addAll(cg.docs);
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          print(
            '[StudentAccountRepo] students collectionGroup index missing; falling back to users scan for email=$normalizedEmail. $e',
          );

          final usersSnap = await _firestore.collection('users').get();
          for (final u in usersSnap.docs) {
            final teacherUid = u.id;
            try {
              final s = await _firestore
                  .collection('users/$teacherUid/students')
                  .where('email', isEqualTo: normalizedEmail)
                  .get();
              matches.addAll(s.docs);
            } catch (inner) {
              print(
                '[StudentAccountRepo] recover users scan error teacherUid=$teacherUid email=$normalizedEmail: $inner',
              );
            }
          }
        } else {
          rethrow;
        }
      }

      print(
        '[StudentAccountRepo] recover matches=${matches.length} email=$normalizedEmail',
      );
      if (matches.isEmpty) {
        // Last resort: scan each teacher's students collection and compare
        // email in code (handles casing/formatting issues and avoids indexes).
        print(
          '[StudentAccountRepo] recover: 0 matches from queries; scanning users/*/students in-code for email=$normalizedEmail',
        );
        try {
          final usersSnap = await _firestore.collection('users').get();
          for (final u in usersSnap.docs) {
            final teacherUid = u.id;
            try {
              final studentsSnap = await _firestore
                  .collection('users/$teacherUid/students')
                  .get();
              for (final s in studentsSnap.docs) {
                final data = s.data();
                final e = (data['email']?.toString() ?? '')
                    .trim()
                    .toLowerCase();
                if (e.isEmpty) continue;
                if (e != normalizedEmail) continue;
                matches.add(s);
              }
            } catch (inner) {
              print(
                '[StudentAccountRepo] recover in-code scan error teacherUid=$teacherUid email=$normalizedEmail: $inner',
              );
            }
          }
        } catch (e) {
          print('[StudentAccountRepo] recover in-code scan failed: $e');
        }

        print(
          '[StudentAccountRepo] recover in-code scan matches=${matches.length} email=$normalizedEmail',
        );
        if (matches.isEmpty) return [];
      }

      final now = DateTime.now().toIso8601String();
      final links = <StudentTeacherLinkInfo>[];

      for (final doc in matches) {
        final data = doc.data();
        final teacherUid = doc.reference.parent.parent?.id;
        if (teacherUid == null || teacherUid.isEmpty) continue;

        final studentId = (data['student_id']?.toString() ?? '').trim();
        if (studentId.isEmpty) {
          print(
            '[StudentAccountRepo] recover skip: missing student_id in users/$teacherUid/students/${doc.id}',
          );
          continue;
        }

        final studentRemoteId = doc.id;
        final docRef = _firestore.collection('student_accounts').doc(studentId);

        await docRef.set({
          'student_id': studentId,
          'updated_at': now,
          'created_at': now,
        }, SetOptions(merge: true));

        await docRef.collection('teachers').doc(teacherUid).set({
          'student_id': studentId,
          'student_remote_id': studentRemoteId,
          'teacher_uid': teacherUid,
          'firebase_uid': firebaseUid,
          'email': normalizedEmail,
          'is_registered': 1,
          'registered_at': now,
          'updated_at': now,
          'created_at': now,
        }, SetOptions(merge: true));

        // Legacy compatibility for older clients.
        await docRef.set({
          'student_remote_id': studentRemoteId,
          'teacher_uid': teacherUid,
          'firebase_uid': firebaseUid,
          'email': normalizedEmail,
          'is_registered': 1,
          'registered_at': now,
          'updated_at': now,
        }, SetOptions(merge: true));

        links.add(
          StudentTeacherLinkInfo(
            studentId: studentId,
            teacherUid: teacherUid,
            teacherName: await _getTeacherName(teacherUid),
            studentRemoteId: studentRemoteId,
            firebaseUid: firebaseUid,
            isRegistered: true,
            email: normalizedEmail,
            registeredAt: DateTime.tryParse(now),
          ),
        );
      }

      print(
        '[StudentAccountRepo] recover completed links=${links.length} email=$normalizedEmail',
      );
      return links;
    } catch (e) {
      print('[StudentAccountRepo] recoverTeacherLinksByEmail error: $e');
      return [];
    }
  }

  static Future<List<StudentTeacherLinkInfo>> _scanTeacherLinksByStudentId(
    String studentId, {
    String? firebaseUid,
  }) async {
    try {
      print(
        '[StudentAccountRepo] Scanning users/*/students by student_id=$studentId to rebuild teacher links',
      );

      final matches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      try {
        final cg = await _firestore
            .collectionGroup('students')
            .where('student_id', isEqualTo: studentId)
            .get();
        matches.addAll(cg.docs);
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          print(
            '[StudentAccountRepo] students collectionGroup index missing; falling back to users scan. $e',
          );

          final usersSnap = await _firestore.collection('users').get();
          for (final u in usersSnap.docs) {
            final teacherUid = u.id;
            try {
              final s = await _firestore
                  .collection('users/$teacherUid/students')
                  .where('student_id', isEqualTo: studentId)
                  .get();
              matches.addAll(s.docs);
            } catch (inner) {
              print(
                '[StudentAccountRepo] users scan error teacherUid=$teacherUid: $inner',
              );
            }
          }
        } else {
          rethrow;
        }
      }

      print(
        '[StudentAccountRepo] users/*/students matches=${matches.length} for student_id=$studentId',
      );

      if (matches.isEmpty) return [];

      final docRef = _firestore.collection('student_accounts').doc(studentId);
      final now = DateTime.now().toIso8601String();
      await docRef.set({
        'student_id': studentId,
        'updated_at': now,
      }, SetOptions(merge: true));

      final links = <StudentTeacherLinkInfo>[];
      for (final doc in matches) {
        final teacherUid = doc.reference.parent.parent?.id;
        if (teacherUid == null || teacherUid.isEmpty) continue;
        final studentRemoteId = doc.id;
        if (studentRemoteId.isEmpty) continue;

        await docRef.collection('teachers').doc(teacherUid).set({
          'student_id': studentId,
          'student_remote_id': studentRemoteId,
          'teacher_uid': teacherUid,
          if (firebaseUid != null && firebaseUid.isNotEmpty)
            'firebase_uid': firebaseUid,
          'updated_at': now,
        }, SetOptions(merge: true));

        links.add(
          StudentTeacherLinkInfo(
            studentId: studentId,
            teacherUid: teacherUid,
            teacherName: await _getTeacherName(teacherUid),
            studentRemoteId: studentRemoteId,
            firebaseUid: firebaseUid,
            isRegistered: false,
            email: null,
            registeredAt: null,
          ),
        );
      }

      print(
        '[StudentAccountRepo] Rebuilt ${links.length} teacher link(s) for studentId=$studentId',
      );
      return links;
    } catch (e) {
      print('[StudentAccountRepo] Error scanning users/*/students: $e');
      return [];
    }
  }

  /// Check if a student ID exists in Firestore (for registration verification)
  static Future<StudentAccountInfo?> checkStudentIdExists(
    String studentId,
  ) async {
    try {
      print('[StudentAccountRepo] Checking Student ID: $studentId');

      final links = await getTeacherLinksForStudentId(studentId);
      if (links.isEmpty) {
        print('[StudentAccountRepo] Student ID not found: $studentId');
        return null;
      }

      final anyRegistered = links.any((l) => l.isRegistered);
      print(
        '[StudentAccountRepo] Student ID links=${links.length} anyRegistered=$anyRegistered studentId=$studentId',
      );
      for (final l in links) {
        print(
          '[StudentAccountRepo] Student ID link teacherUid=${l.teacherUid} teacherName=${l.teacherName} studentRemoteId=${l.studentRemoteId} isRegistered=${l.isRegistered}',
        );
      }

      // Prefer a link whose student doc exists.
      StudentTeacherLinkInfo? resolvedLink;
      Map<String, dynamic>? studentData;
      for (final l in links) {
        final d = await _getStudentDocData(
          teacherUid: l.teacherUid,
          studentRemoteId: l.studentRemoteId,
        );
        if (d != null) {
          resolvedLink = l;
          studentData = d;
          break;
        }
      }

      if (resolvedLink == null || studentData == null) return null;

      return StudentAccountInfo(
        studentId: studentId,
        studentRemoteId: resolvedLink.studentRemoteId,
        teacherUid: resolvedLink.teacherUid,
        teacherName: resolvedLink.teacherName,
        firstName: studentData['first_name'] as String,
        lastName: studentData['last_name'] as String,
        middleName: studentData['middle_name'] as String?,
        isRegistered: anyRegistered,
        email: resolvedLink.email,
        registeredAt: resolvedLink.registeredAt,
      );
    } on FirebaseException catch (e) {
      // IMPORTANT: propagate network errors so the UI can show an offline message.
      if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        print('[StudentAccountRepo] Network error checking Student ID: $e');
        rethrow;
      }
      print('[StudentAccountRepo] Firebase error checking Student ID: $e');
      return null;
    } catch (e) {
      print('[StudentAccountRepo] Error checking Student ID: $e');
      return null;
    }
  }

  /// Multi-teacher: return all teacher links for a single global studentId.
  ///
  /// New schema:
  /// student_accounts/{studentId}/teachers/{teacherUid}
  ///   - student_remote_id
  ///   - teacher_uid
  ///   - firebase_uid
  ///   - is_registered
  ///   - email
  ///   - registered_at
  static Future<List<StudentTeacherLinkInfo>> getTeacherLinksForStudentId(
    String studentId, {
    String? firebaseUid,
  }) async {
    try {
      print(
        '[StudentAccountRepo] Loading teacher links for studentId=$studentId',
      );

      final docRef = _firestore.collection('student_accounts').doc(studentId);
      final teacherLinksSnap = await docRef.collection('teachers').get();

      if (teacherLinksSnap.docs.isNotEmpty) {
        final links = <StudentTeacherLinkInfo>[];
        for (final doc in teacherLinksSnap.docs) {
          final d = doc.data();
          final teacherUid = (d['teacher_uid'] as String?) ?? doc.id;
          final studentRemoteId = (d['student_remote_id'] as String?) ?? '';
          if (teacherUid.isEmpty || studentRemoteId.isEmpty) continue;

          links.add(
            StudentTeacherLinkInfo(
              studentId: studentId,
              teacherUid: teacherUid,
              teacherName: await _getTeacherName(teacherUid),
              studentRemoteId: studentRemoteId,
              firebaseUid: d['firebase_uid'] as String?,
              isRegistered: _effectiveIsRegistered(d),
              email: d['email'] as String?,
              registeredAt: d['registered_at'] != null
                  ? DateTime.tryParse(d['registered_at'] as String)
                  : null,
            ),
          );
        }

        print(
          '[StudentAccountRepo] Loaded ${links.length} teacher link(s) for studentId=$studentId',
        );

        // ALWAYS scan when firebaseUid is provided (login context) to ensure
        // all teachers are discovered, even if we already have some links.
        // This fixes the issue where sync may leave only 1 teacher link but
        // the student actually exists under multiple teachers.
        if (firebaseUid != null && firebaseUid.trim().isNotEmpty) {
          print(
            '[StudentAccountRepo] Scanning all teachers for studentId=$studentId to ensure complete link set',
          );
          final scanned = await _scanTeacherLinksByStudentId(
            studentId,
            firebaseUid: firebaseUid,
          );

          if (scanned.isNotEmpty) {
            final mergedByTeacher = <String, StudentTeacherLinkInfo>{};
            for (final l in links) {
              mergedByTeacher[l.teacherUid] = l;
            }
            for (final l in scanned) {
              mergedByTeacher[l.teacherUid] = l;
            }
            final merged = mergedByTeacher.values.toList();
            print(
              '[StudentAccountRepo] Merged teacher links from scan: before=${links.length} scanned=${scanned.length} merged=${merged.length} studentId=$studentId',
            );
            return merged;
          }
        }

        if (links.isNotEmpty) {
          return links;
        }
        print(
          '[StudentAccountRepo] teachers subcollection had docs but none were valid; continuing to legacy/scan fallback studentId=$studentId',
        );
      }

      // Legacy fallback: single teacher stored on root doc.
      final legacyDoc = await docRef.get();
      if (!legacyDoc.exists) {
        return await _scanTeacherLinksByStudentId(
          studentId,
          firebaseUid: firebaseUid,
        );
      }
      final data = legacyDoc.data();
      if (data == null) {
        return await _scanTeacherLinksByStudentId(
          studentId,
          firebaseUid: firebaseUid,
        );
      }

      final teacherUid = data['teacher_uid'] as String?;
      final studentRemoteId = data['student_remote_id'] as String?;
      if (teacherUid == null || teacherUid.isEmpty) {
        return await _scanTeacherLinksByStudentId(
          studentId,
          firebaseUid: firebaseUid,
        );
      }
      if (studentRemoteId == null || studentRemoteId.isEmpty) {
        return await _scanTeacherLinksByStudentId(
          studentId,
          firebaseUid: firebaseUid,
        );
      }

      final link = StudentTeacherLinkInfo(
        studentId: studentId,
        teacherUid: teacherUid,
        teacherName: await _getTeacherName(teacherUid),
        studentRemoteId: studentRemoteId,
        firebaseUid: data['firebase_uid'] as String?,
        isRegistered: _effectiveIsRegistered(data),
        email: data['email'] as String?,
        registeredAt: data['registered_at'] != null
            ? DateTime.tryParse(data['registered_at'] as String)
            : null,
      );
      return [link];
    } on FirebaseException catch (e) {
      // IMPORTANT: Don't mask network/DNS errors as "Student ID not found".
      // Let the UI show a proper offline/service unavailable message.
      if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        print('[StudentAccountRepo] Network error loading teacher links: $e');
        rethrow;
      }
      print('[StudentAccountRepo] Firebase error loading teacher links: $e');
      return [];
    } catch (e) {
      print('[StudentAccountRepo] Error loading teacher links: $e');
      return [];
    }
  }

  static Future<StudentTeacherLinkInfo?> resolveTeacherLinkByName({
    required String studentId,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final f = _normalizeName(firstName);
      final l = _normalizeName(lastName);
      if (f.isEmpty || l.isEmpty) return null;

      final links = await getTeacherLinksForStudentId(studentId);
      if (links.isEmpty) return null;

      print(
        '[StudentAccountRepo] Resolving teacher by name studentId=$studentId links=${links.length}',
      );

      for (final link in links) {
        final studentData = await _getStudentDocData(
          teacherUid: link.teacherUid,
          studentRemoteId: link.studentRemoteId,
        );
        if (studentData == null) continue;

        final sf = _normalizeName(studentData['first_name']?.toString() ?? '');
        final sl = _normalizeName(studentData['last_name']?.toString() ?? '');
        if (sf == f && sl == l) {
          print(
            '[StudentAccountRepo] Resolved teacher link by name studentId=$studentId teacherUid=${link.teacherUid} studentRemoteId=${link.studentRemoteId}',
          );
          return link;
        }
      }

      print(
        '[StudentAccountRepo] No teacher match by name studentId=$studentId',
      );
      return null;
    } catch (e) {
      print('[StudentAccountRepo] resolveTeacherLinkByName error: $e');
      return null;
    }
  }

  static Future<StudentAccountInfo?> getStudentAccountInfoForTeacher({
    required String studentId,
    required String teacherUid,
  }) async {
    try {
      final links = await getTeacherLinksForStudentId(studentId);
      final match = links.where((l) => l.teacherUid == teacherUid).toList();
      if (match.isEmpty) {
        print(
          '[StudentAccountRepo] No teacher link found for studentId=$studentId teacherUid=$teacherUid',
        );
        return null;
      }

      final link = match.first;
      final studentData = await _getStudentDocData(
        teacherUid: link.teacherUid,
        studentRemoteId: link.studentRemoteId,
      );
      if (studentData == null) return null;

      return StudentAccountInfo(
        studentId: studentId,
        studentRemoteId: link.studentRemoteId,
        teacherUid: link.teacherUid,
        teacherName: link.teacherName,
        firstName: studentData['first_name'] as String,
        lastName: studentData['last_name'] as String,
        middleName: studentData['middle_name'] as String?,
        isRegistered: link.isRegistered,
        email: link.email,
        registeredAt: link.registeredAt,
      );
    } catch (e) {
      print('[StudentAccountRepo] Error building account info for teacher: $e');
      return null;
    }
  }

  /// Register a student account (link Firebase UID to Student ID)
  static Future<bool> registerStudentAccount({
    required String studentId,
    required String teacherUid,
    required String firebaseUid,
    required String email,
  }) async {
    try {
      print(
        '[StudentAccountRepo] Registering student account: studentId=$studentId teacherUid=$teacherUid',
      );

      final docRef = _firestore.collection('student_accounts').doc(studentId);
      final now = DateTime.now().toIso8601String();

      // Ensure we keep the student_remote_id when registering.
      // The teacher link doc is created during teacher sync (createStudentAccountEntry).
      String? studentRemoteId;
      try {
        final existingLink = await docRef
            .collection('teachers')
            .doc(teacherUid)
            .get();
        final existingData = existingLink.data();
        studentRemoteId = existingData?['student_remote_id'] as String?;
      } catch (_) {}

      if (studentRemoteId == null || studentRemoteId.isEmpty) {
        try {
          final legacyDoc = await docRef.get();
          final legacyData = legacyDoc.data();
          studentRemoteId = legacyData?['student_remote_id'] as String?;
        } catch (_) {}
      }

      await docRef.set({
        'student_id': studentId,
        'updated_at': now,
      }, SetOptions(merge: true));

      // New multi-teacher location.
      await docRef.collection('teachers').doc(teacherUid).set({
        if (studentRemoteId != null && studentRemoteId.isNotEmpty)
          'student_remote_id': studentRemoteId,
        'teacher_uid': teacherUid,
        'firebase_uid': firebaseUid,
        'email': email,
        'is_registered': 1,
        'registered_at': now,
        'updated_at': now,
      }, SetOptions(merge: true));

      // Legacy compatibility: keep root doc updated for old clients.
      await docRef.set({
        if (studentRemoteId != null && studentRemoteId.isNotEmpty)
          'student_remote_id': studentRemoteId,
        'teacher_uid': teacherUid,
        'firebase_uid': firebaseUid,
        'email': email,
        'is_registered': 1,
        'registered_at': now,
        'updated_at': now,
      }, SetOptions(merge: true));

      // Update the student's email in the students collection
      // This ensures the email syncs to local database during student sync
      if (studentRemoteId != null && studentRemoteId.isNotEmpty) {
        try {
          await _firestore
              .collection('users/$teacherUid/students')
              .doc(studentRemoteId)
              .set({
                'email': email,
                'updated_at': now,
              }, SetOptions(merge: true));
          print(
            '[StudentAccountRepo] Updated student email in students collection',
          );
        } catch (e) {
          print(
            '[StudentAccountRepo] Error updating student email in students collection: $e',
          );
        }
      }

      // Persist selected teacher context locally for student dashboard/sync.
      await setActiveTeacherContext(
        studentId: studentId,
        teacherUid: teacherUid,
      );

      print('[StudentAccountRepo] Student account registered successfully');
      return true;
    } catch (e) {
      print('[StudentAccountRepo] Error registering student account: $e');
      return false;
    }
  }

  /// Get student account by Firebase UID (for login)
  static Future<StudentAccountInfo?> getStudentAccountByUid(
    String firebaseUid,
  ) async {
    try {
      print('[StudentAccountRepo] Getting student account by Firebase UID');

      // On web platform, skip SQLite access and use Firebase only
      if (kIsWeb) {
        print('[StudentAccountRepo] Web platform: using Firebase only');
        // For web, directly query Firebase for student account
        final studentDoc = await _firestore
            .collection('student_accounts')
            .where('firebase_uid', isEqualTo: firebaseUid)
            .limit(1)
            .get();

        if (studentDoc.docs.isEmpty) {
          print(
            '[StudentAccountRepo] No student account found for UID: $firebaseUid',
          );
          return null;
        }

        final data = studentDoc.docs.first.data();
        return StudentAccountInfo(
          studentId: studentDoc.docs.first.id,
          studentRemoteId: data['remote_id'] ?? '',
          teacherUid: data['teacher_uid'] ?? '',
          firstName: data['first_name'] ?? '',
          lastName: data['last_name'] ?? '',
          isRegistered: (data['is_registered'] as int?) == 1,
          email: data['email'] ?? '',
        );
      }

      final activeTeacherUid = await DatabaseHelper.instance.getSetting(
        _activeTeacherUidKey,
      );
      final activeStudentRemoteId = await DatabaseHelper.instance.getSetting(
        _activeStudentRemoteIdKey,
      );
      final activeStudentId = await DatabaseHelper.instance.getSetting(
        _activeStudentIdKey,
      );

      if (activeTeacherUid != null &&
          activeTeacherUid.isNotEmpty &&
          activeStudentRemoteId != null &&
          activeStudentRemoteId.isNotEmpty &&
          activeStudentId != null &&
          activeStudentId.isNotEmpty) {
        print(
          '[StudentAccountRepo] Using active teacher context teacherUid=$activeTeacherUid studentId=$activeStudentId',
        );

        final studentData = await _getStudentDocData(
          teacherUid: activeTeacherUid,
          studentRemoteId: activeStudentRemoteId,
        );
        if (studentData == null) return null;

        return StudentAccountInfo(
          studentId: activeStudentId,
          studentRemoteId: activeStudentRemoteId,
          teacherUid: activeTeacherUid,
          teacherName: await _getTeacherName(activeTeacherUid),
          firstName: studentData['first_name'] as String,
          lastName: studentData['last_name'] as String,
          middleName: studentData['middle_name'] as String?,
          isRegistered: true,
          email: null,
          registeredAt: null,
        );
      }

      final links = await getTeacherLinksByFirebaseUid(firebaseUid);
      if (links.isEmpty) {
        print('[StudentAccountRepo] No student account found for Firebase UID');
        return null;
      }

      // If multiple teachers, we intentionally return null so caller can force a picker.
      if (links.length > 1) {
        print(
          '[StudentAccountRepo] Multiple teacher links found for firebaseUid=$firebaseUid (count=${links.length})',
        );
        return null;
      }

      final link = links.first;
      await setActiveTeacherContext(
        studentId: link.studentId,
        teacherUid: link.teacherUid,
      );

      final studentData = await _getStudentDocData(
        teacherUid: link.teacherUid,
        studentRemoteId: link.studentRemoteId,
      );
      if (studentData == null) return null;

      return StudentAccountInfo(
        studentId: link.studentId,
        studentRemoteId: link.studentRemoteId,
        teacherUid: link.teacherUid,
        teacherName: link.teacherName,
        firstName: studentData['first_name'] as String,
        lastName: studentData['last_name'] as String,
        middleName: studentData['middle_name'] as String?,
        isRegistered: link.isRegistered,
        email: link.email,
        registeredAt: link.registeredAt,
      );
    } catch (e) {
      print('[StudentAccountRepo] Error getting student account by UID: $e');
      return null;
    }
  }

  /// Multi-teacher: Find all teacher links for a student by firebase uid.
  static Future<List<StudentTeacherLinkInfo>> getTeacherLinksByFirebaseUid(
    String firebaseUid,
  ) async {
    try {
      print(
        '[StudentAccountRepo] Loading teacher links by firebaseUid=$firebaseUid',
      );

      // New schema: query all student_accounts/*/teachers/* where firebase_uid matches.
      // NOTE: This requires a Firestore collectionGroup index.
      try {
        final cg = await _firestore
            .collectionGroup('teachers')
            .where('firebase_uid', isEqualTo: firebaseUid)
            .get();
        if (cg.docs.isNotEmpty) {
          final links = <StudentTeacherLinkInfo>[];
          for (final doc in cg.docs) {
            final d = doc.data();
            final teacherUid = (d['teacher_uid'] as String?) ?? doc.id;
            final studentRemoteId = d['student_remote_id'] as String?;
            final studentId = doc.reference.parent.parent?.id;
            if (studentId == null || studentId.isEmpty) continue;
            if (teacherUid.isEmpty) continue;
            if (studentRemoteId == null || studentRemoteId.isEmpty) continue;

            links.add(
              StudentTeacherLinkInfo(
                studentId: studentId,
                teacherUid: teacherUid,
                teacherName: await _getTeacherName(teacherUid),
                studentRemoteId: studentRemoteId,
                firebaseUid: firebaseUid,
                isRegistered: (d['is_registered'] as int?) == 1,
                email: d['email'] as String?,
                registeredAt: d['registered_at'] != null
                    ? DateTime.tryParse(d['registered_at'] as String)
                    : null,
              ),
            );
          }
          print(
            '[StudentAccountRepo] Found ${links.length} teacher link(s) by firebaseUid',
          );
          return links;
        }
      } on FirebaseException catch (e) {
        // If the index isn't created yet, fall back to legacy lookup.
        if (e.code == 'failed-precondition') {
          print(
            '[StudentAccountRepo] collectionGroup index missing; falling back to legacy query. $e',
          );
        } else {
          rethrow;
        }
      }

      // Legacy fallback: old root-doc query.
      final legacy = await _firestore
          .collection('student_accounts')
          .where('firebase_uid', isEqualTo: firebaseUid)
          .get();

      if (legacy.docs.isEmpty) {
        // No legacy root-doc mapping. As a final fallback, scan student_accounts/*/teachers
        // without using collectionGroup (avoids requiring an index).
        print(
          '[StudentAccountRepo] Legacy query returned 0; scanning student_accounts/*/teachers for firebaseUid=$firebaseUid',
        );
        final accountsSnap = await _firestore
            .collection('student_accounts')
            .get();
        final links = <StudentTeacherLinkInfo>[];
        for (final acc in accountsSnap.docs) {
          try {
            final studentId = acc.id;
            final teachersSnap = await acc.reference
                .collection('teachers')
                .where('firebase_uid', isEqualTo: firebaseUid)
                .get();

            for (final t in teachersSnap.docs) {
              final d = t.data();
              final teacherUid = (d['teacher_uid'] as String?) ?? t.id;
              final studentRemoteId = d['student_remote_id'] as String?;
              if (teacherUid.isEmpty) continue;
              if (studentRemoteId == null || studentRemoteId.isEmpty) continue;

              links.add(
                StudentTeacherLinkInfo(
                  studentId: studentId,
                  teacherUid: teacherUid,
                  teacherName: await _getTeacherName(teacherUid),
                  studentRemoteId: studentRemoteId,
                  firebaseUid: firebaseUid,
                  isRegistered: (d['is_registered'] as int?) == 1,
                  email: d['email'] as String?,
                  registeredAt: d['registered_at'] != null
                      ? DateTime.tryParse(d['registered_at'] as String)
                      : null,
                ),
              );
            }
          } catch (inner) {
            print(
              '[StudentAccountRepo] teachers scan error studentAccountId=${acc.id}: $inner',
            );
          }
        }
        print(
          '[StudentAccountRepo] teachers scan found ${links.length} teacher link(s) for firebaseUid=$firebaseUid',
        );
        return links;
      }

      final links = <StudentTeacherLinkInfo>[];
      for (final doc in legacy.docs) {
        final data = doc.data();
        final studentId = doc.id;
        final teacherUid = data['teacher_uid'] as String?;
        final studentRemoteId = data['student_remote_id'] as String?;
        if (teacherUid == null || teacherUid.isEmpty) continue;
        if (studentRemoteId == null || studentRemoteId.isEmpty) continue;

        links.add(
          StudentTeacherLinkInfo(
            studentId: studentId,
            teacherUid: teacherUid,
            teacherName: await _getTeacherName(teacherUid),
            studentRemoteId: studentRemoteId,
            firebaseUid: firebaseUid,
            isRegistered: (data['is_registered'] as int?) == 1,
            email: data['email'] as String?,
            registeredAt: data['registered_at'] != null
                ? DateTime.tryParse(data['registered_at'] as String)
                : null,
          ),
        );
      }

      return links;
    } catch (e) {
      print('[StudentAccountRepo] Error loading teacher links by UID: $e');
      return [];
    }
  }

  /// Create student account entry (called during teacher sync)
  static Future<void> createStudentAccountEntry({
    required String studentId,
    required String studentRemoteId,
    required String teacherUid,
  }) async {
    try {
      print('[StudentAccountRepo] Creating student account entry: $studentId');

      final docRef = _firestore.collection('student_accounts').doc(studentId);
      final now = DateTime.now().toIso8601String();

      // IMPORTANT:
      // Teacher-side sync may run multiple times. Never overwrite an existing
      // registered mapping (firebase_uid/email/is_registered/registered_at)
      // with null values.
      Map<String, dynamic>? existingTeacherLink;
      try {
        final existing = await docRef
            .collection('teachers')
            .doc(teacherUid)
            .get();
        existingTeacherLink = existing.data();
      } catch (_) {}

      Map<String, dynamic>? existingRoot;
      try {
        final root = await docRef.get();
        existingRoot = root.data();
      } catch (_) {}

      // Ensure root exists.
      await docRef.set({
        'student_id': studentId,
        'updated_at': now,
        'created_at': now,
      }, SetOptions(merge: true));

      // New multi-teacher link location.
      final teacherLinkPayload = <String, dynamic>{
        'student_id': studentId,
        'student_remote_id': studentRemoteId,
        'teacher_uid': teacherUid,
        'updated_at': now,
      };
      final hasExistingFirebaseUid =
          (existingTeacherLink?['firebase_uid']?.toString() ?? '').isNotEmpty;
      if (!hasExistingFirebaseUid) {
        teacherLinkPayload['firebase_uid'] = null;
        teacherLinkPayload['is_registered'] = 0;
        teacherLinkPayload['email'] = null;
        teacherLinkPayload['registered_at'] = null;
      }
      if (existingTeacherLink == null || existingTeacherLink.isEmpty) {
        teacherLinkPayload['created_at'] = now;
      }
      await docRef
          .collection('teachers')
          .doc(teacherUid)
          .set(teacherLinkPayload, SetOptions(merge: true));

      // Legacy compatibility.
      final legacyPayload = <String, dynamic>{
        'student_remote_id': studentRemoteId,
        'teacher_uid': teacherUid,
        'updated_at': now,
      };
      final hasLegacyFirebaseUid =
          (existingRoot?['firebase_uid']?.toString() ?? '').isNotEmpty;
      if (!hasLegacyFirebaseUid) {
        legacyPayload['firebase_uid'] = null;
        legacyPayload['is_registered'] = 0;
        legacyPayload['email'] = null;
        legacyPayload['registered_at'] = null;
      }
      if (existingRoot == null || existingRoot.isEmpty) {
        legacyPayload['created_at'] = now;
      }
      await docRef.set(legacyPayload, SetOptions(merge: true));

      print('[StudentAccountRepo] Student account entry created');
    } catch (e) {
      print('[StudentAccountRepo] Error creating student account entry: $e');
      rethrow;
    }
  }

  static Future<void> setActiveTeacherContext({
    required String studentId,
    required String teacherUid,
  }) async {
    try {
      final links = await getTeacherLinksForStudentId(studentId);
      final match = links.where((l) => l.teacherUid == teacherUid).toList();
      if (match.isEmpty) {
        print(
          '[StudentAccountRepo] Cannot set active teacher context: teacher link not found studentId=$studentId teacherUid=$teacherUid',
        );
        return;
      }

      final link = match.first;

      await DatabaseHelper.instance.setSetting(
        _activeTeacherUidKey,
        teacherUid,
      );
      await DatabaseHelper.instance.setSetting(
        _activeStudentRemoteIdKey,
        link.studentRemoteId,
      );
      await DatabaseHelper.instance.setSetting(_activeStudentIdKey, studentId);

      print(
        '[StudentAccountRepo] Active teacher context set: studentId=$studentId teacherUid=$teacherUid studentRemoteId=${link.studentRemoteId}',
      );
    } catch (e) {
      print('[StudentAccountRepo] Error setting active teacher context: $e');
    }
  }

  static Future<void> clearActiveTeacherContext() async {
    try {
      await DatabaseHelper.instance.setSetting(_activeTeacherUidKey, '');
      await DatabaseHelper.instance.setSetting(_activeStudentRemoteIdKey, '');
      await DatabaseHelper.instance.setSetting(_activeStudentIdKey, '');
      print('[StudentAccountRepo] Cleared active teacher context');
    } catch (e) {
      print('[StudentAccountRepo] Error clearing active teacher context: $e');
    }
  }

  static Future<Map<String, dynamic>?> _getStudentDocData({
    required String teacherUid,
    required String studentRemoteId,
  }) async {
    try {
      final studentDocRef = _firestore
          .collection('users/$teacherUid/students')
          .doc(studentRemoteId);
      final studentDoc = await studentDocRef.get();
      if (!studentDoc.exists) {
        print(
          '[StudentAccountRepo] Student details not found in teacher collection teacherUid=$teacherUid remoteId=$studentRemoteId',
        );
        return null;
      }
      return studentDoc.data();
    } catch (e) {
      print('[StudentAccountRepo] Error loading student doc: $e');
      return null;
    }
  }

  static Future<String> _getTeacherName(String teacherUid) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(teacherUid)
          .get();
      final data = userDoc.data();
      final name = (data != null ? data['teacher_name'] : null) as String?;
      if (name != null && name.trim().isNotEmpty) return name.trim();
      return teacherUid;
    } catch (e) {
      print('[StudentAccountRepo] Error loading teacher name: $e');
      return teacherUid;
    }
  }
}

/// Lightweight class for student account information (used during registration/login)
class StudentAccountInfo {
  final String studentId;
  final String studentRemoteId;
  final String teacherUid;
  final String? teacherName;
  final String firstName;
  final String lastName;
  final String? middleName;
  final bool isRegistered;
  final String? email;
  final DateTime? registeredAt;

  StudentAccountInfo({
    required this.studentId,
    required this.studentRemoteId,
    required this.teacherUid,
    this.teacherName,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.isRegistered,
    this.email,
    this.registeredAt,
  });

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$lastName, $firstName ${middleName![0]}.';
    }
    return '$lastName, $firstName';
  }

  String get displayName => '$firstName $lastName';
}

class StudentTeacherLinkInfo {
  final String studentId;
  final String teacherUid;
  final String teacherName;
  final String studentRemoteId;
  final String? firebaseUid;
  final bool isRegistered;
  final String? email;
  final DateTime? registeredAt;

  StudentTeacherLinkInfo({
    required this.studentId,
    required this.teacherUid,
    required this.teacherName,
    required this.studentRemoteId,
    this.firebaseUid,
    required this.isRegistered,
    this.email,
    this.registeredAt,
  });
}
