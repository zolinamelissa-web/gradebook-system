import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';

class AutoSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final AuthRepository _authRepo = AuthRepository();
  static final Connectivity _connectivity = Connectivity();

  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.ethernet);
    } catch (e) {
      print('[AutoSync] Error checking connectivity: $e');
      return false;
    }
  }

  static Future<void> syncStudent(int studentId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping student sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final students = await db.query(
        'students',
        where: 'id = ?',
        whereArgs: [studentId],
      );

      if (students.isEmpty) return;

      final student = students.first;
      final collection = _firestore.collection('users/${user.uid}/students');

      final remoteId = student['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeStudentForFirestore(student);
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'students',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [studentId],
        );
      }

      print('[AutoSync] Student synced successfully: id=$studentId');
    } catch (e) {
      print('[AutoSync] Error syncing student: $e');
    }
  }

  static Future<void> syncClass(int classId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping class sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final classes = await db.query(
        'classes',
        where: 'id = ?',
        whereArgs: [classId],
      );

      if (classes.isEmpty) return;

      final classData = classes.first;
      final collection = _firestore.collection('users/${user.uid}/classes');

      // Resolve stable subject reference for cross-device linking
      String subjectCode = '';
      String subjectRemoteId = '';
      final subjectId = classData['subject_id'] as int?;
      if (subjectId != null) {
        final subjects = await db.query(
          'subjects',
          where: 'id = ?',
          whereArgs: [subjectId],
          limit: 1,
        );
        if (subjects.isNotEmpty) {
          subjectCode = (subjects.first['code'] as String?) ?? '';
          subjectRemoteId = (subjects.first['remote_id'] as String?) ?? '';
        }
      }

      final remoteId = classData['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeClassForFirestore(classData)
        ..['subject_code'] = subjectCode
        ..['subject_remote_id'] = subjectRemoteId;
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'classes',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [classId],
        );
      }

      print('[AutoSync] Class synced successfully: id=$classId');
    } catch (e) {
      print('[AutoSync] Error syncing class: $e');
    }
  }

  static Future<void> syncSubject(int subjectId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping subject sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final subjects = await db.query(
        'subjects',
        where: 'id = ?',
        whereArgs: [subjectId],
      );

      if (subjects.isEmpty) return;

      final subject = subjects.first;
      final collection = _firestore.collection('users/${user.uid}/subjects');

      final remoteId = subject['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeSubjectForFirestore(subject);
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'subjects',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [subjectId],
        );
      }

      print('[AutoSync] Subject synced successfully: id=$subjectId');
    } catch (e) {
      print('[AutoSync] Error syncing subject: $e');
    }
  }

  static Future<void> syncGrade(int gradeId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping grade sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final grades = await db.query(
        'grades',
        where: 'id = ?',
        whereArgs: [gradeId],
      );

      if (grades.isEmpty) return;

      final grade = grades.first;
      final collection = _firestore.collection('users/${user.uid}/grades');

      final remoteId = grade['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeGradeForFirestore(grade);
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'grades',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [gradeId],
        );
      }

      print('[AutoSync] Grade synced successfully: id=$gradeId');
    } catch (e) {
      print('[AutoSync] Error syncing grade: $e');
    }
  }

  static Future<void> syncAttendance(int attendanceId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping attendance sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final attendances = await db.query(
        'attendance',
        where: 'id = ?',
        whereArgs: [attendanceId],
      );

      if (attendances.isEmpty) return;

      final attendance = attendances.first;
      final collection = _firestore.collection('users/${user.uid}/attendance');

      final remoteId = attendance['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeAttendanceForFirestore(attendance);
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'attendance',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [attendanceId],
        );
      }

      print('[AutoSync] Attendance synced successfully: id=$attendanceId');
    } catch (e) {
      print('[AutoSync] Error syncing attendance: $e');
    }
  }

  static Future<void> syncSettings() async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping settings sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final localRows = await db.query('settings');
      final localMap = <String, String>{};
      for (final row in localRows) {
        localMap[row['key'] as String] = row['value'] as String;
      }

      final docRef = _firestore.collection('users').doc(user.uid);
      final remoteDoc = await docRef.get();
      final remoteSettings =
          remoteDoc.data()?['settings'] as Map<String, dynamic>? ?? {};

      // Keys to sync including grade equivalency
      final keysToSync = [
        'teacher_name',
        'school_name',
        'grade_threshold',
        'attendance_threshold',
        'grading_system',
        'grade_equivalency_table',
      ];

      // Upload local settings to cloud
      for (final key in keysToSync) {
        if (localMap.containsKey(key)) {
          remoteSettings[key] = localMap[key];
        }
      }

      await docRef.set({'settings': remoteSettings}, SetOptions(merge: true));
      print('[AutoSync] Settings synced successfully');
    } catch (e) {
      print('[AutoSync] Error syncing settings: $e');
    }
  }

  static Future<void> syncAssessmentScore(int scoreId) async {
    if (!await hasInternetConnection()) {
      print('[AutoSync] No internet, skipping assessment score sync');
      return;
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) return;

      final db = await DatabaseHelper.instance.database;
      final scores = await db.query(
        'assessment_scores',
        where: 'id = ?',
        whereArgs: [scoreId],
      );

      if (scores.isEmpty) return;

      final score = scores.first;
      final collection = _firestore.collection(
        'users/${user.uid}/assessment_scores',
      );

      final remoteId = score['remote_id'] as String?;
      final docRef = remoteId != null
          ? collection.doc(remoteId)
          : collection.doc();

      final data = _encodeAssessmentScoreForFirestore(score);
      await docRef.set(data, SetOptions(merge: true));

      if (remoteId == null) {
        await db.update(
          'assessment_scores',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [scoreId],
        );
      }

      print('[AutoSync] Assessment score synced successfully: id=$scoreId');
    } catch (e) {
      print('[AutoSync] Error syncing assessment score: $e');
    }
  }

  // Encoding helpers
  static Map<String, dynamic> _encodeStudentForFirestore(
    Map<String, Object?> student,
  ) {
    return {
      'student_id': student['student_id'],
      'first_name': student['first_name'],
      'last_name': student['last_name'],
      'middle_name': student['middle_name'] ?? '',
      'email': student['email'] ?? '',
      'phone': student['phone'] ?? '',
      'gender': student['gender'] ?? '',
      'birth_date': student['birth_date'] ?? '',
      'address': student['address'] ?? '',
      'photo_path': student['photo_path'] ?? '',
      'updated_at': _parseTimestamp(student['updated_at']),
    };
  }

  static Map<String, dynamic> _encodeClassForFirestore(
    Map<String, Object?> classData,
  ) {
    return {
      'subject_id': classData['subject_id'],
      'section': classData['section'],
      'school_year': classData['school_year'],
      'semester': classData['semester'] ?? '',
      'schedule': classData['schedule'] ?? '',
      'room': classData['room'] ?? '',
      'is_archived': classData['is_archived'] ?? 0,
      'updated_at': _parseTimestamp(classData['updated_at']),
    };
  }

  static Map<String, dynamic> _encodeSubjectForFirestore(
    Map<String, Object?> subject,
  ) {
    return {
      'code': subject['code'],
      'name': subject['name'],
      'description': subject['description'] ?? '',
      'units': subject['units'] ?? 3,
      'is_archived': subject['is_archived'] ?? 0,
      'updated_at': _parseTimestamp(subject['updated_at']),
    };
  }

  static Map<String, dynamic> _encodeGradeForFirestore(
    Map<String, Object?> grade,
  ) {
    return {
      'student_id': grade['student_id'],
      'class_id': grade['class_id'],
      'grading_period_id': grade['grading_period_id'],
      'category_id': grade['category_id'],
      'score': grade['score'],
      'max_score': grade['max_score'],
      'remarks': grade['remarks'] ?? '',
      'recorded_at': _parseTimestamp(grade['recorded_at']),
      'updated_at': _parseTimestamp(grade['updated_at']),
    };
  }

  static Map<String, dynamic> _encodeAttendanceForFirestore(
    Map<String, Object?> attendance,
  ) {
    return {
      'student_id': attendance['student_id'],
      'class_id': attendance['class_id'],
      'grading_period_id': attendance['grading_period_id'],
      'date': attendance['date'],
      'status': attendance['status'],
      'remarks': attendance['remarks'] ?? '',
      'created_at': _parseTimestamp(attendance['created_at']),
    };
  }

  static Map<String, dynamic> _encodeAssessmentScoreForFirestore(
    Map<String, Object?> score,
  ) {
    return {
      'assessment_id': score['assessment_id'],
      'student_id': score['student_id'],
      'score': score['score'],
      'remarks': score['remarks'] ?? '',
      'recorded_at': _parseTimestamp(score['recorded_at']),
      'updated_at': _parseTimestamp(score['updated_at']),
    };
  }

  static Timestamp _parseTimestamp(Object? value) {
    if (value == null) return Timestamp.now();
    final str = value.toString();
    final dt = DateTime.tryParse(str);
    return dt != null ? Timestamp.fromDate(dt) : Timestamp.now();
  }
}
