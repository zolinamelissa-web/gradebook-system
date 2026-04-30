import '../database/database_helper.dart';
import '../models/student_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import '../../core/services/student_sync_service.dart';
import '../models/grade_equivalency.dart';
import '../models/grading_system_config.dart';
import '../models/intervention_model.dart';
import 'student_account_repository.dart';

/// Repository for student-specific data access
/// This repository filters data to show the student's records across ALL teachers
class StudentDataRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> _hasInternetConnection() async {
    if (kIsWeb) {
      print(
        '[StudentDataRepository] Web platform detected, using Firebase source',
      );
      return true;
    }
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) return false;

      final lookup = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (e) {
      print('[StudentDataRepository] Internet check failed: $e');
      return false;
    }
  }

  Future<int?> _resolveLocalClassIdByRemoteId(String classRemoteId) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'classes',
        columns: ['id'],
        where: 'remote_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [classRemoteId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final v = rows.first['id'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    } catch (e) {
      print(
        '[StudentDataRepository] Error resolving local class id by remote_id=$classRemoteId: $e',
      );
      return null;
    }
  }

  Future<String> _resolveStudentIdFromFirebaseUid(String firebaseUid) async {
    try {
      final active = await StudentAccountRepository.getStudentAccountByUid(
        firebaseUid,
      );
      final id = (active?.studentId ?? '').trim();
      if (id.isNotEmpty) return id;
      return (await StudentAccountRepository.getStudentIdForFirebaseUid(
        firebaseUid,
      )).trim();
    } catch (e) {
      print(
        '[StudentDataRepository] Error resolving studentId for uid=$firebaseUid: $e',
      );
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> getStudentClassAttendanceSmart({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Class attendance source=${online ? 'firebase' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    if (online) {
      return getStudentClassAttendanceFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    return _getStudentClassAttendanceFromLocal(
      firebaseUid: firebaseUid,
      classRemoteId: classRemoteId,
    );
  }

  Future<List<Intervention>> getStudentInterventionsForClassSmart({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    if (kIsWeb) {
      print(
        '[StudentDataRepository] Student interventions source=firebase teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return _getStudentInterventionsForClassFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Student interventions source=${online ? 'sqlite_synced_online' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    return _getStudentInterventionsForClassFromLocal(
      firebaseUid: firebaseUid,
      classRemoteId: classRemoteId,
    );
  }

  Future<List<Intervention>> _getStudentInterventionsForClassFromLocal({
    required String firebaseUid,
    required String classRemoteId,
  }) async {
    try {
      final studentId = await _resolveStudentIdFromFirebaseUid(firebaseUid);
      if (studentId.isEmpty) return [];
      final localStudentId = await _getLocalStudentRowId(studentId);
      if (localStudentId == null) return [];

      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) return [];

      final db = await _db.database;
      final rows = await db.query(
        'interventions',
        where: 'student_id = ? AND class_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [localStudentId, localClassId],
        orderBy: 'intervention_date DESC',
      );
      print(
        '[StudentDataRepository] Local interventions rows=${rows.length} classRemoteId=$classRemoteId',
      );
      return rows.map((r) => Intervention.fromMap(r)).toList();
    } catch (e) {
      print('[StudentDataRepository] Local interventions error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentFollowUpsDueTodaySmart({
    required String firebaseUid,
  }) async {
    if (kIsWeb) {
      print('[StudentDataRepository] Follow-ups due today source=firebase');
      return _getStudentFollowUpsDueTodayFromFirebase(firebaseUid: firebaseUid);
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Follow-ups due today source=${online ? 'sqlite_synced_online' : 'sqlite'}',
    );
    return _getStudentFollowUpsDueTodayFromLocal(firebaseUid: firebaseUid);
  }

  Future<List<Map<String, dynamic>>> getStudentAssessmentScoresSmart(
    String firebaseUid,
  ) async {
    if (kIsWeb) {
      print(
        '[StudentDataRepository] Student assessment scores source=firebase',
      );
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Student assessment scores source=${online ? 'firebase' : 'sqlite'}',
    );
    print(
      '[StudentDataRepository] Student assessment scores source=${online ? 'firebase' : 'sqlite'}',
    );
    if (!online) {
      return getStudentAssessmentScores(firebaseUid);
    }
    try {
      var links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) {
        final fallbackStudentId =
            (await _db.getSetting('student_id'))?.toString().trim() ?? '';
        if (fallbackStudentId.isNotEmpty) {
          try {
            final expanded =
                await StudentAccountRepository.getTeacherLinksForStudentId(
                  fallbackStudentId,
                );
            if (expanded.isNotEmpty) links = expanded;
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores expand teacher links error: $e',
            );
          }
        }
      }

      if (links.isEmpty) {
        print(
          '[StudentDataRepository] Student assessment scores blocked: no teacher links',
        );
        print(
          '[StudentDataRepository] Student assessment scores blocked: no teacher links',
        );
        return [];
      }

      final out = <Map<String, dynamic>>[];

      for (final link in links) {
        final teacherUid = (link.teacherUid).trim();
        final studentRemoteId = (link.studentRemoteId).trim();
        final studentId = (link.studentId).trim();
        if (teacherUid.isEmpty) continue;

        Future<int?> resolveNumericStudentId() async {
          try {
            if (studentRemoteId.isEmpty) return null;
            final doc = await _firestore
                .collection('users/$teacherUid/students')
                .doc(studentRemoteId)
                .get();
            final data = doc.data();
            if (data == null) return null;
            final candidates = [
              data['id'],
              data['local_id'],
              data['student_local_id'],
              data['student_id_num'],
              data['student_id_numeric'],
            ];
            for (final c in candidates) {
              if (c is int) return c;
              if (c is num) return c.toInt();
              final parsed = int.tryParse(c?.toString() ?? '');
              if (parsed != null) return parsed;
            }
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores resolveNumericStudentId error teacherUid=$teacherUid studentRemoteId=$studentRemoteId: $e',
            );
            print(
              '[StudentDataRepository] Student assessment scores resolveNumericStudentId error teacherUid=$teacherUid studentRemoteId=$studentRemoteId: $e',
            );
          }
          return null;
        }

        if (studentRemoteId.isEmpty && studentId.isEmpty) {
          print(
            '[StudentDataRepository] Student assessment scores skip teacherUid=$teacherUid missing studentRemoteId+studentId',
          );
          print(
            '[StudentDataRepository] Student assessment scores skip teacherUid=$teacherUid missing studentRemoteId+studentId',
          );
          continue;
        }

        final scoresCol = _firestore.collection(
          'users/$teacherUid/assessment_scores',
        );

        QuerySnapshot<Map<String, dynamic>> scoresSnap;
        try {
          if (studentRemoteId.isNotEmpty) {
            scoresSnap = await scoresCol
                .where('student_remote_id', isEqualTo: studentRemoteId)
                .get();
          } else {
            scoresSnap = await scoresCol
                .where('student_id', isEqualTo: studentId)
                .get();
          }
        } catch (e) {
          print(
            '[StudentDataRepository] Student assessment scores query error teacherUid=$teacherUid: $e',
          );
          print(
            '[StudentDataRepository] Student assessment scores query error teacherUid=$teacherUid: $e',
          );
          continue;
        }

        if (scoresSnap.docs.isEmpty && studentId.isNotEmpty) {
          try {
            scoresSnap = await scoresCol
                .where('student_id', isEqualTo: studentId)
                .get();
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id error teacherUid=$teacherUid: $e',
            );
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id error teacherUid=$teacherUid: $e',
            );
          }
        }

        if (scoresSnap.docs.isEmpty && studentRemoteId.isNotEmpty) {
          try {
            scoresSnap = await scoresCol
                .where('student_id', isEqualTo: studentRemoteId)
                .get();
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id(remoteId) error teacherUid=$teacherUid: $e',
            );
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id(remoteId) error teacherUid=$teacherUid: $e',
            );
          }
        }

        if (scoresSnap.docs.isEmpty) {
          try {
            final numericId = await resolveNumericStudentId();
            if (numericId != null) {
              scoresSnap = await scoresCol
                  .where('student_id', isEqualTo: numericId)
                  .get();
              print(
                '[StudentDataRepository] Student assessment scores fallback by student_id(numeric) teacherUid=$teacherUid numericId=$numericId count=${scoresSnap.docs.length}',
              );
              print(
                '[StudentDataRepository] Student assessment scores fallback by student_id(numeric) teacherUid=$teacherUid numericId=$numericId count=${scoresSnap.docs.length}',
              );
            }
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id(numeric) error teacherUid=$teacherUid: $e',
            );
            print(
              '[StudentDataRepository] Student assessment scores fallback by student_id(numeric) error teacherUid=$teacherUid: $e',
            );
          }
        }

        print(
          '[StudentDataRepository] Student assessment scores fetched teacherUid=$teacherUid count=${scoresSnap.docs.length}',
        );
        for (final s in scoresSnap.docs) {
          out.add({...s.data(), 'doc_id': s.id, 'teacher_uid': teacherUid});
        }
      }

      if (out.isEmpty) {
        print('[StudentDataRepository] Student assessment scores total=0');
        print('[StudentDataRepository] Student assessment scores total=0');
        return [];
      }

      // Enrich with grading_assessments data (name, max_score, category id)
      final byTeacher = <String, List<Map<String, dynamic>>>{};
      for (final row in out) {
        final t = (row['teacher_uid']?.toString() ?? '').trim();
        if (t.isEmpty) continue;
        byTeacher.putIfAbsent(t, () => <Map<String, dynamic>>[]).add(row);
      }

      for (final entry in byTeacher.entries) {
        final teacherUid = entry.key;
        final rows = entry.value;
        final ids = <String>{};
        for (final r in rows) {
          final aId = (r['assessment_remote_id'] ?? r['assessment_id'] ?? '')
              .toString()
              .trim();
          if (aId.isNotEmpty) ids.add(aId);
        }
        if (ids.isEmpty) continue;

        final assessmentsCol = _firestore.collection(
          'users/$teacherUid/grading_assessments',
        );

        final assessmentById = <String, Map<String, dynamic>>{};
        final idsList = ids.toList();
        const chunkSize = 10;
        for (var i = 0; i < idsList.length; i += chunkSize) {
          final chunk = idsList.sublist(
            i,
            (i + chunkSize) > idsList.length ? idsList.length : (i + chunkSize),
          );
          try {
            final snap = await assessmentsCol
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
            for (final doc in snap.docs) {
              assessmentById[doc.id] = doc.data();
            }
          } catch (e) {
            print(
              '[StudentDataRepository] Student assessment scores enrich assessments error teacherUid=$teacherUid: $e',
            );
            print(
              '[StudentDataRepository] Student assessment scores enrich assessments error teacherUid=$teacherUid: $e',
            );
          }
        }

        for (final r in rows) {
          final aId = (r['assessment_remote_id'] ?? r['assessment_id'] ?? '')
              .toString()
              .trim();
          final a = assessmentById[aId];
          if (a == null) continue;
          r['assessment_name'] = (a['name']?.toString() ?? '').trim();
          r['max_score'] = a['max_score'];
          r['category_remote_id'] = a['category_remote_id'] ?? a['category_id'];
          r['grading_period_remote_id'] =
              a['grading_period_remote_id'] ?? a['grading_period_id'];
          r['class_remote_id'] = a['class_remote_id'] ?? a['class_id'];
        }
      }

      out.sort((a, b) {
        DateTime parse(dynamic v) {
          if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
          if (v is Timestamp) return v.toDate();
          return DateTime.tryParse(v.toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
        }

        final ad = parse(
          a['recorded_at'] ?? a['updated_at'] ?? a['created_at'],
        );
        final bd = parse(
          b['recorded_at'] ?? b['updated_at'] ?? b['created_at'],
        );
        return bd.compareTo(ad);
      });

      print(
        '[StudentDataRepository] Student assessment scores total=${out.length}',
      );
      print(
        '[StudentDataRepository] Student assessment scores total=${out.length}',
      );
      return out;
    } catch (e) {
      print(
        '[StudentDataRepository] Student assessment scores firebase error: $e',
      );
      print(
        '[StudentDataRepository] Student assessment scores firebase error: $e',
      );
      return getStudentAssessmentScores(firebaseUid);
    }
  }

  Future<List<Map<String, dynamic>>> _getStudentFollowUpsDueTodayFromLocal({
    required String firebaseUid,
  }) async {
    try {
      var studentId = await _resolveStudentIdFromFirebaseUid(firebaseUid);
      if (studentId.isEmpty) {
        final fallback =
            (await _db.getSetting('student_id'))?.toString().trim() ?? '';
        if (fallback.isNotEmpty) {
          print(
            '[StudentDataRepository] Follow-ups due today fallback student_id from settings: $fallback',
          );
          studentId = fallback;
        }
      }
      if (studentId.isEmpty) {
        print(
          '[StudentDataRepository] Follow-ups due today blocked: unable to resolve student_id for uid=$firebaseUid',
        );
        return [];
      }
      final localStudentId = await _getLocalStudentRowId(studentId);
      if (localStudentId == null) {
        print(
          '[StudentDataRepository] Follow-ups due today blocked: no local students row for student_id=$studentId',
        );
        return [];
      }

      final today = _todayYmd();
      final db = await _db.database;
      final rows = await db.rawQuery(
        '''
        SELECT
          i.*, 
          c.remote_id as class_remote_id,
          c.section as class_section,
          c.school_year as class_school_year,
          sub.code as subject_code,
          sub.name as subject_name
        FROM interventions i
        INNER JOIN classes c ON i.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        WHERE i.student_id = ?
          AND COALESCE(i.deleted, 0) = 0
          AND SUBSTR(COALESCE(i.follow_up_date, ''), 1, 10) = ?
        ORDER BY i.updated_at DESC
      ''',
        [localStudentId, today],
      );
      print(
        '[StudentDataRepository] Follow-ups due today rows=${rows.length} date=$today localStudentId=$localStudentId student_id=$studentId',
      );
      return rows;
    } catch (e) {
      print('[StudentDataRepository] Follow-ups due today local error: $e');
      return [];
    }
  }

  Future<List<Intervention>> _getStudentInterventionsForClassFromFirebase({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      final identity = await _resolveStudentIdentityForTeacher(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
      );
      final studentRemoteId = (identity['studentRemoteId'] ?? '').trim();
      final studentId = (identity['studentId'] ?? '').trim();
      if (studentRemoteId.isEmpty && studentId.isEmpty) {
        print(
          '[StudentDataRepository] Firebase interventions blocked: missing student identity teacherUid=$teacherUid classRemoteId=$classRemoteId',
        );
        return [];
      }

      final collection = _firestore.collection(
        'users/$teacherUid/interventions',
      );
      QuerySnapshot<Map<String, dynamic>> snap;
      if (studentRemoteId.isNotEmpty) {
        snap = await collection
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_remote_id', isEqualTo: studentRemoteId)
            .get();
      } else {
        snap = await collection
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_id', isEqualTo: studentId)
            .get();
      }

      if (snap.docs.isEmpty &&
          studentId.isNotEmpty &&
          studentRemoteId.isNotEmpty) {
        snap = await collection
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_id', isEqualTo: studentId)
            .get();
      }

      final rows = snap.docs
          .map(
            (doc) => Intervention.fromMap({...doc.data(), 'remote_id': doc.id}),
          )
          .toList();
      print(
        '[StudentDataRepository] Firebase interventions rows=${rows.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return rows;
    } catch (e) {
      print('[StudentDataRepository] Firebase interventions error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getStudentFollowUpsDueTodayFromFirebase({
    required String firebaseUid,
  }) async {
    try {
      final today = _todayYmd();
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      final out = <Map<String, dynamic>>[];

      for (final link in links) {
        final teacherUid = link.teacherUid.trim();
        if (teacherUid.isEmpty) continue;

        final identity = await _resolveStudentIdentityForTeacher(
          firebaseUid: firebaseUid,
          teacherUid: teacherUid,
        );
        final studentRemoteId = (identity['studentRemoteId'] ?? '').trim();
        final studentId = (identity['studentId'] ?? '').trim();
        if (studentRemoteId.isEmpty && studentId.isEmpty) continue;

        QuerySnapshot<Map<String, dynamic>> snap;
        if (studentRemoteId.isNotEmpty) {
          snap = await _firestore
              .collection('users/$teacherUid/interventions')
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .get();
        } else {
          snap = await _firestore
              .collection('users/$teacherUid/interventions')
              .where('student_id', isEqualTo: studentId)
              .get();
        }

        if (snap.docs.isEmpty &&
            studentId.isNotEmpty &&
            studentRemoteId.isNotEmpty) {
          snap = await _firestore
              .collection('users/$teacherUid/interventions')
              .where('student_id', isEqualTo: studentId)
              .get();
        }

        for (final doc in snap.docs) {
          final data = doc.data();
          final followUpDate = (data['follow_up_date']?.toString() ?? '')
              .trim();
          if (!followUpDate.startsWith(today)) continue;
          out.add({...data, 'remote_id': doc.id, 'teacher_uid': teacherUid});
        }
      }

      out.sort((a, b) {
        final av = (a['updated_at'] ?? a['created_at'] ?? '').toString();
        final bv = (b['updated_at'] ?? b['created_at'] ?? '').toString();
        return bv.compareTo(av);
      });
      print(
        '[StudentDataRepository] Firebase follow-ups due today rows=${out.length} date=$today',
      );
      return out;
    } catch (e) {
      print('[StudentDataRepository] Firebase follow-ups due today error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getStudentClassAttendanceFromLocal({
    required String firebaseUid,
    required String classRemoteId,
  }) async {
    try {
      final studentId = await _resolveStudentIdFromFirebaseUid(firebaseUid);
      if (studentId.isEmpty) return [];
      final localStudentId = await _getLocalStudentRowId(studentId);
      if (localStudentId == null) return [];

      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) return [];

      final db = await _db.database;
      final rows = await db.rawQuery(
        '''
        SELECT 
          a.*, 
          c.remote_id as class_remote_id,
          c.section as class_section,
          c.school_year,
          sub.code as subject_code,
          sub.name as subject_name
        FROM attendance a
        INNER JOIN classes c ON a.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        WHERE a.student_id = ?
          AND a.class_id = ?
          AND COALESCE(a.deleted, 0) = 0
        ORDER BY a.date DESC
      ''',
        [localStudentId, localClassId],
      );
      print(
        '[StudentDataRepository] Local class attendance rows=${rows.length} classRemoteId=$classRemoteId',
      );
      return rows;
    } catch (e) {
      print('[StudentDataRepository] Local class attendance error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>>
  getStudentClassScoresGroupedByCategorySmart({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Class scores source=${online ? 'firebase' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    if (online) {
      return getStudentClassScoresGroupedByCategoryFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    return _getStudentClassScoresGroupedByCategoryFromLocal(
      firebaseUid: firebaseUid,
      classRemoteId: classRemoteId,
    );
  }

  Future<List<Map<String, dynamic>>>
  _getStudentClassScoresGroupedByCategoryFromLocal({
    required String firebaseUid,
    required String classRemoteId,
  }) async {
    try {
      final studentId = await _resolveStudentIdFromFirebaseUid(firebaseUid);
      if (studentId.isEmpty) return [];
      final localStudentId = await _getLocalStudentRowId(studentId);
      if (localStudentId == null) return [];

      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) return [];

      final db = await _db.database;
      final rows = await db.rawQuery(
        '''
        SELECT
          sc.id as score_id,
          sc.score,
          sc.remarks,
          sc.recorded_at,
          sc.updated_at,
          ga.id as assessment_id,
          ga.name as assessment_name,
          ga.max_score,
          gc.id as category_id,
          gc.name as category_name
        FROM assessment_scores sc
        INNER JOIN grading_assessments ga ON sc.assessment_id = ga.id
        INNER JOIN grading_categories gc ON ga.category_id = gc.id
        WHERE sc.student_id = ?
          AND ga.class_id = ?
          AND COALESCE(sc.deleted, 0) = 0
          AND COALESCE(ga.deleted, 0) = 0
          AND COALESCE(gc.deleted, 0) = 0
        ORDER BY gc.name ASC, ga.order_num ASC
      ''',
        [localStudentId, localClassId],
      );

      final byCategory = <int, List<Map<String, dynamic>>>{};
      final categoryNames = <int, String>{};
      for (final r in rows) {
        final catId = r['category_id'] as int;
        byCategory.putIfAbsent(catId, () => []).add(r);
        categoryNames[catId] = r['category_name']?.toString() ?? '';
      }

      final result = <Map<String, dynamic>>[];
      for (final entry in byCategory.entries) {
        final catId = entry.key;
        final items = entry.value;
        final name = categoryNames[catId] ?? '';
        var totalPct = 0.0;
        var scoredCount = 0;
        for (final it in items) {
          final s = (it['score'] is num)
              ? (it['score'] as num).toDouble()
              : double.tryParse(it['score']?.toString() ?? '');
          final m = (it['max_score'] is num)
              ? (it['max_score'] as num).toDouble()
              : double.tryParse(it['max_score']?.toString() ?? '');
          if (s != null && m != null && m > 0) {
            totalPct += (s / m) * 100.0;
            scoredCount++;
          }
        }
        final avgPct = scoredCount == 0 ? 0.0 : (totalPct / scoredCount);
        result.add({
          'category_remote_id': catId.toString(),
          'category_name': name,
          'average_pct': avgPct,
          'assessments': items,
        });
      }

      result.sort(
        (a, b) => (a['category_name']?.toString() ?? '').compareTo(
          b['category_name']?.toString() ?? '',
        ),
      );
      print(
        '[StudentDataRepository] Local class scores groupedCategories=${result.length} classRemoteId=$classRemoteId',
      );
      return result;
    } catch (e) {
      print('[StudentDataRepository] Local class scores error: $e');
      return [];
    }
  }

  Future<List<String>> getTeacherCategoryNamesForClassSmart({
    required String teacherUid,
    required String classRemoteId,
  }) async {
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Category names source=${online ? 'firebase' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    if (online) {
      return getTeacherCategoryNamesForClassFromFirebase(
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    return _getTeacherCategoryNamesForClassFromLocal(
      classRemoteId: classRemoteId,
    );
  }

  Future<List<String>> _getTeacherCategoryNamesForClassFromLocal({
    required String classRemoteId,
  }) async {
    try {
      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) return [];
      final db = await _db.database;
      final rows = await db.rawQuery(
        '''
        SELECT DISTINCT gc.name as category_name
        FROM grading_assessments ga
        INNER JOIN grading_categories gc ON ga.category_id = gc.id
        WHERE ga.class_id = ?
          AND COALESCE(ga.deleted, 0) = 0
          AND COALESCE(gc.deleted, 0) = 0
        ORDER BY gc.name ASC
      ''',
        [localClassId],
      );
      final names = rows
          .map((r) => (r['category_name']?.toString() ?? '').trim())
          .where((v) => v.isNotEmpty)
          .toList();
      print(
        '[StudentDataRepository] Local category names count=${names.length} classRemoteId=$classRemoteId',
      );
      return names;
    } catch (e) {
      print('[StudentDataRepository] Local category names error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentPeriodGradesForClassSmart({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Period grades source=${online ? 'firebase' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    if (online) {
      return getStudentPeriodGradesForClassFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    return _getStudentPeriodGradesForClassFromLocal(
      firebaseUid: firebaseUid,
      classRemoteId: classRemoteId,
    );
  }

  Future<List<Map<String, dynamic>>> _getStudentPeriodGradesForClassFromLocal({
    required String firebaseUid,
    required String classRemoteId,
  }) async {
    try {
      // Load equivalency table from settings (same as local dashboard stats)
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      try {
        final dbh = DatabaseHelper.instance;
        final eqJson = await dbh.getSetting('grade_equivalency_table');
        if (eqJson != null && eqJson.isNotEmpty) {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJson) as Map<String, dynamic>,
          );
        }
        if (eqTable.isNotEmpty) {
          final filtered = eqTable.equivalencies
              .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
              .toList();
          eqTable = eqTable.copyWith(equivalencies: filtered);
        }
        if (eqTable.isEmpty) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      } catch (e) {
        print('[StudentDataRepository] Local period grades eq parse error: $e');
        eqTable = GradeEquivalencyTable.depedTo1to5;
      }

      final studentId = await _resolveStudentIdFromFirebaseUid(firebaseUid);
      if (studentId.isEmpty) return [];
      final localStudentId = await _getLocalStudentRowId(studentId);
      if (localStudentId == null) return [];

      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) return [];

      final db = await _db.database;
      final periods = await db.query(
        'grading_periods',
        where: 'class_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [localClassId],
        orderBy: 'order_num ASC',
      );
      if (periods.isEmpty) return [];

      final out = <Map<String, dynamic>>[];
      for (final p in periods) {
        final periodId = p['id'] as int;
        final periodName = (p['name']?.toString() ?? '').trim();
        final orderNum = (p['order_num'] as int?) ?? 0;

        // Prefer explicit grades table if present
        final gradeRows = await db.query(
          'grades',
          where:
              'student_id = ? AND class_id = ? AND grading_period_id = ? AND COALESCE(deleted, 0) = 0',
          whereArgs: [localStudentId, localClassId, periodId],
        );

        double periodPct = 0.0;
        if (gradeRows.isNotEmpty) {
          // Weighted by category weights
          final categories = await db.query(
            'grading_categories',
            where: 'grading_period_id = ? AND COALESCE(deleted, 0) = 0',
            whereArgs: [periodId],
          );
          for (final c in categories) {
            final catId = c['id'] as int;
            final weight = (c['weight'] as num?)?.toDouble() ?? 0.0;
            var scoreSum = 0.0;
            var maxSum = 0.0;
            for (final g in gradeRows.where(
              (r) => (r['category_id'] as int) == catId,
            )) {
              scoreSum += (g['score'] as num?)?.toDouble() ?? 0.0;
              maxSum += (g['max_score'] as num?)?.toDouble() ?? 0.0;
            }
            final contribution = (maxSum > 0 && weight > 0)
                ? (scoreSum / maxSum) * 100.0 * (weight / 100.0)
                : 0.0;
            periodPct += contribution;
          }
        } else {
          // Fallback: compute from assessments + scores
          final categories = await db.query(
            'grading_categories',
            where: 'grading_period_id = ? AND COALESCE(deleted, 0) = 0',
            whereArgs: [periodId],
          );
          for (final c in categories) {
            final catId = c['id'] as int;
            final weight = (c['weight'] as num?)?.toDouble() ?? 0.0;
            final assessmentRows = await db.query(
              'grading_assessments',
              where:
                  'class_id = ? AND grading_period_id = ? AND category_id = ? AND COALESCE(deleted, 0) = 0',
              whereArgs: [localClassId, periodId, catId],
            );
            var scoreSum = 0.0;
            var maxSum = 0.0;
            for (final a in assessmentRows) {
              final aId = a['id'] as int;
              final maxScore = (a['max_score'] as num?)?.toDouble() ?? 0.0;
              maxSum += maxScore;
              final s = await db.query(
                'assessment_scores',
                columns: ['score'],
                where:
                    'assessment_id = ? AND student_id = ? AND COALESCE(deleted, 0) = 0',
                whereArgs: [aId, localStudentId],
                limit: 1,
              );
              final score = s.isNotEmpty
                  ? (s.first['score'] as num?)?.toDouble() ?? 0.0
                  : 0.0;
              scoreSum += score;
            }
            final contribution = (maxSum > 0 && weight > 0)
                ? (scoreSum / maxSum) * 100.0 * (weight / 100.0)
                : 0.0;
            periodPct += contribution;
          }
        }

        final equivalent = eqTable.convertPercentageToNumerical(periodPct);
        final descriptor = eqTable.getDescriptor(periodPct);
        out.add({
          'grading_period_remote_id': p['remote_id']?.toString() ?? '',
          'grading_period_id': periodId,
          'name': periodName,
          'order_num': orderNum,
          'percent': periodPct,
          'equivalent': equivalent,
          'descriptor': descriptor,
        });
      }

      out.sort(
        (a, b) => (a['order_num'] as int? ?? 0).compareTo(
          b['order_num'] as int? ?? 0,
        ),
      );
      print(
        '[StudentDataRepository] Local period grades periods=${out.length} classRemoteId=$classRemoteId',
      );
      return out;
    } catch (e) {
      print('[StudentDataRepository] Local period grades error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStudentDashboardStats(
    String firebaseUid,
  ) async {
    if (kIsWeb) {
      print('[StudentDataRepository] Dashboard stats source=firebase');
      return getStudentDashboardStatsFromFirebase(firebaseUid);
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Dashboard stats source=${online ? 'firebase' : 'sqlite'}',
    );
    if (online) {
      return getStudentDashboardStatsFromFirebase(firebaseUid);
    }
    return _getStudentDashboardStatsFromLocal(firebaseUid);
  }

  Future<List<Map<String, dynamic>>> getStudentClassesSmart(
    String firebaseUid,
  ) async {
    if (kIsWeb) {
      print('[StudentDataRepository] Classes source=firebase');
      return getStudentClassesFromFirebase(firebaseUid);
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Classes source=${online ? 'firebase' : 'sqlite'}',
    );
    if (online) {
      return getStudentClassesFromFirebase(firebaseUid);
    }
    return getStudentClasses(firebaseUid);
  }

  Future<Map<String, dynamic>> _getStudentDashboardStatsFromLocal(
    String firebaseUid,
  ) async {
    try {
      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      try {
        final dbh = DatabaseHelper.instance;
        final gradingSystemJson = await dbh.getSetting('grading_system');
        if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gradingSystemJson) as Map<String, dynamic>,
          );
        }
        final eqJson = await dbh.getSetting('grade_equivalency_table');
        if (eqJson != null && eqJson.isNotEmpty) {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJson) as Map<String, dynamic>,
          );
        }
        if (eqTable.isNotEmpty) {
          final filtered = eqTable.equivalencies
              .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
              .toList();
          eqTable = eqTable.copyWith(equivalencies: filtered);
        }
        if (eqTable.isEmpty) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      } catch (e) {
        print('[StudentDataRepository] Local stats settings parse error: $e');
        eqTable = GradeEquivalencyTable.depedTo1to5;
      }

      final grades = await getStudentGrades(firebaseUid);
      final attendance = await getStudentAttendance(firebaseUid);

      double avgPct = 0.0;
      var scored = 0;
      for (final g in grades) {
        final score = (g['score'] is num)
            ? (g['score'] as num).toDouble()
            : double.tryParse(g['score']?.toString() ?? '') ?? 0.0;
        final maxScore = (g['max_score'] is num)
            ? (g['max_score'] as num).toDouble()
            : double.tryParse(g['max_score']?.toString() ?? '') ?? 0.0;
        if (maxScore <= 0) continue;
        avgPct += (score / maxScore) * 100.0;
        scored++;
      }
      avgPct = scored == 0 ? 0.0 : (avgPct / scored);

      DateTime _parseMaybeDate(dynamic v) {
        if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
        return DateTime.tryParse(v.toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }

      final gradesSorted = [...grades];
      gradesSorted.sort((a, b) {
        final ad = _parseMaybeDate(a['updated_at'] ?? a['recorded_at']);
        final bd = _parseMaybeDate(b['updated_at'] ?? b['recorded_at']);
        return bd.compareTo(ad);
      });

      final attendanceSorted = [...attendance];
      attendanceSorted.sort((a, b) {
        final ad = _parseMaybeDate(a['date'] ?? a['created_at']);
        final bd = _parseMaybeDate(b['date'] ?? b['created_at']);
        return bd.compareTo(ad);
      });

      var present = 0;
      var absent = 0;
      for (final a in attendance) {
        final s = (a['status']?.toString() ?? '').toLowerCase();
        if (s == 'present') present++;
        if (s == 'absent') absent++;
      }
      final totalAttendance = attendance.length;
      final attendanceRate = totalAttendance == 0
          ? 0.0
          : (present / totalAttendance) * 100.0;

      final avgEquivalent = eqTable.convertPercentageToNumerical(avgPct);
      final avgDescriptor = eqTable.getDescriptor(avgPct);

      final gradeSummary = <String, dynamic>{
        'totalGrades': grades.length,
        'averageScore': avgPct,
        'averageEquivalent': avgEquivalent,
        'averageDescriptor': avgDescriptor,
        'generalAverageScore': avgPct,
        'generalAverageEquivalent': avgEquivalent,
        'generalAverageDescriptor': avgDescriptor,
        'generalAveragePeriodCount': grades.isEmpty ? 0 : 1,
        'grading_system_type': gradingSystem.typeString,
      };
      final attendanceSummary = <String, dynamic>{
        'totalRecords': totalAttendance,
        'presentCount': present,
        'absentCount': absent,
        'attendanceRate': attendanceRate,
      };

      print(
        '[StudentDataRepository] Local stats totalGrades=${grades.length} avgScore=${avgPct.toStringAsFixed(2)} totalAttendance=$totalAttendance rate=${attendanceRate.toStringAsFixed(2)}',
      );

      return {
        'gradeSummary': gradeSummary,
        'attendanceSummary': attendanceSummary,
        'recentGrades': gradesSorted.take(10).toList(),
        'recentAttendance': attendanceSorted.take(10).toList(),
      };
    } catch (e) {
      print('[StudentDataRepository] Local stats error: $e');
      return {
        'gradeSummary': <String, dynamic>{},
        'attendanceSummary': <String, dynamic>{},
        'recentGrades': <Map<String, dynamic>>[],
        'recentAttendance': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, String>> _resolveStudentIdentityForTeacher({
    required String firebaseUid,
    required String teacherUid,
  }) async {
    try {
      // Prefer active context (local DB) which is already derived from School ID.
      final active = await StudentAccountRepository.getStudentAccountByUid(
        firebaseUid,
      );
      final activeStudentId = (active?.studentId ?? '').trim();
      final activeTeacherUid = (active?.teacherUid ?? '').trim();
      final activeStudentRemoteId = (active?.studentRemoteId ?? '').trim();

      if (activeStudentId.isNotEmpty &&
          activeTeacherUid == teacherUid &&
          activeStudentRemoteId.isNotEmpty) {
        return {
          'studentId': activeStudentId,
          'studentRemoteId': activeStudentRemoteId,
        };
      }

      // If links by firebaseUid are available, use them.
      try {
        final links =
            await StudentAccountRepository.getTeacherLinksByFirebaseUid(
              firebaseUid,
            );
        final linkForTeacher = links.cast<StudentTeacherLinkInfo?>().firstWhere(
          (l) => l?.teacherUid == teacherUid,
          orElse: () => null,
        );
        final linkStudentId = (linkForTeacher?.studentId ?? '').trim();
        final linkStudentRemoteId = (linkForTeacher?.studentRemoteId ?? '')
            .trim();
        if (linkStudentId.isNotEmpty && linkStudentRemoteId.isNotEmpty) {
          return {
            'studentId': linkStudentId,
            'studentRemoteId': linkStudentRemoteId,
          };
        }
      } catch (e) {
        print(
          '[StudentDataRepository] resolveStudentIdentityForTeacher links lookup error teacherUid=$teacherUid: $e',
        );
      }

      if (activeStudentId.isEmpty) {
        print(
          '[StudentDataRepository] resolveStudentIdentityForTeacher: missing active studentId for uid=$firebaseUid teacherUid=$teacherUid',
        );
        return {'studentId': '', 'studentRemoteId': ''};
      }

      // Last resort: query teacher's students collection by School ID.
      try {
        final s = await _firestore
            .collection('users/$teacherUid/students')
            .where('student_id', isEqualTo: activeStudentId)
            .limit(1)
            .get();
        if (s.docs.isEmpty) {
          print(
            '[StudentDataRepository] resolveStudentIdentityForTeacher: no student doc match in users/$teacherUid/students for student_id=$activeStudentId',
          );
          return {'studentId': activeStudentId, 'studentRemoteId': ''};
        }

        final resolvedRemoteId = s.docs.first.id;
        print(
          '[StudentDataRepository] resolveStudentIdentityForTeacher: resolved studentRemoteId=$resolvedRemoteId for studentId=$activeStudentId teacherUid=$teacherUid',
        );

        // Cache mapping so future reads don’t depend on scans/indexes.
        try {
          await _firestore
              .collection('student_accounts')
              .doc(activeStudentId)
              .collection('teachers')
              .doc(teacherUid)
              .set({
                'student_id': activeStudentId,
                'teacher_uid': teacherUid,
                'student_remote_id': resolvedRemoteId,
                'firebase_uid': firebaseUid,
                'updated_at': DateTime.now().toIso8601String(),
              }, SetOptions(merge: true));
          print(
            '[StudentDataRepository] Cached teacher link mapping studentId=$activeStudentId teacherUid=$teacherUid studentRemoteId=$resolvedRemoteId',
          );
        } catch (e) {
          print(
            '[StudentDataRepository] Failed to cache teacher link mapping studentId=$activeStudentId teacherUid=$teacherUid: $e',
          );
        }

        return {
          'studentId': activeStudentId,
          'studentRemoteId': resolvedRemoteId,
        };
      } catch (e) {
        print(
          '[StudentDataRepository] resolveStudentIdentityForTeacher users scan error teacherUid=$teacherUid studentId=$activeStudentId: $e',
        );
        return {'studentId': activeStudentId, 'studentRemoteId': ''};
      }
    } catch (e) {
      print(
        '[StudentDataRepository] resolveStudentIdentityForTeacher error: $e',
      );
      return {'studentId': '', 'studentRemoteId': ''};
    }
  }

  Future<List<Map<String, dynamic>>>
  getStudentPeriodGradesForClassFromFirebase({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      final identity = await _resolveStudentIdentityForTeacher(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
      );
      final studentRemoteId = identity['studentRemoteId'] ?? '';
      final studentId = identity['studentId'] ?? '';
      if (studentRemoteId.isEmpty) {
        print(
          '[StudentDataRepository] Firebase period grades: no studentRemoteId for uid=$firebaseUid teacherUid=$teacherUid',
        );
        return [];
      }

      // Load local grading system + equivalency table (synced via settings)
      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      try {
        final dbh = DatabaseHelper.instance;
        final gradingSystemJson = await dbh.getSetting('grading_system');
        if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gradingSystemJson) as Map<String, dynamic>,
          );
        }
        final eqJson = await dbh.getSetting('grade_equivalency_table');
        if (eqJson != null && eqJson.isNotEmpty) {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJson) as Map<String, dynamic>,
          );
        }

        if (eqTable.isNotEmpty) {
          final filtered = eqTable.equivalencies
              .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
              .toList();
          eqTable = eqTable.copyWith(equivalencies: filtered);
        }

        if (eqTable.isEmpty) {
          if (gradingSystem.type == GradingSystemType.college4point0) {
            eqTable = GradeEquivalencyTable.depedTo4point0;
          } else if (gradingSystem.type == GradingSystemType.college1to5) {
            eqTable = GradeEquivalencyTable.depedTo1to5;
          }
        }
      } catch (e) {
        print('[StudentDataRepository] Period grades settings parse error: $e');
      }

      // Student accounts do not necessarily have the teacher's settings locally.
      // Always prefer the teacher's Firestore settings when available, because
      // student devices may have a default/local equivalency that doesn't match
      // the teacher/class equivalency.
      try {
        final teacherDoc = await _firestore
            .collection('users')
            .doc(teacherUid)
            .get();
        final remoteSettings =
            teacherDoc.data()?['settings'] as Map<String, dynamic>? ?? {};

        final remoteGradingSystemJson =
            remoteSettings['grading_system']?.toString() ?? '';
        if (remoteGradingSystemJson.isNotEmpty) {
          try {
            gradingSystem = GradingSystemConfig.fromJson(
              jsonDecode(remoteGradingSystemJson) as Map<String, dynamic>,
            );
            print(
              '[StudentDataRepository] Period grades loaded grading_system from teacher settings teacherUid=$teacherUid type=${gradingSystem.typeString}',
            );
          } catch (e) {
            print(
              '[StudentDataRepository] Period grades teacher grading_system parse error teacherUid=$teacherUid: $e',
            );
          }
        }

        final remoteEqJson =
            remoteSettings['grade_equivalency_table']?.toString() ?? '';
        if (remoteEqJson.isNotEmpty) {
          try {
            final remoteTable = GradeEquivalencyTable.fromJson(
              jsonDecode(remoteEqJson) as Map<String, dynamic>,
            );
            final filtered = remoteTable.equivalencies
                .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
                .toList();
            eqTable = remoteTable.copyWith(equivalencies: filtered);
            print(
              '[StudentDataRepository] Period grades using teacher grade_equivalency_table teacherUid=$teacherUid eqRows=${eqTable.equivalencies.length}',
            );
          } catch (e) {
            print(
              '[StudentDataRepository] Period grades teacher grade_equivalency_table parse error teacherUid=$teacherUid: $e',
            );
          }
        }
      } catch (e) {
        print(
          '[StudentDataRepository] Period grades teacher settings load error teacherUid=$teacherUid: $e',
        );
      }

      // If teacher settings didn't provide a table, fallback to a preset based on
      // the grading system type (or deped preset).
      if (eqTable.isEmpty) {
        if (gradingSystem.type == GradingSystemType.college4point0) {
          eqTable = GradeEquivalencyTable.depedTo4point0;
        } else if (gradingSystem.type == GradingSystemType.college1to5) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      }

      // Final fallback: If no equivalency table is configured anywhere, still
      // show an equivalent grade using a default preset so students can see
      // values like 2.75 next to the percentage. This can later be made
      // user-selectable in the UI.
      String equivalencySource = 'none';
      if (eqTable.isNotEmpty) {
        equivalencySource = 'configured';
      } else {
        eqTable = GradeEquivalencyTable.depedTo1to5;
        equivalencySource = 'preset_depedTo1to5';
        print(
          '[StudentDataRepository] Period grades using default equivalency preset teacherUid=$teacherUid preset=depedTo1to5 eqRows=${eqTable.equivalencies.length}',
        );
      }

      print(
        '[StudentDataRepository] Firebase period grades fetch teacherUid=$teacherUid classRemoteId=$classRemoteId studentRemoteId=$studentRemoteId gradingSystem=${gradingSystem.typeString} eqRows=${eqTable.equivalencies.length}',
      );

      final periodsCol = _firestore.collection(
        'users/$teacherUid/grading_periods',
      );
      final categoriesCol = _firestore.collection(
        'users/$teacherUid/grading_categories',
      );
      final gradesCol = _firestore.collection('users/$teacherUid/grades');

      final periodsSnap = await periodsCol
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();

      final periodDocs = periodsSnap.docs.toList();
      periodDocs.sort((a, b) {
        final ao = (a.data()['order_num'] as num?)?.toInt() ?? 0;
        final bo = (b.data()['order_num'] as num?)?.toInt() ?? 0;
        return ao.compareTo(bo);
      });

      print(
        '[StudentDataRepository] Firebase period grades periods=${periodDocs.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      if (periodDocs.isEmpty) return [];

      QuerySnapshot<Map<String, dynamic>> gradesSnap;
      gradesSnap = await gradesCol
          .where('class_remote_id', isEqualTo: classRemoteId)
          .where('student_remote_id', isEqualTo: studentRemoteId)
          .get();

      if (gradesSnap.docs.isEmpty) {
        gradesSnap = await gradesCol
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_id', isEqualTo: studentRemoteId)
            .get();
      }
      if (gradesSnap.docs.isEmpty && studentId.isNotEmpty) {
        gradesSnap = await gradesCol
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_id', isEqualTo: studentId)
            .get();
      }

      final allGrades = gradesSnap.docs
          .map((d) => {...d.data(), 'doc_id': d.id})
          .toList();
      print(
        '[StudentDataRepository] Firebase period grades gradeRows=${allGrades.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );

      // If no grade rows exist, compute from grading_assessments + assessment_scores
      // (this mirrors the teacher-side computation from assessment totals).
      final bool useAssessments = allGrades.isEmpty;
      Map<String, Map<String, dynamic>> assessmentById = {};
      Map<String, double> scoreByAssessmentId = {};

      if (useAssessments) {
        try {
          final assessmentsCol = _firestore.collection(
            'users/$teacherUid/grading_assessments',
          );
          final scoresCol = _firestore.collection(
            'users/$teacherUid/assessment_scores',
          );

          final assessmentsSnap = await assessmentsCol
              .where('class_remote_id', isEqualTo: classRemoteId)
              .get();
          for (final a in assessmentsSnap.docs) {
            final d = a.data();
            assessmentById[a.id] = {
              ...d,
              'doc_id': a.id,
              'grading_period_remote_id':
                  d['grading_period_remote_id']?.toString() ?? '',
              'category_remote_id': d['category_remote_id']?.toString() ?? '',
              'max_score': (d['max_score'] is num)
                  ? (d['max_score'] as num).toDouble()
                  : double.tryParse(d['max_score']?.toString() ?? '') ?? 0.0,
            };
          }

          print(
            '[StudentDataRepository] Firebase period grades using assessments path assessments=${assessmentById.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
          );

          // Load scores for this student for those assessments. Chunk to avoid "whereIn" limits.
          final assessmentIds = assessmentById.keys.toList();
          const chunkSize = 10;
          for (var i = 0; i < assessmentIds.length; i += chunkSize) {
            final chunk = assessmentIds.sublist(
              i,
              (i + chunkSize) > assessmentIds.length
                  ? assessmentIds.length
                  : (i + chunkSize),
            );

            QuerySnapshot<Map<String, dynamic>> snap;
            snap = await scoresCol
                .where('assessment_remote_id', whereIn: chunk)
                .where('student_remote_id', isEqualTo: studentRemoteId)
                .get();

            if (snap.docs.isEmpty) {
              snap = await scoresCol
                  .where('assessment_remote_id', whereIn: chunk)
                  .where('student_id', isEqualTo: studentRemoteId)
                  .get();
            }

            if (snap.docs.isEmpty && studentId.isNotEmpty) {
              snap = await scoresCol
                  .where('assessment_remote_id', whereIn: chunk)
                  .where('student_id', isEqualTo: studentId)
                  .get();
            }

            for (final s in snap.docs) {
              final d = s.data();
              final assessmentRemoteId =
                  d['assessment_remote_id']?.toString() ?? '';
              if (assessmentRemoteId.isEmpty) continue;
              final score = (d['score'] is num)
                  ? (d['score'] as num).toDouble()
                  : double.tryParse(d['score']?.toString() ?? '') ?? 0.0;
              scoreByAssessmentId[assessmentRemoteId] = score;
            }
          }

          print(
            '[StudentDataRepository] Firebase period grades using assessments path scoresFound=${scoreByAssessmentId.length} studentRemoteId=$studentRemoteId',
          );
        } catch (e) {
          print(
            '[StudentDataRepository] Firebase period grades assessments fallback error: $e',
          );
        }
      }

      final out = <Map<String, dynamic>>[];
      for (final p in periodDocs) {
        final pData = p.data();
        final periodRemoteId = p.id;
        final periodName = (pData['name']?.toString() ?? '').trim();
        final periodOrder = (pData['order_num'] as num?)?.toInt() ?? 0;

        // Load categories for this period (for weights)
        final catsSnap = await categoriesCol
            .where('grading_period_remote_id', isEqualTo: periodRemoteId)
            .get();

        final catWeights = <String, double>{};
        final catNames = <String, String>{};
        for (final c in catsSnap.docs) {
          final w = (c.data()['weight'] as num?)?.toDouble() ?? 0.0;
          catWeights[c.id] = w;
          catNames[c.id] = (c.data()['name']?.toString() ?? '').trim();
        }
        print(
          '[StudentDataRepository] Firebase period grades categories period=$periodRemoteId count=${catWeights.length}',
        );
        for (final c in catsSnap.docs) {
          final w = (c.data()['weight'] as num?)?.toDouble() ?? 0.0;
          final name = c.data()['name']?.toString() ?? '';
          print(
            '[StudentDataRepository] Firebase period grades category id=${c.id} name=$name weight=$w',
          );
        }

        // Teacher Excel formula mapping (Option A):
        // U = sum of non-exam weighted contributions
        // X = avg of exam weighted contributions
        // Period = ROUND(100 - ((5/8) * (100 - (U + X))), 0) with min 70, clamp 0..100
        double uNonExam = 0.0;
        final examContribs = <double>[];

        for (final entry in catWeights.entries) {
          final catRemoteId = entry.key;
          final weight = entry.value;

          var scoreSum = 0.0;
          var maxSum = 0.0;

          if (!useAssessments) {
            final rows = allGrades.where((g) {
              final gPeriod = g['grading_period_remote_id']?.toString() ?? '';
              final gCat = g['category_remote_id']?.toString() ?? '';
              return gPeriod == periodRemoteId && gCat == catRemoteId;
            }).toList();

            for (final r in rows) {
              final s = (r['score'] is num)
                  ? (r['score'] as num).toDouble()
                  : double.tryParse(r['score']?.toString() ?? '') ?? 0.0;
              final m = (r['max_score'] is num)
                  ? (r['max_score'] as num).toDouble()
                  : double.tryParse(r['max_score']?.toString() ?? '') ?? 0.0;
              scoreSum += s;
              maxSum += m;
            }
          } else {
            // Teacher-side style: sum assessment scores and max scores per category.
            // If a score doc is missing, treat score as 0 but still include max_score.
            for (final a in assessmentById.values) {
              final pId = a['grading_period_remote_id']?.toString() ?? '';
              final cId = a['category_remote_id']?.toString() ?? '';
              if (pId != periodRemoteId || cId != catRemoteId) continue;
              final aId = a['doc_id']?.toString() ?? '';
              final max = (a['max_score'] is num)
                  ? (a['max_score'] as num).toDouble()
                  : double.tryParse(a['max_score']?.toString() ?? '') ?? 0.0;
              final score = scoreByAssessmentId[aId] ?? 0.0;
              maxSum += max;
              scoreSum += score;
            }
          }

          final contribution = (maxSum > 0 && weight > 0)
              ? (scoreSum / maxSum) * 100.0 * (weight / 100.0)
              : 0.0;

          final name = (catNames[catRemoteId] ?? '').toLowerCase();
          final isExam = name.contains('exam');
          if (isExam) {
            if (contribution > 0) examContribs.add(contribution);
          } else {
            uNonExam += contribution;
          }

          print(
            '[StudentDataRepository] Firebase period grades category catRemoteId=$catRemoteId weight=$weight scoreSum=${scoreSum.toStringAsFixed(2)} maxSum=${maxSum.toStringAsFixed(2)} contribution=${contribution.toStringAsFixed(2)}',
          );
        }

        final xExamAvg = examContribs.isEmpty
            ? 0.0
            : (examContribs.reduce((a, b) => a + b) / examContribs.length);

        double periodPct = 0.0;
        if (uNonExam > 0 && xExamAvg > 0) {
          final sumUx = uNonExam + xExamAvg;
          final raw = 100 - ((5 / 8) * (100 - sumUx));
          final rounded = raw.roundToDouble();
          final minApplied = rounded > 70 ? rounded : 70.0;
          periodPct = minApplied.clamp(0.0, 100.0).toDouble();
          print(
            '[StudentDataRepository] Firebase period grades formula period=$periodName U=$uNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$periodPct',
          );
        } else {
          print(
            '[StudentDataRepository] Firebase period grades formula missing U/X period=$periodName U=$uNonExam X=$xExamAvg -> 0',
          );
          periodPct = 0.0;
        }

        double? equivalent;
        String? descriptor;
        if (eqTable.isNotEmpty) {
          equivalent = eqTable.convertPercentageToNumerical(periodPct);
          descriptor = eqTable.getDescriptor(periodPct);
          print(
            '[StudentDataRepository] Firebase period grades equivalency applied period=$periodName pct=${periodPct.toStringAsFixed(2)} eq=${equivalent?.toStringAsFixed(2) ?? ''} desc=${descriptor ?? ''}',
          );
        }

        print(
          '[StudentDataRepository] Firebase period grades computed period=$periodName pct=${periodPct.toStringAsFixed(2)} eq=${equivalent?.toStringAsFixed(2) ?? ''} desc=${descriptor ?? ''}',
        );

        out.add({
          'grading_period_remote_id': periodRemoteId,
          'period_name': periodName.isNotEmpty ? periodName : 'Period',
          'order_num': periodOrder,
          'percent': periodPct,
          'equivalent': equivalent,
          'descriptor': descriptor,
          'grading_system_type': gradingSystem.typeString,
          'equivalency_source': equivalencySource,
        });
      }

      out.sort(
        (a, b) => (a['order_num'] as int? ?? 0).compareTo(
          b['order_num'] as int? ?? 0,
        ),
      );
      return out;
    } catch (e) {
      print('[StudentDataRepository] Firebase period grades error: $e');
      return [];
    }
  }

  Future<List<String>> getTeacherCategoryNamesForClassFromFirebase({
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      print(
        '[StudentDataRepository] Firebase categoriesForClass fetch teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );

      final assessmentsCol = _firestore.collection(
        'users/$teacherUid/grading_assessments',
      );
      final categoriesCol = _firestore.collection(
        'users/$teacherUid/grading_categories',
      );

      final assessmentsSnap = await assessmentsCol
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
      print(
        '[StudentDataRepository] Firebase categoriesForClass assessments=${assessmentsSnap.docs.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      if (assessmentsSnap.docs.isEmpty) return [];

      final categoryRemoteIds = <String>{};
      for (final d in assessmentsSnap.docs) {
        final cId = d.data()['category_remote_id']?.toString() ?? '';
        if (cId.isNotEmpty) categoryRemoteIds.add(cId);
      }
      print(
        '[StudentDataRepository] Firebase categoriesForClass uniqueCategoryIds=${categoryRemoteIds.length} teacherUid=$teacherUid',
      );
      if (categoryRemoteIds.isEmpty) return [];

      final names = <Map<String, dynamic>>[];
      const chunkSize = 10;
      final ids = categoryRemoteIds.toList();
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(
          i,
          (i + chunkSize) > ids.length ? ids.length : (i + chunkSize),
        );
        final snap = await categoriesCol
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final c in snap.docs) {
          final data = c.data();
          final name = (data['name']?.toString() ?? '').trim();
          final order =
              (data['order_num'] as num?)?.toInt() ??
              int.tryParse(data['order_num']?.toString() ?? '') ??
              9999;
          if (name.isNotEmpty) {
            names.add({'name': name, 'order_num': order});
          } else {
            names.add({'name': c.id, 'order_num': order});
          }
        }
      }

      names.sort((a, b) {
        final ao = a['order_num'] as int? ?? 9999;
        final bo = b['order_num'] as int? ?? 9999;
        if (ao != bo) return ao.compareTo(bo);
        return (a['name']?.toString() ?? '').compareTo(
          b['name']?.toString() ?? '',
        );
      });

      final out = <String>[];
      final seen = <String>{};
      for (final it in names) {
        final n = (it['name']?.toString() ?? '').trim();
        if (n.isEmpty) continue;
        final key = n.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        out.add(n);
      }

      print(
        '[StudentDataRepository] Firebase categoriesForClass resolvedNames=${out.length} teacherUid=$teacherUid classRemoteId=$classRemoteId names=$out',
      );
      return out;
    } catch (e) {
      print('[StudentDataRepository] Firebase categoriesForClass error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentLessonsForClassSmart({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    if (kIsWeb) {
      print(
        '[StudentDataRepository] Lessons source=firebase teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return getStudentLessonsForClassFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    final online = await _hasInternetConnection();
    print(
      '[StudentDataRepository] Lessons source=${online ? 'firebase' : 'sqlite'} teacherUid=$teacherUid classRemoteId=$classRemoteId',
    );
    if (online) {
      return getStudentLessonsForClassFromFirebase(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );
    }
    return _getStudentLessonsForClassFromLocal(
      teacherUid: teacherUid,
      classRemoteId: classRemoteId,
    );
  }

  Future<List<Map<String, dynamic>>> _getStudentLessonsForClassFromLocal({
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      final localClassId = await _resolveLocalClassIdByRemoteId(classRemoteId);
      if (localClassId == null) {
        print(
          '[StudentDataRepository] Local lessons: class not found for remote_id=$classRemoteId',
        );
        return [];
      }

      final db = await _db.database;
      final rows = await db.query(
        'lessons',
        where: 'class_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [localClassId],
        orderBy: 'week_number ASC',
      );

      final lessons = rows
          .map(
            (r) => <String, dynamic>{
              ...r,
              'teacher_uid': teacherUid,
              'class_remote_id': classRemoteId,
            },
          )
          .toList();

      print(
        '[StudentDataRepository] Local lessons fetched count=${lessons.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return lessons;
    } catch (e) {
      print('[StudentDataRepository] Local lessons fetch error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentLessonsForClassFromFirebase({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      print(
        '[StudentDataRepository] Firebase lessons fetch teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );

      final lessonsCol = _firestore.collection('users/$teacherUid/lessons');

      QuerySnapshot<Map<String, dynamic>> snap;
      snap = await lessonsCol
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();

      // Legacy fallback: some older sync paths used class_id only.
      if (snap.docs.isEmpty) {
        print(
          '[StudentDataRepository] Firebase lessons by class_remote_id=0 teacherUid=$teacherUid classRemoteId=$classRemoteId; trying legacy class_id',
        );
        // We don't have numeric class_id in student view; still attempt if classRemoteId is numeric.
        final maybeClassId = int.tryParse(classRemoteId);
        if (maybeClassId != null) {
          snap = await lessonsCol
              .where('class_id', isEqualTo: maybeClassId)
              .get();
        }
      }

      final lessons = snap.docs
          .map((d) => {...d.data(), 'doc_id': d.id, 'teacher_uid': teacherUid})
          .toList();
      lessons.sort((a, b) {
        final aw =
            (a['week_number'] as num?)?.toInt() ??
            int.tryParse(a['week_number']?.toString() ?? '') ??
            0;
        final bw =
            (b['week_number'] as num?)?.toInt() ??
            int.tryParse(b['week_number']?.toString() ?? '') ??
            0;
        return aw.compareTo(bw);
      });

      print(
        '[StudentDataRepository] Firebase lessons fetched count=${lessons.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      if (lessons.isNotEmpty) {
        print(
          '[StudentDataRepository] Firebase lessons sampleKeys=${lessons.first.keys.toList()}',
        );
      }
      return lessons;
    } catch (e) {
      print('[StudentDataRepository] Firebase lessons fetch error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentClassAttendanceFromFirebase({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      final identity = await _resolveStudentIdentityForTeacher(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
      );
      final studentRemoteId = identity['studentRemoteId'] ?? '';
      final studentId = identity['studentId'] ?? '';
      if (studentRemoteId.isEmpty) {
        print(
          '[StudentDataRepository] Firebase class attendance: no studentRemoteId for uid=$firebaseUid teacherUid=$teacherUid',
        );
        return [];
      }

      print(
        '[StudentDataRepository] Firebase class attendance fetch teacherUid=$teacherUid classRemoteId=$classRemoteId studentRemoteId=$studentRemoteId',
      );

      final attCol = _firestore.collection('users/$teacherUid/attendance');

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await attCol
            .where('class_remote_id', isEqualTo: classRemoteId)
            .where('student_remote_id', isEqualTo: studentRemoteId)
            .get();
        print(
          '[StudentDataRepository] Firebase class attendance by class_remote_id+student_remote_id=${snap.docs.length} teacherUid=$teacherUid',
        );
      } on FirebaseException catch (e) {
        print(
          '[StudentDataRepository] Firebase class attendance targeted query error (class_remote_id+student_remote_id): $e',
        );
        snap = await attCol.limit(0).get();
      }

      if (snap.docs.isEmpty) {
        try {
          snap = await attCol
              .where('class_remote_id', isEqualTo: classRemoteId)
              .where('student_id', isEqualTo: studentRemoteId)
              .get();
          print(
            '[StudentDataRepository] Firebase class attendance by class_remote_id+student_id(remoteId)=${snap.docs.length} teacherUid=$teacherUid',
          );
        } on FirebaseException catch (e) {
          print(
            '[StudentDataRepository] Firebase class attendance targeted query error (class_remote_id+student_id(remoteId)): $e',
          );
          snap = await attCol.limit(0).get();
        }
      }

      if (snap.docs.isEmpty && studentId.isNotEmpty) {
        try {
          snap = await attCol
              .where('class_remote_id', isEqualTo: classRemoteId)
              .where('student_id', isEqualTo: studentId)
              .get();
          print(
            '[StudentDataRepository] Firebase class attendance by class_remote_id+student_id(studentId)=${snap.docs.length} teacherUid=$teacherUid',
          );
        } on FirebaseException catch (e) {
          print(
            '[StudentDataRepository] Firebase class attendance targeted query error (class_remote_id+student_id(studentId)): $e',
          );
          snap = await attCol.limit(0).get();
        }
      }

      // Fallback: fetch by student only (no class filter) then filter locally.
      if (snap.docs.isEmpty) {
        print(
          '[StudentDataRepository] Firebase class attendance targeted query returned 0; falling back to fetch-by-student then filter locally',
        );

        QuerySnapshot<Map<String, dynamic>> studentSnap;
        try {
          studentSnap = await attCol
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .get();
          print(
            '[StudentDataRepository] Firebase class attendance fetch-by-student student_remote_id=${studentSnap.docs.length} teacherUid=$teacherUid',
          );
        } on FirebaseException catch (e) {
          print(
            '[StudentDataRepository] Firebase class attendance fetch-by-student error (student_remote_id): $e',
          );
          studentSnap = await attCol.limit(0).get();
        }

        if (studentSnap.docs.isEmpty) {
          try {
            studentSnap = await attCol
                .where('student_id', isEqualTo: studentRemoteId)
                .get();
            print(
              '[StudentDataRepository] Firebase class attendance fetch-by-student student_id(remoteId)=${studentSnap.docs.length} teacherUid=$teacherUid',
            );
          } on FirebaseException catch (e) {
            print(
              '[StudentDataRepository] Firebase class attendance fetch-by-student error (student_id(remoteId)): $e',
            );
            studentSnap = await attCol.limit(0).get();
          }
        }

        if (studentSnap.docs.isEmpty && studentId.isNotEmpty) {
          try {
            studentSnap = await attCol
                .where('student_id', isEqualTo: studentId)
                .get();
            print(
              '[StudentDataRepository] Firebase class attendance fetch-by-student student_id(studentId)=${studentSnap.docs.length} teacherUid=$teacherUid',
            );
          } on FirebaseException catch (e) {
            print(
              '[StudentDataRepository] Firebase class attendance fetch-by-student error (student_id(studentId)): $e',
            );
            studentSnap = await attCol.limit(0).get();
          }
        }

        final filteredDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in studentSnap.docs) {
          final data = d.data();
          final docClassRemoteId = data['class_remote_id']?.toString() ?? '';
          final docClassId = data['class_id']?.toString() ?? '';

          if (docClassRemoteId.isNotEmpty) {
            if (docClassRemoteId == classRemoteId) filteredDocs.add(d);
            continue;
          }

          // Some legacy docs may store class remote id in class_id as a string.
          if (docClassId.isNotEmpty && docClassId == classRemoteId) {
            filteredDocs.add(d);
          }
        }

        print(
          '[StudentDataRepository] Firebase class attendance local filter results=${filteredDocs.length} from studentTotal=${studentSnap.docs.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
        );

        // Convert filteredDocs into a QuerySnapshot-like flow.
        // We reuse parsing logic below by creating a list.
        snap = await attCol.limit(0).get();
        final tempDocs = filteredDocs;

        DateTime _parseDate(dynamic v) {
          if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
          if (v is Timestamp) return v.toDate();
          if (v is DateTime) return v;
          final parsed = DateTime.tryParse(v.toString());
          return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
        }

        final out = <Map<String, dynamic>>[];
        for (final d in tempDocs) {
          final data = d.data();
          final status = (data['status']?.toString() ?? '').trim();
          final date = _parseDate(data['date'] ?? data['created_at']);

          out.add({
            ...data,
            'doc_id': d.id,
            'status': status,
            'date_obj': date,
          });
        }

        out.sort((a, b) {
          final ad =
              a['date_obj'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              b['date_obj'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

        print(
          '[StudentDataRepository] Firebase class attendance records=${out.length} teacherUid=$teacherUid classRemoteId=$classRemoteId (fallback path)',
        );
        return out;
      }

      DateTime _parseDate(dynamic v) {
        if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        final parsed = DateTime.tryParse(v.toString());
        return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
      }

      final out = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final status = (data['status']?.toString() ?? '').trim();
        final date = _parseDate(data['date'] ?? data['created_at']);

        out.add({...data, 'doc_id': d.id, 'status': status, 'date_obj': date});
      }

      out.sort((a, b) {
        final ad =
            a['date_obj'] as DateTime? ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            b['date_obj'] as DateTime? ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

      print(
        '[StudentDataRepository] Firebase class attendance records=${out.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return out;
    } catch (e) {
      print('[StudentDataRepository] Firebase class attendance error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>>
  getStudentClassScoresGroupedByCategoryFromFirebase({
    required String firebaseUid,
    required String teacherUid,
    required String classRemoteId,
  }) async {
    try {
      final identity = await _resolveStudentIdentityForTeacher(
        firebaseUid: firebaseUid,
        teacherUid: teacherUid,
      );
      final studentRemoteId = identity['studentRemoteId'] ?? '';
      final studentId = identity['studentId'] ?? '';
      if (studentRemoteId.isEmpty) {
        print(
          '[StudentDataRepository] Firebase class scores: no studentRemoteId for uid=$firebaseUid teacherUid=$teacherUid',
        );
        return [];
      }

      print(
        '[StudentDataRepository] Firebase class scores fetch teacherUid=$teacherUid classRemoteId=$classRemoteId studentRemoteId=$studentRemoteId',
      );

      final assessmentsCol = _firestore.collection(
        'users/$teacherUid/grading_assessments',
      );
      final categoriesCol = _firestore.collection(
        'users/$teacherUid/grading_categories',
      );
      final scoresCol = _firestore.collection(
        'users/$teacherUid/assessment_scores',
      );

      final assessmentsSnap = await assessmentsCol
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
      print(
        '[StudentDataRepository] Firebase class scores assessments=${assessmentsSnap.docs.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );

      if (assessmentsSnap.docs.isEmpty) return [];

      final assessments = <Map<String, dynamic>>[];
      final assessmentRemoteIds = <String>[];
      final categoryRemoteIds = <String>{};

      for (final d in assessmentsSnap.docs) {
        final data = d.data();
        final catRemoteId = data['category_remote_id']?.toString() ?? '';
        if (catRemoteId.isNotEmpty) categoryRemoteIds.add(catRemoteId);
        assessments.add({...data, 'doc_id': d.id});
        assessmentRemoteIds.add(d.id);
      }

      final categoryNameByRemoteId = <String, String>{};
      try {
        final catsSnap = await categoriesCol.get();
        for (final c in catsSnap.docs) {
          final name = c.data()['name']?.toString() ?? '';
          categoryNameByRemoteId[c.id] = name.isNotEmpty ? name : c.id;
        }
        print(
          '[StudentDataRepository] Firebase class scores categoriesLoaded=${catsSnap.docs.length} teacherUid=$teacherUid',
        );
      } catch (e) {
        print(
          '[StudentDataRepository] Firebase class scores categories load error: $e',
        );
      }

      Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchScoresByAssessmentIds(List<String> ids) async {
        final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        const chunkSize = 10;
        for (var i = 0; i < ids.length; i += chunkSize) {
          final chunk = ids.sublist(
            i,
            (i + chunkSize) > ids.length ? ids.length : (i + chunkSize),
          );

          QuerySnapshot<Map<String, dynamic>> snap;
          snap = await scoresCol
              .where('assessment_remote_id', whereIn: chunk)
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .get();
          print(
            '[StudentDataRepository] Firebase class scores scoresChunk=${snap.docs.length} by assessment_remote_id+student_remote_id chunkSize=${chunk.length}',
          );

          if (snap.docs.isEmpty) {
            snap = await scoresCol
                .where('assessment_remote_id', whereIn: chunk)
                .where('student_id', isEqualTo: studentRemoteId)
                .get();
            print(
              '[StudentDataRepository] Firebase class scores scoresChunk=${snap.docs.length} by assessment_remote_id+student_id(remoteId) chunkSize=${chunk.length}',
            );
          }

          if (snap.docs.isEmpty && studentId.isNotEmpty) {
            snap = await scoresCol
                .where('assessment_remote_id', whereIn: chunk)
                .where('student_id', isEqualTo: studentId)
                .get();
            print(
              '[StudentDataRepository] Firebase class scores scoresChunk=${snap.docs.length} by assessment_remote_id+student_id(studentId) chunkSize=${chunk.length}',
            );
          }

          out.addAll(snap.docs);
        }
        return out;
      }

      final scoresDocs = await _fetchScoresByAssessmentIds(assessmentRemoteIds);
      print(
        '[StudentDataRepository] Firebase class scores totalScores=${scoresDocs.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );

      final scoreByAssessmentRemoteId = <String, Map<String, dynamic>>{};
      for (final s in scoresDocs) {
        final data = s.data();
        final aid = data['assessment_remote_id']?.toString() ?? '';
        if (aid.isEmpty) continue;
        scoreByAssessmentRemoteId[aid] = {...data, 'doc_id': s.id};
      }

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final a in assessments) {
        final assessmentId = a['doc_id']?.toString() ?? '';
        final catRemoteId =
            a['category_remote_id']?.toString() ?? 'uncategorized';
        final scoreRow = scoreByAssessmentRemoteId[assessmentId];
        final score = scoreRow?['score'];
        final maxScore = a['max_score'] ?? a['maxScore'];

        final item = <String, dynamic>{
          'assessment_remote_id': assessmentId,
          'assessment_name': a['name']?.toString() ?? 'Assessment',
          'max_score': maxScore,
          'score': score,
          'remarks': scoreRow?['remarks']?.toString() ?? '',
          'recorded_at': scoreRow?['recorded_at'],
          'updated_at': scoreRow?['updated_at'],
          'category_remote_id': catRemoteId,
        };

        grouped.putIfAbsent(catRemoteId, () => []).add(item);
      }

      final result = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final catId = entry.key;
        final name =
            categoryNameByRemoteId[catId] ??
            (catId == 'uncategorized' ? 'Uncategorized' : catId);
        final items = entry.value;
        items.sort(
          (a, b) => (a['assessment_name']?.toString() ?? '').compareTo(
            b['assessment_name']?.toString() ?? '',
          ),
        );

        var scoredCount = 0;
        var totalPct = 0.0;
        for (final it in items) {
          final s = (it['score'] is num)
              ? (it['score'] as num).toDouble()
              : double.tryParse(it['score']?.toString() ?? '');
          final m = (it['max_score'] is num)
              ? (it['max_score'] as num).toDouble()
              : double.tryParse(it['max_score']?.toString() ?? '');
          if (s != null && m != null && m > 0) {
            totalPct += (s / m) * 100.0;
            scoredCount++;
          }
        }

        final avgPct = scoredCount == 0 ? 0.0 : (totalPct / scoredCount);
        result.add({
          'category_remote_id': catId,
          'category_name': name,
          'average_pct': avgPct,
          'assessments': items,
        });
      }

      result.sort(
        (a, b) => (a['category_name']?.toString() ?? '').compareTo(
          b['category_name']?.toString() ?? '',
        ),
      );

      print(
        '[StudentDataRepository] Firebase class scores groupedCategories=${result.length} teacherUid=$teacherUid classRemoteId=$classRemoteId',
      );
      return result;
    } catch (e) {
      print('[StudentDataRepository] Firebase class scores error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStudentDashboardStatsFromFirebase(
    String firebaseUid,
  ) async {
    try {
      // Load local grading system + equivalency table for student-side display.
      // Student accounts may not have teacher settings locally, so we also
      // fallback to a preset if nothing is configured.
      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      try {
        final dbh = DatabaseHelper.instance;
        final gradingSystemJson = await dbh.getSetting('grading_system');
        if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gradingSystemJson) as Map<String, dynamic>,
          );
        }
        final eqJson = await dbh.getSetting('grade_equivalency_table');
        if (eqJson != null && eqJson.isNotEmpty) {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJson) as Map<String, dynamic>,
          );
        }

        if (eqTable.isNotEmpty) {
          final filtered = eqTable.equivalencies
              .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
              .toList();
          eqTable = eqTable.copyWith(equivalencies: filtered);
        }

        if (eqTable.isEmpty) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      } catch (e) {
        print(
          '[StudentDataRepository] Firebase stats settings parse error: $e',
        );
        eqTable = GradeEquivalencyTable.depedTo1to5;
      }

      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) {
        print(
          '[StudentDataRepository] Firebase stats: no teacher links for uid=$firebaseUid',
        );
        return {
          'gradeSummary': <String, dynamic>{},
          'attendanceSummary': <String, dynamic>{},
          'recentGrades': <Map<String, dynamic>>[],
          'recentAttendance': <Map<String, dynamic>>[],
        };
      }

      // Student dashboard should reflect the teacher's grading system and
      // equivalency remarks (source of truth). Try loading from the teacher's
      // Firestore user doc settings.
      try {
        final teacherUid = links.first.teacherUid;
        if (teacherUid.isNotEmpty) {
          final teacherDoc = await _firestore
              .collection('users')
              .doc(teacherUid)
              .get();
          final remoteSettings =
              teacherDoc.data()?['settings'] as Map<String, dynamic>? ?? {};

          final remoteGradingSystemJson =
              remoteSettings['grading_system']?.toString() ?? '';
          if (remoteGradingSystemJson.isNotEmpty) {
            try {
              gradingSystem = GradingSystemConfig.fromJson(
                jsonDecode(remoteGradingSystemJson) as Map<String, dynamic>,
              );
              print(
                '[StudentDataRepository] Firebase stats loaded grading_system from teacher settings teacherUid=$teacherUid type=${gradingSystem.typeString}',
              );
            } catch (e) {
              print(
                '[StudentDataRepository] Firebase stats teacher grading_system parse error teacherUid=$teacherUid: $e',
              );
            }
          }

          final remoteEqJson =
              remoteSettings['grade_equivalency_table']?.toString() ?? '';
          if (remoteEqJson.isNotEmpty) {
            try {
              var remoteTable = GradeEquivalencyTable.fromJson(
                jsonDecode(remoteEqJson) as Map<String, dynamic>,
              );
              if (remoteTable.isNotEmpty) {
                final filtered = remoteTable.equivalencies
                    .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
                    .toList();
                remoteTable = remoteTable.copyWith(equivalencies: filtered);
              }
              if (remoteTable.isNotEmpty) {
                eqTable = remoteTable;
                print(
                  '[StudentDataRepository] Firebase stats loaded grade_equivalency_table from teacher settings teacherUid=$teacherUid eqRows=${eqTable.equivalencies.length}',
                );
              }
            } catch (e) {
              print(
                '[StudentDataRepository] Firebase stats teacher grade_equivalency_table parse error teacherUid=$teacherUid: $e',
              );
            }
          }
        }
      } catch (e) {
        print(
          '[StudentDataRepository] Firebase stats teacher settings load error: $e',
        );
      }

      // Final fallback if teacher settings are not available.
      if (eqTable.isEmpty) {
        if (gradingSystem.type == GradingSystemType.college4point0) {
          eqTable = GradeEquivalencyTable.depedTo4point0;
        } else if (gradingSystem.type == GradingSystemType.college1to5) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        } else {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      }

      final studentId = links.first.studentId;

      // If the collectionGroup index is missing, getTeacherLinksByFirebaseUid()
      // may return only a partial set (or legacy single-teacher link). Expand
      // links via the per-student teachers subcollection which does not require
      // a collectionGroup index.
      var effectiveLinks = links;
      try {
        final byStudentId =
            await StudentAccountRepository.getTeacherLinksForStudentId(
              studentId,
            );
        if (byStudentId.isNotEmpty) {
          effectiveLinks = byStudentId;
        }
      } catch (e) {
        print(
          '[StudentDataRepository] Firebase stats teacher links expand error studentId=$studentId: $e',
        );
      }
      print(
        '[StudentDataRepository] Firebase stats scan by student_id=$studentId',
      );

      print(
        '[StudentDataRepository] Firebase stats teacherLinks count=${effectiveLinks.length} studentId=$studentId',
      );
      for (final l in effectiveLinks) {
        print(
          '[StudentDataRepository] Firebase stats teacherLink teacherUid=${l.teacherUid} studentRemoteId=${l.studentRemoteId} studentId=${l.studentId}',
        );
      }

      Future<int?> _resolveNumericStudentId({
        required String teacherUid,
        required String studentRemoteId,
      }) async {
        try {
          final doc = await _firestore
              .collection('users/$teacherUid/students')
              .doc(studentRemoteId)
              .get();
          final data = doc.data();
          if (data == null) return null;
          final candidates = [
            data['id'],
            data['local_id'],
            data['student_local_id'],
            data['student_id_num'],
          ];
          for (final c in candidates) {
            if (c is int) return c;
            if (c is num) return c.toInt();
            final parsed = int.tryParse(c?.toString() ?? '');
            if (parsed != null) return parsed;
          }
        } catch (e) {
          print(
            '[StudentDataRepository] Firebase stats resolveNumericStudentId error teacherUid=$teacherUid studentRemoteId=$studentRemoteId: $e',
          );
        }
        return null;
      }

      final allGrades = <Map<String, dynamic>>[];
      final allAttendance = <Map<String, dynamic>>[];

      for (final link in effectiveLinks) {
        final teacherUid = link.teacherUid;
        final studentRemoteId = link.studentRemoteId;

        print(
          '[StudentDataRepository] Firebase stats fetch teacherUid=$teacherUid studentRemoteId=$studentRemoteId',
        );

        try {
          final gradesCol = _firestore.collection('users/$teacherUid/grades');

          QuerySnapshot<Map<String, dynamic>> gradesSnap;
          gradesSnap = await gradesCol
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .get();
          print(
            '[StudentDataRepository] Firebase stats grades by student_remote_id=${gradesSnap.docs.length} teacherUid=$teacherUid studentRemoteId=$studentRemoteId',
          );

          if (gradesSnap.docs.isEmpty) {
            final numericStudentId = await _resolveNumericStudentId(
              teacherUid: teacherUid,
              studentRemoteId: studentRemoteId,
            );
            if (numericStudentId != null) {
              gradesSnap = await gradesCol
                  .where('student_id', isEqualTo: numericStudentId)
                  .get();
              print(
                '[StudentDataRepository] Firebase stats grades by student_id(numeric)=${gradesSnap.docs.length} teacherUid=$teacherUid numericStudentId=$numericStudentId',
              );
            }
          }

          if (gradesSnap.docs.isEmpty) {
            gradesSnap = await gradesCol
                .where('student_id', isEqualTo: studentRemoteId)
                .get();
            print(
              '[StudentDataRepository] Firebase stats grades by student_id(remoteId)=${gradesSnap.docs.length} teacherUid=$teacherUid studentRemoteId=$studentRemoteId',
            );
          }

          if (gradesSnap.docs.isEmpty) {
            gradesSnap = await gradesCol
                .where('student_id', isEqualTo: studentId)
                .get();
            print(
              '[StudentDataRepository] Firebase stats grades by student_id(studentId)=${gradesSnap.docs.length} teacherUid=$teacherUid studentId=$studentId',
            );
          }

          // Fallback: some deployments do not write per-assessment grade rows
          // into users/{teacherUid}/grades. Compute from assessments + scores.
          if (gradesSnap.docs.isEmpty) {
            try {
              final assessmentsCol = _firestore.collection(
                'users/$teacherUid/grading_assessments',
              );
              final scoresCol = _firestore.collection(
                'users/$teacherUid/assessment_scores',
              );
              final categoriesCol = _firestore.collection(
                'users/$teacherUid/grading_categories',
              );

              QuerySnapshot<Map<String, dynamic>> scoresSnap;
              scoresSnap = await scoresCol
                  .where('student_remote_id', isEqualTo: studentRemoteId)
                  .get();
              if (scoresSnap.docs.isEmpty) {
                scoresSnap = await scoresCol
                    .where('student_id', isEqualTo: studentRemoteId)
                    .get();
              }
              if (scoresSnap.docs.isEmpty && studentId.isNotEmpty) {
                scoresSnap = await scoresCol
                    .where('student_id', isEqualTo: studentId)
                    .get();
              }

              print(
                '[StudentDataRepository] Firebase stats grades fallback using assessment_scores count=${scoresSnap.docs.length} teacherUid=$teacherUid studentRemoteId=$studentRemoteId',
              );

              final scoreByAssessmentId = <String, double>{};
              for (final s in scoresSnap.docs) {
                final d = s.data();
                final aId = d['assessment_remote_id']?.toString() ?? '';
                if (aId.isEmpty) continue;
                final score = (d['score'] is num)
                    ? (d['score'] as num).toDouble()
                    : double.tryParse(d['score']?.toString() ?? '') ?? 0.0;
                scoreByAssessmentId[aId] = score;
              }

              final assessmentIds = scoreByAssessmentId.keys.toList();
              final assessmentById = <String, Map<String, dynamic>>{};
              const chunkSize = 10;
              for (var i = 0; i < assessmentIds.length; i += chunkSize) {
                final chunk = assessmentIds.sublist(
                  i,
                  (i + chunkSize) > assessmentIds.length
                      ? assessmentIds.length
                      : (i + chunkSize),
                );
                final aSnap = await assessmentsCol
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();
                for (final a in aSnap.docs) {
                  final d = a.data();
                  assessmentById[a.id] = {
                    ...d,
                    'doc_id': a.id,
                    'grading_period_remote_id':
                        d['grading_period_remote_id']?.toString() ?? '',
                    'category_remote_id':
                        d['category_remote_id']?.toString() ?? '',
                    'max_score': (d['max_score'] is num)
                        ? (d['max_score'] as num).toDouble()
                        : double.tryParse(d['max_score']?.toString() ?? '') ??
                              0.0,
                  };
                }
              }

              // Cache category weights per period.
              final catWeightsByPeriod = <String, Map<String, double>>{};
              for (final a in assessmentById.values) {
                final pId = a['grading_period_remote_id']?.toString() ?? '';
                if (pId.isEmpty || catWeightsByPeriod.containsKey(pId)) {
                  continue;
                }
                final catsSnap = await categoriesCol
                    .where('grading_period_remote_id', isEqualTo: pId)
                    .get();
                final weights = <String, double>{};
                for (final c in catsSnap.docs) {
                  weights[c.id] =
                      (c.data()['weight'] as num?)?.toDouble() ?? 0.0;
                }
                catWeightsByPeriod[pId] = weights;
              }

              // Compute period-weighted averages from assessments (mirrors Class View).
              // IMPORTANT: aggregate score/max per category FIRST, then apply the
              // category weight once. Applying weight per assessment can exceed 100%.
              final sumsByPeriodAndCategory =
                  <String, Map<String, Map<String, double>>>{};
              for (final a in assessmentById.values) {
                final pId = a['grading_period_remote_id']?.toString() ?? '';
                final cId = a['category_remote_id']?.toString() ?? '';
                if (pId.isEmpty || cId.isEmpty) continue;

                final aId = a['doc_id']?.toString() ?? '';
                final max = (a['max_score'] is num)
                    ? (a['max_score'] as num).toDouble()
                    : double.tryParse(a['max_score']?.toString() ?? '') ?? 0.0;
                final score = scoreByAssessmentId[aId] ?? 0.0;

                final perCat = sumsByPeriodAndCategory.putIfAbsent(
                  pId,
                  () => <String, Map<String, double>>{},
                );
                final sums = perCat.putIfAbsent(
                  cId,
                  () => <String, double>{'scoreSum': 0.0, 'maxSum': 0.0},
                );
                sums['scoreSum'] = (sums['scoreSum'] ?? 0.0) + score;
                sums['maxSum'] = (sums['maxSum'] ?? 0.0) + max;
              }

              final periodAverages = <String, double>{};
              for (final entry in sumsByPeriodAndCategory.entries) {
                final pId = entry.key;
                final perCat = entry.value;
                var periodPct = 0.0;
                for (final catEntry in perCat.entries) {
                  final cId = catEntry.key;
                  final scoreSum = catEntry.value['scoreSum'] ?? 0.0;
                  final maxSum = catEntry.value['maxSum'] ?? 0.0;
                  final weight = catWeightsByPeriod[pId]?[cId] ?? 0.0;
                  final contribution = (maxSum > 0 && weight > 0)
                      ? (scoreSum / maxSum) * 100.0 * (weight / 100.0)
                      : 0.0;
                  periodPct += contribution;
                }
                periodAverages[pId] = periodPct;
              }

              // Create one synthetic row per period with its weighted average so
              // the downstream generalAverage logic (period averages) works.
              for (final entry in periodAverages.entries) {
                final pId = entry.key;
                final pct = entry.value;
                allGrades.add({
                  'teacher_uid': teacherUid,
                  'doc_id': 'period:$pId',
                  'score': pct,
                  'max_score': 100.0,
                  'remarks': '',
                  'grading_period_remote_id': pId,
                  'category_remote_id': '',
                  'category_weight': 0.0,
                });
              }

              print(
                '[StudentDataRepository] Firebase stats grades fallback periodAverages=${periodAverages.length} teacherUid=$teacherUid',
              );
              for (final entry in periodAverages.entries) {
                print(
                  '[StudentDataRepository] Firebase stats grades fallback period=${entry.key} avgPct=${entry.value.toStringAsFixed(2)}',
                );
              }
            } catch (e) {
              print(
                '[StudentDataRepository] Firebase stats grades fallback error teacherUid=$teacherUid: $e',
              );
            }
          }

          for (final g in gradesSnap.docs) {
            final d = g.data();
            print(
              '[StudentDataRepository] Firebase stats gradeDoc teacherUid=$teacherUid docId=${g.id} fields=${d.keys.toList()}',
            );
            allGrades.add({...d, 'doc_id': g.id, 'teacher_uid': teacherUid});
          }
        } catch (e) {
          print(
            '[StudentDataRepository] Firebase stats grades query error teacherUid=$teacherUid: $e',
          );
        }

        try {
          final attCol = _firestore.collection('users/$teacherUid/attendance');

          QuerySnapshot<Map<String, dynamic>> attSnap;
          attSnap = await attCol
              .where('student_remote_id', isEqualTo: studentRemoteId)
              .get();
          print(
            '[StudentDataRepository] Firebase stats attendance by student_remote_id=${attSnap.docs.length} teacherUid=$teacherUid',
          );

          if (attSnap.docs.isEmpty) {
            attSnap = await attCol
                .where('student_id', isEqualTo: studentRemoteId)
                .get();
            print(
              '[StudentDataRepository] Firebase stats attendance by student_id(remoteId)=${attSnap.docs.length} teacherUid=$teacherUid',
            );
          }

          if (attSnap.docs.isEmpty) {
            attSnap = await attCol
                .where('student_id', isEqualTo: studentId)
                .get();
            print(
              '[StudentDataRepository] Firebase stats attendance by student_id(studentId)=${attSnap.docs.length} teacherUid=$teacherUid',
            );
          }

          for (final a in attSnap.docs) {
            final d = a.data();
            allAttendance.add({
              ...d,
              'doc_id': a.id,
              'teacher_uid': teacherUid,
            });
          }
          print(
            '[StudentDataRepository] Firebase stats attendance fetched teacherUid=$teacherUid count=${attSnap.docs.length}',
          );
          for (final a in attSnap.docs) {
            final d = a.data();
            final status = d['status']?.toString() ?? '';
            final date = d['date']?.toString() ?? '';
            print(
              '[StudentDataRepository] Firebase attendance raw teacherUid=$teacherUid status=$status date=$date',
            );
          }
        } catch (e) {
          print(
            '[StudentDataRepository] Firebase stats attendance query error teacherUid=$teacherUid: $e',
          );
        }
      }

      double avgPct = 0;
      if (allGrades.isNotEmpty) {
        var total = 0.0;
        var count = 0;
        for (final g in allGrades) {
          final score = (g['score'] is num)
              ? (g['score'] as num).toDouble()
              : double.tryParse(g['score']?.toString() ?? '') ?? 0.0;
          final maxScore = (g['max_score'] is num)
              ? (g['max_score'] as num).toDouble()
              : double.tryParse(g['max_score']?.toString() ?? '') ?? 0.0;

          if (maxScore > 0) {
            total += (score / maxScore) * 100.0;
            count++;
          } else {
            total += score;
            count++;
          }
        }
        avgPct = count == 0 ? 0 : (total / count);
      }

      final avgEquivalent = eqTable.convertPercentageToNumerical(avgPct);
      final avgDescriptor = eqTable.getDescriptor(avgPct);

      // General average: compute the teacher period-grade formula per period,
      // then average across periods with records.
      // Formula:
      //   Period = ROUND(100 - ((5/8) * (100 - (U + X))), 0)
      // Where:
      //   U = SUM of non-exam weighted contributions
      //   X = AVERAGE of exam weighted contributions
      final perPeriodComputed = <String, double>{};
      final perTeacherPeriodCats = <String, Map<String, Map<String, double>>>{};
      final perTeacherPeriodRawSumUx = <String, double>{};
      final teacherUids = <String>{};
      var missingPeriodKeyCount = 0;

      if (allGrades.isNotEmpty) {
        final sample = allGrades.first;
        print(
          '[StudentDataRepository] Firebase stats generalAverage sampleGradeKeys=${sample.keys.toList()}',
        );
      }

      // Enrich grade rows for UI (percent/equivalent/descriptor) + aggregate per
      // period/category.
      for (final g in allGrades) {
        final score = (g['score'] is num)
            ? (g['score'] as num).toDouble()
            : double.tryParse(g['score']?.toString() ?? '') ?? 0.0;
        final maxScore = (g['max_score'] is num)
            ? (g['max_score'] as num).toDouble()
            : double.tryParse(g['max_score']?.toString() ?? '') ?? 0.0;
        final pct = maxScore > 0 ? (score / maxScore) * 100.0 : score;
        g['percent'] = pct;
        g['equivalent'] = eqTable.convertPercentageToNumerical(pct);
        g['descriptor'] = eqTable.getDescriptor(pct);

        final teacherUid = (g['teacher_uid']?.toString() ?? '').trim();
        if (teacherUid.isNotEmpty) {
          teacherUids.add(teacherUid);
        }

        final periodKey =
            (g['grading_period_remote_id']?.toString() ??
                    g['grading_period_id']?.toString() ??
                    g['grading_period']?.toString() ??
                    g['period_remote_id']?.toString() ??
                    g['period_id']?.toString() ??
                    g['period']?.toString() ??
                    g['period_name']?.toString() ??
                    '')
                .trim();

        final categoryKey =
            (g['category_remote_id']?.toString() ??
                    g['category_id']?.toString() ??
                    '')
                .trim();

        if (teacherUid.isEmpty || periodKey.isEmpty) {
          if (periodKey.isEmpty) missingPeriodKeyCount++;
          continue;
        }

        // If category id is missing, we may still have per-period weighted sums
        // (U+X) available (e.g. synthetic period rows). Capture them so we can
        // still apply the teacher formula.
        if (categoryKey.isEmpty) {
          final teacherPeriodKey = '$teacherUid|$periodKey';
          perTeacherPeriodRawSumUx[teacherPeriodKey] = pct;
          continue;
        }

        // Composite key to prevent collisions across different teachers.
        final teacherPeriodKey = '$teacherUid|$periodKey';
        final cats = perTeacherPeriodCats.putIfAbsent(
          teacherPeriodKey,
          () => <String, Map<String, double>>{},
        );
        final sums = cats.putIfAbsent(
          categoryKey,
          () => <String, double>{'scoreSum': 0.0, 'maxSum': 0.0},
        );
        sums['scoreSum'] = (sums['scoreSum'] ?? 0.0) + score;
        sums['maxSum'] = (sums['maxSum'] ?? 0.0) + maxScore;
      }

      // Resolve category weights + names from Firestore and compute the teacher
      // period formula per period.
      final catMetaCache = <String, Map<String, Map<String, dynamic>>>{};
      for (final teacherPeriodEntry in perTeacherPeriodCats.entries) {
        final teacherPeriodKey = teacherPeriodEntry.key;
        final parts = teacherPeriodKey.split('|');
        final teacherUid = parts.isNotEmpty ? parts.first : '';
        final periodRemoteId = parts.length > 1 ? parts[1] : '';
        if (teacherUid.isEmpty || periodRemoteId.isEmpty) continue;

        final cacheKey = '$teacherUid|$periodRemoteId';
        if (!catMetaCache.containsKey(cacheKey)) {
          try {
            final catsSnap = await _firestore
                .collection('users/$teacherUid/grading_categories')
                .where('grading_period_remote_id', isEqualTo: periodRemoteId)
                .get();
            final meta = <String, Map<String, dynamic>>{};
            for (final c in catsSnap.docs) {
              final d = c.data();
              meta[c.id] = {
                'weight': (d['weight'] as num?)?.toDouble() ?? 0.0,
                'name': (d['name']?.toString() ?? '').trim(),
              };
            }
            catMetaCache[cacheKey] = meta;
            print(
              '[StudentDataRepository] Firebase stats generalAverage loaded categories teacherUid=$teacherUid period=$periodRemoteId count=${meta.length}',
            );
          } catch (e) {
            print(
              '[StudentDataRepository] Firebase stats generalAverage category load error teacherUid=$teacherUid period=$periodRemoteId: $e',
            );
            catMetaCache[cacheKey] = <String, Map<String, dynamic>>{};
          }
        }

        final meta = catMetaCache[cacheKey] ?? {};

        double uNonExam = 0.0;
        final examContribs = <double>[];

        for (final catEntry in teacherPeriodEntry.value.entries) {
          final catRemoteId = catEntry.key;
          final scoreSum = catEntry.value['scoreSum'] ?? 0.0;
          final maxSum = catEntry.value['maxSum'] ?? 0.0;
          final weight =
              (meta[catRemoteId]?['weight'] as num?)?.toDouble() ??
              (catEntry.value['weight'] ?? 0.0);
          final name = (meta[catRemoteId]?['name']?.toString() ?? '')
              .toLowerCase();
          final isExam = name.contains('exam');

          final contribution = (maxSum > 0 && weight > 0)
              ? (scoreSum / maxSum) * 100.0 * (weight / 100.0)
              : 0.0;

          if (isExam) {
            if (contribution > 0) examContribs.add(contribution);
          } else {
            uNonExam += contribution;
          }
        }

        final xExamAvg = examContribs.isEmpty
            ? 0.0
            : (examContribs.reduce((a, b) => a + b) / examContribs.length);

        if (uNonExam > 0 && xExamAvg > 0) {
          final sumUx = uNonExam + xExamAvg;
          final raw = 100 - ((5 / 8) * (100 - sumUx));
          final rounded = raw.roundToDouble();
          final minApplied = rounded > 70 ? rounded : 70.0;
          final finalPct = minApplied.clamp(0.0, 100.0).toDouble();
          perPeriodComputed[teacherPeriodKey] = finalPct;
          print(
            '[StudentDataRepository] Firebase stats generalAverage periodFormula teacherPeriod=$teacherPeriodKey U=$uNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$finalPct',
          );
        } else {
          print(
            '[StudentDataRepository] Firebase stats generalAverage periodFormula missing U/X teacherPeriod=$teacherPeriodKey U=$uNonExam X=$xExamAvg -> skipped',
          );
        }
      }

      // Fallback: if we couldn't compute any period formulas (missing category
      // rows) but we *do* have per-period weighted sums (U+X), apply the same
      // teacher formula directly to those sums.
      if (perPeriodComputed.isEmpty && perTeacherPeriodRawSumUx.isNotEmpty) {
        for (final entry in perTeacherPeriodRawSumUx.entries) {
          final teacherPeriodKey = entry.key;
          final sumUx = entry.value;
          if (sumUx <= 0) continue;

          final raw = 100 - ((5 / 8) * (100 - sumUx));
          final rounded = raw.roundToDouble();
          final minApplied = rounded > 70 ? rounded : 70.0;
          final finalPct = minApplied.clamp(0.0, 100.0).toDouble();
          perPeriodComputed[teacherPeriodKey] = finalPct;

          print(
            '[StudentDataRepository] Firebase stats generalAverage periodFormulaFromSumUx teacherPeriod=$teacherPeriodKey SUM=$sumUx raw=$raw rounded=$rounded final=$finalPct',
          );
        }
      }

      final computedPeriods = perPeriodComputed.values
          .where((v) => v > 0)
          .toList();

      // Fallback: if we couldn't compute any period formulas, use the old avgPct.
      var generalAvgPct = computedPeriods.isEmpty
          ? avgPct
          : computedPeriods.fold<double>(0.0, (a, b) => a + b) /
                computedPeriods.length;

      // Prefer the same source of truth as the Student Class View:
      // use per-class period grades (already computed with the teacher formula)
      // and average across all periods/classes with records.
      final dashboardPeriodGrades = <double>[];
      try {
        final classes = await getStudentClassesFromFirebase(firebaseUid);
        print(
          '[StudentDataRepository] Firebase stats dashboardGeneralAverage classes=${classes.length}',
        );
        for (final c in classes) {
          final teacherUid = (c['teacher_uid']?.toString() ?? '').trim();
          final classRemoteId = (c['class_remote_id']?.toString() ?? '').trim();
          if (teacherUid.isEmpty || classRemoteId.isEmpty) continue;

          final periodGrades = await getStudentPeriodGradesForClassFromFirebase(
            firebaseUid: firebaseUid,
            teacherUid: teacherUid,
            classRemoteId: classRemoteId,
          );

          for (final p in periodGrades) {
            final pct = (p['percent'] is num)
                ? (p['percent'] as num).toDouble()
                : double.tryParse(p['percent']?.toString() ?? '') ?? 0.0;
            if (pct > 0) dashboardPeriodGrades.add(pct);
          }
        }
      } catch (e) {
        print(
          '[StudentDataRepository] Firebase stats dashboardGeneralAverage error: $e',
        );
      }

      if (dashboardPeriodGrades.isNotEmpty) {
        final sum = dashboardPeriodGrades.fold<double>(0.0, (a, b) => a + b);
        generalAvgPct = sum / dashboardPeriodGrades.length;
        print(
          '[StudentDataRepository] Firebase stats dashboardGeneralAverage override periods=${dashboardPeriodGrades.length} generalAvgPct=${generalAvgPct.toStringAsFixed(2)}',
        );
      }

      final generalAvgEq = eqTable.convertPercentageToNumerical(generalAvgPct);
      final generalAvgDesc = eqTable.getDescriptor(generalAvgPct);

      print(
        '[StudentDataRepository] Firebase stats generalAverage computedPeriods=${computedPeriods.length} missingPeriodKeyCount=$missingPeriodKeyCount generalAvgPct=${generalAvgPct.toStringAsFixed(2)} generalAvgEq=${generalAvgEq?.toStringAsFixed(2) ?? ''} generalAvgDesc=${generalAvgDesc ?? ''}',
      );

      DateTime _parseMaybeDate(dynamic v) {
        if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        return DateTime.tryParse(v.toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }

      // De-dupe attendance by class/day. Some datasets may have duplicate docs for
      // the same date which would otherwise inflate absent counts.
      final groupStatus = <String, String>{};
      final perTeacherCounts = <String, Map<String, int>>{};
      final perStudentCounts = <String, Map<String, int>>{};
      for (final a in allAttendance) {
        final teacher = a['teacher_uid']?.toString() ?? 'unknown';
        final classRemoteId =
            (a['class_remote_id']?.toString() ??
                    a['class_id']?.toString() ??
                    '')
                .trim();
        final d = _parseMaybeDate(a['date'] ?? a['created_at']);
        final dayKey =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final groupKey = '$teacher|$classRemoteId|$dayKey';

        final status = (a['status']?.toString() ?? '').toLowerCase();
        final prev = groupStatus[groupKey];
        if (prev == 'absent') {
          // keep absent
        } else if (status == 'absent') {
          groupStatus[groupKey] = 'absent';
        } else if (status == 'present') {
          groupStatus[groupKey] = prev ?? 'present';
        }

        final studentKey =
            (a['student_name']?.toString() ??
                    a['student_id']?.toString() ??
                    'unknown')
                .toLowerCase()
                .trim();
        perStudentCounts.putIfAbsent(
          studentKey,
          () => {'present': 0, 'absent': 0, 'total': 0},
        );
      }

      var present = 0;
      var absent = 0;
      var totalAttendance = groupStatus.length;
      for (final entry in groupStatus.entries) {
        final parts = entry.key.split('|');
        final teacher = parts.isNotEmpty ? parts.first : 'unknown';

        perTeacherCounts.putIfAbsent(
          teacher,
          () => {'present': 0, 'absent': 0, 'total': 0},
        );
        perTeacherCounts[teacher]!['total'] =
            (perTeacherCounts[teacher]!['total'] ?? 0) + 1;

        if (entry.value == 'present') {
          present++;
          perTeacherCounts[teacher]!['present'] =
              (perTeacherCounts[teacher]!['present'] ?? 0) + 1;
        } else if (entry.value == 'absent') {
          absent++;
          perTeacherCounts[teacher]!['absent'] =
              (perTeacherCounts[teacher]!['absent'] ?? 0) + 1;
        }
      }

      print(
        '[StudentDataRepository] Firebase attendance aggregation rawRecords=${allAttendance.length} uniqueClassDays=$totalAttendance present=$present absent=$absent',
      );
      for (final entry in perStudentCounts.entries) {
        print(
          '[StudentDataRepository] Firebase attendance perStudent student=${entry.key} present=${entry.value['present']} absent=${entry.value['absent']} total=${entry.value['total']}',
        );
      }
      for (final entry in perTeacherCounts.entries) {
        print(
          '[StudentDataRepository] Firebase attendance perTeacher teacher=${entry.key} present=${entry.value['present']} absent=${entry.value['absent']} total=${entry.value['total']}',
        );
      }
      final attendanceRate = totalAttendance == 0
          ? 0.0
          : (present / totalAttendance) * 100.0;

      allGrades.sort((a, b) {
        final ad = _parseMaybeDate(a['updated_at'] ?? a['created_at']);
        final bd = _parseMaybeDate(b['updated_at'] ?? b['created_at']);
        return bd.compareTo(ad);
      });
      allAttendance.sort((a, b) {
        final ad = _parseMaybeDate(a['date'] ?? a['created_at']);
        final bd = _parseMaybeDate(b['date'] ?? b['created_at']);
        return bd.compareTo(ad);
      });

      final recentGrades = allGrades.take(10).toList();
      final recentAttendance = allAttendance.take(10).toList();

      final gradeSummary = <String, dynamic>{
        'totalGrades': allGrades.length,
        'averageScore': avgPct,
        'averageEquivalent': avgEquivalent,
        'averageDescriptor': avgDescriptor,
        'generalAverageScore': generalAvgPct,
        'generalAverageEquivalent': generalAvgEq,
        'generalAverageDescriptor': generalAvgDesc,
        'generalAveragePeriodCount': dashboardPeriodGrades.isNotEmpty
            ? dashboardPeriodGrades.length
            : computedPeriods.length,
        'grading_system_type': gradingSystem.typeString,
      };
      final attendanceSummary = <String, dynamic>{
        'totalRecords': totalAttendance,
        'presentCount': present,
        'absentCount': absent,
        'attendanceRate': attendanceRate,
      };

      print(
        '[StudentDataRepository] Firebase stats totalGrades=${allGrades.length} avgScore=${avgPct.toStringAsFixed(2)} totalAttendance=$totalAttendance attendanceRate=${attendanceRate.toStringAsFixed(2)}',
      );
      print(
        '[StudentDataRepository] Firebase stats grade equivalency avgEq=${avgEquivalent?.toStringAsFixed(2) ?? ''} avgDesc=${avgDescriptor ?? ''}',
      );

      return {
        'gradeSummary': gradeSummary,
        'attendanceSummary': attendanceSummary,
        'recentGrades': recentGrades,
        'recentAttendance': recentAttendance,
      };
    } catch (e) {
      print('[StudentDataRepository] Firebase stats error: $e');
      return {
        'gradeSummary': <String, dynamic>{},
        'attendanceSummary': <String, dynamic>{},
        'recentGrades': <Map<String, dynamic>>[],
        'recentAttendance': <Map<String, dynamic>>[],
      };
    }
  }

  Future<int?> _getLocalStudentRowId(String studentId) async {
    try {
      final db = await _db.database;
      final maps = await db.query(
        'students',
        columns: ['id'],
        where: 'student_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [studentId],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return maps.first['id'] as int?;
    } catch (e) {
      print('[StudentDataRepository] Error resolving local student id: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getStudentClassesFromFirebase(
    String firebaseUid,
  ) async {
    try {
      // Derive the student's global student_id (e.g., 2026-0001)
      // then scan all users/*/students where student_id matches.
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) {
        print(
          '[StudentDataRepository] No teacher links found; cannot resolve student_id for Firebase scan',
        );
        return [];
      }

      final studentId = links.first.studentId;
      print(
        '[StudentDataRepository] Firebase class scan by student_id=$studentId',
      );

      final studentsMatches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        final studentsSnap = await _firestore
            .collectionGroup('students')
            .where('student_id', isEqualTo: studentId)
            .get();
        studentsMatches.addAll(studentsSnap.docs);
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          print(
            '[StudentDataRepository] Firebase classes students collectionGroup index missing; falling back to users scan. $e',
          );

          final usersSnap = await _firestore.collection('users').get();
          for (final u in usersSnap.docs) {
            final teacherUid = u.id;
            try {
              final s = await _firestore
                  .collection('users/$teacherUid/students')
                  .where('student_id', isEqualTo: studentId)
                  .get();
              studentsMatches.addAll(s.docs);
            } catch (inner) {
              print(
                '[StudentDataRepository] Firebase classes users scan error teacherUid=$teacherUid: $inner',
              );
            }
          }
        } else {
          print(
            '[StudentDataRepository] Firebase students collectionGroup error: $e',
          );
          return [];
        }
      }

      print(
        '[StudentDataRepository] Firebase students matches=${studentsMatches.length} for student_id=$studentId',
      );

      final results = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final studentDoc in studentsMatches) {
        final teacherUid = studentDoc.reference.parent.parent?.id;
        if (teacherUid == null || teacherUid.isEmpty) {
          print(
            '[StudentDataRepository] Skipping student doc: cannot resolve teacherUid from path ${studentDoc.reference.path}',
          );
          continue;
        }
        final studentRemoteId = studentDoc.id;

        // Load teacher display name from settings (source of truth)
        String teacherName = '';
        try {
          final teacherDoc = await _firestore
              .collection('users')
              .doc(teacherUid)
              .get();
          final settings =
              teacherDoc.data()?['settings'] as Map<String, dynamic>? ?? {};
          teacherName = (settings['teacher_name']?.toString() ?? '').trim();
          if (teacherName.isEmpty) {
            teacherName = (teacherDoc.data()?['display_name']?.toString() ?? '')
                .trim();
          }
        } catch (e) {
          print(
            '[StudentDataRepository] Firebase classes teacher settings load error teacherUid=$teacherUid: $e',
          );
        }

        print(
          '[StudentDataRepository] Fetching enrollments teacherUid=$teacherUid studentRemoteId=$studentRemoteId',
        );

        final classStudentsSnap = await _firestore
            .collection('users/$teacherUid/class_students')
            .where('student_remote_id', isEqualTo: studentRemoteId)
            .get();

        print(
          '[StudentDataRepository] Firebase class_students=${classStudentsSnap.docs.length} teacherUid=$teacherUid',
        );

        for (final doc in classStudentsSnap.docs) {
          final d = doc.data();
          final classRemoteId = d['class_remote_id']?.toString() ?? '';
          if (classRemoteId.isEmpty) continue;

          final key = '$teacherUid|$classRemoteId';
          if (seen.contains(key)) continue;
          seen.add(key);

          final classDoc = await _firestore
              .collection('users/$teacherUid/classes')
              .doc(classRemoteId)
              .get();

          if (!classDoc.exists) {
            print(
              '[StudentDataRepository] Firebase class doc missing teacherUid=$teacherUid classRemoteId=$classRemoteId',
            );
            continue;
          }

          final c = classDoc.data() ?? <String, dynamic>{};

          // Fetch risk status from teacher's computed risk_flags (uses teacher thresholds)
          String riskLevel = 'unknown';
          try {
            final riskSnap = await _firestore
                .collection('users/$teacherUid/risk_flags')
                .where('student_remote_id', isEqualTo: studentRemoteId)
                .where('class_remote_id', isEqualTo: classRemoteId)
                .orderBy('updated_at', descending: true)
                .limit(1)
                .get();
            if (riskSnap.docs.isNotEmpty) {
              final rd = riskSnap.docs.first.data();
              riskLevel = (rd['risk_level']?.toString() ?? '').trim();
              if (riskLevel.isEmpty) riskLevel = 'unknown';
            } else {
              riskLevel = 'none';
            }
          } catch (e) {
            // orderBy may require index; keep graceful fallback
            print(
              '[StudentDataRepository] Firebase classes risk_flags load error teacherUid=$teacherUid classRemoteId=$classRemoteId: $e',
            );
          }

          // If the teacher hasn't computed risk flags (or student hasn't been evaluated
          // yet), derive a basic risk signal from period grades.
          if (riskLevel == 'none' || riskLevel == 'unknown') {
            try {
              final periodGrades =
                  await getStudentPeriodGradesForClassFromFirebase(
                    firebaseUid: firebaseUid,
                    teacherUid: teacherUid,
                    classRemoteId: classRemoteId,
                  );
              final nonZero = periodGrades
                  .map((p) {
                    final pct = (p['percent'] is num)
                        ? (p['percent'] as num).toDouble()
                        : double.tryParse(p['percent']?.toString() ?? '') ??
                              0.0;
                    final desc = (p['descriptor']?.toString() ?? '').trim();
                    return {'pct': pct, 'desc': desc};
                  })
                  .where((e) => (e['pct'] as double) > 0)
                  .toList();

              String derived = 'low';
              if (nonZero.isNotEmpty) {
                final hasFailedDescriptor = nonZero.any(
                  (e) => (e['desc'] as String).toLowerCase().contains('fail'),
                );
                final minPct = nonZero
                    .map((e) => (e['pct'] as double))
                    .reduce((a, b) => a < b ? a : b);
                if (hasFailedDescriptor || minPct < 75) {
                  derived = 'high';
                }
              }

              print(
                '[StudentDataRepository] Firebase classes derived riskLevel=$derived source=period_grades teacherUid=$teacherUid classRemoteId=$classRemoteId periods=${nonZero.length}',
              );
              riskLevel = derived;
            } catch (e) {
              print(
                '[StudentDataRepository] Firebase classes derived riskLevel error teacherUid=$teacherUid classRemoteId=$classRemoteId: $e',
              );
            }
          }

          print(
            '[StudentDataRepository] Firebase classes row teacherUid=$teacherUid classRemoteId=$classRemoteId teacherName=$teacherName riskLevel=$riskLevel',
          );
          results.add({
            'teacher_uid': teacherUid,
            'teacher_name': teacherName,
            'class_remote_id': classRemoteId,
            'subject_code': c['subject_code']?.toString() ?? '',
            'subject_remote_id': c['subject_remote_id']?.toString() ?? '',
            'section': c['section']?.toString() ?? '',
            'school_year': c['school_year']?.toString() ?? '',
            'semester': c['semester']?.toString() ?? '',
            'schedule': c['schedule']?.toString() ?? '',
            'room': c['room']?.toString() ?? '',
            'enrolled_at': d['enrolled_at']?.toString() ?? '',
            'risk_level': riskLevel,
          });
        }
      }

      print(
        '[StudentDataRepository] Firebase fetched classes total=${results.length}',
      );
      return results;
    } catch (e) {
      print('[StudentDataRepository] Error fetching classes from Firebase: $e');
      return [];
    }
  }

  /// Get the current student's profile information
  Future<Student?> getCurrentStudentProfile(String firebaseUid) async {
    try {
      // Get student account info from Firebase
      final studentInfo = await StudentAccountRepository.getStudentAccountByUid(
        firebaseUid,
      );
      if (studentInfo == null) {
        print(
          '[StudentDataRepository] No student account found for Firebase UID',
        );
        return null;
      }

      // Get student from local database
      final db = await _db.database;
      final maps = await db.query(
        'students',
        where: 'student_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [studentInfo.studentId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        print(
          '[StudentDataRepository] Found student profile: ${studentInfo.studentId}',
        );
        return Student.fromMap(maps.first);
      }

      print(
        '[StudentDataRepository] Student profile not found locally: ${studentInfo.studentId}',
      );
      return null;
    } catch (e) {
      print('[StudentDataRepository] Error getting student profile: $e');
      return null;
    }
  }

  /// Get student's grades across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentGrades(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) {
        print('[StudentDataRepository] No teacher links found for student');
        return [];
      }

      // Get all local student row IDs across all teachers
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      if (localStudentIds.isEmpty) {
        print('[StudentDataRepository] No local student records found');
        return [];
      }

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          g.*,
          c.section as class_section,
          c.school_year,
          sub.name as subject_name,
          sub.code as subject_code,
          gp.name as grading_period_name,
          gc.name as category_name,
          s.first_name,
          s.last_name
        FROM grades g
        LEFT JOIN classes c ON g.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN grading_periods gp ON g.grading_period_id = gp.id
        LEFT JOIN grading_categories gc ON g.category_id = gc.id
        LEFT JOIN students s ON g.student_id = s.id
        WHERE g.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(g.deleted, 0) = 0
        ORDER BY gp.order_num ASC, c.school_year DESC, sub.name ASC
      ''', localStudentIds);

      print('[StudentDataRepository] Found ${maps.length} grades for student');
      return maps;
    } catch (e) {
      print('[StudentDataRepository] Error getting student grades: $e');
      return [];
    }
  }

  /// Get student's attendance records across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentAttendance(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) return [];

      // Get all local student row IDs
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      if (localStudentIds.isEmpty) return [];

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          a.*,
          c.section as class_section,
          c.school_year,
          sub.name as subject_name,
          sub.code as subject_code,
          s.first_name,
          s.last_name
        FROM attendance a
        LEFT JOIN classes c ON a.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN students s ON a.student_id = s.id
        WHERE a.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(a.deleted, 0) = 0
        ORDER BY a.date DESC
      ''', localStudentIds);

      print(
        '[StudentDataRepository] Found ${maps.length} attendance records for student',
      );
      return maps;
    } catch (e) {
      print('[StudentDataRepository] Error getting student attendance: $e');
      return [];
    }
  }

  /// Get student's assessment scores across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentAssessmentScores(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );

      // Get all local student row IDs
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      // Fallback: if teacher links are not available yet, use local settings.
      if (localStudentIds.isEmpty) {
        final fallbackStudentId =
            (await _db.getSetting('student_id'))?.toString().trim() ?? '';
        if (fallbackStudentId.isNotEmpty) {
          final localId = await _getLocalStudentRowId(fallbackStudentId);
          if (localId != null) {
            localStudentIds.add(localId);
            print(
              '[StudentDataRepository] getStudentAssessmentScores fallback: student_id=$fallbackStudentId localStudentId=$localId',
            );
          } else {
            print(
              '[StudentDataRepository] getStudentAssessmentScores fallback failed: no local students row for student_id=$fallbackStudentId',
            );
          }
        } else {
          print(
            '[StudentDataRepository] getStudentAssessmentScores blocked: no teacher links + missing settings student_id',
          );
        }
      }

      if (localStudentIds.isEmpty) return [];

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          ass.*,
          ga.name as assessment_name,
          ga.max_score,
          gc.name as category_name,
          c.section as class_section,
          c.school_year as class_school_year,
          sub.name as subject_name,
          sub.code as subject_code,
          s.first_name,
          s.last_name
        FROM assessment_scores ass
        LEFT JOIN grading_assessments ga ON ass.assessment_id = ga.id
        LEFT JOIN grading_categories gc ON ga.category_id = gc.id
        LEFT JOIN classes c ON ga.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN students s ON ass.student_id = s.id
        WHERE ass.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(ass.deleted, 0) = 0
        ORDER BY COALESCE(ass.recorded_at, ass.updated_at) DESC
      ''', localStudentIds);

      print(
        '[StudentDataRepository] Found ${maps.length} assessment scores for student localStudentIds=${localStudentIds.join(',')}',
      );
      return maps;
    } catch (e) {
      print(
        '[StudentDataRepository] Error getting student assessment scores: $e',
      );
      return [];
    }
  }

  /// Get student's interventions across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentInterventions(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) return [];

      // Get all local student row IDs
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      if (localStudentIds.isEmpty) return [];

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          i.*,
          c.section as class_section,
          c.school_year,
          sub.name as subject_name,
          s.first_name,
          s.last_name
        FROM interventions i
        LEFT JOIN classes c ON i.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN students s ON i.student_id = s.id
        WHERE i.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(i.deleted, 0) = 0
        ORDER BY i.date DESC
      ''', localStudentIds);

      print(
        '[StudentDataRepository] Found ${maps.length} interventions for student',
      );
      return maps;
    } catch (e) {
      print('[StudentDataRepository] Error getting student interventions: $e');
      return [];
    }
  }

  /// Get student's risk flags across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentRiskFlags(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) return [];

      // Get all local student row IDs
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      if (localStudentIds.isEmpty) return [];

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          r.*,
          c.section as class_section,
          c.school_year,
          sub.name as subject_name,
          s.first_name,
          s.last_name
        FROM risk_flags r
        LEFT JOIN classes c ON r.class_id = c.id
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN students s ON r.student_id = s.id
        WHERE r.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(r.deleted, 0) = 0
        ORDER BY r.date DESC
      ''', localStudentIds);

      print(
        '[StudentDataRepository] Found ${maps.length} risk flags for student',
      );
      return maps;
    } catch (e) {
      print('[StudentDataRepository] Error getting student risk flags: $e');
      return [];
    }
  }

  /// Get student's enrolled classes across ALL teachers
  Future<List<Map<String, dynamic>>> getStudentClasses(
    String firebaseUid,
  ) async {
    try {
      // Get all teacher links for this student
      final links = await StudentAccountRepository.getTeacherLinksByFirebaseUid(
        firebaseUid,
      );
      if (links.isEmpty) return [];

      // Get all local student row IDs
      final List<int> localStudentIds = [];
      for (final link in links) {
        final localId = await _getLocalStudentRowId(link.studentId);
        if (localId != null) {
          localStudentIds.add(localId);
        }
      }

      if (localStudentIds.isEmpty) return [];

      final db = await _db.database;
      final maps = await db.rawQuery('''
        SELECT 
          c.*,
          sub.name as subject_name,
          sub.code as subject_code,
          cs.enrolled_at,
          s.first_name,
          s.last_name
        FROM classes c
        LEFT JOIN subjects sub ON c.subject_id = sub.id
        LEFT JOIN class_students cs ON c.id = cs.class_id
        LEFT JOIN students s ON cs.student_id = s.id
        WHERE cs.student_id IN (${localStudentIds.map((_) => '?').join(', ')}) AND COALESCE(c.deleted, 0) = 0 AND COALESCE(cs.deleted, 0) = 0
        ORDER BY c.school_year DESC, sub.name ASC
      ''', localStudentIds);

      print('[StudentDataRepository] Found ${maps.length} classes for student');
      return maps;
    } catch (e) {
      print('[StudentDataRepository] Error getting student classes: $e');
      return [];
    }
  }

  /// Get student's grade summary statistics
  Future<Map<String, dynamic>> getStudentGradeSummary(
    String firebaseUid,
  ) async {
    try {
      final grades = await getStudentGrades(firebaseUid);

      if (grades.isEmpty) {
        return {
          'totalGrades': 0,
          'averageScore': 0.0,
          'highestScore': 0.0,
          'lowestScore': 0.0,
          'subjectsCount': 0,
        };
      }

      final scores = grades
          .map((g) => (g['score'] as num?)?.toDouble() ?? 0.0)
          .toList();
      final averageScore = scores.reduce((a, b) => a + b) / scores.length;
      final highestScore = scores.reduce((a, b) => a > b ? a : b);
      final lowestScore = scores.reduce((a, b) => a < b ? a : b);

      final uniqueSubjects = grades
          .map((g) => g['subject_name'])
          .toSet()
          .length;

      return {
        'totalGrades': grades.length,
        'averageScore': averageScore,
        'highestScore': highestScore,
        'lowestScore': lowestScore,
        'subjectsCount': uniqueSubjects,
      };
    } catch (e) {
      print('[StudentDataRepository] Error getting grade summary: $e');
      return {
        'totalGrades': 0,
        'averageScore': 0.0,
        'highestScore': 0.0,
        'lowestScore': 0.0,
        'subjectsCount': 0,
      };
    }
  }

  /// Get student's attendance summary
  Future<Map<String, dynamic>> getStudentAttendanceSummary(
    String firebaseUid,
  ) async {
    try {
      final attendance = await getStudentAttendance(firebaseUid);

      if (attendance.isEmpty) {
        return {
          'totalDays': 0,
          'presentDays': 0,
          'absentDays': 0,
          'lateDays': 0,
          'attendanceRate': 0.0,
        };
      }

      final totalDays = attendance.length;
      final presentDays = attendance
          .where((a) => a['status'] == 'Present')
          .length;
      final absentDays = attendance
          .where((a) => a['status'] == 'Absent')
          .length;
      final lateDays = attendance.where((a) => a['status'] == 'Late').length;
      final attendanceRate = totalDays > 0
          ? (presentDays / totalDays) * 100
          : 0.0;

      return {
        'totalDays': totalDays,
        'presentDays': presentDays,
        'absentDays': absentDays,
        'lateDays': lateDays,
        'attendanceRate': attendanceRate,
      };
    } catch (e) {
      print('[StudentDataRepository] Error getting attendance summary: $e');
      return {
        'totalDays': 0,
        'presentDays': 0,
        'absentDays': 0,
        'lateDays': 0,
        'attendanceRate': 0.0,
      };
    }
  }

  /// Sync student data from Firestore
  Future<StudentSyncResult> syncStudentData({
    required String firebaseUid,
    String? direction,
    Function(String)? onStatusUpdate,
  }) async {
    return await StudentSyncService.syncStudentData(
      firebaseUid: firebaseUid,
      direction: direction,
      onStatusUpdate: onStatusUpdate,
    );
  }
}
