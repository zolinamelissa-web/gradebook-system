import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/attendance_model.dart';

class AttendanceRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  Future<List<Attendance>> getAttendanceByDate({
    required int classId,
    required int periodId,
    required String date,
  }) async {
    if (kIsWeb) {
      return await _getWebAttendanceByDate(
        classId: classId,
        periodId: periodId,
        date: date,
      );
    }

    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT a.*, (s.first_name || ' ' || s.last_name) as student_name
      FROM attendance a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.class_id = ? AND a.grading_period_id = ? AND a.date = ?
      ORDER BY s.last_name ASC
    ''',
      [classId, periodId, date],
    );
    print(
      '[AttendanceRepository] getAttendanceByDate date=$date: ${maps.length}',
    );
    return maps.map((m) => Attendance.fromMap(m)).toList();
  }

  Future<List<Attendance>> _getWebAttendanceByDate({
    required int classId,
    required int periodId,
    required String date,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final attendanceSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/attendance')
          .where('class_id', isEqualTo: classId)
          .where('grading_period_id', isEqualTo: periodId)
          .where('date', isEqualTo: date)
          .get();

      final attendance = attendanceSnapshot.docs.map((doc) {
        final data = doc.data();
        return Attendance(
          id: int.tryParse(doc.id),
          studentId: data['student_id'] ?? 0,
          classId: data['class_id'] ?? 0,
          gradingPeriodId: data['grading_period_id'] ?? 0,
          date: data['date'] ?? '',
          status: data['status'] ?? '',
          remarks: data['remarks'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[AttendanceRepository] Web loaded ${attendance.length} attendance records for date=$date',
      );
      return attendance;
    } catch (e) {
      print('[AttendanceRepository] Error loading web attendance by date: $e');
      return [];
    }
  }

  Future<List<Attendance>> getAttendanceByStudent({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    if (kIsWeb) {
      return await _getWebAttendanceByStudent(
        studentId: studentId,
        classId: classId,
        periodId: periodId,
      );
    }

    final db = await _db.database;
    final maps = await db.query(
      'attendance',
      where: 'student_id = ? AND class_id = ? AND grading_period_id = ?',
      whereArgs: [studentId, classId, periodId],
      orderBy: 'date DESC',
    );
    print(
      '[AttendanceRepository] getAttendanceByStudent s=$studentId c=$classId p=$periodId: ${maps.length}',
    );
    return maps.map((m) => Attendance.fromMap(m)).toList();
  }

  Future<List<Attendance>> _getWebAttendanceByStudent({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final attendanceSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/attendance')
          .where('student_id', isEqualTo: studentId)
          .where('class_id', isEqualTo: classId)
          .where('grading_period_id', isEqualTo: periodId)
          .orderBy('date', descending: true)
          .get();

      final attendance = attendanceSnapshot.docs.map((doc) {
        final data = doc.data();
        return Attendance(
          id: int.tryParse(doc.id),
          studentId: data['student_id'] ?? 0,
          classId: data['class_id'] ?? 0,
          gradingPeriodId: data['grading_period_id'] ?? 0,
          date: data['date'] ?? '',
          status: data['status'] ?? '',
          remarks: data['remarks'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[AttendanceRepository] Web loaded ${attendance.length} attendance records for student=$studentId',
      );
      return attendance;
    } catch (e) {
      print(
        '[AttendanceRepository] Error loading web attendance by student: $e',
      );
      return [];
    }
  }

  Future<Map<String, int>> getAttendanceSummary({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT status, COUNT(*) as count
      FROM attendance
      WHERE student_id = ? AND class_id = ? AND grading_period_id = ?
      GROUP BY status
    ''',
      [studentId, classId, periodId],
    );
    final summary = {'present': 0, 'absent': 0, 'late': 0};
    for (final row in maps) {
      final status = row['status'] as String;
      summary[status] = (row['count'] as int?) ?? 0;
    }
    print('[AttendanceRepository] getAttendanceSummary s=$studentId: $summary');
    return summary;
  }

  Future<double> getAttendancePercentage({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final summary = await getAttendanceSummary(
      studentId: studentId,
      classId: classId,
      periodId: periodId,
    );
    final total = summary.values.fold(0, (a, b) => a + b);
    if (total == 0) return 100;
    final present = (summary['present'] ?? 0) + (summary['late'] ?? 0);
    return (present / total) * 100;
  }

  Future<int> upsertAttendance(Attendance attendance) async {
    final db = await _db.database;
    final existing = await db.query(
      'attendance',
      where:
          'student_id = ? AND class_id = ? AND grading_period_id = ? AND date = ?',
      whereArgs: [
        attendance.studentId,
        attendance.classId,
        attendance.gradingPeriodId,
        attendance.date,
      ],
      limit: 1,
    );
    int id;
    if (existing.isNotEmpty) {
      await db.update(
        'attendance',
        {'status': attendance.status, 'remarks': attendance.remarks},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      id = existing.first['id'] as int;
      print(
        '[AttendanceRepository] upsertAttendance UPDATED id=$id status=${attendance.status}',
      );
    } else {
      id = await db.insert(
        'attendance',
        attendance.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
        '[AttendanceRepository] upsertAttendance INSERTED id=$id status=${attendance.status}',
      );
    }
    return id;
  }

  Future<List<String>> getAttendanceDates({
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT DISTINCT date FROM attendance
      WHERE class_id = ? AND grading_period_id = ?
      ORDER BY date DESC
    ''',
      [classId, periodId],
    );
    return maps.map((m) => m['date'] as String).toList();
  }

  Future<List<Attendance>> getAttendanceByDateRange({
    required int classId,
    required int periodId,
    required String startDate,
    required String endDate,
  }) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT a.*, (s.first_name || ' ' || s.last_name) as student_name
      FROM attendance a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.class_id = ?
        AND a.grading_period_id = ?
        AND a.date >= ?
        AND a.date <= ?
      ORDER BY a.date DESC, s.last_name ASC
    ''',
      [classId, periodId, startDate, endDate],
    );
    print(
      '[AttendanceRepository] getAttendanceByDateRange start=$startDate end=$endDate: ${maps.length}',
    );
    return maps.map((m) => Attendance.fromMap(m)).toList();
  }

  Future<Map<int, double>> getClassAttendancePercentages({
    required int classId,
    required int periodId,
    required List<int> studentIds,
  }) async {
    final result = <int, double>{};
    for (final sid in studentIds) {
      result[sid] = await getAttendancePercentage(
        studentId: sid,
        classId: classId,
        periodId: periodId,
      );
    }
    return result;
  }
}
