import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/subject_model.dart';
import '../models/class_model.dart';
import '../../core/services/auto_sync_service.dart';

class SubjectRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  Future<List<Subject>> getAllSubjects({bool includeArchived = false}) async {
    if (kIsWeb) {
      return await _getWebAllSubjects(includeArchived: includeArchived);
    }

    final db = await _db.database;
    final maps = includeArchived
        ? await db.query('subjects', orderBy: 'name ASC')
        : await db.query(
            'subjects',
            where: 'COALESCE(is_archived, 0) = 0',
            orderBy: 'name ASC',
          );
    print('[SubjectRepository] getAllSubjects: ${maps.length} records');
    return maps.map((m) => Subject.fromMap(m)).toList();
  }

  Future<List<Subject>> _getWebAllSubjects({
    bool includeArchived = false,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      QuerySnapshot<Map<String, dynamic>> subjectsSnapshot;
      if (includeArchived) {
        subjectsSnapshot = await _firestore
            .collection('users/${firebaseUser.uid}/subjects')
            .orderBy('name')
            .get();
      } else {
        subjectsSnapshot = await _firestore
            .collection('users/${firebaseUser.uid}/subjects')
            .where('is_archived', isEqualTo: false)
            .orderBy('name')
            .get();
      }

      final subjects = subjectsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Subject(
          id: int.tryParse(doc.id),
          code: data['code'] ?? '',
          name: data['name'] ?? '',
          description: data['description'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print('[SubjectRepository] Web loaded ${subjects.length} subjects');
      return subjects;
    } catch (e) {
      print('[SubjectRepository] Error loading web subjects: $e');
      return [];
    }
  }

  Future<Subject?> getSubjectById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'subjects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Subject.fromMap(maps.first);
  }

  Future<int> insertSubject(Subject subject) async {
    final db = await _db.database;
    final id = await db.insert(
      'subjects',
      subject.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print('[SubjectRepository] insertSubject: id=$id code=${subject.code}');

    // Auto-sync to Firebase if internet is available
    AutoSyncService.syncSubject(id).catchError((e) {
      print('[SubjectRepository] Auto-sync failed: $e');
    });

    return id;
  }

  Future<int> updateSubject(Subject subject) async {
    final db = await _db.database;
    final count = await db.update(
      'subjects',
      subject.toMap(),
      where: 'id = ?',
      whereArgs: [subject.id],
    );
    print('[SubjectRepository] updateSubject id=${subject.id}: $count rows');

    // Auto-sync to Firebase if internet is available
    if (subject.id != null) {
      AutoSyncService.syncSubject(subject.id!).catchError((e) {
        print('[SubjectRepository] Auto-sync failed: $e');
      });
    }

    return count;
  }

  Future<int> deleteSubject(int id) async {
    final db = await _db.database;
    final count = await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
    print('[SubjectRepository] deleteSubject id=$id: $count rows');
    return count;
  }

  Future<List<ClassModel>> getClassesBySubject(int subjectId) async {
    final db = await _db.database;
    final maps = await db.query(
      'classes',
      where: 'subject_id = ? AND COALESCE(is_archived, 0) = 0',
      whereArgs: [subjectId],
    );
    print(
      '[SubjectRepository] getClassesBySubject($subjectId): ${maps.length}',
    );
    return maps.map((m) => ClassModel.fromMap(m)).toList();
  }

  Future<List<ClassModel>> getAllClasses({bool includeArchived = false}) async {
    final db = await _db.database;
    final maps = includeArchived
        ? await db.rawQuery('''
            SELECT c.*, s.name as subject_name, s.code as subject_code, s.description as subject_description
            FROM classes c
            LEFT JOIN subjects s ON s.id = c.subject_id
            ORDER BY c.created_at DESC
          ''')
        : await db.rawQuery('''
            SELECT c.*, s.name as subject_name, s.code as subject_code, s.description as subject_description
            FROM classes c
            LEFT JOIN subjects s ON s.id = c.subject_id
            WHERE COALESCE(c.is_archived, 0) = 0
            ORDER BY c.created_at DESC
          ''');
    print('[SubjectRepository] getAllClasses: ${maps.length}');
    return maps.map((m) {
      final cls = ClassModel.fromMap(m);
      if (m['subject_name'] != null) {
        cls.subject = Subject(
          id: cls.subjectId,
          code: m['subject_code'] as String? ?? '',
          name: m['subject_name'] as String,
          description: m['subject_description'] as String?,
          createdAt: '',
          updatedAt: '',
        );
      }
      return cls;
    }).toList();
  }

  Future<ClassModel?> getClassById(int id) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT c.*, s.name as subject_name, s.code as subject_code, s.description as subject_description
      FROM classes c
      LEFT JOIN subjects s ON s.id = c.subject_id
      WHERE c.id = ?
    ''',
      [id],
    );
    if (maps.isEmpty) return null;
    final cls = ClassModel.fromMap(maps.first);
    if (maps.first['subject_name'] != null) {
      cls.subject = Subject(
        id: cls.subjectId,
        code: maps.first['subject_code'] as String? ?? '',
        name: maps.first['subject_name'] as String,
        description: maps.first['subject_description'] as String?,
        createdAt: '',
        updatedAt: '',
      );
    }
    return cls;
  }

  Future<int> insertClass(ClassModel cls) async {
    final db = await _db.database;
    final id = await db.insert(
      'classes',
      cls.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print('[SubjectRepository] insertClass: id=$id section=${cls.section}');

    // Auto-sync to Firebase if internet is available
    AutoSyncService.syncClass(id).catchError((e) {
      print('[SubjectRepository] Auto-sync failed: $e');
    });

    return id;
  }

  Future<int> updateClass(ClassModel cls) async {
    final db = await _db.database;
    final count = await db.update(
      'classes',
      cls.toMap(),
      where: 'id = ?',
      whereArgs: [cls.id],
    );
    print('[SubjectRepository] updateClass id=${cls.id}: $count rows');

    // Auto-sync to Firebase if internet is available
    if (cls.id != null) {
      AutoSyncService.syncClass(cls.id!).catchError((e) {
        print('[SubjectRepository] Auto-sync failed: $e');
      });
    }

    return count;
  }

  Future<int> deleteClass(int id) async {
    final db = await _db.database;
    final count = await db.delete('classes', where: 'id = ?', whereArgs: [id]);
    print('[SubjectRepository] deleteClass id=$id: $count rows');
    return count;
  }

  Future<int> getTotalClasses() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM classes WHERE COALESCE(is_archived, 0) = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
