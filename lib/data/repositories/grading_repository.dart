import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/grading_period_model.dart';
import '../models/grading_category_model.dart';
import '../models/grade_model.dart';
import '../models/grading_assessment_model.dart';
import '../models/assessment_score_model.dart';

class GradingRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  // ─── Grading Periods ───────────────────────────────────────────────────────

  Future<List<GradingPeriod>> getPeriodsByClass(int classId) async {
    if (kIsWeb) {
      return await _getWebPeriodsByClass(classId);
    }

    final db = await _db.database;
    final maps = await db.query(
      'grading_periods',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'order_num ASC',
    );
    print('[GradingRepository] getPeriodsByClass($classId): ${maps.length}');
    return maps.map((m) => GradingPeriod.fromMap(m)).toList();
  }

  Future<List<GradingPeriod>> _getWebPeriodsByClass(int classId) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[GradingRepository] Web periods load skipped: no Firebase user');
      return [];
    }

    try {
      final periodsSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .where('class_id', isEqualTo: classId)
          .orderBy('order_num')
          .get();

      final periods = periodsSnapshot.docs.map((doc) {
        final data = doc.data();
        return GradingPeriod(
          id: int.tryParse(doc.id),
          classId: data['class_id'] ?? 0,
          name: data['name'] ?? '',
          orderNum: data['order_num'] ?? 1,
          isActive: data['is_active'] ?? false,
          isLocked: data['is_locked'] ?? false,
          startDate: data['start_date'],
          endDate: data['end_date'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[GradingRepository] Web loaded ${periods.length} periods for class $classId',
      );
      return periods;
    } catch (e) {
      print('[GradingRepository] Error loading web periods: $e');
      return [];
    }
  }

  Future<GradingPeriod?> getPeriodById(int id) async {
    if (kIsWeb) {
      return await _getWebPeriodById(id);
    }

    final db = await _db.database;
    final maps = await db.query(
      'grading_periods',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GradingPeriod.fromMap(maps.first);
  }

  Future<GradingPeriod?> _getWebPeriodById(int id) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    try {
      final doc = await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .doc(id.toString())
          .get();

      if (!doc.exists) return null;
      final data = doc.data()!;
      return GradingPeriod(
        id: int.tryParse(doc.id),
        classId: data['class_id'] ?? 0,
        name: data['name'] ?? '',
        orderNum: data['order_num'] ?? 1,
        isActive: data['is_active'] ?? false,
        isLocked: data['is_locked'] ?? false,
        startDate: data['start_date'],
        endDate: data['end_date'],
        createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
        updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('[GradingRepository] Error loading web period by id: $e');
      return null;
    }
  }

  Future<int> insertPeriod(GradingPeriod period) async {
    if (kIsWeb) {
      return await _insertWebPeriod(period);
    }

    final db = await _db.database;
    final id = await db.insert(
      'grading_periods',
      period.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print('[GradingRepository] insertPeriod id=$id name=${period.name}');
    return id;
  }

  Future<int> _insertWebPeriod(GradingPeriod period) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) throw Exception('No Firebase user');

    try {
      final docRef = await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .add({
            'class_id': period.classId,
            'name': period.name,
            'order_num': period.orderNum,
            'is_active': period.isActive,
            'is_locked': period.isLocked,
            'start_date': period.startDate,
            'end_date': period.endDate,
            'created_at': period.createdAt,
            'updated_at': period.updatedAt,
          });

      print(
        '[GradingRepository] Web insertPeriod id=${docRef.id} name=${period.name}',
      );
      return int.tryParse(docRef.id) ?? 0;
    } catch (e) {
      print('[GradingRepository] Error inserting web period: $e');
      rethrow;
    }
  }

  Future<int> updatePeriod(GradingPeriod period) async {
    if (kIsWeb) {
      return await _updateWebPeriod(period);
    }

    final db = await _db.database;
    final count = await db.update(
      'grading_periods',
      period.toMap(),
      where: 'id = ?',
      whereArgs: [period.id],
    );
    print('[GradingRepository] updatePeriod id=${period.id}: $count rows');
    return count;
  }

  Future<int> _updateWebPeriod(GradingPeriod period) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) throw Exception('No Firebase user');

    try {
      await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .doc(period.id.toString())
          .update({
            'class_id': period.classId,
            'name': period.name,
            'order_num': period.orderNum,
            'is_active': period.isActive,
            'is_locked': period.isLocked,
            'start_date': period.startDate,
            'end_date': period.endDate,
            'updated_at': DateTime.now().toIso8601String(),
          });

      print('[GradingRepository] Web updatePeriod id=${period.id}');
      return 1;
    } catch (e) {
      print('[GradingRepository] Error updating web period: $e');
      return 0;
    }
  }

  Future<void> activatePeriod(int periodId, int classId) async {
    if (kIsWeb) {
      await _activateWebPeriod(periodId, classId);
      return;
    }

    final db = await _db.database;
    await db.update(
      'grading_periods',
      {'is_active': 0},
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    await db.update(
      'grading_periods',
      {'is_active': 1},
      where: 'id = ?',
      whereArgs: [periodId],
    );
    print(
      '[GradingRepository] activatePeriod periodId=$periodId classId=$classId',
    );
  }

  Future<void> _activateWebPeriod(int periodId, int classId) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return;

    try {
      final batch = _firestore.batch();

      // Deactivate all periods in the class
      final classPeriods = await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .where('class_id', isEqualTo: classId)
          .get();

      for (final doc in classPeriods.docs) {
        batch.update(doc.reference, {'is_active': false});
      }

      // Activate the specified period
      await _firestore
          .collection('users/${firebaseUser.uid}/grading_periods')
          .doc(periodId.toString())
          .update({'is_active': true});

      print(
        '[GradingRepository] Web activatePeriod periodId=$periodId classId=$classId',
      );
    } catch (e) {
      print('[GradingRepository] Error activating web period: $e');
    }
  }

  Future<void> lockPeriod(int periodId) async {
    final db = await _db.database;
    await db.update(
      'grading_periods',
      {'is_locked': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [periodId],
    );
    print('[GradingRepository] lockPeriod periodId=$periodId');
  }

  Future<void> unlockPeriod(int periodId) async {
    final db = await _db.database;
    await db.update(
      'grading_periods',
      {'is_locked': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [periodId],
    );
    print('[GradingRepository] unlockPeriod periodId=$periodId');
  }

  Future<int> deletePeriod(int id) async {
    final db = await _db.database;
    final count = await db.delete(
      'grading_periods',
      where: 'id = ?',
      whereArgs: [id],
    );
    print('[GradingRepository] deletePeriod id=$id: $count rows');
    return count;
  }

  // ─── Grading Categories ────────────────────────────────────────────────────

  Future<List<GradingCategory>> getCategoriesByPeriod(int periodId) async {
    if (kIsWeb) {
      return await _getWebCategoriesByPeriod(periodId);
    }

    final db = await _db.database;
    final maps = await db.query(
      'grading_categories',
      where: 'grading_period_id = ?',
      whereArgs: [periodId],
      orderBy: 'name ASC',
    );
    print(
      '[GradingRepository] getCategoriesByPeriod($periodId): ${maps.length}',
    );
    return maps.map((m) => GradingCategory.fromMap(m)).toList();
  }

  Future<List<GradingCategory>> _getWebCategoriesByPeriod(int periodId) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return [];

    try {
      final categoriesSnapshot = await _firestore
          .collection('users/${firebaseUser.uid}/grading_categories')
          .where('grading_period_id', isEqualTo: periodId)
          .orderBy('name')
          .get();

      final categories = categoriesSnapshot.docs.map((doc) {
        final data = doc.data();
        return GradingCategory(
          id: int.tryParse(doc.id),
          gradingPeriodId: data['grading_period_id'] ?? 0,
          name: data['name'] ?? '',
          weight: (data['weight'] ?? 0).toDouble(),
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      print(
        '[GradingRepository] Web loaded ${categories.length} categories for period $periodId',
      );
      return categories;
    } catch (e) {
      print('[GradingRepository] Error loading web categories: $e');
      return [];
    }
  }

  Future<GradingCategory?> getCategoryById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'grading_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GradingCategory.fromMap(maps.first);
  }

  /// Get all categories that have assessments in the specified period
  /// This includes categories from other periods if their assessments were moved
  Future<List<GradingCategory>> getCategoriesWithAssessmentsInPeriod(
    int periodId,
  ) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT DISTINCT c.*
      FROM grading_categories c
      INNER JOIN grading_assessments a ON a.category_id = c.id
      WHERE a.grading_period_id = ? AND a.deleted = 0
      ORDER BY c.name ASC
    ''',
      [periodId],
    );
    print(
      '[GradingRepository] getCategoriesWithAssessmentsInPeriod($periodId): ${maps.length}',
    );
    return maps.map((m) => GradingCategory.fromMap(m)).toList();
  }

  Future<int> insertCategory(GradingCategory category) async {
    final db = await _db.database;
    final id = await db.insert(
      'grading_categories',
      category.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    print('[GradingRepository] insertCategory id=$id name=${category.name}');
    return id;
  }

  Future<int> updateCategory(GradingCategory category) async {
    final db = await _db.database;
    final count = await db.update(
      'grading_categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    print('[GradingRepository] updateCategory id=${category.id}: $count rows');
    return count;
  }

  Future<int> deleteCategory(int id) async {
    final db = await _db.database;
    final count = await db.delete(
      'grading_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    print('[GradingRepository] deleteCategory id=$id: $count rows');
    return count;
  }

  Future<double> getTotalWeight(int periodId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT SUM(weight) as total FROM grading_categories WHERE grading_period_id = ?',
      [periodId],
    );
    final total = (result.first['total'] as num?)?.toDouble() ?? 0;
    print('[GradingRepository] getTotalWeight($periodId): $total');
    return total;
  }

  // ─── Grades ────────────────────────────────────────────────────────────────

  // ─── Assessments (graded items inside a category) ─────────────────────────

  Future<List<GradingAssessment>> getAssessments({
    required int classId,
    required int periodId,
    required int categoryId,
  }) async {
    final db = await _db.database;
    final maps = await db.query(
      'grading_assessments',
      where:
          'class_id = ? AND grading_period_id = ? AND category_id = ? AND deleted = 0',
      whereArgs: [classId, periodId, categoryId],
      orderBy: 'order_num ASC, id ASC',
    );
    print(
      '[GradingRepository] getAssessments c=$classId p=$periodId cat=$categoryId: ${maps.length}',
    );
    return maps.map((m) => GradingAssessment.fromMap(m)).toList();
  }

  Future<int> insertAssessment(GradingAssessment assessment) async {
    // Validation: Ensure max_score is positive
    if (assessment.maxScore <= 0) {
      throw ArgumentError(
        '[GradingRepository] max_score must be greater than 0. Provided value: ${assessment.maxScore}',
      );
    }

    // Validation: Ensure max_score is reasonable (not too high)
    if (assessment.maxScore > 1000) {
      throw ArgumentError(
        '[GradingRepository] max_score seems too high: ${assessment.maxScore}. Please verify the correct maximum score.',
      );
    }

    final db = await _db.database;
    final id = await db.insert(
      'grading_assessments',
      assessment.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print(
      '[GradingRepository] insertAssessment id=$id name=${assessment.name} max=${assessment.maxScore}',
    );
    return id;
  }

  Future<int> updateAssessment(GradingAssessment assessment) async {
    // Validation: Ensure max_score is positive
    if (assessment.maxScore <= 0) {
      throw ArgumentError(
        '[GradingRepository] max_score must be greater than 0. Provided value: ${assessment.maxScore}',
      );
    }

    // Validation: Ensure max_score is reasonable (not too high)
    if (assessment.maxScore > 1000) {
      throw ArgumentError(
        '[GradingRepository] max_score seems too high: ${assessment.maxScore}. Please verify the correct maximum score.',
      );
    }

    final db = await _db.database;
    final count = await db.update(
      'grading_assessments',
      assessment.toMap(),
      where: 'id = ?',
      whereArgs: [assessment.id],
    );
    print(
      '[GradingRepository] updateAssessment id=${assessment.id}: $count rows',
    );
    return count;
  }

  Future<int> deleteAssessment(int id) async {
    final db = await _db.database;
    final count = await db.update(
      'grading_assessments',
      {'deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    print('[GradingRepository] deleteAssessment id=$id: $count rows');
    return count;
  }

  Future<Map<int, AssessmentScore>> getAssessmentScoresForStudent({
    required int studentId,
    required List<int> assessmentIds,
  }) async {
    if (assessmentIds.isEmpty) return {};
    final db = await _db.database;
    final placeholders = List.filled(assessmentIds.length, '?').join(',');
    final args = <Object?>[studentId, ...assessmentIds];
    final maps = await db.rawQuery(
      'SELECT * FROM assessment_scores WHERE student_id = ? AND deleted = 0 AND assessment_id IN ($placeholders)',
      args,
    );
    final out = <int, AssessmentScore>{};
    for (final m in maps) {
      final s = AssessmentScore.fromMap(m);
      out[s.assessmentId] = s;
    }
    print(
      '[GradingRepository] getAssessmentScoresForStudent s=$studentId items=${assessmentIds.length}: ${maps.length}',
    );
    return out;
  }

  Future<List<AssessmentScore>> getScoresByAssessment(int assessmentId) async {
    final db = await _db.database;
    final maps = await db.query(
      'assessment_scores',
      where: 'assessment_id = ? AND deleted = 0',
      whereArgs: [assessmentId],
    );
    final scores = maps.map((m) => AssessmentScore.fromMap(m)).toList();
    print(
      '[GradingRepository] getScoresByAssessment assessment=$assessmentId: ${scores.length} scores',
    );
    return scores;
  }

  Future<int> upsertAssessmentScore(AssessmentScore score) async {
    final db = await _db.database;

    // Get the assessment to validate max_score
    final assessments = await db.query(
      'grading_assessments',
      where: 'id = ? AND deleted = 0',
      whereArgs: [score.assessmentId],
      limit: 1,
    );

    if (assessments.isEmpty) {
      throw StateError(
        '[GradingRepository] Assessment with id ${score.assessmentId} not found',
      );
    }

    final assessment = assessments.first;
    final maxScore = assessment['max_score'] as double? ?? 0.0;

    // Validation: Check if max_score is valid
    if (maxScore <= 0) {
      throw StateError(
        '[GradingRepository] Assessment ${score.assessmentId} has invalid max_score: $maxScore. Please fix the assessment first.',
      );
    }

    // Validation: Ensure score doesn't exceed max_score
    if (score.score > maxScore) {
      throw ArgumentError(
        '[GradingRepository] Score (${score.score}) cannot exceed max_score ($maxScore) for assessment ${score.assessmentId}',
      );
    }

    // Validation: Ensure score is not negative
    if (score.score < 0) {
      throw ArgumentError(
        '[GradingRepository] Score cannot be negative. Provided value: ${score.score}',
      );
    }

    final existing = await db.query(
      'assessment_scores',
      where: 'assessment_id = ? AND student_id = ?',
      whereArgs: [score.assessmentId, score.studentId],
      limit: 1,
    );
    int id;
    if (existing.isNotEmpty) {
      id = existing.first['id'] as int;
      await db.update(
        'assessment_scores',
        {
          'score': score.score,
          'remarks': score.remarks,
          'deleted': score.deleted,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print(
        '[GradingRepository] upsertAssessmentScore updated id=$id score=${score.score}',
      );
    } else {
      id = await db.insert(
        'assessment_scores',
        score.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
        '[GradingRepository] upsertAssessmentScore inserted id=$id score=${score.score}',
      );
    }
    return id;
  }

  Future<bool> hasAssessments({
    required int classId,
    required int periodId,
    required int categoryId,
  }) async {
    final db = await _db.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM grading_assessments WHERE class_id = ? AND grading_period_id = ? AND category_id = ? AND deleted = 0',
      [classId, periodId, categoryId],
    );
    final cnt = (res.first['cnt'] as num?)?.toInt() ?? 0;
    return cnt > 0;
  }

  /// Returns the effective total score/max score for a student in a category.
  /// If assessment items exist, totals are computed from assessment_scores + max_score.
  /// Otherwise, falls back to the legacy `grades` table (single row per category).
  Future<({double score, double maxScore})> getEffectiveCategoryTotal({
    required int studentId,
    required int classId,
    required int periodId,
    required int categoryId,
  }) async {
    final db = await _db.database;

    final hasItems = await hasAssessments(
      classId: classId,
      periodId: periodId,
      categoryId: categoryId,
    );

    if (hasItems) {
      final rows = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(s.score), 0) AS total_score,
          COALESCE(SUM(a.max_score), 0) AS total_max
        FROM grading_assessments a
        LEFT JOIN assessment_scores s
          ON s.assessment_id = a.id
          AND s.student_id = ?
          AND s.deleted = 0
        WHERE a.class_id = ?
          AND a.grading_period_id = ?
          AND a.category_id = ?
          AND a.deleted = 0
      ''',
        [studentId, classId, periodId, categoryId],
      );

      final score = (rows.first['total_score'] as num?)?.toDouble() ?? 0;
      final max = (rows.first['total_max'] as num?)?.toDouble() ?? 0;
      return (score: score, maxScore: max);
    }

    final legacy = await getGrade(
      studentId: studentId,
      classId: classId,
      periodId: periodId,
      categoryId: categoryId,
    );
    return (score: legacy?.score ?? 0, maxScore: legacy?.maxScore ?? 0);
  }

  Future<List<Grade>> getGradesByStudent({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT g.*, gc.name as category_name, gc.weight
      FROM grades g
      INNER JOIN grading_categories gc ON gc.id = g.category_id
      WHERE g.student_id = ? AND g.class_id = ? AND g.grading_period_id = ?
    ''',
      [studentId, classId, periodId],
    );
    print(
      '[GradingRepository] getGradesByStudent s=$studentId c=$classId p=$periodId: ${maps.length}',
    );
    return maps.map((m) => Grade.fromMap(m)).toList();
  }

  /// Like [getGradesByStudent] but uses assessment totals when assessment items exist.
  /// Returns a Grade object per category with computed score/maxScore.
  Future<List<Grade>> getEffectiveGradesByStudent({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;

    final categories = await db.rawQuery(
      '''
      SELECT id, weight
      FROM grading_categories
      WHERE grading_period_id = ?
      ORDER BY name ASC
    ''',
      [periodId],
    );

    final now = DateTime.now().toIso8601String();
    final out = <Grade>[];

    for (final c in categories) {
      final categoryId = c['id'] as int;
      final totals = await getEffectiveCategoryTotal(
        studentId: studentId,
        classId: classId,
        periodId: periodId,
        categoryId: categoryId,
      );
      out.add(
        Grade(
          studentId: studentId,
          classId: classId,
          gradingPeriodId: periodId,
          categoryId: categoryId,
          score: totals.score,
          maxScore: totals.maxScore,
          recordedAt: now,
          updatedAt: now,
          categoryWeight: (c['weight'] as num?)?.toDouble(),
        ),
      );
    }
    print(
      '[GradingRepository] getEffectiveGradesByStudent s=$studentId c=$classId p=$periodId: ${out.length}',
    );
    return out;
  }

  Future<Grade?> getGrade({
    required int studentId,
    required int classId,
    required int periodId,
    required int categoryId,
  }) async {
    final db = await _db.database;
    final maps = await db.query(
      'grades',
      where:
          'student_id = ? AND class_id = ? AND grading_period_id = ? AND category_id = ?',
      whereArgs: [studentId, classId, periodId, categoryId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Grade.fromMap(maps.first);
  }

  Future<int> upsertGrade(Grade grade) async {
    final db = await _db.database;
    final existing = await getGrade(
      studentId: grade.studentId,
      classId: grade.classId,
      periodId: grade.gradingPeriodId,
      categoryId: grade.categoryId,
    );
    int id;
    if (existing != null) {
      await db.update(
        'grades',
        {
          'score': grade.score,
          'max_score': grade.maxScore,
          'remarks': grade.remarks,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      id = existing.id!;
      print(
        '[GradingRepository] upsertGrade updated id=$id score=${grade.score}',
      );
    } else {
      id = await db.insert(
        'grades',
        grade.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
        '[GradingRepository] upsertGrade inserted id=$id score=${grade.score}',
      );
    }
    return id;
  }

  Future<Map<int, double>> computePeriodGrades({
    required int classId,
    required int periodId,
    required List<int> studentIds,
  }) async {
    final db = await _db.database;
    final result = <int, double>{};
    for (final sid in studentIds) {
      final categories = await db.rawQuery(
        '''
        SELECT id, weight
        FROM grading_categories
        WHERE grading_period_id = ?
      ''',
        [periodId],
      );

      double periodGrade = 0;

      for (final row in categories) {
        final catId = row['id'] as int;
        final weight = (row['weight'] as num).toDouble();
        final totals = await getEffectiveCategoryTotal(
          studentId: sid,
          classId: classId,
          periodId: periodId,
          categoryId: catId,
        );
        if (totals.maxScore > 0) {
          periodGrade +=
              (totals.score / totals.maxScore) * 100 * (weight / 100);
        }
      }
      result[sid] = periodGrade;
    }
    print(
      '[GradingRepository] computePeriodGrades classId=$classId periodId=$periodId students=${studentIds.length}',
    );
    return result;
  }

  Future<Map<int, double>> computePeriodGradesTeacherFormula({
    required int classId,
    required int periodId,
    required List<int> studentIds,
  }) async {
    final db = await _db.database;
    final result = <int, double>{};

    final categories = await db.rawQuery(
      '''
        SELECT id, weight, name
        FROM grading_categories
        WHERE grading_period_id = ?
      ''',
      [periodId],
    );

    for (final sid in studentIds) {
      double uNonExam = 0.0;
      final examContribs = <double>[];

      for (final row in categories) {
        final catId = row['id'] as int;
        final weight = (row['weight'] as num).toDouble();
        final name = (row['name']?.toString() ?? '').trim().toLowerCase();
        final isExam = name.contains('exam');

        final totals = await getEffectiveCategoryTotal(
          studentId: sid,
          classId: classId,
          periodId: periodId,
          categoryId: catId,
        );

        final contribution = (totals.maxScore > 0 && weight > 0)
            ? (totals.score / totals.maxScore) * 100 * (weight / 100)
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

      double finalPct = 0.0;
      if (uNonExam > 0 && xExamAvg > 0) {
        final sumUx = uNonExam + xExamAvg;
        final raw = 100 - ((5 / 8) * (100 - sumUx));
        final rounded = raw.roundToDouble();
        final minApplied = rounded > 70 ? rounded : 70.0;
        finalPct = minApplied.clamp(0.0, 100.0).toDouble();
        print(
          '[GradingRepository] periodFormula studentId=$sid U=$uNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$finalPct',
        );
      } else {
        print(
          '[GradingRepository] periodFormula missing U/X studentId=$sid U=$uNonExam X=$xExamAvg -> 0',
        );
      }

      result[sid] = finalPct;
    }

    print(
      '[GradingRepository] computePeriodGradesTeacherFormula classId=$classId periodId=$periodId students=${studentIds.length}',
    );
    return result;
  }

  Future<double> computeStudentPeriodGrade({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;

    final categories = await db.rawQuery(
      '''
      SELECT id, weight
      FROM grading_categories
      WHERE grading_period_id = ?
    ''',
      [periodId],
    );

    double periodGrade = 0;
    for (final row in categories) {
      final catId = row['id'] as int;
      final weight = (row['weight'] as num).toDouble();
      final totals = await getEffectiveCategoryTotal(
        studentId: studentId,
        classId: classId,
        periodId: periodId,
        categoryId: catId,
      );
      if (totals.maxScore > 0) {
        periodGrade += (totals.score / totals.maxScore) * 100 * (weight / 100);
      }
    }
    return periodGrade;
  }

  Future<double> computeStudentPeriodGradeTeacherFormula({
    required int studentId,
    required int classId,
    required int periodId,
  }) async {
    final db = await _db.database;

    final categories = await db.rawQuery(
      '''
      SELECT id, weight, name
      FROM grading_categories
      WHERE grading_period_id = ?
    ''',
      [periodId],
    );

    double uNonExam = 0.0;
    final examContribs = <double>[];

    for (final row in categories) {
      final catId = row['id'] as int;
      final weight = (row['weight'] as num).toDouble();
      final name = (row['name']?.toString() ?? '').trim().toLowerCase();
      final isExam = name.contains('exam');

      final totals = await getEffectiveCategoryTotal(
        studentId: studentId,
        classId: classId,
        periodId: periodId,
        categoryId: catId,
      );

      final contribution = (totals.maxScore > 0 && weight > 0)
          ? (totals.score / totals.maxScore) * 100 * (weight / 100)
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

    if (uNonExam <= 0 || xExamAvg <= 0) {
      print(
        '[GradingRepository] studentPeriodFormula missing U/X studentId=$studentId periodId=$periodId U=$uNonExam X=$xExamAvg -> 0',
      );
      return 0.0;
    }

    final sumUx = uNonExam + xExamAvg;
    final raw = 100 - ((5 / 8) * (100 - sumUx));
    final rounded = raw.roundToDouble();
    final minApplied = rounded > 70 ? rounded : 70.0;
    final finalPct = minApplied.clamp(0.0, 100.0).toDouble();

    print(
      '[GradingRepository] studentPeriodFormula studentId=$studentId periodId=$periodId U=$uNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$finalPct',
    );
    return finalPct;
  }

  Future<double> computeCumulativeGrade({
    required int studentId,
    required int classId,
  }) async {
    final db = await _db.database;
    final periods = await db.query(
      'grading_periods',
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    if (periods.isEmpty) return 0;

    double total = 0;
    int count = 0;
    for (final p in periods) {
      final pid = p['id'] as int;
      final pg = await computeStudentPeriodGradeTeacherFormula(
        studentId: studentId,
        classId: classId,
        periodId: pid,
      );
      if (pg > 0) {
        total += pg;
        count++;
      }
    }
    return count > 0 ? total / count : 0;
  }
}
