import 'package:sqflite/sqflite.dart';
import '../../data/database/database_helper.dart';

/// Service to handle data migration and fixing invalid records
class DataMigrationService {
  static const String _migrationVersion = '1.0.0';

  /// Fix all invalid max_score values in grading_assessments table
  static Future<void> fixInvalidMaxScores() async {
    print('[DataMigration] Starting fix for invalid max_scores...');
    final db = await DatabaseHelper.instance.database;

    // Find all assessments with invalid max_score (<= 0)
    final invalidAssessments = await db.query(
      'grading_assessments',
      where: 'max_score <= 0 OR max_score IS NULL',
      columns: ['id', 'name', 'max_score', 'class_id'],
    );

    print(
      '[DataMigration] Found ${invalidAssessments.length} assessments with invalid max_score',
    );

    int fixed = 0;
    for (final assessment in invalidAssessments) {
      final assessmentId = assessment['id'] as int;
      final name = assessment['name'] as String? ?? 'Unknown';
      final classId = assessment['class_id'] as int;

      // Get some assessment scores to infer reasonable max_score
      final scores = await db.query(
        'assessment_scores',
        where: 'assessment_id = ? AND deleted = 0',
        columns: ['score'],
        orderBy: 'score DESC',
        limit: 10,
      );

      double newMaxScore = 100.0; // Default

      if (scores.isNotEmpty) {
        // Find the highest score and set max_score to the next reasonable value
        final highestScore = scores
            .map((s) => s['score'] as double? ?? 0.0)
            .reduce((a, b) => a > b ? a : b);

        // Determine reasonable max_score based on highest score
        if (highestScore <= 50) {
          newMaxScore = 50.0;
        } else if (highestScore <= 100) {
          newMaxScore = 100.0;
        } else {
          // Round up to nearest 10 or 100
          newMaxScore = (highestScore / 10).ceil() * 10.0;
          if (newMaxScore > 200) {
            newMaxScore = (highestScore / 100).ceil() * 100.0;
          }
        }
      }

      // Update the assessment
      await db.update(
        'grading_assessments',
        {
          'max_score': newMaxScore,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [assessmentId],
      );

      print(
        '[DataMigration] Fixed assessment "$name" (id: $assessmentId): set max_score to $newMaxScore',
      );
      fixed++;
    }

    print('[DataMigration] Fixed $fixed assessments with invalid max_score');
  }

  /// Fix assessment scores that exceed their max_score
  static Future<void> fixExceedingScores() async {
    print('[DataMigration] Starting fix for exceeding scores...');
    final db = await DatabaseHelper.instance.database;

    // Find all scores that exceed their assessment's max_score
    final query = '''
      SELECT ascore.id, ascore.assessment_id, ascore.student_id, ascore.score, 
             a.max_score, a.name as assessment_name
      FROM assessment_scores ascore
      INNER JOIN grading_assessments a ON ascore.assessment_id = a.id
      WHERE a.max_score > 0 AND ascore.score > a.max_score
      AND ascore.deleted = 0 AND a.deleted = 0
    ''';

    final exceedingScores = await db.rawQuery(query);

    print(
      '[DataMigration] Found ${exceedingScores.length} scores exceeding max_score',
    );

    int fixed = 0;
    for (final score in exceedingScores) {
      final scoreId = score['id'] as int;
      final assessmentId = score['assessment_id'] as int;
      final studentId = score['student_id'] as int;
      final rawScore = score['score'] as double;
      final maxScore = score['max_score'] as double;
      final assessmentName = score['assessment_name'] as String? ?? 'Unknown';

      // Calculate percentage and cap at max_score
      final percentage = (rawScore / maxScore) * 100;
      double fixedScore;

      if (percentage > 150) {
        // Very high percentage, likely data entry error
        // Assume the score should be a percentage
        fixedScore = rawScore > 100 ? 100.0 : rawScore;
        print(
          '[DataMigration] Score $rawScore seems to be a percentage, capping at $fixedScore',
        );
      } else {
        // Cap at max_score
        fixedScore = maxScore;
        print('[DataMigration] Capping score $rawScore to max_score $maxScore');
      }

      // Update the score
      await db.update(
        'assessment_scores',
        {'score': fixedScore, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [scoreId],
      );

      print(
        '[DataMigration] Fixed score for assessment "$assessmentName" (id: $assessmentId, student: $studentId): $rawScore → $fixedScore',
      );
      fixed++;
    }

    print('[DataMigration] Fixed $fixed scores that exceeded max_score');
  }

  /// Run all data migrations
  static Future<void> runAllMigrations() async {
    print('[DataMigration] Starting data migration v$_migrationVersion...');

    try {
      await fixInvalidMaxScores();
      await fixExceedingScores();

      print('[DataMigration] Data migration completed successfully!');
    } catch (e) {
      print('[DataMigration] Migration failed: $e');
      rethrow;
    }
  }

  /// Check if migration is needed
  static Future<bool> isMigrationNeeded() async {
    final db = await DatabaseHelper.instance.database;

    // Check if there are assessments with invalid max_score
    final invalidAssessments = await db.query(
      'grading_assessments',
      where: 'max_score <= 0 OR max_score IS NULL',
      limit: 1,
    );

    if (invalidAssessments.isNotEmpty) {
      print(
        '[DataMigration] Migration needed: Found assessments with invalid max_score',
      );
      return true;
    }

    // Check if there are scores exceeding max_score
    final query = '''
      SELECT COUNT(*) as count
      FROM assessment_scores ascore
      INNER JOIN grading_assessments a ON ascore.assessment_id = a.id
      WHERE a.max_score > 0 AND ascore.score > a.max_score
      AND ascore.deleted = 0 AND a.deleted = 0
      LIMIT 1
    ''';

    final result = await db.rawQuery(query);
    final count = result.first['count'] as int? ?? 0;

    if (count > 0) {
      print(
        '[DataMigration] Migration needed: Found scores exceeding max_score',
      );
      return true;
    }

    print('[DataMigration] No migration needed');
    return false;
  }
}
