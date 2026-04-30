import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../../data/database/database_helper.dart';
import '../../data/repositories/student_account_repository.dart';
import 'package:sqflite/sqflite.dart';

class StudentSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _noInternetMessage =
      'No internet connection. Sync cancelled.';

  static Future<bool> _hasInternetConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        return false;
      }
      final lookup = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (e) {
      print('[StudentSyncService] Internet check failed: $e');
      return false;
    }
  }

  static Future<StudentSyncResult> _syncCounselingReasons(
    StudentAccountInfo studentInfo, {
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;
    try {
      if (direction == 'download') {
        // For now, counseling reasons are student-authored; teacher downloads via
        // teacher sync. Student device doesn't need to download them.
        return StudentSyncResult(uploaded: 0, downloaded: 0);
      }

      final db = await DatabaseHelper.instance.database;
      final teacherUid = studentInfo.teacherUid;
      final studentId = studentInfo.studentId;

      final rows = await db.query(
        'counseling_reasons',
        where:
            'teacher_uid = ? AND student_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [teacherUid, studentId],
      );

      if (rows.isEmpty) {
        print(
          '[StudentSyncService] No counseling reasons to upload teacherUid=$teacherUid studentId=$studentId',
        );
        return StudentSyncResult(uploaded: 0, downloaded: 0);
      }

      final col = _firestore.collection('users/$teacherUid/counseling_reasons');

      for (final r in rows) {
        final localId = r['id'] as int;
        final remoteId = r['remote_id'] as String?;
        final updatedAt = DateTime.tryParse(r['updated_at']?.toString() ?? '');
        final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '');
        final now = DateTime.now();

        final payload = <String, dynamic>{
          'teacher_uid': teacherUid,
          'student_id': studentId,
          'student_remote_id': (r['student_remote_id']?.toString() ?? ''),
          'class_remote_id': (r['class_remote_id']?.toString() ?? ''),
          'subject_code': (r['subject_code']?.toString() ?? ''),
          'reason': (r['reason']?.toString() ?? ''),
          'updated_at': Timestamp.fromDate(updatedAt ?? now),
        };

        if (remoteId == null || remoteId.isEmpty) {
          payload['created_at'] = Timestamp.fromDate(createdAt ?? now);
          final docRef = await col.add(payload);
          await db.update(
            'counseling_reasons',
            {'remote_id': docRef.id, 'updated_at': now.toIso8601String()},
            where: 'id = ?',
            whereArgs: [localId],
          );
          uploaded++;
          print(
            '[StudentSyncService] Uploaded counseling reason localId=$localId remoteId=${docRef.id} teacherUid=$teacherUid studentId=$studentId',
          );
        } else {
          await col.doc(remoteId).set(payload, SetOptions(merge: true));
          uploaded++;
          print(
            '[StudentSyncService] Updated counseling reason localId=$localId remoteId=$remoteId teacherUid=$teacherUid studentId=$studentId',
          );
        }
      }
    } catch (e) {
      print('[StudentSyncService] Counseling reasons sync error: $e');
    }

    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  static Future<void> _syncTeacherSettings(String teacherUid) async {
    try {
      final doc = await _firestore.collection('users').doc(teacherUid).get();
      final settings = doc.data()?['settings'] as Map<String, dynamic>? ?? {};

      final gradingSystem = settings['grading_system']?.toString() ?? '';
      final eqTable = settings['grade_equivalency_table']?.toString() ?? '';

      if (gradingSystem.trim().isEmpty && eqTable.trim().isEmpty) {
        print(
          '[StudentSyncService] Teacher settings empty; skip download teacherUid=$teacherUid',
        );
        return;
      }

      final dbh = DatabaseHelper.instance;
      if (gradingSystem.trim().isNotEmpty) {
        await dbh.setSetting(
          'teacher_${teacherUid}_grading_system',
          gradingSystem.trim(),
        );
      }
      if (eqTable.trim().isNotEmpty) {
        await dbh.setSetting(
          'teacher_${teacherUid}_grade_equivalency_table',
          eqTable.trim(),
        );
      }

      print(
        '[StudentSyncService] Downloaded teacher grading settings teacherUid=$teacherUid gradingSystemLen=${gradingSystem.length} eqLen=${eqTable.length}',
      );
    } catch (e) {
      print('[StudentSyncService] Teacher settings download error: $e');
    }
  }

  /// Main sync method for students - syncs data from ALL teachers
  static Future<StudentSyncResult> syncStudentData({
    required String firebaseUid,
    String? direction, // 'upload', 'download', or null for both
    Function(String)? onStatusUpdate,
  }) async {
    print(
      '[StudentSyncService] Starting student data sync across all teachers... direction=$direction',
    );

    if (!await _hasInternetConnection()) {
      print('[StudentSyncService] No internet connection');
      return StudentSyncResult(
        uploaded: 0,
        downloaded: 0,
        error: _noInternetMessage,
      );
    }

    // Get ALL teacher links for this student
    final teacherLinks =
        await StudentAccountRepository.getTeacherLinksByFirebaseUid(
          firebaseUid,
        );
    if (teacherLinks.isEmpty) {
      final error = 'No teacher links found for student';
      print('[StudentSyncService] $error');
      return StudentSyncResult(uploaded: 0, downloaded: 0, error: error);
    }

    print(
      '[StudentSyncService] Found ${teacherLinks.length} teacher link(s) for student',
    );

    // Aggregate results across all teachers
    int totalUploaded = 0;
    int totalDownloaded = 0;

    // Sync data for each teacher link
    for (int i = 0; i < teacherLinks.length; i++) {
      final link = teacherLinks[i];

      // Fetch student name from Firestore for this teacher link
      String firstName = 'Student';
      String lastName = '';
      try {
        final studentDoc = await _firestore
            .collection('users/${link.teacherUid}/students')
            .doc(link.studentRemoteId)
            .get();
        if (studentDoc.exists) {
          final data = studentDoc.data()!;
          firstName = data['first_name'] ?? 'Student';
          lastName = data['last_name'] ?? '';
        }
      } catch (e) {
        print('[StudentSyncService] Error fetching student name: $e');
      }

      final studentInfo = StudentAccountInfo(
        studentId: link.studentId,
        teacherUid: link.teacherUid,
        studentRemoteId: link.studentRemoteId,
        teacherName: link.teacherName,
        firstName: firstName,
        lastName: lastName,
        isRegistered: link.isRegistered,
        email: link.email,
        registeredAt: link.registeredAt,
      );

      print(
        '[StudentSyncService] Syncing teacher ${i + 1}: teacherUid=${link.teacherUid} studentId=${link.studentId} studentRemoteId=${link.studentRemoteId}',
      );

      final db = await DatabaseHelper.instance.database;
      int? resolvedLocalStudentId = await _resolveLocalStudentId(
        db,
        studentInfo.studentId,
      );

      // If local student doesn't exist and we're downloading, create it
      if (resolvedLocalStudentId == null && direction != 'upload') {
        print(
          '[StudentSyncService] Local student not found, creating for download student_id=${studentInfo.studentId}',
        );
        resolvedLocalStudentId = await _createLocalStudentRecord(
          db,
          studentInfo,
        );
        if (resolvedLocalStudentId == null) {
          print(
            '[StudentSyncService] Failed to create local student record student_id=${studentInfo.studentId}',
          );
          continue;
        }
      } else if (resolvedLocalStudentId == null) {
        print(
          '[StudentSyncService] Skipping teacher sync: local student not found student_id=${studentInfo.studentId}',
        );
        continue;
      }

      onStatusUpdate?.call(
        'Syncing from teacher ${i + 1}/${teacherLinks.length}...',
      );

      // Download teacher data structures first (classes, periods, categories, etc.)
      if (direction != 'upload') {
        onStatusUpdate?.call('Syncing teacher data structures...');
        await _syncTeacherDataStructures(studentInfo, onStatusUpdate);

        onStatusUpdate?.call('Syncing student profile...');
        await _syncStudentProfile(studentInfo);
      }

      onStatusUpdate?.call('Syncing grades...');
      final gradesResult = await _syncStudentGrades(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += gradesResult.uploaded;
      totalDownloaded += gradesResult.downloaded;
      print(
        '[StudentSyncService] Grades sync complete: uploaded=${gradesResult.uploaded} downloaded=${gradesResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing attendance...');
      final attendanceResult = await _syncStudentAttendance(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += attendanceResult.uploaded;
      totalDownloaded += attendanceResult.downloaded;
      print(
        '[StudentSyncService] Attendance sync complete: uploaded=${attendanceResult.uploaded} downloaded=${attendanceResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing assessment scores...');
      final scoresResult = await _syncStudentAssessmentScores(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += scoresResult.uploaded;
      totalDownloaded += scoresResult.downloaded;
      print(
        '[StudentSyncService] Assessment scores sync complete: uploaded=${scoresResult.uploaded} downloaded=${scoresResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing interventions...');
      final interventionsResult = await _syncStudentInterventions(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += interventionsResult.uploaded;
      totalDownloaded += interventionsResult.downloaded;
      print(
        '[StudentSyncService] Interventions sync complete: uploaded=${interventionsResult.uploaded} downloaded=${interventionsResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing risk flags...');
      final riskFlagsResult = await _syncStudentRiskFlags(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += riskFlagsResult.uploaded;
      totalDownloaded += riskFlagsResult.downloaded;
      print(
        '[StudentSyncService] Risk flags sync complete: uploaded=${riskFlagsResult.uploaded} downloaded=${riskFlagsResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing class enrollments...');
      final classStudentsResult = await _syncStudentClassEnrollments(
        studentInfo,
        localStudentId: resolvedLocalStudentId,
        direction: direction,
      );
      totalUploaded += classStudentsResult.uploaded;
      totalDownloaded += classStudentsResult.downloaded;
      print(
        '[StudentSyncService] Class enrollments sync complete: uploaded=${classStudentsResult.uploaded} downloaded=${classStudentsResult.downloaded}',
      );

      onStatusUpdate?.call('Syncing counseling reasons...');
      final counselingResult = await _syncCounselingReasons(
        studentInfo,
        direction: direction,
      );
      totalUploaded += counselingResult.uploaded;
      totalDownloaded += counselingResult.downloaded;
      print(
        '[StudentSyncService] Counseling reasons sync complete: uploaded=${counselingResult.uploaded} downloaded=${counselingResult.downloaded}',
      );
    }

    print(
      '[StudentSyncService] Student sync complete across ${teacherLinks.length} teacher(s): uploaded=$totalUploaded downloaded=$totalDownloaded',
    );

    return StudentSyncResult(
      uploaded: totalUploaded,
      downloaded: totalDownloaded,
    );
  }

  /// Sync teacher data structures (classes, periods, categories, assessments)
  static Future<void> _syncTeacherDataStructures(
    StudentAccountInfo studentInfo,
    Function(String)? onStatusUpdate,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final teacherUid = studentInfo.teacherUid;

      // Sync teacher settings needed for correct grade equivalency/descriptor.
      onStatusUpdate?.call('Downloading grading settings...');
      await _syncTeacherSettings(teacherUid);

      // Sync subjects first (needed for classes)
      onStatusUpdate?.call('Downloading subjects...');
      await _syncSubjects(db, teacherUid);

      // Sync classes (needs subjects)
      onStatusUpdate?.call('Downloading classes...');
      await _syncClasses(db, teacherUid);

      // Sync grading periods (needs classes)
      onStatusUpdate?.call('Downloading grading periods...');
      await _syncGradingPeriods(db, teacherUid);

      // Sync grading categories (needs periods)
      onStatusUpdate?.call('Downloading grading categories...');
      await _syncGradingCategories(db, teacherUid);

      // Sync assessments
      onStatusUpdate?.call('Downloading assessments...');
      await _syncAssessments(db, teacherUid);

      print(
        '[StudentSyncService] Teacher data structures synced for teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing teacher data structures: $e');
    }
  }

  /// Sync subjects from teacher (needed for classes)
  static Future<void> _syncSubjects(Database db, String teacherUid) async {
    try {
      final snapshot = await _firestore
          .collection('users/$teacherUid/subjects')
          .get();

      int downloaded = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final remoteId = doc.id;

        final existing = await db.query(
          'subjects',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );

        final subjectData = {
          'code': data['code'] ?? data['subject_code'] ?? 'SUBJ',
          'name': data['name'] ?? data['subject_name'] ?? '',
          'description': data['description'] ?? '',
          'units': data['units'] ?? 3,
          'is_archived': data['is_archived'] == true ? 1 : 0,
          'remote_id': remoteId,
          'deleted': 0,
          'created_at': data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] != null
              ? (data['updated_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await db.insert('subjects', subjectData);
          downloaded++;
        } else {
          await db.update(
            'subjects',
            subjectData,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      print(
        '[StudentSyncService] Downloaded $downloaded subjects from teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing subjects: $e');
    }
  }

  /// Sync classes from teacher
  static Future<void> _syncClasses(Database db, String teacherUid) async {
    try {
      final snapshot = await _firestore
          .collection('users/$teacherUid/classes')
          .get();

      int downloaded = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final remoteId = doc.id;

        final existing = await db.query(
          'classes',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );

        // Resolve subject_id from subject_remote_id
        final subjectRemoteId = data['subject_remote_id']?.toString() ?? '';
        int? subjectId;
        if (subjectRemoteId.isNotEmpty) {
          subjectId = await _getLocalIdForRemoteId(
            db,
            'subjects',
            subjectRemoteId,
          );
        }

        // Skip if subject not found locally
        if (subjectId == null) {
          print(
            '[StudentSyncService] Skipping class $remoteId: subject not found',
          );
          continue;
        }

        final classData = {
          'subject_id': subjectId,
          'section': data['section'] ?? '',
          'school_year': data['school_year'] ?? '',
          'semester': data['semester'] ?? '',
          'schedule': data['schedule'] ?? '',
          'room': data['room'] ?? '',
          'is_archived': data['is_archived'] == true ? 1 : 0,
          'remote_id': remoteId,
          'deleted': 0,
          'created_at': data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] != null
              ? (data['updated_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await db.insert('classes', classData);
          downloaded++;
        } else {
          await db.update(
            'classes',
            classData,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      print(
        '[StudentSyncService] Downloaded $downloaded classes from teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing classes: $e');
    }
  }

  /// Sync grading periods from teacher
  static Future<void> _syncGradingPeriods(
    Database db,
    String teacherUid,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users/$teacherUid/grading_periods')
          .get();

      int downloaded = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final remoteId = doc.id;

        final existing = await db.query(
          'grading_periods',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );

        // Resolve class_id from class_remote_id
        final classRemoteId = data['class_remote_id']?.toString() ?? '';
        int? classId;
        if (classRemoteId.isNotEmpty) {
          classId = await _getLocalIdForRemoteId(db, 'classes', classRemoteId);
        }

        // Skip if class not found locally
        if (classId == null) {
          print(
            '[StudentSyncService] Skipping period $remoteId: class not found',
          );
          continue;
        }

        final periodData = {
          'class_id': classId,
          'name': data['name'] ?? data['period_name'] ?? '',
          'order_num': data['order_num'] ?? data['order'] ?? 1,
          'is_active': data['is_active'] == true ? 1 : 0,
          'is_locked': data['is_locked'] == true ? 1 : 0,
          'start_date': data['start_date'] ?? '',
          'end_date': data['end_date'] ?? '',
          'remote_id': remoteId,
          'deleted': 0,
          'created_at': data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] != null
              ? (data['updated_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await db.insert('grading_periods', periodData);
          downloaded++;
        } else {
          await db.update(
            'grading_periods',
            periodData,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      print(
        '[StudentSyncService] Downloaded $downloaded grading periods from teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing grading periods: $e');
    }
  }

  /// Sync grading categories from teacher
  static Future<void> _syncGradingCategories(
    Database db,
    String teacherUid,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users/$teacherUid/grading_categories')
          .get();

      int downloaded = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final remoteId = doc.id;

        final existing = await db.query(
          'grading_categories',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );

        // Resolve grading_period_id from grading_period_remote_id
        final periodRemoteId =
            data['grading_period_remote_id']?.toString() ?? '';
        int? periodId;
        if (periodRemoteId.isNotEmpty) {
          periodId = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            periodRemoteId,
          );
        }

        // Skip if period not found locally
        if (periodId == null) {
          print(
            '[StudentSyncService] Skipping category $remoteId: period not found',
          );
          continue;
        }

        final categoryData = {
          'grading_period_id': periodId,
          'name': data['name'] ?? data['category_name'] ?? '',
          'weight': data['weight'] ?? 0,
          'remote_id': remoteId,
          'deleted': 0,
          'created_at': data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] != null
              ? (data['updated_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await db.insert('grading_categories', categoryData);
          downloaded++;
        } else {
          await db.update(
            'grading_categories',
            categoryData,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      print(
        '[StudentSyncService] Downloaded $downloaded grading categories from teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing grading categories: $e');
    }
  }

  /// Sync assessments from teacher
  static Future<void> _syncAssessments(Database db, String teacherUid) async {
    try {
      final snapshot = await _firestore
          .collection('users/$teacherUid/assessments')
          .get();

      int downloaded = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final remoteId = doc.id;

        final existing = await db.query(
          'grading_assessments',
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );

        // Resolve foreign key remote_ids to local ids
        final classRemoteId = data['class_remote_id']?.toString() ?? '';
        final periodRemoteId =
            data['grading_period_remote_id']?.toString() ?? '';
        final categoryRemoteId = data['category_remote_id']?.toString() ?? '';

        if (classRemoteId.isEmpty ||
            periodRemoteId.isEmpty ||
            categoryRemoteId.isEmpty) {
          continue;
        }

        final classId = await _getLocalIdForRemoteId(
          db,
          'classes',
          classRemoteId,
        );
        final periodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          periodRemoteId,
        );
        final categoryId = await _getLocalIdForRemoteId(
          db,
          'grading_categories',
          categoryRemoteId,
        );

        if (classId == null || periodId == null || categoryId == null) {
          continue;
        }

        final assessmentData = {
          'class_id': classId,
          'grading_period_id': periodId,
          'category_id': categoryId,
          'name': data['name'] ?? data['assessment_name'] ?? '',
          'max_score': data['max_score'] ?? 0,
          'order_num': data['order_num'] ?? data['order'] ?? 0,
          'remote_id': remoteId,
          'deleted': 0,
          'created_at': data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] != null
              ? (data['updated_at'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await db.insert('grading_assessments', assessmentData);
          downloaded++;
        } else {
          await db.update(
            'grading_assessments',
            assessmentData,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      print(
        '[StudentSyncService] Downloaded $downloaded assessments from teacher $teacherUid',
      );
    } catch (e) {
      print('[StudentSyncService] Error syncing assessments: $e');
    }
  }

  /// Sync student profile information
  static Future<void> _syncStudentProfile(
    StudentAccountInfo studentInfo,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore
          .collection('users/${studentInfo.teacherUid}/students')
          .doc(studentInfo.studentRemoteId);

      // Get remote student data
      final remoteDoc = await collection.get();
      if (!remoteDoc.exists) {
        print('[StudentSyncService] Student profile not found in Firestore');
        return;
      }

      final remoteData = remoteDoc.data()!;

      // Update local student record
      final localStudents = await db.query(
        'students',
        where: 'student_id = ?',
        whereArgs: [studentInfo.studentId],
      );

      if (localStudents.isNotEmpty) {
        final localId = localStudents.first['id'] as int;
        await db.update(
          'students',
          {
            'first_name': remoteData['first_name'],
            'last_name': remoteData['last_name'],
            'middle_name': remoteData['middle_name'],
            'email': remoteData['email'],
            'phone': remoteData['phone'],
            'gender': remoteData['gender'],
            'birth_date': remoteData['birth_date'],
            'address': remoteData['address'],
            'photo_path': remoteData['photo_path'],
            'remote_id': studentInfo.studentRemoteId,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        print('[StudentSyncService] Updated student profile locally');
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing student profile: $e');
    }
  }

  /// Create a local student record in SQLite for download sync
  static Future<int?> _createLocalStudentRecord(
    Database db,
    StudentAccountInfo studentInfo,
  ) async {
    try {
      // Fetch student data from Firestore
      final studentDoc = await _firestore
          .collection('users/${studentInfo.teacherUid}/students')
          .doc(studentInfo.studentRemoteId)
          .get();

      if (!studentDoc.exists) {
        print('[StudentSyncService] Student document not found in Firestore');
        return null;
      }

      final remoteData = studentDoc.data()!;
      final now = DateTime.now().toIso8601String();

      // Create local student record
      final studentData = {
        'student_id': studentInfo.studentId,
        'first_name': remoteData['first_name'] ?? studentInfo.firstName,
        'last_name': remoteData['last_name'] ?? studentInfo.lastName,
        'middle_name': remoteData['middle_name'],
        'email': remoteData['email'] ?? studentInfo.email,
        'phone': remoteData['phone'],
        'gender': remoteData['gender'],
        'birth_date': remoteData['birth_date'],
        'address': remoteData['address'],
        'photo_path': remoteData['photo_path'],
        'remote_id': studentInfo.studentRemoteId,
        'deleted': 0,
        'created_at': now,
        'updated_at': now,
      };

      final localId = await db.insert('students', studentData);
      print(
        '[StudentSyncService] Created local student record id=$localId student_id=${studentInfo.studentId}',
      );
      return localId;
    } catch (e) {
      print('[StudentSyncService] Error creating local student record: $e');
      return null;
    }
  }

  static Future<int?> _resolveLocalStudentId(
    Database db,
    String studentId,
  ) async {
    final rows = await db.query(
      'students',
      columns: ['id'],
      where: 'student_id = ? AND deleted = 0',
      whereArgs: [studentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static Future<String?> _getRemoteIdForLocalId(
    Database db,
    String table,
    int localId,
  ) async {
    final rows = await db.query(
      table,
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_id'] as String?;
  }

  static Future<int?> _getLocalIdForRemoteId(
    Database db,
    String table,
    String remoteId,
  ) async {
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  /// Sync student grades
  static Future<StudentSyncResult> _syncStudentGrades(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/grades',
      );

      // Get local grades for this student
      final localGrades = await db.query(
        'grades',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );
      print('[StudentSyncService] Found ${localGrades.length} local grades');

      // Get remote grades for this student
      print(
        '[StudentSyncService] Querying grades: users/${studentInfo.teacherUid}/grades where student_remote_id == ${studentInfo.studentRemoteId}',
      );
      final remoteSnapshot = await collection
          .where('student_remote_id', isEqualTo: studentInfo.studentRemoteId)
          .get();
      print(
        '[StudentSyncService] Found ${remoteSnapshot.docs.length} remote grades',
      );
      if (remoteSnapshot.docs.isEmpty) {
        print(
          '[StudentSyncService] No grades found in Firebase - check if student_remote_id=${studentInfo.studentRemoteId} exists in users/${studentInfo.teacherUid}/grades collection',
        );
      }

      if (direction != 'download') {
        // Upload local grades
        for (final localGrade in localGrades) {
          final localId = localGrade['id'] as int;
          final remoteId = localGrade['remote_id'] as String?;
          final localUpdated = DateTime.parse(
            localGrade['updated_at'] as String,
          );

          final localClassId = localGrade['class_id'] as int?;
          final localPeriodId = localGrade['grading_period_id'] as int?;
          final localCategoryId = localGrade['category_id'] as int?;

          final classRemoteId = localClassId == null
              ? null
              : await _getRemoteIdForLocalId(db, 'classes', localClassId);
          final periodRemoteId = localPeriodId == null
              ? null
              : await _getRemoteIdForLocalId(
                  db,
                  'grading_periods',
                  localPeriodId,
                );
          final categoryRemoteId = localCategoryId == null
              ? null
              : await _getRemoteIdForLocalId(
                  db,
                  'grading_categories',
                  localCategoryId,
                );

          // Cross-device safety: we require FK remote_ids.
          if (classRemoteId == null ||
              classRemoteId.isEmpty ||
              periodRemoteId == null ||
              periodRemoteId.isEmpty ||
              categoryRemoteId == null ||
              categoryRemoteId.isEmpty) {
            print(
              '[StudentSyncService] Skipping grade upload id=$localId: missing FK remote_ids class=$classRemoteId period=$periodRemoteId category=$categoryRemoteId',
            );
            continue;
          }

          final payload = {
            'student_id': localStudentId,
            'class_id': localGrade['class_id'],
            'grading_period_id': localGrade['grading_period_id'],
            'category_id': localGrade['category_id'],
            'student_remote_id': studentInfo.studentRemoteId,
            'class_remote_id': classRemoteId,
            'grading_period_remote_id': periodRemoteId,
            'category_remote_id': categoryRemoteId,
            'score': localGrade['score'],
            'max_score': localGrade['max_score'],
            'remarks': localGrade['remarks'] ?? '',
            'recorded_at': Timestamp.fromDate(
              DateTime.parse(localGrade['recorded_at'] as String),
            ),
            'updated_at': Timestamp.fromDate(localUpdated),
          };

          if (remoteId != null) {
            final remoteDoc = await collection.doc(remoteId).get();
            if (remoteDoc.exists) {
              final remoteUpdated =
                  (remoteDoc.data()!['updated_at'] as Timestamp).toDate();
              if (direction == 'upload' &&
                  remoteUpdated.isAfter(localUpdated)) {
                // Upload-only mode: local must win and should never be blocked by remote timestamps.
                final now = DateTime.now();
                print(
                  '[StudentSyncService] Upload-only: remote newer, forcing grade upload localId=$localId remoteId=$remoteId localUpdated=$localUpdated remoteUpdated=$remoteUpdated',
                );
                await collection.doc(remoteId).update({
                  ...payload,
                  'updated_at': Timestamp.fromDate(now),
                });
                await db.update(
                  'grades',
                  {'updated_at': now.toIso8601String()},
                  where: 'id = ?',
                  whereArgs: [localId],
                );
                uploaded++;
                continue;
              }

              if (localUpdated.isAfter(remoteUpdated)) {
                // Local is newer, upload
                await collection.doc(remoteId).update(payload);
                uploaded++;
                print('[StudentSyncService] Uploaded grade id=$localId');
              }
            }
          } else {
            // New local grade, upload
            final docRef = await collection.add(payload);
            await db.update(
              'grades',
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
            print(
              '[StudentSyncService] Created remote grade for local id=$localId',
            );
          }
        }
      }

      if (direction != 'upload') {
        // Download remote grades
        for (final remoteDoc in remoteSnapshot.docs) {
          final remoteData = remoteDoc.data();
          final remoteId = remoteDoc.id;

          final localGrades = await db.query(
            'grades',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
          );

          final remoteClassRemoteId =
              remoteData['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remoteData['grading_period_remote_id']?.toString() ?? '';
          final remoteCategoryRemoteId =
              remoteData['category_remote_id']?.toString() ?? '';

          if (remoteClassRemoteId.isEmpty ||
              remotePeriodRemoteId.isEmpty ||
              remoteCategoryRemoteId.isEmpty) {
            print(
              '[StudentSyncService] Skipping grade download: missing FK remote_ids class=$remoteClassRemoteId period=$remotePeriodRemoteId category=$remoteCategoryRemoteId',
            );
            continue;
          }

          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            remoteClassRemoteId,
          );
          final resolvedPeriodId = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            remotePeriodRemoteId,
          );
          final resolvedCategoryId = await _getLocalIdForRemoteId(
            db,
            'grading_categories',
            remoteCategoryRemoteId,
          );
          if (resolvedClassId == null ||
              resolvedPeriodId == null ||
              resolvedCategoryId == null) {
            print(
              '[StudentSyncService] Skipping grade download: FK remote_id not found locally class=$remoteClassRemoteId period=$remotePeriodRemoteId category=$remoteCategoryRemoteId',
            );
            continue;
          }

          final remoteUpdated = (remoteData['updated_at'] as Timestamp)
              .toDate();

          final gradeData = {
            'student_id': localStudentId,
            'class_id': resolvedClassId,
            'grading_period_id': resolvedPeriodId,
            'category_id': resolvedCategoryId,
            'score': remoteData['score'],
            'max_score': remoteData['max_score'],
            'remarks': remoteData['remarks'] ?? '',
            'recorded_at': (remoteData['recorded_at'] as Timestamp)
                .toDate()
                .toIso8601String(),
            'updated_at': remoteUpdated.toIso8601String(),
          };

          if (localGrades.isEmpty) {
            final insertData = <String, Object?>{
              ...gradeData,
              'remote_id': remoteId,
              'deleted': 0,
            };
            await db.insert('grades', insertData);
            downloaded++;
            print('[StudentSyncService] Downloaded new grade');
          } else {
            final localId = localGrades.first['id'] as int;
            final localUpdated = DateTime.parse(
              localGrades.first['updated_at'] as String,
            );
            if (remoteUpdated.isAfter(localUpdated)) {
              await db.update(
                'grades',
                gradeData,
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
              print('[StudentSyncService] Updated existing grade id=$localId');
            }
          }
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing grades: $e');
    }

    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  /// Sync student attendance
  static Future<StudentSyncResult> _syncStudentAttendance(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/attendance',
      );

      final localRows = await db.query(
        'attendance',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );
      print('[StudentSyncService] Found ${localRows.length} local attendance');

      // Prefer remote filtering by student_remote_id
      QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
      try {
        remoteSnapshot = await collection
            .where('student_remote_id', isEqualTo: studentInfo.studentRemoteId)
            .get();
      } catch (e) {
        print('[StudentSyncService] Attendance query fallback get(): $e');
        remoteSnapshot = await collection.get();
      }

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final doc in remoteSnapshot.docs) {
        final d = doc.data();
        final sr = d['student_remote_id']?.toString() ?? '';
        if (sr.isNotEmpty && sr != studentInfo.studentRemoteId) continue;
        remoteMap[doc.id] = {...d, 'doc_id': doc.id};
      }

      if (direction != 'download') {
        for (final localRow in localRows) {
          final localId = localRow['id'] as int;
          final remoteId = localRow['remote_id'] as String?;
          final localCreated = DateTime.parse(localRow['created_at'] as String);

          final localClassId = localRow['class_id'] as int?;
          final localPeriodId = localRow['grading_period_id'] as int?;
          final classRemoteId = localClassId == null
              ? null
              : await _getRemoteIdForLocalId(db, 'classes', localClassId);
          final periodRemoteId = localPeriodId == null
              ? null
              : await _getRemoteIdForLocalId(
                  db,
                  'grading_periods',
                  localPeriodId,
                );

          final payload = {
            'student_id': localStudentId,
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentInfo.studentRemoteId,
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'date': localRow['date'],
            'status': localRow['status'],
            'remarks': localRow['remarks'] ?? '',
            'created_at': Timestamp.fromDate(localCreated),
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            final remoteDoc = await collection.doc(remoteId).get();
            if (remoteDoc.exists) {
              final remoteCreated =
                  (remoteDoc.data()!['created_at'] as Timestamp).toDate();
              if (localCreated.isAfter(remoteCreated)) {
                await collection.doc(remoteId).update(payload);
                uploaded++;
              }
            } else {
              final docRef = await collection.add(payload);
              await db.update(
                'attendance',
                {'remote_id': docRef.id},
                where: 'id = ?',
                whereArgs: [localId],
              );
              uploaded++;
            }
          } else {
            final docRef = await collection.add(payload);
            await db.update(
              'attendance',
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
          }
        }
      }

      if (direction != 'upload') {
        for (final remote in remoteMap.values) {
          final remoteId = remote['doc_id']?.toString() ?? '';
          if (remoteId.isEmpty) continue;

          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remoteClassRemoteId.isEmpty || remotePeriodRemoteId.isEmpty) {
            // Legacy row not safe cross-device
            continue;
          }
          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            remoteClassRemoteId,
          );
          final resolvedPeriodId = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            remotePeriodRemoteId,
          );
          if (resolvedClassId == null || resolvedPeriodId == null) continue;

          final localExisting = await db.query(
            'attendance',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );

          final remoteCreated = (remote['created_at'] as Timestamp).toDate();
          if (localExisting.isEmpty) {
            await db.insert('attendance', {
              'student_id': localStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'date': remote['date'],
              'status': remote['status'],
              'remarks': remote['remarks'] ?? '',
              'remote_id': remoteId,
              'deleted': 0,
              'created_at': remoteCreated.toIso8601String(),
            });
            downloaded++;
          } else {
            final localId = localExisting.first['id'] as int;
            final localCreated = DateTime.parse(
              localExisting.first['created_at'] as String,
            );
            if (remoteCreated.isAfter(localCreated)) {
              await db.update(
                'attendance',
                {
                  'student_id': localStudentId,
                  'class_id': resolvedClassId,
                  'grading_period_id': resolvedPeriodId,
                  'date': remote['date'],
                  'status': remote['status'],
                  'remarks': remote['remarks'] ?? '',
                  'created_at': remoteCreated.toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
            }
          }
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing attendance: $e');
    }

    print(
      '[StudentSyncService] Attendance sync done uploaded=$uploaded downloaded=$downloaded',
    );
    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  /// Sync student assessment scores
  static Future<StudentSyncResult> _syncStudentAssessmentScores(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/assessment_scores',
      );

      final localRows = await db.query(
        'assessment_scores',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );
      print(
        '[StudentSyncService] Found ${localRows.length} local assessment_scores',
      );

      QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
      try {
        remoteSnapshot = await collection
            .where('student_remote_id', isEqualTo: studentInfo.studentRemoteId)
            .get();
      } catch (e) {
        // Legacy collections may not have student_remote_id yet
        print(
          '[StudentSyncService] assessment_scores query fallback get(): $e',
        );
        remoteSnapshot = await collection.get();
      }

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final doc in remoteSnapshot.docs) {
        final d = doc.data();
        final sr = d['student_remote_id']?.toString() ?? '';
        if (sr.isNotEmpty && sr != studentInfo.studentRemoteId) continue;
        // For legacy docs without student_remote_id, we skip (can't safely match).
        if (sr.isEmpty) continue;
        remoteMap[doc.id] = {...d, 'doc_id': doc.id};
      }

      if (direction != 'download') {
        for (final localRow in localRows) {
          final localId = localRow['id'] as int;
          final remoteId = localRow['remote_id'] as String?;
          final localUpdated = DateTime.parse(localRow['updated_at'] as String);

          final assessmentId = localRow['assessment_id'] as int;
          final assessmentRemoteId = await _getRemoteIdForLocalId(
            db,
            'grading_assessments',
            assessmentId,
          );
          if (assessmentRemoteId == null || assessmentRemoteId.isEmpty) {
            continue;
          }

          final payload = {
            'assessment_id': assessmentId,
            'assessment_remote_id': assessmentRemoteId,
            'student_id': localStudentId,
            'student_remote_id': studentInfo.studentRemoteId,
            'score': localRow['score'],
            'remarks': localRow['remarks'] ?? '',
            'recorded_at': Timestamp.fromDate(
              DateTime.parse(localRow['recorded_at'] as String),
            ),
            'updated_at': Timestamp.fromDate(localUpdated),
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            final remoteDoc = await collection.doc(remoteId).get();
            if (remoteDoc.exists) {
              final remoteUpdated =
                  (remoteDoc.data()!['updated_at'] as Timestamp).toDate();
              if (direction == 'upload' &&
                  remoteUpdated.isAfter(localUpdated)) {
                // Upload-only mode: local must win and should never be blocked by remote timestamps.
                final now = DateTime.now();
                print(
                  '[StudentSyncService] Upload-only: remote newer, forcing assessment_score upload localId=$localId remoteId=$remoteId localUpdated=$localUpdated remoteUpdated=$remoteUpdated',
                );
                await collection.doc(remoteId).update({
                  ...payload,
                  'updated_at': Timestamp.fromDate(now),
                });
                await db.update(
                  'assessment_scores',
                  {'updated_at': now.toIso8601String()},
                  where: 'id = ?',
                  whereArgs: [localId],
                );
                uploaded++;
                continue;
              }

              if (localUpdated.isAfter(remoteUpdated)) {
                await collection.doc(remoteId).update(payload);
                uploaded++;
              }
            } else {
              final docRef = await collection.add(payload);
              await db.update(
                'assessment_scores',
                {'remote_id': docRef.id},
                where: 'id = ?',
                whereArgs: [localId],
              );
              uploaded++;
            }
          } else {
            final docRef = await collection.add(payload);
            await db.update(
              'assessment_scores',
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
          }
        }
      }

      if (direction != 'upload') {
        for (final remote in remoteMap.values) {
          final remoteId = remote['doc_id']?.toString() ?? '';
          if (remoteId.isEmpty) continue;

          final assessmentRemoteId =
              remote['assessment_remote_id']?.toString() ?? '';
          if (assessmentRemoteId.isEmpty) continue;
          final resolvedAssessmentId = await _getLocalIdForRemoteId(
            db,
            'grading_assessments',
            assessmentRemoteId,
          );
          if (resolvedAssessmentId == null) continue;

          final localExisting = await db.query(
            'assessment_scores',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );

          final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();
          if (localExisting.isEmpty) {
            await db.insert('assessment_scores', {
              'assessment_id': resolvedAssessmentId,
              'student_id': localStudentId,
              'score': remote['score'],
              'remarks': remote['remarks'] ?? '',
              'remote_id': remoteId,
              'deleted': 0,
              'recorded_at': (remote['recorded_at'] as Timestamp)
                  .toDate()
                  .toIso8601String(),
              'updated_at': remoteUpdated.toIso8601String(),
            });
            downloaded++;
          } else {
            final localId = localExisting.first['id'] as int;
            final localUpdated = DateTime.parse(
              localExisting.first['updated_at'] as String,
            );
            if (remoteUpdated.isAfter(localUpdated)) {
              await db.update(
                'assessment_scores',
                {
                  'assessment_id': resolvedAssessmentId,
                  'student_id': localStudentId,
                  'score': remote['score'],
                  'remarks': remote['remarks'] ?? '',
                  'recorded_at': (remote['recorded_at'] as Timestamp)
                      .toDate()
                      .toIso8601String(),
                  'updated_at': remoteUpdated.toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
            }
          }
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing assessment scores: $e');
    }

    print(
      '[StudentSyncService] Assessment scores sync done uploaded=$uploaded downloaded=$downloaded',
    );
    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  /// Sync student interventions
  static Future<StudentSyncResult> _syncStudentInterventions(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    String normalizeYmd(dynamic v) {
      try {
        if (v == null) return '';
        if (v is Timestamp) {
          final d = v.toDate();
          final y = d.year.toString().padLeft(4, '0');
          final m = d.month.toString().padLeft(2, '0');
          final day = d.day.toString().padLeft(2, '0');
          return '$y-$m-$day';
        }
        final s = v.toString().trim();
        if (s.isEmpty) return '';
        if (s.length >= 10) return s.substring(0, 10);
        return s;
      } catch (e) {
        print('[StudentSyncService] normalizeYmd error: $e');
        return '';
      }
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/interventions',
      );

      final localRows = await db.query(
        'interventions',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );

      QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
      try {
        remoteSnapshot = await collection
            .where('student_remote_id', isEqualTo: studentInfo.studentRemoteId)
            .get();
      } catch (e) {
        print('[StudentSyncService] interventions query fallback get(): $e');
        remoteSnapshot = await collection.get();
      }

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final doc in remoteSnapshot.docs) {
        final d = doc.data();
        final sr = d['student_remote_id']?.toString() ?? '';
        if (sr.isNotEmpty && sr != studentInfo.studentRemoteId) continue;
        if (sr.isEmpty) continue;
        remoteMap[doc.id] = {...d, 'doc_id': doc.id};
      }

      if (direction != 'download') {
        for (final localRow in localRows) {
          final localId = localRow['id'] as int;
          final remoteId = localRow['remote_id'] as String?;
          final localUpdated = DateTime.parse(localRow['updated_at'] as String);

          final localClassId = localRow['class_id'] as int?;
          final localPeriodId = localRow['grading_period_id'] as int?;
          final classRemoteId = localClassId == null
              ? null
              : await _getRemoteIdForLocalId(db, 'classes', localClassId);
          final periodRemoteId = localPeriodId == null
              ? null
              : await _getRemoteIdForLocalId(
                  db,
                  'grading_periods',
                  localPeriodId,
                );
          if (classRemoteId == null || classRemoteId.isEmpty) continue;

          final payload = {
            'student_id': localStudentId,
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentInfo.studentRemoteId,
            'class_remote_id': classRemoteId,
            'grading_period_remote_id': periodRemoteId ?? '',
            'title': localRow['title'],
            'description': localRow['description'],
            'intervention_date': localRow['intervention_date'],
            'follow_up_date': localRow['follow_up_date'] ?? '',
            'status': localRow['status'] ?? 'open',
            'updated_at': Timestamp.fromDate(localUpdated),
            'created_at': Timestamp.fromDate(
              DateTime.parse(localRow['created_at'] as String),
            ),
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            final remoteDoc = await collection.doc(remoteId).get();
            if (remoteDoc.exists) {
              final remoteUpdated =
                  (remoteDoc.data()!['updated_at'] as Timestamp).toDate();
              if (localUpdated.isAfter(remoteUpdated)) {
                await collection.doc(remoteId).update(payload);
                uploaded++;
              }
            } else {
              final docRef = await collection.add(payload);
              await db.update(
                'interventions',
                {'remote_id': docRef.id},
                where: 'id = ?',
                whereArgs: [localId],
              );
              uploaded++;
            }
          } else {
            final docRef = await collection.add(payload);
            await db.update(
              'interventions',
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
          }
        }
      }

      if (direction != 'upload') {
        for (final remote in remoteMap.values) {
          final remoteId = remote['doc_id']?.toString() ?? '';
          if (remoteId.isEmpty) continue;

          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          if (remoteClassRemoteId.isEmpty) continue;
          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            remoteClassRemoteId,
          );
          if (resolvedClassId == null) continue;

          int? resolvedPeriodId;
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remotePeriodRemoteId.isNotEmpty) {
            resolvedPeriodId = await _getLocalIdForRemoteId(
              db,
              'grading_periods',
              remotePeriodRemoteId,
            );
          }

          final localExisting = await db.query(
            'interventions',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );

          final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();
          final interventionDateYmd = normalizeYmd(remote['intervention_date']);
          final followUpYmd = normalizeYmd(remote['follow_up_date']);

          if (followUpYmd.isNotEmpty) {
            print(
              '[StudentSyncService] Download intervention followUp=$followUpYmd remoteId=$remoteId studentRemoteId=${studentInfo.studentRemoteId}',
            );
          }

          if (localExisting.isEmpty) {
            await db.insert('interventions', {
              'student_id': localStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'title': remote['title'],
              'description': remote['description'],
              'intervention_date': interventionDateYmd,
              'follow_up_date': followUpYmd,
              'status': remote['status'] ?? 'open',
              'remote_id': remoteId,
              'deleted': 0,
              'created_at': (remote['created_at'] as Timestamp)
                  .toDate()
                  .toIso8601String(),
              'updated_at': remoteUpdated.toIso8601String(),
            });
            downloaded++;
          } else {
            final localId = localExisting.first['id'] as int;
            final localUpdated = DateTime.parse(
              localExisting.first['updated_at'] as String,
            );
            if (remoteUpdated.isAfter(localUpdated)) {
              await db.update(
                'interventions',
                {
                  'student_id': localStudentId,
                  'class_id': resolvedClassId,
                  'grading_period_id': resolvedPeriodId,
                  'title': remote['title'],
                  'description': remote['description'],
                  'intervention_date': interventionDateYmd,
                  'follow_up_date': followUpYmd,
                  'status': remote['status'] ?? 'open',
                  'updated_at': remoteUpdated.toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
            }
          }
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing interventions: $e');
    }

    print(
      '[StudentSyncService] Interventions sync done uploaded=$uploaded downloaded=$downloaded',
    );
    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  /// Sync student risk flags
  static Future<StudentSyncResult> _syncStudentRiskFlags(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/risk_flags',
      );

      final localRows = await db.query(
        'risk_flags',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );

      QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
      try {
        remoteSnapshot = await collection
            .where('student_remote_id', isEqualTo: studentInfo.studentRemoteId)
            .get();
      } catch (e) {
        print('[StudentSyncService] risk_flags query fallback get(): $e');
        remoteSnapshot = await collection.get();
      }

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final doc in remoteSnapshot.docs) {
        final d = doc.data();
        final sr = d['student_remote_id']?.toString() ?? '';
        if (sr.isNotEmpty && sr != studentInfo.studentRemoteId) continue;
        if (sr.isEmpty) continue;
        remoteMap[doc.id] = {...d, 'doc_id': doc.id};
      }

      if (direction != 'download') {
        for (final localRow in localRows) {
          final localId = localRow['id'] as int;
          final remoteId = localRow['remote_id'] as String?;
          final localUpdated = DateTime.parse(localRow['updated_at'] as String);

          final localClassId = localRow['class_id'] as int?;
          final localPeriodId = localRow['grading_period_id'] as int?;
          final classRemoteId = localClassId == null
              ? null
              : await _getRemoteIdForLocalId(db, 'classes', localClassId);
          final periodRemoteId = localPeriodId == null
              ? null
              : await _getRemoteIdForLocalId(
                  db,
                  'grading_periods',
                  localPeriodId,
                );
          if (classRemoteId == null || classRemoteId.isEmpty) continue;
          if (periodRemoteId == null || periodRemoteId.isEmpty) continue;

          final payload = {
            'student_id': localStudentId,
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentInfo.studentRemoteId,
            'class_remote_id': classRemoteId,
            'grading_period_remote_id': periodRemoteId,
            'risk_level': localRow['risk_level'] ?? 'low',
            'grade_score': localRow['grade_score'],
            'attendance_percentage': localRow['attendance_percentage'],
            'flagged_at': Timestamp.fromDate(
              DateTime.parse(localRow['flagged_at'] as String),
            ),
            'updated_at': Timestamp.fromDate(localUpdated),
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            final remoteDoc = await collection.doc(remoteId).get();
            if (remoteDoc.exists) {
              final remoteUpdated =
                  (remoteDoc.data()!['updated_at'] as Timestamp).toDate();
              if (localUpdated.isAfter(remoteUpdated)) {
                await collection.doc(remoteId).update(payload);
                uploaded++;
              }
            } else {
              final docRef = await collection.add(payload);
              await db.update(
                'risk_flags',
                {'remote_id': docRef.id},
                where: 'id = ?',
                whereArgs: [localId],
              );
              uploaded++;
            }
          } else {
            final docRef = await collection.add(payload);
            await db.update(
              'risk_flags',
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
          }
        }
      }

      if (direction != 'upload') {
        for (final remote in remoteMap.values) {
          final remoteId = remote['doc_id']?.toString() ?? '';
          if (remoteId.isEmpty) continue;

          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remoteClassRemoteId.isEmpty || remotePeriodRemoteId.isEmpty) {
            continue;
          }
          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            remoteClassRemoteId,
          );
          final resolvedPeriodId = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            remotePeriodRemoteId,
          );
          if (resolvedClassId == null || resolvedPeriodId == null) continue;

          final localExisting = await db.query(
            'risk_flags',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
            limit: 1,
          );

          final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();
          if (localExisting.isEmpty) {
            await db.insert('risk_flags', {
              'student_id': localStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'risk_level': remote['risk_level'] ?? 'low',
              'grade_score': remote['grade_score'],
              'attendance_percentage': remote['attendance_percentage'],
              'remote_id': remoteId,
              'deleted': 0,
              'flagged_at': (remote['flagged_at'] as Timestamp)
                  .toDate()
                  .toIso8601String(),
              'updated_at': remoteUpdated.toIso8601String(),
            });
            downloaded++;
          } else {
            final localId = localExisting.first['id'] as int;
            final localUpdated = DateTime.parse(
              localExisting.first['updated_at'] as String,
            );
            if (remoteUpdated.isAfter(localUpdated)) {
              await db.update(
                'risk_flags',
                {
                  'student_id': localStudentId,
                  'class_id': resolvedClassId,
                  'grading_period_id': resolvedPeriodId,
                  'risk_level': remote['risk_level'] ?? 'low',
                  'grade_score': remote['grade_score'],
                  'attendance_percentage': remote['attendance_percentage'],
                  'flagged_at': (remote['flagged_at'] as Timestamp)
                      .toDate()
                      .toIso8601String(),
                  'updated_at': remoteUpdated.toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
            }
          }
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing risk flags: $e');
    }

    print(
      '[StudentSyncService] Risk flags sync done uploaded=$uploaded downloaded=$downloaded',
    );
    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }

  /// Sync student class enrollments
  static Future<StudentSyncResult> _syncStudentClassEnrollments(
    StudentAccountInfo studentInfo, {
    required int localStudentId,
    String? direction,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    try {
      final db = await DatabaseHelper.instance.database;
      final collection = _firestore.collection(
        'users/${studentInfo.teacherUid}/class_students',
      );

      final studentRemoteId = await _getRemoteIdForLocalId(
        db,
        'students',
        localStudentId,
      );
      if (studentRemoteId == null || studentRemoteId.isEmpty) {
        print(
          '[StudentSyncService] class_students sync skipped: local student has no remote_id',
        );
        return StudentSyncResult(uploaded: 0, downloaded: 0);
      }

      final localRows = await db.query(
        'class_students',
        where: 'student_id = ? AND deleted = 0',
        whereArgs: [localStudentId],
      );

      QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
      try {
        remoteSnapshot = await collection
            .where('student_remote_id', isEqualTo: studentRemoteId)
            .get();
      } catch (e) {
        print('[StudentSyncService] class_students query fallback get(): $e');
        remoteSnapshot = await collection.get();
      }

      final remotePairs = <String>{};
      for (final doc in remoteSnapshot.docs) {
        final d = doc.data();
        final sr = d['student_remote_id']?.toString() ?? '';
        if (sr.isEmpty || sr != studentRemoteId) continue;
        final cr = d['class_remote_id']?.toString() ?? '';
        if (cr.isEmpty) continue;
        remotePairs.add('$cr|$sr');
      }

      if (direction != 'download') {
        for (final r in localRows) {
          final classId = r['class_id'] as int;
          final classRemoteId = await _getRemoteIdForLocalId(
            db,
            'classes',
            classId,
          );
          if (classRemoteId == null || classRemoteId.isEmpty) continue;

          final key = '$classRemoteId|$studentRemoteId';
          if (remotePairs.contains(key)) continue;

          await collection.add({
            'class_id': classId,
            'student_id': localStudentId,
            'class_remote_id': classRemoteId,
            'student_remote_id': studentRemoteId,
            'enrolled_at': r['enrolled_at'] ?? DateTime.now().toIso8601String(),
          });
          uploaded++;
        }
      }

      if (direction != 'upload') {
        final localPairs = <String>{};
        for (final r in localRows) {
          final classId = r['class_id'] as int;
          final classRemoteId = await _getRemoteIdForLocalId(
            db,
            'classes',
            classId,
          );
          if (classRemoteId == null || classRemoteId.isEmpty) continue;
          localPairs.add('$classRemoteId|$studentRemoteId');
        }

        for (final doc in remoteSnapshot.docs) {
          final d = doc.data();
          final sr = d['student_remote_id']?.toString() ?? '';
          if (sr.isEmpty || sr != studentRemoteId) continue;
          final cr = d['class_remote_id']?.toString() ?? '';
          if (cr.isEmpty) continue;

          final key = '$cr|$sr';
          if (localPairs.contains(key)) continue;

          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            cr,
          );
          if (resolvedClassId == null) continue;

          await db.insert('class_students', {
            'class_id': resolvedClassId,
            'student_id': localStudentId,
            'enrolled_at':
                (d['enrolled_at'] as String?) ??
                DateTime.now().toIso8601String(),
            'remote_id': doc.id,
            'deleted': 0,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          downloaded++;
        }
      }
    } catch (e) {
      print('[StudentSyncService] Error syncing class enrollments: $e');
    }

    print(
      '[StudentSyncService] Class enrollments sync done uploaded=$uploaded downloaded=$downloaded',
    );
    return StudentSyncResult(uploaded: uploaded, downloaded: downloaded);
  }
}

/// Result class for student sync operations
class StudentSyncResult {
  final int uploaded;
  final int downloaded;
  final String? error;

  StudentSyncResult({
    required this.uploaded,
    required this.downloaded,
    this.error,
  });

  String summary() {
    if (error != null) {
      return 'Error: $error';
    }
    return 'Uploaded: $uploaded, Downloaded: $downloaded';
  }
}
