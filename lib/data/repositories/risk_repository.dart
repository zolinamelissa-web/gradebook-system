import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';

class RiskRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  Future<Map<String, dynamic>?> getLatestRiskFlagForStudent({
    required int studentId,
    required int classId,
  }) async {
    if (kIsWeb) {
      return await _getWebLatestRiskFlagForStudent(
        studentId: studentId,
        classId: classId,
      );
    }

    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT rf.*
      FROM risk_flags rf
      WHERE rf.student_id = ? AND rf.class_id = ?
      ORDER BY rf.updated_at DESC
      LIMIT 1
    ''',
      [studentId, classId],
    );
    print(
      '[RiskRepository] getLatestRiskFlagForStudent s=$studentId c=$classId: ${maps.length}',
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<Map<String, dynamic>?> _getWebLatestRiskFlagForStudent({
    required int studentId,
    required int classId,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    try {
      final riskFlagsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/risk_flags')
          .where('student_id', isEqualTo: studentId)
          .where('class_id', isEqualTo: classId)
          .orderBy('updated_at', descending: true)
          .limit(1)
          .get();

      if (riskFlagsSnapshot.docs.isEmpty) return null;

      final data = riskFlagsSnapshot.docs.first.data();
      print(
        '[RiskRepository] Web getLatestRiskFlagForStudent s=$studentId c=$classId: 1',
      );
      return data;
    } catch (e) {
      print('[RiskRepository] Error loading web risk flag: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAtRiskStudents() async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT
        s.id as student_id,
        COALESCE(rf.class_id, 0) as class_id,
        (s.first_name || ' ' || s.last_name) as student_name,
        s.student_id as student_code,
        s.photo_path,
        rf.risk_level as risk_level
      FROM (
        SELECT student_id, class_id, risk_level, MAX(updated_at) as updated_at
        FROM risk_flags
        GROUP BY student_id, class_id
      ) rf
      INNER JOIN students s ON s.id = rf.student_id
      WHERE rf.risk_level IN ('high', 'medium')
      ORDER BY
        CASE rf.risk_level
          WHEN 'high' THEN 2
          WHEN 'medium' THEN 1
          ELSE 0
        END DESC,
        s.last_name ASC
    ''');
    print('[RiskRepository] getAtRiskStudents: ${maps.length}');
    return maps;
  }

  Future<List<Map<String, dynamic>>> getRiskFlags({
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT rf.*, (s.first_name || ' ' || s.last_name) as student_name, s.student_id as student_code
      FROM risk_flags rf
      INNER JOIN students s ON s.id = rf.student_id
      WHERE rf.class_id = ? AND rf.grading_period_id = ?
      ORDER BY rf.risk_level DESC
    ''',
      [classId, periodId],
    );
    print(
      '[RiskRepository] getRiskFlags c=$classId p=$periodId: ${maps.length}',
    );
    return maps;
  }

  Future<void> upsertRiskFlag({
    required int studentId,
    required int classId,
    required int periodId,
    required String riskLevel,
    required double gradeScore,
    required double attendancePercentage,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'risk_flags',
      where: 'student_id = ? AND class_id = ? AND grading_period_id = ?',
      whereArgs: [studentId, classId, periodId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'risk_flags',
        {
          'risk_level': riskLevel,
          'grade_score': gradeScore,
          'attendance_percentage': attendancePercentage,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('risk_flags', {
        'student_id': studentId,
        'class_id': classId,
        'grading_period_id': periodId,
        'risk_level': riskLevel,
        'grade_score': gradeScore,
        'attendance_percentage': attendancePercentage,
        'flagged_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    print(
      '[RiskRepository] upsertRiskFlag s=$studentId level=$riskLevel grade=$gradeScore att=$attendancePercentage',
    );
  }

  Future<int> getAtRiskCount(int classId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT student_id) as count FROM risk_flags
      WHERE class_id = ? AND risk_level IN ('high', 'medium')
    ''',
      [classId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> computeAndSaveRiskFlags({
    required int classId,
    required int periodId,
    required List<int> studentIds,
    required double gradeThreshold,
    required double attendanceThreshold,
    required Map<int, double> grades,
    required Map<int, double> attendances,
  }) async {
    for (final sid in studentIds) {
      final grade = grades[sid] ?? 0;
      final att = attendances[sid] ?? 100;
      String riskLevel = 'low';
      if (grade < gradeThreshold && att < attendanceThreshold) {
        riskLevel = 'high';
      } else if (grade < gradeThreshold || att < attendanceThreshold) {
        riskLevel = 'medium';
      }
      await upsertRiskFlag(
        studentId: sid,
        classId: classId,
        periodId: periodId,
        riskLevel: riskLevel,
        gradeScore: grade,
        attendancePercentage: att,
      );
    }
    print(
      '[RiskRepository] computeAndSaveRiskFlags for ${studentIds.length} students',
    );
  }
}
