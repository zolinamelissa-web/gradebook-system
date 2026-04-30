import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/intervention_model.dart';

class InterventionRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<List<Intervention>> getInterventionsByStudent({
    required int studentId,
    required int classId,
  }) async {
    if (kIsWeb) {
      return await _getWebInterventionsByStudent(
        studentId: studentId,
        classId: classId,
      );
    }

    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT i.*, (s.first_name || ' ' || s.last_name) as student_name
      FROM interventions i
      INNER JOIN students s ON s.id = i.student_id
      WHERE i.student_id = ? AND i.class_id = ?
      ORDER BY i.intervention_date DESC
    ''',
      [studentId, classId],
    );
    print(
      '[InterventionRepository] getInterventionsByStudent s=$studentId c=$classId: ${maps.length}',
    );
    return maps.map((m) => Intervention.fromMap(m)).toList();
  }

  Future<List<Intervention>> _getWebInterventionsByStudent({
    required int studentId,
    required int classId,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final interventionsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/interventions')
          .where('student_id', isEqualTo: studentId)
          .where('class_id', isEqualTo: classId)
          .orderBy('intervention_date', descending: true)
          .get();

      final interventions = interventionsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Intervention(
          id: int.tryParse(doc.id),
          studentId: data['student_id'] ?? 0,
          classId: data['class_id'] ?? 0,
          gradingPeriodId: data['grading_period_id'],
          title: data['title'] ?? '',
          description: data['description'] ?? '',
          interventionDate: data['intervention_date'] ?? '',
          followUpDate: data['follow_up_date'],
          status: data['status'] ?? 'open',
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[InterventionRepository] Web loaded ${interventions.length} interventions for student=$studentId',
      );
      return interventions;
    } catch (e) {
      print('[InterventionRepository] Error loading web interventions: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowUpInterventionsDueToday() async {
    final db = await _db.database;
    final today = _todayYmd();

    final rows = await db.rawQuery(
      '''
      SELECT
        i.*, 
        (s.first_name || ' ' || s.last_name) as student_name,
        c.section as class_section,
        c.school_year as class_school_year,
        sub.code as subject_code,
        sub.name as subject_name
      FROM interventions i
      INNER JOIN students s ON s.id = i.student_id
      INNER JOIN classes c ON c.id = i.class_id
      INNER JOIN subjects sub ON sub.id = c.subject_id
      WHERE COALESCE(i.deleted, 0) = 0
        AND COALESCE(i.follow_up_date, '') != ''
        AND substr(i.follow_up_date, 1, 10) = ?
      ORDER BY i.follow_up_date ASC, i.updated_at DESC
      ''',
      [today],
    );

    print(
      '[InterventionRepository] getFollowUpInterventionsDueToday today=$today count=${rows.length}',
    );
    return rows;
  }

  Future<List<Intervention>> getInterventionsByClass(int classId) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT i.*, (s.first_name || ' ' || s.last_name) as student_name
      FROM interventions i
      INNER JOIN students s ON s.id = i.student_id
      WHERE i.class_id = ?
      ORDER BY i.intervention_date DESC
    ''',
      [classId],
    );
    print(
      '[InterventionRepository] getInterventionsByClass c=$classId: ${maps.length}',
    );
    return maps.map((m) => Intervention.fromMap(m)).toList();
  }

  Future<int> insertIntervention(Intervention intervention) async {
    final db = await _db.database;
    final id = await db.insert(
      'interventions',
      intervention.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print(
      '[InterventionRepository] insertIntervention id=$id title=${intervention.title}',
    );
    return id;
  }

  Future<int> updateIntervention(Intervention intervention) async {
    final db = await _db.database;
    final count = await db.update(
      'interventions',
      intervention.toMap(),
      where: 'id = ?',
      whereArgs: [intervention.id],
    );
    print(
      '[InterventionRepository] updateIntervention id=${intervention.id}: $count rows',
    );
    return count;
  }

  Future<int> deleteIntervention(int id) async {
    final db = await _db.database;
    final count = await db.delete(
      'interventions',
      where: 'id = ?',
      whereArgs: [id],
    );
    print('[InterventionRepository] deleteIntervention id=$id: $count rows');
    return count;
  }

  Future<int> getInterventionCount(int classId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM interventions WHERE class_id = ?',
      [classId],
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
