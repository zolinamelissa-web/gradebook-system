class Grade {
  final int? id;
  final int studentId;
  final int classId;
  final int gradingPeriodId;
  final int categoryId;
  final double score;
  final double maxScore;
  final String? remarks;
  final String recordedAt;
  final String updatedAt;
  String? categoryName;
  double? categoryWeight;

  Grade({
    this.id,
    required this.studentId,
    required this.classId,
    required this.gradingPeriodId,
    required this.categoryId,
    required this.score,
    required this.maxScore,
    this.remarks,
    required this.recordedAt,
    required this.updatedAt,
    this.categoryName,
    this.categoryWeight,
  });

  double get percentage => maxScore > 0 ? (score / maxScore) * 100 : 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'grading_period_id': gradingPeriodId,
        'category_id': categoryId,
        'score': score,
        'max_score': maxScore,
        'remarks': remarks,
        'recorded_at': recordedAt,
        'updated_at': updatedAt,
      };

  factory Grade.fromMap(Map<String, dynamic> map) => Grade(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        classId: map['class_id'] as int,
        gradingPeriodId: map['grading_period_id'] as int,
        categoryId: map['category_id'] as int,
        score: (map['score'] as num).toDouble(),
        maxScore: (map['max_score'] as num).toDouble(),
        remarks: map['remarks'] as String?,
        recordedAt: map['recorded_at'] as String,
        updatedAt: map['updated_at'] as String,
        categoryName: map['category_name'] as String?,
        categoryWeight: map['weight'] != null
            ? (map['weight'] as num).toDouble()
            : null,
      );

  Grade copyWith({
    int? id,
    double? score,
    double? maxScore,
    String? remarks,
    String? updatedAt,
  }) =>
      Grade(
        id: id ?? this.id,
        studentId: studentId,
        classId: classId,
        gradingPeriodId: gradingPeriodId,
        categoryId: categoryId,
        score: score ?? this.score,
        maxScore: maxScore ?? this.maxScore,
        remarks: remarks ?? this.remarks,
        recordedAt: recordedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        categoryName: categoryName,
        categoryWeight: categoryWeight,
      );
}
