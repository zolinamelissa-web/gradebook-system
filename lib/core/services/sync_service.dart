import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_account_repository.dart';

enum SyncMode { both, upload, download }

class SyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final AuthRepository _authRepo = AuthRepository();

  static final Map<String, bool> _studentAccountExistsCache = {};

  static SyncMode _mode = SyncMode.both;

  static SyncMode _parseMode(String? direction) {
    if (direction == 'upload') return SyncMode.upload;
    if (direction == 'download') return SyncMode.download;
    return SyncMode.both;
  }

  static bool get _doUpload => _mode != SyncMode.download;
  static bool get _doDownload => _mode != SyncMode.upload;

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
      print('[SyncService] Internet check failed: $e');
      return false;
    }
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
    return rows.first['id'] as int?;
  }

  static Future<String> _getStudentIdStringFromLocalStudentRowId(
    Database db,
    int localStudentRowId,
  ) async {
    try {
      final rows = await db.query(
        'students',
        columns: ['student_id'],
        where: 'id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [localStudentRowId],
        limit: 1,
      );
      if (rows.isEmpty) return '';
      return (rows.first['student_id']?.toString() ?? '').trim();
    } catch (e) {
      print(
        '[SyncService] Error resolving student_id for local student row id=$localStudentRowId: $e',
      );
      return '';
    }
  }

  static Future<bool> _studentAccountExists(String studentId) async {
    final key = studentId.trim();
    if (key.isEmpty) return false;
    final cached = _studentAccountExistsCache[key];
    if (cached != null) return cached;
    try {
      final doc = await _firestore
          .collection('student_accounts')
          .doc(key)
          .get();
      final ok = doc.exists;
      _studentAccountExistsCache[key] = ok;
      return ok;
    } catch (e) {
      print('[SyncService] student_accounts check failed studentId=$key: $e');
      _studentAccountExistsCache[key] = false;
      return false;
    }
  }

  static Future<bool> _studentAccountExistsForLocalStudentRowId(
    Database db,
    int localStudentRowId,
  ) async {
    final studentId = await _getStudentIdStringFromLocalStudentRowId(
      db,
      localStudentRowId,
    );
    final ok = await _studentAccountExists(studentId);
    if (!ok) {
      print(
        '[SyncService] Upload skipped: student_id not in student_accounts studentId=$studentId localStudentRowId=$localStudentRowId',
      );
    }
    return ok;
  }

  static Future<void> _logLocalCounts(String tag) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final tables = <String, String>{
        'settings': 'settings',
        'students': 'students',
        'subjects': 'subjects',
        'classes': 'classes',
        'class_students': 'class_students',
        'grading_periods': 'grading_periods',
        'grading_categories': 'grading_categories',
        'grading_configurations': 'grading_configurations',
        'grading_assessments': 'grading_assessments',
        'assessment_scores': 'assessment_scores',
        'grades': 'grades',
        'attendance': 'attendance',
        'interventions': 'interventions',
        'risk_flags': 'risk_flags',
        'counseling_reasons': 'counseling_reasons',
        'lessons': 'lessons',
      };

      final counts = <String, int>{};
      for (final entry in tables.entries) {
        final res = await db.rawQuery(
          'SELECT COUNT(*) as c FROM ${entry.value}',
        );
        counts[entry.key] = (res.first['c'] as int?) ?? 0;
      }
      print('[SyncService] Local counts after $tag: $counts');
    } catch (e) {
      print('[SyncService] Local counts log error after $tag: $e');
    }
  }

  /// Main sync method - syncs all entities
  static Future<SyncResult> syncAll({
    Function(String)? onStatusUpdate,
    String? direction,
    List<String>? selectedTables,
  }) async {
    print('[SyncService] Starting full sync...');
    final result = SyncResult();

    final previousMode = _mode;
    _mode = _parseMode(direction);

    try {
      final online = await _hasInternetConnection();
      if (!online) {
        result.error = _noInternetMessage;
        onStatusUpdate?.call(_noInternetMessage);
        print('[SyncService] $_noInternetMessage');
        return result;
      }

      // Get active user from local database
      onStatusUpdate?.call('Connecting to cloud...');
      final user = await _authRepo.getActiveUser();
      if (user == null) {
        result.error = 'No active user found. Please sign in again.';
        print('[SyncService] Error: ${result.error}');
        return result;
      }
      final userId = user.uid;
      print('[SyncService] Syncing for user: $userId (${user.email})');

      // Sync each entity type - All 16 SQLite tables
      // Note: Users table is managed by Firebase Auth, not synced manually
      // If selectedTables is null, sync all tables

      if (selectedTables == null || selectedTables.contains('settings')) {
        onStatusUpdate?.call('Syncing Settings...');
        await _syncSettings(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('students')) {
        onStatusUpdate?.call('Syncing Students...');
        await _syncStudents(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('subjects')) {
        onStatusUpdate?.call('Syncing Subjects...');
        await _syncSubjects(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('classes')) {
        onStatusUpdate?.call('Syncing Classes...');
        await _syncClasses(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('class_students')) {
        onStatusUpdate?.call('Syncing Class Students...');
        await _syncClassStudents(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('grading_periods')) {
        onStatusUpdate?.call('Syncing Grading Periods...');
        await _syncGradingPeriods(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('grading_categories')) {
        onStatusUpdate?.call('Syncing Grading Categories...');
        await _syncGradingCategories(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('grading_configurations')) {
        onStatusUpdate?.call('Syncing Grading Configurations...');
        await _syncGradingConfigurations(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('grading_assessments')) {
        onStatusUpdate?.call('Syncing Grading Assessments...');
        await _syncGradingAssessments(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('assessment_scores')) {
        onStatusUpdate?.call('Syncing Assessment Scores...');
        await _syncAssessmentScores(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('grades')) {
        onStatusUpdate?.call('Syncing Grades...');
        await _syncGrades(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('attendance')) {
        onStatusUpdate?.call('Syncing Attendance...');
        await _syncAttendance(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('interventions')) {
        onStatusUpdate?.call('Syncing Interventions...');
        await _syncInterventions(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('risk_flags')) {
        onStatusUpdate?.call('Syncing Risk Flags...');
        await _syncRiskFlags(userId, result);
      }

      if (selectedTables == null ||
          selectedTables.contains('counseling_reasons')) {
        onStatusUpdate?.call('Syncing Counseling Reasons...');
        await _syncCounselingReasons(userId, result);
      }

      if (selectedTables == null || selectedTables.contains('lessons')) {
        onStatusUpdate?.call('Syncing Lessons...');
        await _syncLessons(userId, result);
      }

      result.success = true;
      onStatusUpdate?.call('Sync completed successfully!');
      print('[SyncService] Sync completed successfully: ${result.summary()}');
      await _logLocalCounts('syncAll');
    } catch (e) {
      result.error = e.toString();
      onStatusUpdate?.call('Sync failed: $e');
      print('[SyncService] Sync failed: $e');
    } finally {
      _mode = previousMode;
    }

    return result;
  }

  /// Sync method - syncs only entities related to a specific class
  static Future<SyncResult> syncClass(int classId) async {
    print('[SyncService] Starting class sync classId=$classId...');
    final result = SyncResult();

    try {
      final online = await _hasInternetConnection();
      if (!online) {
        result.error = _noInternetMessage;
        print('[SyncService] $_noInternetMessage');
        return result;
      }

      final user = await _authRepo.getActiveUser();
      if (user == null) {
        result.error = 'No active user found. Please sign in again.';
        print('[SyncService] Error: ${result.error}');
        return result;
      }

      final userId = user.uid;
      print('[SyncService] Class sync for user: $userId (${user.email})');

      await _syncSingleClass(userId, result, classId);
      await _syncClassStudentsForClass(userId, result, classId);
      await _syncGradingPeriodsForClass(userId, result, classId);
      await _syncGradingCategoriesForClass(userId, result, classId);
      await _syncGradingConfigurationsForClass(userId, result, classId);
      await _syncLessonsForClass(userId, result, classId);
      await _syncGradingAssessmentsForClass(userId, result, classId);
      await _syncAssessmentScoresForClass(userId, result, classId);
      await _syncGradesForClass(userId, result, classId);
      await _syncAttendanceForClass(userId, result, classId);
      await _syncInterventionsForClass(userId, result, classId);
      await _syncRiskFlagsForClass(userId, result, classId);

      await _syncDynamicTables(userId, result, classId: classId);

      result.success = true;
      print(
        '[SyncService] Class sync completed successfully classId=$classId: ${result.summary()}',
      );
      await _logLocalCounts('syncClass classId=$classId');
    } catch (e) {
      result.error = e.toString();
      print('[SyncService] Class sync failed classId=$classId: $e');
    }

    return result;
  }

  static Future<void> _syncSingleClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing single class id=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/classes');

    // Prefer non-deleted row, but fall back to any row in case the local
    // record was soft-deleted while still being referenced in the UI.
    var localList = await db.query(
      'classes',
      where: 'id = ? AND deleted = 0',
      whereArgs: [classId],
      limit: 1,
    );
    if (localList.isEmpty) {
      localList = await db.query(
        'classes',
        where: 'id = ?',
        whereArgs: [classId],
        limit: 1,
      );
    }
    if (localList.isEmpty) {
      throw Exception('Class not found locally: id=$classId');
    }

    final localRow = localList.first;
    final localDeleted = (localRow['deleted'] as int?) ?? 0;
    if (localDeleted == 1) {
      print(
        '[SyncService] Warning: class id=$classId is marked deleted=1 locally',
      );
    }
    final remoteId = localRow['remote_id'] as String?;
    final localUpdated = DateTime.parse(localRow['updated_at'] as String);

    if (remoteId != null && remoteId.isNotEmpty) {
      final remoteDoc = await collection.doc(remoteId).get();
      if (remoteDoc.exists) {
        final remote = {...?remoteDoc.data(), 'doc_id': remoteDoc.id};
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          if (_doUpload) {
            await collection.doc(remoteId).update({
              'subject_id': localRow['subject_id'],
              'section': localRow['section'],
              'school_year': localRow['school_year'],
              'semester': localRow['semester'] ?? '',
              'schedule': localRow['schedule'] ?? '',
              'room': localRow['room'] ?? '',
              'is_archived': localRow['is_archived'] ?? 0,
              'updated_at': Timestamp.fromDate(localUpdated),
            });
            result.uploaded++;
            print('[SyncService] Uploaded class id=$classId to remote');
          }
        } else if (remoteUpdated.isAfter(localUpdated)) {
          if (_doDownload) {
            await db.update(
              'classes',
              {
                'subject_id': remote['subject_id'],
                'section': remote['section'],
                'school_year': remote['school_year'],
                'semester': remote['semester'] ?? '',
                'schedule': remote['schedule'] ?? '',
                'room': remote['room'] ?? '',
                'is_archived': remote['is_archived'] ?? 0,
                'updated_at': remoteUpdated.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [classId],
            );
            result.downloaded++;
            print('[SyncService] Downloaded class id=$classId from remote');
          }
        }
      } else {
        // Remote doc missing; recreate it.
        if (_doUpload) {
          final docRef = await collection.add({
            'subject_id': localRow['subject_id'],
            'section': localRow['section'],
            'school_year': localRow['school_year'],
            'semester': localRow['semester'] ?? '',
            'schedule': localRow['schedule'] ?? '',
            'room': localRow['room'] ?? '',
            'is_archived': localRow['is_archived'] ?? 0,
            'updated_at': Timestamp.fromDate(localUpdated),
            'created_at': Timestamp.fromDate(
              DateTime.parse(localRow['created_at'] as String),
            ),
          });
          await db.update(
            'classes',
            {'remote_id': docRef.id},
            where: 'id = ?',
            whereArgs: [classId],
          );
          result.uploaded++;
          print('[SyncService] Recreated remote class for local id=$classId');
        }
      }
    } else {
      if (_doUpload) {
        final docRef = await collection.add({
          'subject_id': localRow['subject_id'],
          'section': localRow['section'],
          'school_year': localRow['school_year'],
          'semester': localRow['semester'] ?? '',
          'schedule': localRow['schedule'] ?? '',
          'room': localRow['room'] ?? '',
          'is_archived': localRow['is_archived'] ?? 0,
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'classes',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [classId],
        );
        result.uploaded++;
        print('[SyncService] Created remote class for local id=$classId');
      }
    }
  }

  static Future<void> _syncClassStudentsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing class_students for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/class_students');

    final classRemoteId = await _getRemoteIdForLocalId(db, 'classes', classId);

    // Note: class_students does not have remote_id / deleted / updated_at.
    // Merge-only sync (no deletes, no last-write-wins).
    final localRows = await db.query(
      'class_students',
      where: 'class_id = ?',
      whereArgs: [classId],
    );

    QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
    if (classRemoteId != null && classRemoteId.isNotEmpty) {
      remoteSnapshot = await collection
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
    } else {
      // Legacy fallback (same-device only)
      remoteSnapshot = await collection
          .where('class_id', isEqualTo: classId)
          .get();
    }

    final remotePairs = <String>{};
    for (final doc in remoteSnapshot.docs) {
      final d = doc.data();
      final remoteClassRemoteId = d['class_remote_id']?.toString() ?? '';
      final remoteStudentRemoteId = d['student_remote_id']?.toString() ?? '';
      if (remoteClassRemoteId.isNotEmpty && remoteStudentRemoteId.isNotEmpty) {
        remotePairs.add('$remoteClassRemoteId|$remoteStudentRemoteId');
      } else {
        // Legacy fallback (same-device only)
        remotePairs.add('${d['class_id']}_${d['student_id']}');
      }
    }

    int uploaded = 0;
    int downloaded = 0;

    for (final r in localRows) {
      final localStudentId = r['student_id'] as int?;
      if (localStudentId == null) continue;

      if (_doUpload) {
        final ok = await _studentAccountExistsForLocalStudentRowId(
          db,
          localStudentId,
        );
        if (!ok) continue;
      }

      final studentRemoteId = await _getRemoteIdForLocalId(
        db,
        'students',
        localStudentId,
      );

      final key =
          (classRemoteId != null &&
              classRemoteId.isNotEmpty &&
              studentRemoteId != null &&
              studentRemoteId.isNotEmpty)
          ? '$classRemoteId|$studentRemoteId'
          : '${r['class_id']}_${r['student_id']}';
      if (!remotePairs.contains(key)) {
        await collection.add({
          'class_id': r['class_id'],
          'student_id': r['student_id'],
          'class_remote_id': classRemoteId ?? '',
          'student_remote_id': studentRemoteId ?? '',
          'enrolled_at': r['enrolled_at'],
        });
        uploaded++;
      }
    }

    final localPairs = <String>{};
    for (final r in localRows) {
      final localStudentId = r['student_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      if (classRemoteId != null &&
          classRemoteId.isNotEmpty &&
          studentRemoteId != null &&
          studentRemoteId.isNotEmpty) {
        localPairs.add('$classRemoteId|$studentRemoteId');
      }
      localPairs.add('${r['class_id']}_${r['student_id']}');
    }

    for (final doc in remoteSnapshot.docs) {
      final d = doc.data();

      final remoteClassRemoteId = d['class_remote_id']?.toString() ?? '';
      final remoteStudentRemoteId = d['student_remote_id']?.toString() ?? '';
      final legacyKey = '${d['class_id']}_${d['student_id']}';
      final remoteKey =
          (remoteClassRemoteId.isNotEmpty && remoteStudentRemoteId.isNotEmpty)
          ? '$remoteClassRemoteId|$remoteStudentRemoteId'
          : legacyKey;

      if (localPairs.contains(remoteKey)) continue;

      // For cross-device safety: require remote ids to resolve to local ids.
      if (remoteClassRemoteId.isEmpty || remoteStudentRemoteId.isEmpty) {
        print(
          '[SyncService] Skipping class_students insert (legacy-only row): missing class_remote_id/student_remote_id',
        );
        continue;
      }

      final resolvedClassId = await _getLocalIdForRemoteId(
        db,
        'classes',
        remoteClassRemoteId,
      );
      if (resolvedClassId == null) {
        print(
          '[SyncService] Skipping class_students insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
        );
        continue;
      }
      final resolvedStudentId = await _getLocalIdForRemoteId(
        db,
        'students',
        remoteStudentRemoteId,
      );
      if (resolvedStudentId == null) {
        print(
          '[SyncService] Skipping class_students insert: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
        );
        continue;
      }

      await db.insert('class_students', {
        'class_id': resolvedClassId,
        'student_id': resolvedStudentId,
        'enrolled_at':
            (d['enrolled_at'] as String?) ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      downloaded++;
    }

    result.uploaded += uploaded;
    result.downloaded += downloaded;
    print(
      '[SyncService] class_students sync classId=$classId uploaded=$uploaded downloaded=$downloaded local=${localRows.length} remote=${remoteSnapshot.docs.length}',
    );
  }

  static Future<void> _syncLessonsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing lessons for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/lessons');

    final classRemoteId = await _getRemoteIdForLocalId(db, 'classes', classId);

    final localRows = await db.query(
      'lessons',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final remoteSnapshot = await collection
        .where('class_id', isEqualTo: classId)
        .get();

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (_doUpload) {
        final localStudentId = localRow['student_id'] as int?;
        if (localStudentId == null) {
          print(
            '[SyncService] Skipping grade upload id=$localId: missing student_id',
          );
          continue;
        }
        final ok = await _studentAccountExistsForLocalStudentRowId(
          db,
          localStudentId,
        );
        if (!ok) continue;
      }

      if (remoteId != null &&
          remoteId.isNotEmpty &&
          remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'class_id': localRow['class_id'],
            'class_remote_id': classRemoteId ?? '',
            'week_number': localRow['week_number'],
            'title': localRow['title'],
            'pdf_path': localRow['pdf_path'] ?? '',
            'content': localRow['content'] ?? '',
            'objectives': localRow['objectives'] ?? '',
            'refs': localRow['refs'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          int? resolvedClassId;
          if (remoteClassRemoteId.isNotEmpty) {
            resolvedClassId = await _getLocalIdForRemoteId(
              db,
              'classes',
              remoteClassRemoteId,
            );
            if (resolvedClassId == null) {
              print(
                '[SyncService] Skipping lessons download/update: class_remote_id not found locally remote_id=$remoteClassRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'lessons',
            {
              'class_id': resolvedClassId ?? remote['class_id'],
              'week_number': remote['week_number'],
              'title': remote['title'],
              'pdf_path': remote['pdf_path'],
              'content': remote['content'],
              'objectives': remote['objectives'],
              'refs': remote['refs'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'class_id': localRow['class_id'],
          'class_remote_id': classRemoteId ?? '',
          'week_number': localRow['week_number'],
          'title': localRow['title'],
          'pdf_path': localRow['pdf_path'] ?? '',
          'content': localRow['content'] ?? '',
          'objectives': localRow['objectives'] ?? '',
          'refs': localRow['refs'] ?? '',
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'lessons',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      int? resolvedClassId;
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping lessons insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      }
      await db.insert('lessons', {
        'class_id': resolvedClassId ?? remote['class_id'],
        'week_number': remote['week_number'],
        'title': remote['title'],
        'pdf_path': remote['pdf_path'],
        'content': remote['content'],
        'objectives': remote['objectives'],
        'refs': remote['refs'],
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }

    print(
      '[SyncService] lessons sync classId=$classId local=${localRows.length} remote=${remoteSnapshot.docs.length}',
    );
  }

  static Future<void> _syncGradingAssessmentsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing grading assessments for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_assessments',
    );

    final localRows = await db.query(
      'grading_assessments',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final remoteSnapshot = await collection
        .where('class_id', isEqualTo: classId)
        .get();

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null &&
          remoteId.isNotEmpty &&
          remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'category_id': localRow['category_id'],
            'name': localRow['name'],
            'max_score': localRow['max_score'],
            'order_num': localRow['order_num'] ?? 0,
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          await db.update(
            'grading_assessments',
            {
              'class_id': remote['class_id'],
              'grading_period_id': remote['grading_period_id'],
              'category_id': remote['category_id'],
              'name': remote['name'],
              'max_score': remote['max_score'],
              'order_num': remote['order_num'] ?? 0,
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'category_id': localRow['category_id'],
          'name': localRow['name'],
          'max_score': localRow['max_score'],
          'order_num': localRow['order_num'] ?? 0,
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_assessments',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('grading_assessments', {
        'class_id': remote['class_id'],
        'grading_period_id': remote['grading_period_id'],
        'category_id': remote['category_id'],
        'name': remote['name'],
        'max_score': remote['max_score'],
        'order_num': remote['order_num'] ?? 0,
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }

    print(
      '[SyncService] grading_assessments sync classId=$classId local=${localRows.length} remote=${remoteSnapshot.docs.length}',
    );
  }

  static Future<void> _syncAssessmentScoresForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing assessment scores for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/assessment_scores');

    final localAssessmentRows = await db.query(
      'grading_assessments',
      columns: ['id'],
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final assessmentIds = localAssessmentRows
        .map((r) => r['id'] as int)
        .toList();
    if (assessmentIds.isEmpty) {
      print(
        '[SyncService] assessment_scores sync skipped: no assessments for classId=$classId',
      );
      return;
    }

    final localRows = await db.rawQuery(
      '''
      SELECT s.*
      FROM assessment_scores s
      INNER JOIN grading_assessments a ON a.id = s.assessment_id
      WHERE a.class_id = ? AND s.deleted = 0
    ''',
      [classId],
    );

    QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
    if (assessmentIds.length <= 10) {
      remoteSnapshot = await collection
          .where('assessment_id', whereIn: assessmentIds)
          .get();
    } else {
      // Fallback (Firestore whereIn limit)
      remoteSnapshot = await collection.get();
    }

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      final data = doc.data();
      final aid = data['assessment_id'];
      if (assessmentIds.contains(aid)) {
        remoteMap[doc.id] = {...data, 'doc_id': doc.id};
      }
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null &&
          remoteId.isNotEmpty &&
          remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'assessment_id': localRow['assessment_id'],
            'student_id': localRow['student_id'],
            'score': localRow['score'],
            'remarks': localRow['remarks'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          await db.update(
            'assessment_scores',
            {
              'assessment_id': remote['assessment_id'],
              'student_id': remote['student_id'],
              'score': remote['score'],
              'remarks': remote['remarks'] ?? '',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'assessment_id': localRow['assessment_id'],
          'student_id': localRow['student_id'],
          'score': localRow['score'],
          'remarks': localRow['remarks'] ?? '',
          'updated_at': Timestamp.fromDate(localUpdated),
          'recorded_at': Timestamp.fromDate(
            DateTime.parse(localRow['recorded_at'] as String),
          ),
        });
        await db.update(
          'assessment_scores',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('assessment_scores', {
        'assessment_id': remote['assessment_id'],
        'student_id': remote['student_id'],
        'score': remote['score'],
        'remarks': remote['remarks'] ?? '',
        'recorded_at':
            (remote['recorded_at'] as Timestamp?)?.toDate().toIso8601String() ??
            DateTime.now().toIso8601String(),
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }

    print(
      '[SyncService] assessment_scores sync classId=$classId local=${localRows.length} remote=${remoteSnapshot.docs.length}',
    );
  }

  static Future<void> _syncGradingPeriodsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing grading periods for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/grading_periods');

    final classRemoteId = await _getRemoteIdForLocalId(db, 'classes', classId);

    final localRows = await db.query(
      'grading_periods',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );

    QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
    if (classRemoteId != null && classRemoteId.isNotEmpty) {
      remoteSnapshot = await collection
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
    } else {
      // Legacy fallback (same-device only)
      remoteSnapshot = await collection
          .where('class_id', isEqualTo: classId)
          .get();
    }
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localPeriodId = localRow['grading_period_id'] as int?;
      final localCategoryId = localRow['category_id'] as int?;
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);
      final categoryRemoteId = localCategoryId == null
          ? null
          : await _getRemoteIdForLocalId(
              db,
              'grading_categories',
              localCategoryId,
            );

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'grading_period',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'class_id': localRow['class_id'],
            'class_remote_id': classRemoteId ?? '',
            'name': localRow['name'],
            'order_num': localRow['order_num'],
            'is_active': localRow['is_active'] ?? 0,
            'is_locked': localRow['is_locked'] ?? 0,
            'start_date': localRow['start_date'] ?? '',
            'end_date': localRow['end_date'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          int? resolvedClassId;
          if (remoteClassRemoteId.isNotEmpty) {
            resolvedClassId = await _getLocalIdForRemoteId(
              db,
              'classes',
              remoteClassRemoteId,
            );
            if (resolvedClassId == null) {
              print(
                '[SyncService] Skipping grading_periods download/update: class_remote_id not found locally remote_id=$remoteClassRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'grading_periods',
            {
              'class_id': resolvedClassId ?? remote['class_id'],
              'name': remote['name'],
              'order_num': remote['order_num'],
              'is_active': remote['is_active'] ?? 0,
              'is_locked': remote['is_locked'] ?? 0,
              'start_date': remote['start_date'] ?? '',
              'end_date': remote['end_date'] ?? '',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'class_id': localRow['class_id'],
          'class_remote_id': classRemoteId ?? '',
          'name': localRow['name'],
          'order_num': localRow['order_num'],
          'is_active': localRow['is_active'] ?? 0,
          'is_locked': localRow['is_locked'] ?? 0,
          'start_date': localRow['start_date'] ?? '',
          'end_date': localRow['end_date'] ?? '',
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_periods',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      int? resolvedClassId;
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping grading_periods insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      } else {
        // Cross-device safety: avoid legacy-only inserts
        print(
          '[SyncService] Skipping grading_periods insert (legacy-only row): missing class_remote_id',
        );
        continue;
      }

      await db.insert('grading_periods', {
        'class_id': resolvedClassId,
        'name': remote['name'],
        'order_num': remote['order_num'],
        'is_active': remote['is_active'] ?? 0,
        'is_locked': remote['is_locked'] ?? 0,
        'start_date': remote['start_date'] ?? '',
        'end_date': remote['end_date'] ?? '',
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncGradingCategoriesForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing grading categories for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_categories',
    );

    final localRows = await db.rawQuery(
      '''
      SELECT c.*
      FROM grading_categories c
      INNER JOIN grading_periods p ON p.id = c.grading_period_id
      WHERE p.class_id = ? AND c.deleted = 0
    ''',
      [classId],
    );

    // Fetch all remote categories and filter by class
    final remoteSnapshot = await collection.get();

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localPeriodId = localRow['grading_period_id'] as int?;
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'class',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'grading_period_id': localRow['grading_period_id'],
            'grading_period_remote_id': periodRemoteId ?? '',
            'name': localRow['name'],
            'weight': localRow['weight'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          int? resolvedPeriodId;
          if (remotePeriodRemoteId.isNotEmpty) {
            resolvedPeriodId = await _getLocalIdForRemoteId(
              db,
              'grading_periods',
              remotePeriodRemoteId,
            );
            if (resolvedPeriodId == null) {
              print(
                '[SyncService] Skipping grading_categories download/update: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'grading_categories',
            {
              'grading_period_id':
                  resolvedPeriodId ?? remote['grading_period_id'],
              'name': remote['name'],
              'weight': remote['weight'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'grading_period_id': localRow['grading_period_id'],
          'grading_period_remote_id': periodRemoteId ?? '',
          'name': localRow['name'],
          'weight': localRow['weight'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_categories',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('grading_categories', {
        'grading_period_id': remote['grading_period_id'],
        'name': remote['name'],
        'weight': remote['weight'],
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncGradingConfigurationsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print(
      '[SyncService] Syncing grading configurations for classId=$classId...',
    );
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_configurations',
    );

    final localRows = await db.rawQuery(
      '''
      SELECT gc.*
      FROM grading_configurations gc
      INNER JOIN grading_periods p ON p.id = gc.grading_period_id
      WHERE p.class_id = ? AND gc.deleted = 0
    ''',
      [classId],
    );

    // Fetch all remote configurations and filter by class
    final remoteSnapshot = await collection.get();

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localPeriodId = localRow['grading_period_id'] as int?;
      final localCategoryId = localRow['category_id'] as int?;
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);
      final categoryRemoteId = localCategoryId == null
          ? null
          : await _getRemoteIdForLocalId(
              db,
              'grading_categories',
              localCategoryId,
            );

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'grading_period_id': localRow['grading_period_id'],
            'category_id': localRow['category_id'],
            'grading_period_remote_id': periodRemoteId ?? '',
            'category_remote_id': categoryRemoteId ?? '',
            'max_score': localRow['max_score'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          final remoteCategoryRemoteId =
              remote['category_remote_id']?.toString() ?? '';
          int? resolvedPeriodId;
          int? resolvedCategoryId;
          if (remotePeriodRemoteId.isNotEmpty) {
            resolvedPeriodId = await _getLocalIdForRemoteId(
              db,
              'grading_periods',
              remotePeriodRemoteId,
            );
            if (resolvedPeriodId == null) {
              print(
                '[SyncService] Skipping grading_configurations download/update: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remoteCategoryRemoteId.isNotEmpty) {
            resolvedCategoryId = await _getLocalIdForRemoteId(
              db,
              'grading_categories',
              remoteCategoryRemoteId,
            );
            if (resolvedCategoryId == null) {
              print(
                '[SyncService] Skipping grading_configurations download/update: category_remote_id not found locally remote_id=$remoteCategoryRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'grading_configurations',
            {
              'grading_period_id':
                  resolvedPeriodId ?? remote['grading_period_id'],
              'category_id': resolvedCategoryId ?? remote['category_id'],
              'max_score': remote['max_score'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'grading_period_id': localRow['grading_period_id'],
          'category_id': localRow['category_id'],
          'grading_period_remote_id': periodRemoteId ?? '',
          'category_remote_id': categoryRemoteId ?? '',
          'max_score': localRow['max_score'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_configurations',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('grading_configurations', {
        'grading_period_id': remote['grading_period_id'],
        'category_id': remote['category_id'],
        'max_score': remote['max_score'],
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncGradesForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing grades for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/grades');

    final localRows = await db.query(
      'grades',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final remoteSnapshot = await collection
        .where('class_id', isEqualTo: classId)
        .get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final localCategoryId = localRow['category_id'] as int?;

      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);
      final categoryRemoteId = localCategoryId == null
          ? null
          : await _getRemoteIdForLocalId(
              db,
              'grading_categories',
              localCategoryId,
            );

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'subject',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          if (_doUpload) {
            await collection.doc(remoteId).update({
              'student_id': localRow['student_id'],
              'class_id': localRow['class_id'],
              'grading_period_id': localRow['grading_period_id'],
              'category_id': localRow['category_id'],
              'student_remote_id': studentRemoteId ?? '',
              'class_remote_id': classRemoteId ?? '',
              'grading_period_remote_id': periodRemoteId ?? '',
              'category_remote_id': categoryRemoteId ?? '',
              'score': localRow['score'],
              'max_score': localRow['max_score'],
              'remarks': localRow['remarks'] ?? '',
              'updated_at': Timestamp.fromDate(localUpdated),
            });
            result.uploaded++;
          } else {
            print(
              '[SyncService] Skipping grades upload (download-only mode) localId=$localId remoteId=$remoteId',
            );
          }
        } else if (remoteUpdated.isAfter(localUpdated)) {
          if (!_doDownload) {
            // Upload-only mode should never revert local edits. Force local to win.
            final now = DateTime.now();
            print(
              '[SyncService] Upload-only: remote newer, forcing grades upload localId=$localId remoteId=$remoteId localUpdated=$localUpdated remoteUpdated=$remoteUpdated',
            );
            await collection.doc(remoteId).update({
              'student_id': localRow['student_id'],
              'class_id': localRow['class_id'],
              'grading_period_id': localRow['grading_period_id'],
              'category_id': localRow['category_id'],
              'student_remote_id': studentRemoteId ?? '',
              'class_remote_id': classRemoteId ?? '',
              'grading_period_remote_id': periodRemoteId ?? '',
              'category_remote_id': categoryRemoteId ?? '',
              'score': localRow['score'],
              'max_score': localRow['max_score'],
              'remarks': localRow['remarks'] ?? '',
              'updated_at': Timestamp.fromDate(now),
            });
            await db.update(
              'grades',
              {'updated_at': now.toIso8601String()},
              where: 'id = ?',
              whereArgs: [localId],
            );
            result.uploaded++;
            remoteMap.remove(remoteId);
            continue;
          }
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          final remoteCategoryRemoteId =
              remote['category_remote_id']?.toString() ?? '';
          int? resolvedStudentId;
          int? resolvedClassId;
          int? resolvedPeriodId;
          int? resolvedCategoryId;
          if (remoteStudentRemoteId.isNotEmpty) {
            resolvedStudentId = await _getLocalIdForRemoteId(
              db,
              'students',
              remoteStudentRemoteId,
            );
            if (resolvedStudentId == null) {
              print(
                '[SyncService] Skipping grades download/update: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remoteClassRemoteId.isNotEmpty) {
            resolvedClassId = await _getLocalIdForRemoteId(
              db,
              'classes',
              remoteClassRemoteId,
            );
            if (resolvedClassId == null) {
              print(
                '[SyncService] Skipping grades download/update: class_remote_id not found locally remote_id=$remoteClassRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remotePeriodRemoteId.isNotEmpty) {
            resolvedPeriodId = await _getLocalIdForRemoteId(
              db,
              'grading_periods',
              remotePeriodRemoteId,
            );
            if (resolvedPeriodId == null) {
              print(
                '[SyncService] Skipping grades download/update: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remoteCategoryRemoteId.isNotEmpty) {
            resolvedCategoryId = await _getLocalIdForRemoteId(
              db,
              'grading_categories',
              remoteCategoryRemoteId,
            );
            if (resolvedCategoryId == null) {
              print(
                '[SyncService] Skipping grades download/update: category_remote_id not found locally remote_id=$remoteCategoryRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'grades',
            {
              'student_id': resolvedStudentId ?? remote['student_id'],
              'class_id': resolvedClassId ?? remote['class_id'],
              'grading_period_id':
                  resolvedPeriodId ?? remote['grading_period_id'],
              'category_id': resolvedCategoryId ?? remote['category_id'],
              'score': remote['score'],
              'max_score': remote['max_score'],
              'remarks': remote['remarks'] ?? '',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        if (_doUpload) {
          final localStudentId = localRow['student_id'] as int?;
          if (localStudentId == null) {
            print(
              '[SyncService] Skipping grades upload id=$localId: missing student_id',
            );
            continue;
          }
          final ok = await _studentAccountExistsForLocalStudentRowId(
            db,
            localStudentId,
          );
          if (!ok) continue;

          final docRef = await collection.add({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'category_id': localRow['category_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'category_remote_id': categoryRemoteId ?? '',
            'score': localRow['score'],
            'max_score': localRow['max_score'],
            'remarks': localRow['remarks'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
            'recorded_at': Timestamp.fromDate(
              DateTime.parse(localRow['recorded_at'] as String),
            ),
          });
          await db.update(
            'grades',
            {'remote_id': docRef.id},
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.uploaded++;
        } else {
          print(
            '[SyncService] Skipping grades create remote (download-only mode) localId=$localId',
          );
        }
      }
    }

    if (!_doDownload) {
      print('[SyncService] Grades sync complete (upload-only mode)');
      return;
    }
    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      final remoteCategoryRemoteId =
          remote['category_remote_id']?.toString() ?? '';
      int? resolvedStudentId;
      int? resolvedClassId;
      int? resolvedPeriodId;
      int? resolvedCategoryId;
      if (remoteStudentRemoteId.isNotEmpty) {
        resolvedStudentId = await _getLocalIdForRemoteId(
          db,
          'students',
          remoteStudentRemoteId,
        );
        if (resolvedStudentId == null) {
          print(
            '[SyncService] Skipping grades insert: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
          );
          continue;
        }
      }
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping grades insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      }
      if (remotePeriodRemoteId.isNotEmpty) {
        resolvedPeriodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          remotePeriodRemoteId,
        );
        if (resolvedPeriodId == null) {
          print(
            '[SyncService] Skipping grades insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
          );
          continue;
        }
      }
      if (remoteCategoryRemoteId.isNotEmpty) {
        resolvedCategoryId = await _getLocalIdForRemoteId(
          db,
          'grading_categories',
          remoteCategoryRemoteId,
        );
        if (resolvedCategoryId == null) {
          print(
            '[SyncService] Skipping grades insert: category_remote_id not found locally remote_id=$remoteCategoryRemoteId',
          );
          continue;
        }
      }
      await db.insert('grades', {
        'student_id': resolvedStudentId ?? remote['student_id'],
        'class_id': resolvedClassId ?? remote['class_id'],
        'grading_period_id': resolvedPeriodId ?? remote['grading_period_id'],
        'category_id': resolvedCategoryId ?? remote['category_id'],
        'score': remote['score'],
        'max_score': remote['max_score'],
        'remarks': remote['remarks'] ?? '',
        'remote_id': remote['doc_id'],
        'recorded_at': (remote['recorded_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncAttendanceForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing attendance for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/attendance');

    final classRemoteId = await _getRemoteIdForLocalId(db, 'classes', classId);

    final localRows = await db.query(
      'attendance',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );

    QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
    if (classRemoteId != null && classRemoteId.isNotEmpty) {
      remoteSnapshot = await collection
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
    } else {
      // Legacy fallback (same-device only)
      remoteSnapshot = await collection
          .where('class_id', isEqualTo: classId)
          .get();
    }
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localCreated = DateTime.parse(localRow['created_at'] as String);

      if (_doUpload) {
        final localStudentId = localRow['student_id'] as int?;
        if (localStudentId == null) {
          print(
            '[SyncService] Skipping attendance upload id=$localId: missing student_id',
          );
          continue;
        }
        final ok = await _studentAccountExistsForLocalStudentRowId(
          db,
          localStudentId,
        );
        if (!ok) continue;
      }

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteCreated = (remote['created_at'] as Timestamp).toDate();

        if (localCreated.isAfter(remoteCreated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'date': localRow['date'],
            'status': localRow['status'],
            'remarks': localRow['remarks'] ?? '',
            'created_at': Timestamp.fromDate(localCreated),
          });
          result.uploaded++;
        } else if (remoteCreated.isAfter(localCreated)) {
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          int? resolvedStudentId;
          int? resolvedClassId;
          int? resolvedPeriodId;
          if (remoteStudentRemoteId.isNotEmpty) {
            resolvedStudentId = await _getLocalIdForRemoteId(
              db,
              'students',
              remoteStudentRemoteId,
            );
            if (resolvedStudentId == null) {
              print(
                '[SyncService] Skipping attendance download/update: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remoteClassRemoteId.isNotEmpty) {
            resolvedClassId = await _getLocalIdForRemoteId(
              db,
              'classes',
              remoteClassRemoteId,
            );
            if (resolvedClassId == null) {
              print(
                '[SyncService] Skipping attendance download/update: class_remote_id not found locally remote_id=$remoteClassRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          if (remotePeriodRemoteId.isNotEmpty) {
            resolvedPeriodId = await _getLocalIdForRemoteId(
              db,
              'grading_periods',
              remotePeriodRemoteId,
            );
            if (resolvedPeriodId == null) {
              print(
                '[SyncService] Skipping attendance download/update: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
              );
              remoteMap.remove(remoteId);
              continue;
            }
          }
          await db.update(
            'attendance',
            {
              'student_id': resolvedStudentId ?? remote['student_id'],
              'class_id': resolvedClassId ?? remote['class_id'],
              'grading_period_id':
                  resolvedPeriodId ?? remote['grading_period_id'],
              'date': remote['date'],
              'status': remote['status'],
              'remarks': remote['remarks'] ?? '',
              'created_at': remoteCreated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'student_remote_id': studentRemoteId ?? '',
          'class_remote_id': classRemoteId ?? '',
          'grading_period_remote_id': periodRemoteId ?? '',
          'date': localRow['date'],
          'status': localRow['status'],
          'remarks': localRow['remarks'] ?? '',
          'created_at': Timestamp.fromDate(localCreated),
        });
        await db.update(
          'attendance',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';

      if (remoteStudentRemoteId.isEmpty ||
          remoteClassRemoteId.isEmpty ||
          remotePeriodRemoteId.isEmpty) {
        print(
          '[SyncService] Skipping attendance insert (legacy-only row): missing *_remote_id fields',
        );
        continue;
      }

      final resolvedStudentId = await _getLocalIdForRemoteId(
        db,
        'students',
        remoteStudentRemoteId,
      );
      if (resolvedStudentId == null) {
        print(
          '[SyncService] Skipping attendance insert: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
        );
        continue;
      }
      final resolvedClassId = await _getLocalIdForRemoteId(
        db,
        'classes',
        remoteClassRemoteId,
      );
      if (resolvedClassId == null) {
        print(
          '[SyncService] Skipping attendance insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
        );
        continue;
      }
      final resolvedPeriodId = await _getLocalIdForRemoteId(
        db,
        'grading_periods',
        remotePeriodRemoteId,
      );
      if (resolvedPeriodId == null) {
        print(
          '[SyncService] Skipping attendance insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
        );
        continue;
      }

      await db.insert('attendance', {
        'student_id': resolvedStudentId,
        'class_id': resolvedClassId,
        'grading_period_id': resolvedPeriodId,
        'date': remote['date'],
        'status': remote['status'],
        'remarks': remote['remarks'] ?? '',
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncInterventionsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing interventions for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/interventions');

    final localRows = await db.query(
      'interventions',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final remoteSnapshot = await collection
        .where('class_id', isEqualTo: classId)
        .get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'subject',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'title': localRow['title'],
            'description': localRow['description'],
            'intervention_date': localRow['intervention_date'],
            'follow_up_date': localRow['follow_up_date'] ?? '',
            'status': localRow['status'] ?? 'open',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          await db.update(
            'interventions',
            {
              'student_id': remote['student_id'],
              'class_id': remote['class_id'],
              'grading_period_id': remote['grading_period_id'],
              'title': remote['title'],
              'description': remote['description'],
              'intervention_date': remote['intervention_date'],
              'follow_up_date': remote['follow_up_date'] ?? '',
              'status': remote['status'] ?? 'open',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'title': localRow['title'],
          'description': localRow['description'],
          'intervention_date': localRow['intervention_date'],
          'follow_up_date': localRow['follow_up_date'] ?? '',
          'status': localRow['status'] ?? 'open',
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'interventions',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('interventions', {
        'student_id': remote['student_id'],
        'class_id': remote['class_id'],
        'grading_period_id': remote['grading_period_id'],
        'title': remote['title'],
        'description': remote['description'],
        'intervention_date': remote['intervention_date'],
        'follow_up_date': remote['follow_up_date'] ?? '',
        'status': remote['status'] ?? 'open',
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.downloaded++;
    }
  }

  static Future<void> _syncRiskFlagsForClass(
    String userId,
    SyncResult result,
    int classId,
  ) async {
    print('[SyncService] Syncing risk flags for classId=$classId...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/risk_flags');

    final localRows = await db.query(
      'risk_flags',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
    );
    final remoteSnapshot = await collection
        .where('class_id', isEqualTo: classId)
        .get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'risk_level': localRow['risk_level'],
            'grade_score': localRow['grade_score'],
            'attendance_percentage': localRow['attendance_percentage'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          await db.update(
            'risk_flags',
            {
              'student_id': remote['student_id'],
              'class_id': remote['class_id'],
              'grading_period_id': remote['grading_period_id'],
              'risk_level': remote['risk_level'],
              'grade_score': remote['grade_score'],
              'attendance_percentage': remote['attendance_percentage'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'risk_level': localRow['risk_level'],
          'grade_score': localRow['grade_score'],
          'attendance_percentage': localRow['attendance_percentage'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'flagged_at': Timestamp.fromDate(
            DateTime.parse(localRow['flagged_at'] as String),
          ),
        });
        await db.update(
          'risk_flags',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      await db.insert('risk_flags', {
        'student_id': remote['student_id'],
        'class_id': remote['class_id'],
        'grading_period_id': remote['grading_period_id'],
        'risk_level': remote['risk_level'],
        'grade_score': remote['grade_score'],
        'attendance_percentage': remote['attendance_percentage'],
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'flagged_at': (remote['flagged_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
  }

  // ────────────────────────────────────────────────────────────
  // STUDENTS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncStudents(String userId, SyncResult result) async {
    print('[SyncService] Syncing students...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/students');

    // Get local students
    final localRows = await db.query('students', where: 'deleted = 0');
    print('[SyncService] Found ${localRows.length} local students');

    // Get remote students
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }
    print('[SyncService] Found ${remoteMap.length} remote students');

    // Sync logic: last-write-wins
    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        // Record exists both locally and remotely
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          // Local is newer, push to cloud
          if (_doUpload) {
            await collection.doc(remoteId).update(_studentToMap(localRow));

            // Ensure student_accounts doc exists so student-scoped uploads won't be skipped.
            final studentId = (localRow['student_id'] as String?) ?? '';
            if (studentId.isNotEmpty) {
              try {
                await StudentAccountRepository.createStudentAccountEntry(
                  studentId: studentId,
                  studentRemoteId: remoteId,
                  teacherUid: userId,
                );
                _studentAccountExistsCache.remove(studentId);
                print(
                  '[SyncService] student_accounts upserted for studentId=$studentId (existing remoteId=$remoteId)',
                );
              } catch (e) {
                print(
                  '[SyncService] Warning: Failed to upsert student account entry for studentId=$studentId remoteId=$remoteId: $e',
                );
              }
            }

            result.uploaded++;
            print('[SyncService] Uploaded student id=$localId to remote');
          }
        } else if (remoteUpdated.isAfter(localUpdated)) {
          // Remote is newer, pull to local
          if (_doDownload) {
            await db.update(
              'students',
              _studentFromRemote(remote),
              where: 'id = ?',
              whereArgs: [localId],
            );
            result.downloaded++;
            print('[SyncService] Downloaded student id=$localId from remote');
          }
        }
        remoteMap.remove(remoteId);
      } else {
        // Local only, push to cloud
        if (_doUpload) {
          final docRef = await collection.add(_studentToMap(localRow));
          await db.update(
            'students',
            {'remote_id': docRef.id},
            where: 'id = ?',
            whereArgs: [localId],
          );

          // Create student account entry for registration
          try {
            await StudentAccountRepository.createStudentAccountEntry(
              studentId: localRow['student_id'] as String,
              studentRemoteId: docRef.id,
              teacherUid: userId,
            );
            _studentAccountExistsCache.remove(localRow['student_id'] as String);
            print(
              '[SyncService] student_accounts created for studentId=${localRow['student_id']} (new remoteId=${docRef.id})',
            );
          } catch (e) {
            print(
              '[SyncService] Warning: Failed to create student account entry: $e',
            );
          }

          result.uploaded++;
          print('[SyncService] Created remote student for local id=$localId');
        }
      }
    }

    // Remaining remote records are cloud-only, pull them
    if (!_doDownload) return;
    for (final remote in remoteMap.values) {
      final data = _studentFromRemote(remote);
      data['remote_id'] = remote['doc_id'];
      data['deleted'] = 0;

      final studentId = (data['student_id'] as String?) ?? '';
      final existing = studentId.isEmpty
          ? <Map<String, dynamic>>[]
          : await db.query(
              'students',
              where: 'student_id = ?',
              whereArgs: [studentId],
              limit: 1,
            );

      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        await db.update(
          'students',
          data,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        result.downloaded++;
        print(
          '[SyncService] Updated existing local student (student_id=$studentId, id=$existingId) from remote',
        );
      } else {
        await db.insert(
          'students',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.downloaded++;
        print('[SyncService] Downloaded new student from remote');

        // Create student account entry for new downloaded student
        try {
          await StudentAccountRepository.createStudentAccountEntry(
            studentId: studentId,
            studentRemoteId: remote['doc_id'] as String,
            teacherUid: userId,
          );
        } catch (e) {
          print(
            '[SyncService] Warning: Failed to create student account entry for downloaded student: $e',
          );
        }
      }
    }
  }

  static Map<String, dynamic> _studentToMap(Map<String, dynamic> local) {
    return {
      'student_id': local['student_id'],
      'first_name': local['first_name'],
      'last_name': local['last_name'],
      'middle_name': local['middle_name'] ?? '',
      'email': local['email'] ?? '',
      'phone': local['phone'] ?? '',
      'gender': local['gender'] ?? '',
      'birth_date': local['birth_date'] ?? '',
      'address': local['address'] ?? '',
      'photo_path': local['photo_path'] ?? '',
      'updated_at': Timestamp.fromDate(
        DateTime.parse(local['updated_at'] as String),
      ),
      'created_at': Timestamp.fromDate(
        DateTime.parse(local['created_at'] as String),
      ),
    };
  }

  static String _timestampToIsoStringSafe(
    dynamic value, {
    required String field,
    required String entity,
    required String remoteId,
  }) {
    try {
      if (value is Timestamp) {
        return value.toDate().toIso8601String();
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toIso8601String();
      }
      if (value == null) {
        print(
          '[SyncService] Warning: $entity remoteId=$remoteId has null $field; using now()',
        );
      } else {
        print(
          '[SyncService] Warning: $entity remoteId=$remoteId has invalid $field type=${value.runtimeType}; using now()',
        );
      }
    } catch (e) {
      print(
        '[SyncService] Warning: $entity remoteId=$remoteId failed parsing $field=$value: $e; using now()',
      );
    }
    return DateTime.now().toIso8601String();
  }

  static Map<String, dynamic> _studentFromRemote(Map<String, dynamic> remote) {
    return {
      'student_id': remote['student_id'],
      'first_name': remote['first_name'],
      'last_name': remote['last_name'],
      'middle_name': remote['middle_name'] ?? '',
      'email': remote['email'] ?? '',
      'phone': remote['phone'] ?? '',
      'gender': remote['gender'] ?? '',
      'birth_date': remote['birth_date'] ?? '',
      'address': remote['address'] ?? '',
      'photo_path': remote['photo_path'] ?? '',
      'updated_at': _timestampToIsoStringSafe(
        remote['updated_at'],
        field: 'updated_at',
        entity: 'student',
        remoteId: (remote['doc_id'] as String?) ?? '',
      ),
      'created_at': _timestampToIsoStringSafe(
        remote['created_at'],
        field: 'created_at',
        entity: 'student',
        remoteId: (remote['doc_id'] as String?) ?? '',
      ),
    };
  }

  // ────────────────────────────────────────────────────────────
  // SUBJECTS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncSubjects(String userId, SyncResult result) async {
    print('[SyncService] Syncing subjects...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/subjects');

    final localRows = await db.query('subjects', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'subject',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          if (_doUpload) {
            await collection.doc(remoteId).update({
              'code': localRow['code'],
              'name': localRow['name'],
              'description': localRow['description'] ?? '',
              'units': localRow['units'] ?? 3,
              'is_archived': localRow['is_archived'] ?? 0,
              'updated_at': Timestamp.fromDate(localUpdated),
            });
            result.uploaded++;
          }
        } else if (remoteUpdated.isAfter(localUpdated)) {
          if (_doDownload) {
            await db.update(
              'subjects',
              {
                'code': remote['code'],
                'name': remote['name'],
                'description': remote['description'] ?? '',
                'units': remote['units'] ?? 3,
                'is_archived': remote['is_archived'] ?? 0,
                'updated_at': remoteUpdated.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [localId],
            );
            result.downloaded++;
          }
        }
        remoteMap.remove(remoteId);
      } else {
        if (_doUpload) {
          final docRef = await collection.add({
            'code': localRow['code'],
            'name': localRow['name'],
            'description': localRow['description'] ?? '',
            'units': localRow['units'] ?? 3,
            'is_archived': localRow['is_archived'] ?? 0,
            'updated_at': Timestamp.fromDate(localUpdated),
            'created_at': Timestamp.fromDate(
              DateTime.parse(localRow['created_at'] as String),
            ),
          });
          await db.update(
            'subjects',
            {'remote_id': docRef.id},
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.uploaded++;
        }
      }
    }

    if (!_doDownload) {
      print('[SyncService] Subjects sync complete');
      return;
    }

    for (final remote in remoteMap.values) {
      final data = {
        'code': remote['code'],
        'name': remote['name'],
        'description': remote['description'] ?? '',
        'units': remote['units'] ?? 3,
        'is_archived': remote['is_archived'] ?? 0,
        'remote_id': remote['doc_id'],
        'deleted': 0,
        'created_at': _timestampToIsoStringSafe(
          remote['created_at'],
          field: 'created_at',
          entity: 'subject',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
        'updated_at': _timestampToIsoStringSafe(
          remote['updated_at'],
          field: 'updated_at',
          entity: 'subject',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
      };

      final code = (data['code'] as String?) ?? '';
      final existing = code.isEmpty
          ? <Map<String, dynamic>>[]
          : await db.query(
              'subjects',
              where: 'code = ?',
              whereArgs: [code],
              limit: 1,
            );

      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        await db.update(
          'subjects',
          data,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        result.downloaded++;
        print(
          '[SyncService] Updated existing local subject (code=$code, id=$existingId) from remote',
        );
      } else {
        await db.insert(
          'subjects',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.downloaded++;
        print('[SyncService] Downloaded new subject from remote');
      }
    }
    print('[SyncService] Subjects sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // CLASSES SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncClasses(String userId, SyncResult result) async {
    print('[SyncService] Syncing classes...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/classes');

    Future<int?> resolveLocalSubjectIdFromRemote(
      Map<String, dynamic> remote,
    ) async {
      final legacySubjectId = remote['subject_id'];
      int? legacyId;
      if (legacySubjectId is int) {
        legacyId = legacySubjectId;
      } else if (legacySubjectId is num) {
        legacyId = legacySubjectId.toInt();
      } else if (legacySubjectId is String) {
        legacyId = int.tryParse(legacySubjectId);
      }

      if (legacyId != null) {
        final byLegacyId = await db.query(
          'subjects',
          where: 'id = ?',
          whereArgs: [legacyId],
          limit: 1,
        );
        if (byLegacyId.isNotEmpty) {
          return byLegacyId.first['id'] as int;
        }
      }

      final subjectRemoteIdRaw = remote['subject_remote_id'];
      final subjectRemoteId = subjectRemoteIdRaw is String
          ? subjectRemoteIdRaw
          : subjectRemoteIdRaw?.toString();
      if (subjectRemoteId != null && subjectRemoteId.isNotEmpty) {
        final byRemoteId = await db.query(
          'subjects',
          where: 'remote_id = ?',
          whereArgs: [subjectRemoteId],
          limit: 1,
        );
        if (byRemoteId.isNotEmpty) {
          return byRemoteId.first['id'] as int;
        }
      }

      final subjectCodeRaw = remote['subject_code'];
      final subjectCode = subjectCodeRaw is String
          ? subjectCodeRaw
          : subjectCodeRaw?.toString();
      if (subjectCode != null && subjectCode.isNotEmpty) {
        final byCode = await db.query(
          'subjects',
          where: 'code = ?',
          whereArgs: [subjectCode],
          limit: 1,
        );
        if (byCode.isNotEmpty) {
          return byCode.first['id'] as int;
        }
      }

      return null;
    }

    final localRows = await db.query('classes', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    print(
      '[SyncService] Classes sync local=${localRows.length} remote=${remoteSnapshot.docs.length}',
    );
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    int skippedBySubject = 0;

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      // Fetch subject info for cross-device sync
      final subjectId = localRow['subject_id'] as int;
      final subjectRows = await db.query(
        'subjects',
        where: 'id = ?',
        whereArgs: [subjectId],
        limit: 1,
      );
      final subjectCode = subjectRows.isNotEmpty
          ? (subjectRows.first['code'] as String?)
          : null;
      final subjectRemoteId = subjectRows.isNotEmpty
          ? (subjectRows.first['remote_id'] as String?)
          : null;

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = DateTime.parse(
          _timestampToIsoStringSafe(
            remote['updated_at'],
            field: 'updated_at',
            entity: 'class',
            remoteId: remoteId,
          ),
        );

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            // Use stable subject reference for cross-device sync
            'subject_code': subjectCode ?? '',
            'subject_remote_id': subjectRemoteId ?? '',
            'section': localRow['section'],
            'school_year': localRow['school_year'],
            'semester': localRow['semester'] ?? '',
            'schedule': localRow['schedule'] ?? '',
            'room': localRow['room'] ?? '',
            'is_archived': localRow['is_archived'] ?? 0,
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final resolvedSubjectId = await resolveLocalSubjectIdFromRemote(
            remote,
          );
          if (resolvedSubjectId == null) {
            print(
              '[SyncService] Skipping class download/update: unable to resolve subject (remote classId=$remoteId subject_code=${remote['subject_code']} subject_remote_id=${remote['subject_remote_id']})',
            );
            skippedBySubject++;
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'classes',
            {
              'subject_id': resolvedSubjectId,
              'section': remote['section'],
              'school_year': remote['school_year'],
              'semester': remote['semester'] ?? '',
              'schedule': remote['schedule'] ?? '',
              'room': remote['room'] ?? '',
              'is_archived': remote['is_archived'] ?? 0,
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          // Use stable subject reference for cross-device sync
          'subject_code': subjectCode ?? '',
          'subject_remote_id': subjectRemoteId ?? '',
          'section': localRow['section'],
          'school_year': localRow['school_year'],
          'semester': localRow['semester'] ?? '',
          'schedule': localRow['schedule'] ?? '',
          'room': localRow['room'] ?? '',
          'is_archived': localRow['is_archived'] ?? 0,
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'classes',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final resolvedSubjectId = await resolveLocalSubjectIdFromRemote(remote);
      if (resolvedSubjectId == null) {
        print(
          '[SyncService] Skipping class insert: unable to resolve subject (remote doc_id=${remote['doc_id']} subject_code=${remote['subject_code']} subject_remote_id=${remote['subject_remote_id']})',
        );
        skippedBySubject++;
        continue;
      }
      await db.insert('classes', {
        'subject_id': resolvedSubjectId,
        'section': remote['section'],
        'school_year': remote['school_year'],
        'semester': remote['semester'] ?? '',
        'schedule': remote['schedule'] ?? '',
        'room': remote['room'] ?? '',
        'is_archived': remote['is_archived'] ?? 0,
        'remote_id': remote['doc_id'],
        'created_at': _timestampToIsoStringSafe(
          remote['created_at'],
          field: 'created_at',
          entity: 'class',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
        'updated_at': _timestampToIsoStringSafe(
          remote['updated_at'],
          field: 'updated_at',
          entity: 'class',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
      });
      result.downloaded++;
    }
    print('[SyncService] Classes sync skipped_by_subject=$skippedBySubject');
    print('[SyncService] Classes sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // GRADING PERIODS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncGradingPeriods(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing grading periods...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/grading_periods');

    final localRows = await db.query('grading_periods', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localClassId = localRow['class_id'] as int?;
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'class_id': localRow['class_id'],
            'class_remote_id': classRemoteId ?? '',
            'name': localRow['name'],
            'order_num': localRow['order_num'],
            'is_active': localRow['is_active'] ?? 0,
            'is_locked': localRow['is_locked'] ?? 0,
            'start_date': localRow['start_date'] ?? '',
            'end_date': localRow['end_date'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          if (remoteClassRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping grading_periods download/update (legacy-only row): missing class_remote_id',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedClassId = await _getLocalIdForRemoteId(
            db,
            'classes',
            remoteClassRemoteId,
          );
          if (resolvedClassId == null) {
            print(
              '[SyncService] Skipping grading_periods download/update: class_remote_id not found locally remote_id=$remoteClassRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'grading_periods',
            {
              'class_id': resolvedClassId,
              'name': remote['name'],
              'order_num': remote['order_num'],
              'is_active': remote['is_active'] ?? 0,
              'is_locked': remote['is_locked'] ?? 0,
              'start_date': remote['start_date'] ?? '',
              'end_date': remote['end_date'] ?? '',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'class_id': localRow['class_id'],
          'class_remote_id': classRemoteId ?? '',
          'name': localRow['name'],
          'order_num': localRow['order_num'],
          'is_active': localRow['is_active'] ?? 0,
          'is_locked': localRow['is_locked'] ?? 0,
          'start_date': localRow['start_date'] ?? '',
          'end_date': localRow['end_date'] ?? '',
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_periods',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      int? resolvedClassId;
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping grading_periods insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      } else {
        print(
          '[SyncService] Skipping grading_periods insert (legacy-only row): missing class_remote_id',
        );
        continue;
      }
      await db.insert('grading_periods', {
        'class_id': resolvedClassId,
        'name': remote['name'],
        'order_num': remote['order_num'],
        'is_active': remote['is_active'] ?? 0,
        'is_locked': remote['is_locked'] ?? 0,
        'start_date': remote['start_date'] ?? '',
        'end_date': remote['end_date'] ?? '',
        'remote_id': remote['doc_id'],
        'created_at': _timestampToIsoStringSafe(
          remote['created_at'],
          field: 'created_at',
          entity: 'grading_period',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
        'updated_at': _timestampToIsoStringSafe(
          remote['updated_at'],
          field: 'updated_at',
          entity: 'grading_period',
          remoteId: (remote['doc_id'] as String?) ?? '',
        ),
      });
      result.downloaded++;
    }
    print('[SyncService] Grading periods sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // GRADING CATEGORIES SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncGradingCategories(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing grading categories...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_categories',
    );

    final localRows = await db.query(
      'grading_categories',
      where: 'deleted = 0',
    );
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localPeriodId = localRow['grading_period_id'] as int?;
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'grading_period_id': localRow['grading_period_id'],
            'grading_period_remote_id': periodRemoteId ?? '',
            'name': localRow['name'],
            'weight': localRow['weight'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remotePeriodRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping grading_categories download/update (legacy-only row): missing grading_period_remote_id',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedPeriodId = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            remotePeriodRemoteId,
          );
          if (resolvedPeriodId == null) {
            print(
              '[SyncService] Skipping grading_categories download/update: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'grading_categories',
            {
              'grading_period_id': resolvedPeriodId,
              'name': remote['name'],
              'weight': remote['weight'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'grading_period_id': localRow['grading_period_id'],
          'grading_period_remote_id': periodRemoteId ?? '',
          'name': localRow['name'],
          'weight': localRow['weight'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_categories',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      int? resolvedPeriodId;
      if (remotePeriodRemoteId.isNotEmpty) {
        resolvedPeriodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          remotePeriodRemoteId,
        );
        if (resolvedPeriodId == null) {
          print(
            '[SyncService] Skipping grading_categories insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
          );
          continue;
        }
      }
      await db.insert('grading_categories', {
        'grading_period_id': resolvedPeriodId ?? remote['grading_period_id'],
        'name': remote['name'],
        'weight': remote['weight'],
        'remote_id': remote['doc_id'],
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Grading categories sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // GRADING CONFIGURATIONS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncGradingConfigurations(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing grading configurations...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_configurations',
    );

    final localRows = await db.query(
      'grading_configurations',
      where: 'deleted = 0',
    );
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localPeriodId = localRow['grading_period_id'] as int?;
      final localCategoryId = localRow['category_id'] as int?;
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);
      final categoryRemoteId = localCategoryId == null
          ? null
          : await _getRemoteIdForLocalId(
              db,
              'grading_categories',
              localCategoryId,
            );

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'grading_period_id': localRow['grading_period_id'],
            'category_id': localRow['category_id'],
            'grading_period_remote_id': periodRemoteId ?? '',
            'category_remote_id': categoryRemoteId ?? '',
            'max_score': localRow['max_score'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          final remoteCategoryRemoteId =
              remote['category_remote_id']?.toString() ?? '';
          if (remotePeriodRemoteId.isEmpty || remoteCategoryRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping grading_configurations download/update (legacy-only row): missing FK remote_ids',
            );
            remoteMap.remove(remoteId);
            continue;
          }
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
          if (resolvedPeriodId == null || resolvedCategoryId == null) {
            print(
              '[SyncService] Skipping grading_configurations download/update: FK remote_id not found locally period=$remotePeriodRemoteId category=$remoteCategoryRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'grading_configurations',
            {
              'grading_period_id': resolvedPeriodId,
              'category_id': resolvedCategoryId,
              'max_score': remote['max_score'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'grading_period_id': localRow['grading_period_id'],
          'category_id': localRow['category_id'],
          'grading_period_remote_id': periodRemoteId ?? '',
          'category_remote_id': categoryRemoteId ?? '',
          'max_score': localRow['max_score'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'created_at': Timestamp.fromDate(
            DateTime.parse(localRow['created_at'] as String),
          ),
        });
        await db.update(
          'grading_configurations',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      final remoteCategoryRemoteId =
          remote['category_remote_id']?.toString() ?? '';
      int? resolvedPeriodId;
      int? resolvedCategoryId;
      if (remotePeriodRemoteId.isNotEmpty) {
        resolvedPeriodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          remotePeriodRemoteId,
        );
        if (resolvedPeriodId == null) {
          print(
            '[SyncService] Skipping grading_configurations insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
          );
          continue;
        }
      }
      if (remoteCategoryRemoteId.isNotEmpty) {
        resolvedCategoryId = await _getLocalIdForRemoteId(
          db,
          'grading_categories',
          remoteCategoryRemoteId,
        );
        if (resolvedCategoryId == null) {
          print(
            '[SyncService] Skipping grading_configurations insert: category_remote_id not found locally remote_id=$remoteCategoryRemoteId',
          );
          continue;
        }
      }
      await db.insert('grading_configurations', {
        'grading_period_id': resolvedPeriodId ?? remote['grading_period_id'],
        'category_id': resolvedCategoryId ?? remote['category_id'],
        'max_score': remote['max_score'],
        'remote_id': remote['doc_id'],
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Grading configurations sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // GRADES SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncGrades(String userId, SyncResult result) async {
    print('[SyncService] Syncing grades...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/grades');

    final localRows = await db.query('grades', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final localCategoryId = localRow['category_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);
      final categoryRemoteId = localCategoryId == null
          ? null
          : await _getRemoteIdForLocalId(
              db,
              'grading_categories',
              localCategoryId,
            );

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'category_id': localRow['category_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'category_remote_id': categoryRemoteId ?? '',
            'score': localRow['score'],
            'max_score': localRow['max_score'],
            'remarks': localRow['remarks'] ?? '',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          final remoteCategoryRemoteId =
              remote['category_remote_id']?.toString() ?? '';
          if (remoteStudentRemoteId.isEmpty ||
              remoteClassRemoteId.isEmpty ||
              remotePeriodRemoteId.isEmpty ||
              remoteCategoryRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping grades download/update (legacy-only row): missing FK remote_ids',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedStudentId = await _getLocalIdForRemoteId(
            db,
            'students',
            remoteStudentRemoteId,
          );
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
          if (resolvedStudentId == null ||
              resolvedClassId == null ||
              resolvedPeriodId == null ||
              resolvedCategoryId == null) {
            print(
              '[SyncService] Skipping grades download/update: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId category=$remoteCategoryRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'grades',
            {
              'student_id': resolvedStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'category_id': resolvedCategoryId,
              'score': remote['score'],
              'max_score': remote['max_score'],
              'remarks': remote['remarks'] ?? '',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'category_id': localRow['category_id'],
          'student_remote_id': studentRemoteId ?? '',
          'class_remote_id': classRemoteId ?? '',
          'grading_period_remote_id': periodRemoteId ?? '',
          'category_remote_id': categoryRemoteId ?? '',
          'score': localRow['score'],
          'max_score': localRow['max_score'],
          'remarks': localRow['remarks'] ?? '',
          'updated_at': Timestamp.fromDate(localUpdated),
          'recorded_at': Timestamp.fromDate(
            DateTime.parse(localRow['recorded_at'] as String),
          ),
        });
        await db.update(
          'grades',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      final remoteCategoryRemoteId =
          remote['category_remote_id']?.toString() ?? '';
      int? resolvedStudentId;
      int? resolvedClassId;
      int? resolvedPeriodId;
      int? resolvedCategoryId;
      if (remoteStudentRemoteId.isNotEmpty) {
        resolvedStudentId = await _getLocalIdForRemoteId(
          db,
          'students',
          remoteStudentRemoteId,
        );
        if (resolvedStudentId == null) {
          print(
            '[SyncService] Skipping grades insert: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
          );
          continue;
        }
      }
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping grades insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      }
      if (remotePeriodRemoteId.isNotEmpty) {
        resolvedPeriodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          remotePeriodRemoteId,
        );
        if (resolvedPeriodId == null) {
          print(
            '[SyncService] Skipping grades insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
          );
          continue;
        }
      }
      if (remoteCategoryRemoteId.isNotEmpty) {
        resolvedCategoryId = await _getLocalIdForRemoteId(
          db,
          'grading_categories',
          remoteCategoryRemoteId,
        );
        if (resolvedCategoryId == null) {
          print(
            '[SyncService] Skipping grades insert: category_remote_id not found locally remote_id=$remoteCategoryRemoteId',
          );
          continue;
        }
      }
      await db.insert('grades', {
        'student_id': resolvedStudentId ?? remote['student_id'],
        'class_id': resolvedClassId ?? remote['class_id'],
        'grading_period_id': resolvedPeriodId ?? remote['grading_period_id'],
        'category_id': resolvedCategoryId ?? remote['category_id'],
        'score': remote['score'],
        'max_score': remote['max_score'],
        'remarks': remote['remarks'] ?? '',
        'remote_id': remote['doc_id'],
        'recorded_at': (remote['recorded_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Grades sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // ATTENDANCE SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncAttendance(String userId, SyncResult result) async {
    print('[SyncService] Syncing attendance...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/attendance');

    final localRows = await db.query('attendance', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localCreated = DateTime.parse(localRow['created_at'] as String);

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteCreated = (remote['created_at'] as Timestamp).toDate();

        if (localCreated.isAfter(remoteCreated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'date': localRow['date'],
            'status': localRow['status'],
            'remarks': localRow['remarks'] ?? '',
            'created_at': Timestamp.fromDate(localCreated),
          });
          result.uploaded++;
        } else if (remoteCreated.isAfter(localCreated)) {
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remoteStudentRemoteId.isEmpty ||
              remoteClassRemoteId.isEmpty ||
              remotePeriodRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping attendance download/update (legacy-only row): missing FK remote_ids',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedStudentId = await _getLocalIdForRemoteId(
            db,
            'students',
            remoteStudentRemoteId,
          );
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
          if (resolvedStudentId == null ||
              resolvedClassId == null ||
              resolvedPeriodId == null) {
            print(
              '[SyncService] Skipping attendance download/update: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'attendance',
            {
              'student_id': resolvedStudentId,
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
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'student_remote_id': studentRemoteId ?? '',
          'class_remote_id': classRemoteId ?? '',
          'grading_period_remote_id': periodRemoteId ?? '',
          'date': localRow['date'],
          'status': localRow['status'],
          'remarks': localRow['remarks'] ?? '',
          'created_at': Timestamp.fromDate(localCreated),
        });
        await db.update(
          'attendance',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      int? resolvedStudentId;
      int? resolvedClassId;
      int? resolvedPeriodId;
      if (remoteStudentRemoteId.isNotEmpty) {
        resolvedStudentId = await _getLocalIdForRemoteId(
          db,
          'students',
          remoteStudentRemoteId,
        );
        if (resolvedStudentId == null) {
          print(
            '[SyncService] Skipping attendance insert: student_remote_id not found locally remote_id=$remoteStudentRemoteId',
          );
          continue;
        }
      }
      if (remoteClassRemoteId.isNotEmpty) {
        resolvedClassId = await _getLocalIdForRemoteId(
          db,
          'classes',
          remoteClassRemoteId,
        );
        if (resolvedClassId == null) {
          print(
            '[SyncService] Skipping attendance insert: class_remote_id not found locally remote_id=$remoteClassRemoteId',
          );
          continue;
        }
      }
      if (remotePeriodRemoteId.isNotEmpty) {
        resolvedPeriodId = await _getLocalIdForRemoteId(
          db,
          'grading_periods',
          remotePeriodRemoteId,
        );
        if (resolvedPeriodId == null) {
          print(
            '[SyncService] Skipping attendance insert: grading_period_remote_id not found locally remote_id=$remotePeriodRemoteId',
          );
          continue;
        }
      }
      await db.insert('attendance', {
        'student_id': resolvedStudentId ?? remote['student_id'],
        'class_id': resolvedClassId ?? remote['class_id'],
        'grading_period_id': resolvedPeriodId ?? remote['grading_period_id'],
        'date': remote['date'],
        'status': remote['status'],
        'remarks': remote['remarks'] ?? '',
        'remote_id': remote['doc_id'],
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Attendance sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // INTERVENTIONS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncInterventions(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing interventions...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/interventions');

    final localRows = await db.query('interventions', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'title': localRow['title'],
            'description': localRow['description'],
            'intervention_date': localRow['intervention_date'],
            'follow_up_date': localRow['follow_up_date'] ?? '',
            'status': localRow['status'] ?? 'open',
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remoteStudentRemoteId.isEmpty ||
              remoteClassRemoteId.isEmpty ||
              remotePeriodRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping interventions download/update (legacy-only row): missing FK remote_ids',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedStudentId = await _getLocalIdForRemoteId(
            db,
            'students',
            remoteStudentRemoteId,
          );
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
          if (resolvedStudentId == null ||
              resolvedClassId == null ||
              resolvedPeriodId == null) {
            print(
              '[SyncService] Skipping interventions download/update: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'interventions',
            {
              'student_id': resolvedStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'title': remote['title'],
              'description': remote['description'],
              'intervention_date': remote['intervention_date'],
              'follow_up_date': remote['follow_up_date'] ?? '',
              'status': remote['status'] ?? 'open',
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'student_remote_id': studentRemoteId ?? '',
          'class_remote_id': classRemoteId ?? '',
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
        });
        await db.update(
          'interventions',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      if (remoteStudentRemoteId.isEmpty ||
          remoteClassRemoteId.isEmpty ||
          remotePeriodRemoteId.isEmpty) {
        print(
          '[SyncService] Skipping interventions insert (legacy-only row): missing FK remote_ids',
        );
        continue;
      }
      final resolvedStudentId = await _getLocalIdForRemoteId(
        db,
        'students',
        remoteStudentRemoteId,
      );
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
      if (resolvedStudentId == null ||
          resolvedClassId == null ||
          resolvedPeriodId == null) {
        print(
          '[SyncService] Skipping interventions insert: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId',
        );
        continue;
      }
      await db.insert('interventions', {
        'student_id': resolvedStudentId,
        'class_id': resolvedClassId,
        'grading_period_id': resolvedPeriodId,
        'title': remote['title'],
        'description': remote['description'],
        'intervention_date': remote['intervention_date'],
        'follow_up_date': remote['follow_up_date'] ?? '',
        'status': remote['status'] ?? 'open',
        'remote_id': remote['doc_id'],
        'created_at': (remote['created_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Interventions sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // RISK FLAGS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncRiskFlags(String userId, SyncResult result) async {
    print('[SyncService] Syncing risk flags...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/risk_flags');

    final localRows = await db.query('risk_flags', where: 'deleted = 0');
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated = DateTime.parse(localRow['updated_at'] as String);

      final localStudentId = localRow['student_id'] as int?;
      final localClassId = localRow['class_id'] as int?;
      final localPeriodId = localRow['grading_period_id'] as int?;
      final studentRemoteId = localStudentId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'students', localStudentId);
      final classRemoteId = localClassId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'classes', localClassId);
      final periodRemoteId = localPeriodId == null
          ? null
          : await _getRemoteIdForLocalId(db, 'grading_periods', localPeriodId);

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

        if (localUpdated.isAfter(remoteUpdated)) {
          await collection.doc(remoteId).update({
            'student_id': localRow['student_id'],
            'class_id': localRow['class_id'],
            'grading_period_id': localRow['grading_period_id'],
            'student_remote_id': studentRemoteId ?? '',
            'class_remote_id': classRemoteId ?? '',
            'grading_period_remote_id': periodRemoteId ?? '',
            'risk_level': localRow['risk_level'],
            'grade_score': localRow['grade_score'],
            'attendance_percentage': localRow['attendance_percentage'],
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          result.uploaded++;
        } else if (remoteUpdated.isAfter(localUpdated)) {
          final remoteStudentRemoteId =
              remote['student_remote_id']?.toString() ?? '';
          final remoteClassRemoteId =
              remote['class_remote_id']?.toString() ?? '';
          final remotePeriodRemoteId =
              remote['grading_period_remote_id']?.toString() ?? '';
          if (remoteStudentRemoteId.isEmpty ||
              remoteClassRemoteId.isEmpty ||
              remotePeriodRemoteId.isEmpty) {
            print(
              '[SyncService] Skipping risk_flags download/update (legacy-only row): missing FK remote_ids',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          final resolvedStudentId = await _getLocalIdForRemoteId(
            db,
            'students',
            remoteStudentRemoteId,
          );
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
          if (resolvedStudentId == null ||
              resolvedClassId == null ||
              resolvedPeriodId == null) {
            print(
              '[SyncService] Skipping risk_flags download/update: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId',
            );
            remoteMap.remove(remoteId);
            continue;
          }
          await db.update(
            'risk_flags',
            {
              'student_id': resolvedStudentId,
              'class_id': resolvedClassId,
              'grading_period_id': resolvedPeriodId,
              'risk_level': remote['risk_level'],
              'grade_score': remote['grade_score'],
              'attendance_percentage': remote['attendance_percentage'],
              'updated_at': remoteUpdated.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.downloaded++;
        }
        remoteMap.remove(remoteId);
      } else {
        final docRef = await collection.add({
          'student_id': localRow['student_id'],
          'class_id': localRow['class_id'],
          'grading_period_id': localRow['grading_period_id'],
          'student_remote_id': studentRemoteId ?? '',
          'class_remote_id': classRemoteId ?? '',
          'grading_period_remote_id': periodRemoteId ?? '',
          'risk_level': localRow['risk_level'],
          'grade_score': localRow['grade_score'],
          'attendance_percentage': localRow['attendance_percentage'],
          'updated_at': Timestamp.fromDate(localUpdated),
          'flagged_at': Timestamp.fromDate(
            DateTime.parse(localRow['flagged_at'] as String),
          ),
        });
        await db.update(
          'risk_flags',
          {'remote_id': docRef.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.uploaded++;
      }
    }

    for (final remote in remoteMap.values) {
      final remoteStudentRemoteId =
          remote['student_remote_id']?.toString() ?? '';
      final remoteClassRemoteId = remote['class_remote_id']?.toString() ?? '';
      final remotePeriodRemoteId =
          remote['grading_period_remote_id']?.toString() ?? '';
      if (remoteStudentRemoteId.isEmpty ||
          remoteClassRemoteId.isEmpty ||
          remotePeriodRemoteId.isEmpty) {
        print(
          '[SyncService] Skipping risk_flags insert (legacy-only row): missing FK remote_ids',
        );
        continue;
      }
      final resolvedStudentId = await _getLocalIdForRemoteId(
        db,
        'students',
        remoteStudentRemoteId,
      );
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
      if (resolvedStudentId == null ||
          resolvedClassId == null ||
          resolvedPeriodId == null) {
        print(
          '[SyncService] Skipping risk_flags insert: FK remote_id not found locally student=$remoteStudentRemoteId class=$remoteClassRemoteId period=$remotePeriodRemoteId',
        );
        continue;
      }
      await db.insert('risk_flags', {
        'student_id': resolvedStudentId,
        'class_id': resolvedClassId,
        'grading_period_id': resolvedPeriodId,
        'risk_level': remote['risk_level'],
        'grade_score': remote['grade_score'],
        'attendance_percentage': remote['attendance_percentage'],
        'remote_id': remote['doc_id'],
        'flagged_at': (remote['flagged_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'updated_at': (remote['updated_at'] as Timestamp)
            .toDate()
            .toIso8601String(),
      });
      result.downloaded++;
    }
    print('[SyncService] Risk flags sync complete');
  }

  // ────────────────────────────────────────────────────────────
  // SETTINGS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncSettings(String userId, SyncResult result) async {
    print('[SyncService] Syncing settings...');
    final db = await DatabaseHelper.instance.database;
    final docRef = _firestore.collection('users').doc(userId);

    // Get local settings
    final localRows = await db.query('settings');
    final localMap = <String, String>{};
    for (final row in localRows) {
      localMap[row['key'] as String] = row['value'] as String;
    }

    // Get remote settings
    print('[SyncService] Settings: fetching remote doc users/$userId ...');
    DocumentSnapshot<Map<String, dynamic>> remoteDoc;
    try {
      remoteDoc = await docRef.get().timeout(const Duration(seconds: 20));
      print(
        '[SyncService] Settings: remote doc fetched (exists=${remoteDoc.exists})',
      );
    } catch (e) {
      print(
        '[SyncService] Settings: remote doc fetch error/timeout: $e. Trying cache...',
      );
      try {
        remoteDoc = await docRef
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        print(
          '[SyncService] Settings: remote doc fetched from cache (exists=${remoteDoc.exists})',
        );
      } catch (e2) {
        print('[SyncService] Settings: cache fetch failed: $e2');
        rethrow;
      }
    }

    final remoteSettings =
        remoteDoc.data()?['settings'] as Map<String, dynamic>? ?? {};

    // Sync all settings keys
    final keysToSync = [
      'teacher_name',
      'school_name',
      'grade_threshold',
      'attendance_threshold',
      'grading_system',
      'grade_equivalency_table',
    ];

    int uploaded = 0;
    int downloaded = 0;

    // Upload: Push local settings to cloud
    if (_doUpload) {
      print('[SyncService] Settings: uploading ${keysToSync.length} key(s)...');
      for (final key in keysToSync) {
        if (localMap.containsKey(key)) {
          remoteSettings[key] = localMap[key];
          uploaded++;
        }
      }

      try {
        await docRef
            .set({'settings': remoteSettings}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 20));
        print('[SyncService] Settings: upload complete uploaded=$uploaded');
      } catch (e) {
        print('[SyncService] Settings: upload error/timeout: $e');
        rethrow;
      }
    }

    // Download: Pull remote settings to local DB
    if (_doDownload) {
      print(
        '[SyncService] Settings: downloading ${keysToSync.length} key(s)...',
      );
      for (final key in keysToSync) {
        if (remoteSettings.containsKey(key)) {
          final remoteValue = remoteSettings[key]?.toString() ?? '';
          if (remoteValue.isNotEmpty && remoteValue != localMap[key]) {
            print(
              '[SyncService] Updating local setting $key from remote (was: ${localMap[key]}, now: $remoteValue)',
            );
            await db.rawUpdate(
              'UPDATE settings SET value = ?, updated_at = ? WHERE key = ?',
              [remoteValue, DateTime.now().toIso8601String(), key],
            );
            downloaded++;
          }
        }
      }
      print(
        '[SyncService] Settings: download loop complete downloaded=$downloaded',
      );
    }

    result.uploaded += uploaded;
    result.downloaded += downloaded;
    print(
      '[SyncService] Settings sync complete uploaded=$uploaded downloaded=$downloaded',
    );
  }

  static const Set<String> _dynamicSyncExcludedTables = {
    // system / internal
    'android_metadata',
    'sqlite_sequence',
    // app tables that are not entity-synced as a collection
    'users',
    'settings',
    // explicitly-synced entity tables (avoid double-sync)
    'students',
    'subjects',
    'classes',
    'class_students',
    'grading_periods',
    'grading_categories',
    'grading_configurations',
    'grading_assessments',
    'assessment_scores',
    'lessons',
    'grades',
    'attendance',
    'interventions',
    'risk_flags',
    'counseling_reasons',
  };

  // ────────────────────────────────────────────────────────────
  // COUNSELING REASONS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncCounselingReasons(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing counseling reasons...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/counseling_reasons',
    );

    final localRows = await db.query(
      'counseling_reasons',
      where: 'teacher_uid = ? AND deleted = 0',
      whereArgs: [userId],
    );
    final remoteSnapshot = await collection.get();
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnapshot.docs) {
      remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
    }

    for (final localRow in localRows) {
      final localId = localRow['id'] as int;
      final remoteId = localRow['remote_id'] as String?;
      final localUpdated =
          DateTime.tryParse(localRow['updated_at'] as String) ?? DateTime.now();

      if (remoteId != null && remoteMap.containsKey(remoteId)) {
        final remote = remoteMap[remoteId]!;
        final remoteUpdated = (remote['updated_at'] is Timestamp)
            ? (remote['updated_at'] as Timestamp).toDate()
            : DateTime.tryParse(remote['updated_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);

        if (localUpdated.isAfter(remoteUpdated)) {
          if (_doUpload) {
            await collection.doc(remoteId).set({
              'teacher_uid': userId,
              'student_id': localRow['student_id'],
              'student_remote_id': localRow['student_remote_id'] ?? '',
              'class_remote_id': localRow['class_remote_id'],
              'subject_code': localRow['subject_code'] ?? '',
              'reason': localRow['reason'],
              'updated_at': Timestamp.fromDate(localUpdated),
            }, SetOptions(merge: true));
            result.uploaded++;
          }
        }
        remoteMap.remove(remoteId);
      } else {
        if (_doUpload) {
          final createdAt =
              DateTime.tryParse(localRow['created_at'] as String) ??
              DateTime.now();
          final docRef = await collection.add({
            'teacher_uid': userId,
            'student_id': localRow['student_id'],
            'student_remote_id': localRow['student_remote_id'] ?? '',
            'class_remote_id': localRow['class_remote_id'],
            'subject_code': localRow['subject_code'] ?? '',
            'reason': localRow['reason'],
            'created_at': Timestamp.fromDate(createdAt),
            'updated_at': Timestamp.fromDate(localUpdated),
          });
          await db.update(
            'counseling_reasons',
            {'remote_id': docRef.id},
            where: 'id = ?',
            whereArgs: [localId],
          );
          result.uploaded++;
        }
      }
    }

    if (!_doDownload) {
      print('[SyncService] Counseling reasons sync complete');
      return;
    }

    for (final remote in remoteMap.values) {
      final remoteId = (remote['doc_id'] as String?) ?? '';
      final data = {
        'teacher_uid': userId,
        'student_id': remote['student_id']?.toString() ?? '',
        'student_remote_id': remote['student_remote_id']?.toString() ?? '',
        'class_remote_id': remote['class_remote_id']?.toString() ?? '',
        'subject_code': remote['subject_code']?.toString() ?? '',
        'reason': remote['reason']?.toString() ?? '',
        'remote_id': remoteId,
        'deleted': 0,
        'created_at': (remote['created_at'] is Timestamp)
            ? (remote['created_at'] as Timestamp).toDate().toIso8601String()
            : DateTime.now().toIso8601String(),
        'updated_at': (remote['updated_at'] is Timestamp)
            ? (remote['updated_at'] as Timestamp).toDate().toIso8601String()
            : DateTime.now().toIso8601String(),
      };

      final existing = await db.query(
        'counseling_reasons',
        where: 'remote_id = ?',
        whereArgs: [remoteId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        await db.update(
          'counseling_reasons',
          data,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert(
          'counseling_reasons',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      result.downloaded++;
    }
    print('[SyncService] Counseling reasons sync complete');
  }

  static Future<void> _syncDynamicTables(
    String userId,
    SyncResult result, {
    int? classId,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Discover tables dynamically.
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final tables = rows
        .map((r) => (r['name'] as String?) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();

    print(
      '[SyncService] Dynamic sync tables discovered=${tables.length} classId=$classId',
    );

    for (final table in tables) {
      if (_dynamicSyncExcludedTables.contains(table)) continue;

      try {
        final columnsInfo = await db.rawQuery('PRAGMA table_info($table)');
        final colNames = columnsInfo
            .map((c) => (c['name'] as String?) ?? '')
            .where((c) => c.isNotEmpty)
            .toSet();

        // Convention requirements for generic last-write-wins sync.
        final hasRemoteId = colNames.contains('remote_id');
        final hasUpdatedAt = colNames.contains('updated_at');
        final hasCreatedAt = colNames.contains('created_at');
        if (!hasRemoteId || !hasUpdatedAt || !hasCreatedAt) {
          print(
            '[SyncService] Dynamic sync skipped table=$table (missing remote_id/created_at/updated_at)',
          );
          continue;
        }

        final hasDeleted = colNames.contains('deleted');
        final hasClassId = colNames.contains('class_id');

        if (classId != null && !hasClassId) {
          print(
            '[SyncService] Dynamic sync skipped table=$table for classId=$classId (no class_id column)',
          );
          continue;
        }

        final whereParts = <String>[];
        final whereArgs = <Object?>[];
        if (hasDeleted) {
          whereParts.add('deleted = 0');
        }
        if (classId != null) {
          whereParts.add('class_id = ?');
          whereArgs.add(classId);
        }
        final where = whereParts.isEmpty ? null : whereParts.join(' AND ');

        final localRows = await db.query(
          table,
          where: where,
          whereArgs: whereArgs.isEmpty ? null : whereArgs,
        );

        final collection = _firestore.collection('users/$userId/$table');
        QuerySnapshot<Map<String, dynamic>> remoteSnapshot;
        if (classId != null) {
          remoteSnapshot = await collection
              .where('class_id', isEqualTo: classId)
              .get();
        } else {
          remoteSnapshot = await collection.get();
        }

        final remoteMap = <String, Map<String, dynamic>>{};
        for (final doc in remoteSnapshot.docs) {
          remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
        }

        int uploaded = 0;
        int downloaded = 0;

        for (final local in localRows) {
          final localId = local['id'];
          final remoteId = local['remote_id'] as String?;

          final localUpdatedRaw = local['updated_at'] as String?;
          if (localUpdatedRaw == null || localUpdatedRaw.isEmpty) continue;
          final localUpdated = DateTime.parse(localUpdatedRaw);

          if (remoteId != null &&
              remoteId.isNotEmpty &&
              remoteMap.containsKey(remoteId)) {
            final remote = remoteMap[remoteId]!;
            final remoteUpdatedTs = remote['updated_at'];
            final remoteUpdated = remoteUpdatedTs is Timestamp
                ? remoteUpdatedTs.toDate()
                : DateTime.tryParse(remoteUpdatedTs?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0);

            if (localUpdated.isAfter(remoteUpdated)) {
              await collection
                  .doc(remoteId)
                  .update(
                    _encodeRowForFirestore(local, includeCreatedAt: false),
                  );
              uploaded++;
            } else if (remoteUpdated.isAfter(localUpdated)) {
              await db.update(
                table,
                _decodeRowFromFirestore(remote, colNames),
                where: 'id = ?',
                whereArgs: [localId],
              );
              downloaded++;
            }
            remoteMap.remove(remoteId);
          } else {
            final docRef = await collection.add(
              _encodeRowForFirestore(local, includeCreatedAt: true),
            );
            await db.update(
              table,
              {'remote_id': docRef.id},
              where: 'id = ?',
              whereArgs: [localId],
            );
            uploaded++;
          }
        }

        for (final remote in remoteMap.values) {
          final decoded = _decodeRowFromFirestore(remote, colNames)
            ..['remote_id'] = remote['doc_id']
            ..putIfAbsent('deleted', () => 0);

          await db.insert(
            table,
            decoded,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          downloaded++;
        }

        result.uploaded += uploaded;
        result.downloaded += downloaded;
        print(
          '[SyncService] Dynamic sync table=$table uploaded=$uploaded downloaded=$downloaded local=${localRows.length} remote=${remoteSnapshot.docs.length}',
        );
      } catch (e) {
        print('[SyncService] Dynamic sync error table=$table: $e');
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  // CLASS STUDENTS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncClassStudents(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing class students...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/class_students');

    try {
      final localClassStudents = await db.query('class_students');
      final remoteSnapshot = await collection.get();

      int uploaded = 0;
      int downloaded = 0;

      for (final localRecord in localClassStudents) {
        final remoteDoc = localRecord['remote_id'] != null
            ? collection.doc(localRecord['remote_id'] as String)
            : collection.doc();

        final data = _encodeRowForFirestore(
          localRecord,
          includeCreatedAt: false,
        );
        final localClassId = localRecord['class_id'] as int?;
        final localStudentId = localRecord['student_id'] as int?;
        if (localClassId != null) {
          data['class_remote_id'] =
              await _getRemoteIdForLocalId(db, 'classes', localClassId) ?? '';
        }
        if (localStudentId != null) {
          data['student_remote_id'] =
              await _getRemoteIdForLocalId(db, 'students', localStudentId) ??
              '';
        }
        await remoteDoc.set(data, SetOptions(merge: true));

        if (localRecord['remote_id'] == null) {
          await db.update(
            'class_students',
            {'remote_id': remoteDoc.id},
            where: 'id = ?',
            whereArgs: [localRecord['id']],
          );
        }
        uploaded++;
      }

      for (final remoteDoc in remoteSnapshot.docs) {
        final remoteData = remoteDoc.data();
        final localRecords = await db.query(
          'class_students',
          where: 'remote_id = ?',
          whereArgs: [remoteDoc.id],
        );

        final decoded = _decodeRowFromFirestore(remoteData, {
          'class_id',
          'student_id',
          'enrolled_at',
        });

        final classRemoteId = remoteData['class_remote_id']?.toString() ?? '';
        final studentRemoteId =
            remoteData['student_remote_id']?.toString() ?? '';
        if (classRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'classes',
            classRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping class_students download: class_remote_id not found locally remote_id=$classRemoteId',
            );
            continue;
          }
          decoded['class_id'] = resolved;
        }
        if (studentRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'students',
            studentRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping class_students download: student_remote_id not found locally remote_id=$studentRemoteId',
            );
            continue;
          }
          decoded['student_id'] = resolved;
        }
        decoded['remote_id'] = remoteDoc.id;

        if (localRecords.isEmpty) {
          // Insert new record
          await db.insert(
            'class_students',
            decoded,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          downloaded++;
        } else {
          // Update existing record (UPSERT)
          await db.update(
            'class_students',
            decoded,
            where: 'id = ?',
            whereArgs: [localRecords.first['id']],
          );
          print(
            '[SyncService] Updated existing class_student id=${localRecords.first['id']}',
          );
        }
      }

      result.uploaded += uploaded;
      result.downloaded += downloaded;
      print(
        '[SyncService] Class students sync uploaded=$uploaded downloaded=$downloaded',
      );
    } catch (e) {
      print('[SyncService] Class students sync error: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────
  // GRADING ASSESSMENTS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncGradingAssessments(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing grading assessments...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection(
      'users/$userId/grading_assessments',
    );

    try {
      final localAssessments = await db.query('grading_assessments');
      final remoteSnapshot = await collection.get();

      int uploaded = 0;
      int downloaded = 0;

      for (final localRecord in localAssessments) {
        if (localRecord['deleted'] == 1) {
          if (localRecord['remote_id'] != null) {
            await collection.doc(localRecord['remote_id'] as String).delete();
            uploaded++;
          }
          continue;
        }

        final remoteDoc = localRecord['remote_id'] != null
            ? collection.doc(localRecord['remote_id'] as String)
            : collection.doc();

        final data = _encodeRowForFirestore(
          localRecord,
          includeCreatedAt: false,
        );

        // Add FK remote_ids for cross-device sync
        final localClassId = localRecord['class_id'] as int?;
        final localPeriodId = localRecord['grading_period_id'] as int?;
        final localCategoryId = localRecord['category_id'] as int?;
        if (localClassId != null) {
          final classRemoteId = await _getRemoteIdForLocalId(
            db,
            'classes',
            localClassId,
          );
          data['class_remote_id'] = classRemoteId ?? '';
        }
        if (localPeriodId != null) {
          final periodRemoteId = await _getRemoteIdForLocalId(
            db,
            'grading_periods',
            localPeriodId,
          );
          data['grading_period_remote_id'] = periodRemoteId ?? '';
        }
        if (localCategoryId != null) {
          final categoryRemoteId = await _getRemoteIdForLocalId(
            db,
            'grading_categories',
            localCategoryId,
          );
          data['category_remote_id'] = categoryRemoteId ?? '';
        }

        await remoteDoc.set(data, SetOptions(merge: true));

        if (localRecord['remote_id'] == null) {
          await db.update(
            'grading_assessments',
            {'remote_id': remoteDoc.id},
            where: 'id = ?',
            whereArgs: [localRecord['id']],
          );
        }
        uploaded++;
      }

      for (final remoteDoc in remoteSnapshot.docs) {
        final remoteData = remoteDoc.data();
        final localRecords = await db.query(
          'grading_assessments',
          where: 'remote_id = ?',
          whereArgs: [remoteDoc.id],
        );

        final decoded = _decodeRowFromFirestore(remoteData, {
          'class_id',
          'grading_period_id',
          'category_id',
          'name',
          'max_score',
          'order_num',
          'created_at',
          'updated_at',
        });

        final classRemoteId = remoteData['class_remote_id']?.toString() ?? '';
        final periodRemoteId =
            remoteData['grading_period_remote_id']?.toString() ?? '';
        final categoryRemoteId =
            remoteData['category_remote_id']?.toString() ?? '';

        if (classRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'classes',
            classRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping grading_assessments download: class_remote_id not found locally remote_id=$classRemoteId',
            );
            continue;
          }
          decoded['class_id'] = resolved;
        }
        if (periodRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'grading_periods',
            periodRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping grading_assessments download: grading_period_remote_id not found locally remote_id=$periodRemoteId',
            );
            continue;
          }
          decoded['grading_period_id'] = resolved;
        }
        if (categoryRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'grading_categories',
            categoryRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping grading_assessments download: category_remote_id not found locally remote_id=$categoryRemoteId',
            );
            continue;
          }
          decoded['category_id'] = resolved;
        }
        decoded['remote_id'] = remoteDoc.id;

        // Ensure required fields have values
        final now = DateTime.now().toIso8601String();
        decoded['created_at'] ??= now;
        decoded['updated_at'] ??= now;

        if (localRecords.isEmpty) {
          // Insert new record
          await db.insert(
            'grading_assessments',
            decoded,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          downloaded++;
        } else {
          // Update existing record (UPSERT)
          await db.update(
            'grading_assessments',
            decoded,
            where: 'id = ?',
            whereArgs: [localRecords.first['id']],
          );
          print(
            '[SyncService] Updated existing grading_assessment id=${localRecords.first['id']}',
          );
        }
      }

      result.uploaded += uploaded;
      result.downloaded += downloaded;
      print(
        '[SyncService] Grading assessments sync uploaded=$uploaded downloaded=$downloaded',
      );
    } catch (e) {
      print('[SyncService] Grading assessments sync error: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────
  // ASSESSMENT SCORES SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncAssessmentScores(
    String userId,
    SyncResult result,
  ) async {
    print('[SyncService] Syncing assessment scores...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/assessment_scores');

    try {
      final localScores = await db.query('assessment_scores');
      final remoteSnapshot = _doDownload ? await collection.get() : null;

      int uploaded = 0;
      int downloaded = 0;

      if (_doUpload) {
        for (final localRecord in localScores) {
          if (localRecord['deleted'] == 1) {
            if (localRecord['remote_id'] != null) {
              await collection.doc(localRecord['remote_id'] as String).delete();
              uploaded++;
            }
            continue;
          }

          final remoteDoc = localRecord['remote_id'] != null
              ? collection.doc(localRecord['remote_id'] as String)
              : collection.doc();

          final data = _encodeRowForFirestore(
            localRecord,
            includeCreatedAt: false,
          );

          // Add FK remote_ids for cross-device sync
          final localAssessmentId = localRecord['assessment_id'] as int?;
          final localStudentId = localRecord['student_id'] as int?;
          if (localAssessmentId != null) {
            final assessmentRemoteId = await _getRemoteIdForLocalId(
              db,
              'grading_assessments',
              localAssessmentId,
            );
            data['assessment_remote_id'] = assessmentRemoteId ?? '';
          }
          if (localStudentId != null) {
            final studentRemoteId = await _getRemoteIdForLocalId(
              db,
              'students',
              localStudentId,
            );
            data['student_remote_id'] = studentRemoteId ?? '';
          }

          await remoteDoc.set(data, SetOptions(merge: true));

          if (localRecord['remote_id'] == null) {
            await db.update(
              'assessment_scores',
              {'remote_id': remoteDoc.id},
              where: 'id = ?',
              whereArgs: [localRecord['id']],
            );
          }
          uploaded++;
        }
      } else {
        print(
          '[SyncService] Skipping assessment_scores upload (download-only mode)',
        );
      }

      if (_doDownload && remoteSnapshot != null) {
        for (final remoteDoc in remoteSnapshot.docs) {
          final remoteData = remoteDoc.data();
          final localRecords = await db.query(
            'assessment_scores',
            where: 'remote_id = ?',
            whereArgs: [remoteDoc.id],
          );

          final remoteUpdatedRaw = remoteData['updated_at'];
          final remoteUpdated = remoteUpdatedRaw is Timestamp
              ? remoteUpdatedRaw.toDate()
              : DateTime.tryParse(remoteUpdatedRaw?.toString() ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0);

          final decoded = _decodeRowFromFirestore(remoteData, {
            'assessment_id',
            'student_id',
            'score',
            'remarks',
            'recorded_at',
            'updated_at',
          });

          // Resolve FK remote_ids to local IDs
          final assessmentRemoteId =
              remoteData['assessment_remote_id']?.toString() ?? '';
          final studentRemoteId =
              remoteData['student_remote_id']?.toString() ?? '';

          if (assessmentRemoteId.isNotEmpty) {
            final resolved = await _getLocalIdForRemoteId(
              db,
              'grading_assessments',
              assessmentRemoteId,
            );
            if (resolved == null) {
              print(
                '[SyncService] Skipping assessment_scores download: assessment_remote_id not found locally remote_id=$assessmentRemoteId',
              );
              continue;
            }
            decoded['assessment_id'] = resolved;
          }
          if (studentRemoteId.isNotEmpty) {
            final resolved = await _getLocalIdForRemoteId(
              db,
              'students',
              studentRemoteId,
            );
            if (resolved == null) {
              print(
                '[SyncService] Skipping assessment_scores download: student_remote_id not found locally remote_id=$studentRemoteId',
              );
              continue;
            }
            decoded['student_id'] = resolved;
          }

          decoded['remote_id'] = remoteDoc.id;

          // Ensure required fields have values
          final now = DateTime.now().toIso8601String();
          decoded['recorded_at'] ??= now;
          decoded['updated_at'] ??= now;

          final decodedAssessmentId = decoded['assessment_id'] as int?;
          final decodedStudentId = decoded['student_id'] as int?;
          if (decodedAssessmentId == null || decodedStudentId == null) {
            print(
              '[SyncService] Skipping assessment_scores download: missing resolved assessment_id/student_id (remote doc_id=${remoteDoc.id})',
            );
            continue;
          }

          final existingByPair = await db.query(
            'assessment_scores',
            where: 'assessment_id = ? AND student_id = ?',
            whereArgs: [decodedAssessmentId, decodedStudentId],
            limit: 1,
          );

          if (localRecords.isEmpty && existingByPair.isNotEmpty) {
            final existingId = existingByPair.first['id'] as int;
            final localUpdatedRaw =
                existingByPair.first['updated_at'] as String?;
            final localUpdated =
                localUpdatedRaw == null || localUpdatedRaw.isEmpty
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : DateTime.parse(localUpdatedRaw);
            if (localUpdated.isAfter(remoteUpdated)) {
              print(
                '[SyncService] Skipping assessment_scores download: local newer id=$existingId localUpdated=$localUpdated remoteUpdated=$remoteUpdated',
              );
              continue;
            }
            print(
              '[SyncService] Dedup assessment_scores: attaching remote_id=${remoteDoc.id} to existing row by unique pair id=$existingId assessment_id=$decodedAssessmentId student_id=$decodedStudentId',
            );
            await db.update(
              'assessment_scores',
              decoded,
              where: 'id = ?',
              whereArgs: [existingId],
            );
            downloaded++;
          } else if (localRecords.isEmpty) {
            // Insert new record
            await db.insert(
              'assessment_scores',
              decoded,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            downloaded++;
          } else {
            // Update existing record (UPSERT)
            final currentId = localRecords.first['id'] as int;
            final localUpdatedRaw = localRecords.first['updated_at'] as String?;
            final localUpdated =
                localUpdatedRaw == null || localUpdatedRaw.isEmpty
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : DateTime.parse(localUpdatedRaw);
            if (localUpdated.isAfter(remoteUpdated)) {
              print(
                '[SyncService] Skipping assessment_scores download/update: local newer id=$currentId localUpdated=$localUpdated remoteUpdated=$remoteUpdated',
              );
              continue;
            }
            final dupRows = await db.query(
              'assessment_scores',
              columns: ['id', 'remote_id'],
              where: 'assessment_id = ? AND student_id = ? AND id != ?',
              whereArgs: [decodedAssessmentId, decodedStudentId, currentId],
            );
            for (final dup in dupRows) {
              final dupId = dup['id'] as int;
              print(
                '[SyncService] Dedup assessment_scores: deleting duplicate local row id=$dupId for assessment_id=$decodedAssessmentId student_id=$decodedStudentId (keeping id=$currentId)',
              );
              await db.delete(
                'assessment_scores',
                where: 'id = ?',
                whereArgs: [dupId],
              );
            }

            await db.update(
              'assessment_scores',
              decoded,
              where: 'id = ?',
              whereArgs: [currentId],
            );
            print(
              '[SyncService] Updated existing assessment_score id=$currentId',
            );
          }
        }
      } else {
        print(
          '[SyncService] Skipping assessment_scores download (upload-only mode)',
        );
      }

      result.uploaded += uploaded;
      result.downloaded += downloaded;
      print(
        '[SyncService] Assessment scores sync uploaded=$uploaded downloaded=$downloaded',
      );
    } catch (e) {
      print('[SyncService] Assessment scores sync error: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────
  // LESSONS SYNC
  // ────────────────────────────────────────────────────────────
  static Future<void> _syncLessons(String userId, SyncResult result) async {
    print('[SyncService] Syncing lessons...');
    final db = await DatabaseHelper.instance.database;
    final collection = _firestore.collection('users/$userId/lessons');

    try {
      final localLessons = await db.query('lessons');
      final remoteSnapshot = await collection.get();

      int uploaded = 0;
      int downloaded = 0;

      for (final localRecord in localLessons) {
        if (localRecord['deleted'] == 1) {
          if (localRecord['remote_id'] != null) {
            await collection.doc(localRecord['remote_id'] as String).delete();
            uploaded++;
          }
          continue;
        }

        final remoteDoc = localRecord['remote_id'] != null
            ? collection.doc(localRecord['remote_id'] as String)
            : collection.doc();

        final data = _encodeRowForFirestore(
          localRecord,
          includeCreatedAt: false,
        );

        // Add FK remote_id for cross-device sync
        final localClassId = localRecord['class_id'] as int?;
        if (localClassId != null) {
          final classRemoteId = await _getRemoteIdForLocalId(
            db,
            'classes',
            localClassId,
          );
          data['class_remote_id'] = classRemoteId ?? '';
        }

        await remoteDoc.set(data, SetOptions(merge: true));

        if (localRecord['remote_id'] == null) {
          await db.update(
            'lessons',
            {'remote_id': remoteDoc.id},
            where: 'id = ?',
            whereArgs: [localRecord['id']],
          );
        }
        uploaded++;
      }

      for (final remoteDoc in remoteSnapshot.docs) {
        final remoteData = remoteDoc.data();
        final localRecords = await db.query(
          'lessons',
          where: 'remote_id = ?',
          whereArgs: [remoteDoc.id],
        );

        final decoded = _decodeRowFromFirestore(remoteData, {
          'class_id',
          'week_number',
          'title',
          'pdf_path',
          'content',
          'objectives',
          'refs',
          'created_at',
          'updated_at',
        });

        // Resolve FK remote_id to local ID
        final classRemoteId = remoteData['class_remote_id']?.toString() ?? '';
        if (classRemoteId.isNotEmpty) {
          final resolved = await _getLocalIdForRemoteId(
            db,
            'classes',
            classRemoteId,
          );
          if (resolved == null) {
            print(
              '[SyncService] Skipping lessons download: class_remote_id not found locally remote_id=$classRemoteId',
            );
            continue;
          }
          decoded['class_id'] = resolved;
        }

        decoded['remote_id'] = remoteDoc.id;

        // Ensure required fields have values
        final now = DateTime.now().toIso8601String();
        decoded['created_at'] ??= now;
        decoded['updated_at'] ??= now;

        if (localRecords.isEmpty) {
          // Insert new record
          await db.insert(
            'lessons',
            decoded,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          downloaded++;
        } else {
          // Update existing record (UPSERT)
          await db.update(
            'lessons',
            decoded,
            where: 'id = ?',
            whereArgs: [localRecords.first['id']],
          );
          print(
            '[SyncService] Updated existing lesson id=${localRecords.first['id']}',
          );
        }
      }

      result.uploaded += uploaded;
      result.downloaded += downloaded;
      print(
        '[SyncService] Lessons sync uploaded=$uploaded downloaded=$downloaded',
      );
    } catch (e) {
      print('[SyncService] Lessons sync error: $e');
      rethrow;
    }
  }

  static Map<String, dynamic> _encodeRowForFirestore(
    Map<String, Object?> localRow, {
    required bool includeCreatedAt,
  }) {
    final out = <String, dynamic>{};
    localRow.forEach((k, v) {
      if (k == 'id' || k == 'remote_id') return;
      if (k == 'created_at' && !includeCreatedAt) return;
      if (k == 'updated_at' || k == 'created_at') {
        final s = v?.toString() ?? '';
        final dt = DateTime.tryParse(s);
        if (dt != null) {
          out[k] = Timestamp.fromDate(dt);
          return;
        }
      }
      out[k] = v;
    });
    return out;
  }

  static Map<String, Object?> _decodeRowFromFirestore(
    Map<String, dynamic> remote,
    Set<String> allowedCols,
  ) {
    final out = <String, Object?>{};
    for (final entry in remote.entries) {
      final k = entry.key;
      if (k == 'doc_id') continue;
      if (!allowedCols.contains(k)) continue;
      final v = entry.value;
      if (k == 'updated_at' || k == 'created_at') {
        if (v is Timestamp) {
          out[k] = v.toDate().toIso8601String();
          continue;
        }
      }
      out[k] = v;
    }
    return out;
  }
}

// ────────────────────────────────────────────────────────────
// SYNC RESULT CLASS
// ────────────────────────────────────────────────────────────
class SyncResult {
  int uploaded = 0;
  int downloaded = 0;
  bool success = false;
  String? error;

  String summary() {
    if (error != null) return 'Error: $error';
    return 'Uploaded: $uploaded, Downloaded: $downloaded';
  }
}
