import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/lesson_model.dart';

class LessonRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  Future<int> insertLesson(Lesson lesson) async {
    if (kIsWeb) {
      return await _insertWebLesson(lesson);
    }

    try {
      final db = await _dbHelper.database;
      final data = lesson.toMap()..remove('id');
      print('[LessonRepository] insertLesson DATA: $data');
      final id = await db.insert('lessons', data);
      print('[LessonRepository] Inserted lesson id=$id');
      return id;
    } catch (e, st) {
      print('[LessonRepository] ERROR insertLesson: $e');
      print('[LessonRepository] STACK insertLesson: $st');
      rethrow;
    }
  }

  Future<int> _insertWebLesson(Lesson lesson) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) throw Exception('No Firebase user');

    try {
      final docRef = await _firestore
          .collection('users/${firebaseUser.uid}/lessons')
          .add({
            'title': lesson.title,
            'class_id': lesson.classId,
            'week_number': lesson.weekNumber,
            'pdf_path': lesson.pdfPath,
            'content': lesson.content,
            'objectives': lesson.objectives,
            'refs': lesson.references,
            'remote_id': lesson.remoteId,
            'deleted': lesson.deleted,
            'created_at': lesson.createdAt,
            'updated_at': lesson.updatedAt,
          });

      print('[LessonRepository] Web insertLesson id=${docRef.id}');
      return int.tryParse(docRef.id) ?? 0;
    } catch (e) {
      print('[LessonRepository] Error inserting web lesson: $e');
      rethrow;
    }
  }

  Future<int> updateLesson(Lesson lesson) async {
    try {
      final db = await _dbHelper.database;
      final data = lesson.toMap()..remove('id');
      print('[LessonRepository] updateLesson ID=${lesson.id} DATA: $data');
      final count = await db.update(
        'lessons',
        data,
        where: 'id = ?',
        whereArgs: [lesson.id],
      );
      print('[LessonRepository] Updated lesson id=${lesson.id}: $count rows');
      return count;
    } catch (e, st) {
      print('[LessonRepository] ERROR updateLesson id=${lesson.id}: $e');
      print('[LessonRepository] STACK updateLesson: $st');
      rethrow;
    }
  }

  Future<int> deleteLesson(int id) async {
    try {
      final db = await _dbHelper.database;
      final data = {
        'deleted': 1,
        'updated_at': DateTime.now().toIso8601String(),
      };
      print('[LessonRepository] deleteLesson ID=$id DATA: $data');
      final count = await db.update(
        'lessons',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[LessonRepository] Soft deleted lesson id=$id: $count rows');
      return count;
    } catch (e, st) {
      print('[LessonRepository] ERROR deleteLesson id=$id: $e');
      print('[LessonRepository] STACK deleteLesson: $st');
      rethrow;
    }
  }

  Future<List<Lesson>> getLessonsByClassId(int classId) async {
    try {
      final db = await _dbHelper.database;
      print('[LessonRepository] getLessonsByClassId($classId) START');
      final maps = await db.query(
        'lessons',
        where: 'class_id = ? AND deleted = 0',
        whereArgs: [classId],
        orderBy: 'week_number ASC',
      );
      print(
        '[LessonRepository] getLessonsByClassId($classId): ${maps.length} records',
      );
      return maps.map((map) => Lesson.fromMap(map)).toList();
    } catch (e, st) {
      print('[LessonRepository] ERROR getLessonsByClassId($classId): $e');
      print('[LessonRepository] STACK getLessonsByClassId: $st');
      rethrow;
    }
  }

  Future<Lesson?> getLessonById(int id) async {
    try {
      final db = await _dbHelper.database;
      print('[LessonRepository] getLessonById($id) START');
      final maps = await db.query(
        'lessons',
        where: 'id = ? AND deleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      print('[LessonRepository] getLessonById($id) rows=${maps.length}');
      if (maps.isEmpty) return null;
      return Lesson.fromMap(maps.first);
    } catch (e, st) {
      print('[LessonRepository] ERROR getLessonById($id): $e');
      print('[LessonRepository] STACK getLessonById: $st');
      rethrow;
    }
  }

  Future<Lesson?> getLessonByClassAndWeek(int classId, int weekNumber) async {
    try {
      final db = await _dbHelper.database;
      print(
        '[LessonRepository] getLessonByClassAndWeek(classId=$classId, week=$weekNumber) START',
      );
      final maps = await db.query(
        'lessons',
        where: 'class_id = ? AND week_number = ? AND deleted = 0',
        whereArgs: [classId, weekNumber],
        limit: 1,
      );
      print(
        '[LessonRepository] getLessonByClassAndWeek(classId=$classId, week=$weekNumber) rows=${maps.length}',
      );
      if (maps.isEmpty) return null;
      return Lesson.fromMap(maps.first);
    } catch (e, st) {
      print(
        '[LessonRepository] ERROR getLessonByClassAndWeek(classId=$classId, week=$weekNumber): $e',
      );
      print('[LessonRepository] STACK getLessonByClassAndWeek: $st');
      rethrow;
    }
  }

  Future<List<Lesson>> getAllLessons() async {
    try {
      final db = await _dbHelper.database;
      print('[LessonRepository] getAllLessons START');
      final maps = await db.query(
        'lessons',
        where: 'deleted = 0',
        orderBy: 'class_id ASC, week_number ASC',
      );
      print('[LessonRepository] getAllLessons: ${maps.length} records');
      return maps.map((map) => Lesson.fromMap(map)).toList();
    } catch (e, st) {
      print('[LessonRepository] ERROR getAllLessons: $e');
      print('[LessonRepository] STACK getAllLessons: $st');
      rethrow;
    }
  }
}
