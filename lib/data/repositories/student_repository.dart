import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/student_model.dart';
import '../../core/services/auto_sync_service.dart';

class StudentRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  Future<List<Student>> getAllStudents() async {
    if (kIsWeb) {
      return await _getWebAllStudents();
    }

    final db = await _db.database;
    final maps = await db.query(
      'students',
      where: 'COALESCE(deleted, 0) = 0',
      orderBy: 'last_name ASC, first_name ASC',
    );
    print(
      '[StudentRepository] getAllStudents: ${maps.length} records returned',
    );
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  Future<List<Student>> _getWebAllStudents() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final studentsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/students')
          .where('deleted', isEqualTo: false)
          .orderBy('last_name')
          .orderBy('first_name')
          .get();

      final students = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Student(
          id: int.tryParse(doc.id),
          firstName: data['first_name'] ?? '',
          lastName: data['last_name'] ?? '',
          email: data['email'],
          studentId: data['student_id'],
          phone: data['phone'],
          address: data['address'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print('[StudentRepository] Web loaded ${students.length} students');
      return students;
    } catch (e) {
      print('[StudentRepository] Error loading web students: $e');
      return [];
    }
  }

  Future<List<Student>> getStudentsByClass(int classId) async {
    if (kIsWeb) {
      return await _getWebStudentsByClass(classId);
    }

    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT s.* FROM students s
      INNER JOIN class_students cs ON cs.student_id = s.id
      WHERE cs.class_id = ?
        AND COALESCE(s.deleted, 0) = 0
      ORDER BY s.last_name ASC, s.first_name ASC
    ''',
      [classId],
    );
    print(
      '[StudentRepository] getStudentsByClass($classId): ${maps.length} records',
    );
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  Future<List<Student>> _getWebStudentsByClass(int classId) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final classStudentsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/class_students')
          .where('class_id', isEqualTo: classId)
          .get();

      final studentIds = classStudentsSnapshot.docs
          .map((doc) => doc.data()['student_id'] as int)
          .where((id) => id != null)
          .toSet();

      if (studentIds.isEmpty) return [];

      final studentsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/students')
          .where(
            FieldPath.documentId,
            whereIn: studentIds.map((id) => id.toString()).toList(),
          )
          .where('deleted', isEqualTo: false)
          .orderBy('last_name')
          .orderBy('first_name')
          .get();

      final students = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Student(
          id: int.tryParse(doc.id),
          firstName: data['first_name'] ?? '',
          lastName: data['last_name'] ?? '',
          email: data['email'],
          studentId: data['student_id'],
          phone: data['phone'],
          address: data['address'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[StudentRepository] Web loaded ${students.length} students for class $classId',
      );
      return students;
    } catch (e) {
      print('[StudentRepository] Error loading web students by class: $e');
      return [];
    }
  }

  Future<Student?> getStudentById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'students',
      where: 'id = ? AND COALESCE(deleted, 0) = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Student.fromMap(maps.first);
  }

  Future<bool> isStudentIdDuplicate(String studentId, {int? excludeId}) async {
    final db = await _db.database;
    final query = excludeId != null
        ? await db.query(
            'students',
            where: 'student_id = ? AND id != ?',
            whereArgs: [studentId, excludeId],
          )
        : await db.query(
            'students',
            where: 'student_id = ?',
            whereArgs: [studentId],
          );
    return query.isNotEmpty;
  }

  Future<int> insertStudent(Student student) async {
    final db = await _db.database;
    final id = await db.insert(
      'students',
      student.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print(
      '[StudentRepository] insertStudent: new id=$id, studentId=${student.studentId}',
    );

    // Auto-sync to Firebase if internet is available
    AutoSyncService.syncStudent(id).catchError((e) {
      print('[StudentRepository] Auto-sync failed: $e');
    });

    return id;
  }

  Future<int> updateStudent(Student student) async {
    final db = await _db.database;
    final count = await db.update(
      'students',
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
    print(
      '[StudentRepository] updateStudent id=${student.id}: $count rows affected',
    );

    // Auto-sync to Firebase if internet is available
    if (student.id != null) {
      AutoSyncService.syncStudent(student.id!).catchError((e) {
        print('[StudentRepository] Auto-sync failed: $e');
      });
    }

    return count;
  }

  Future<int> deleteStudent(int id) async {
    final db = await _db.database;
    final count = await db.delete('students', where: 'id = ?', whereArgs: [id]);
    print('[StudentRepository] deleteStudent id=$id: $count rows affected');
    return count;
  }

  Future<void> enrollStudentToClass(int classId, int studentId) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('class_students', {
      'class_id': classId,
      'student_id': studentId,
      'enrolled_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    print(
      '[StudentRepository] enrollStudentToClass classId=$classId studentId=$studentId',
    );
  }

  Future<void> unenrollStudentFromClass(int classId, int studentId) async {
    final db = await _db.database;
    await db.delete(
      'class_students',
      where: 'class_id = ? AND student_id = ?',
      whereArgs: [classId, studentId],
    );
    print(
      '[StudentRepository] unenrollStudentFromClass classId=$classId studentId=$studentId',
    );
  }

  Future<List<Student>> getStudentsNotInClass(int classId) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT * FROM students
      WHERE COALESCE(deleted, 0) = 0
        AND id NOT IN (
        SELECT student_id FROM class_students WHERE class_id = ?
      )
      ORDER BY last_name ASC, first_name ASC
    ''',
      [classId],
    );
    print(
      '[StudentRepository] getStudentsNotInClass($classId): ${maps.length}',
    );
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  Future<int> getTotalStudents() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM students WHERE COALESCE(deleted, 0) = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
