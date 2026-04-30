class AssessmentScore {
  final int? id;
  final int assessmentId;
  final int studentId;
  final double score;
  final String? remarks;
  final String? remoteId;
  final int deleted;
  final String recordedAt;
  final String updatedAt;

  AssessmentScore({
    this.id,
    required this.assessmentId,
    required this.studentId,
    required this.score,
    this.remarks,
    this.remoteId,
    this.deleted = 0,
    required this.recordedAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'assessment_id': assessmentId,
        'student_id': studentId,
        'score': score,
        'remarks': remarks,
        'remote_id': remoteId,
        'deleted': deleted,
        'recorded_at': recordedAt,
        'updated_at': updatedAt,
      };

  factory AssessmentScore.fromMap(Map<String, dynamic> map) => AssessmentScore(
        id: map['id'] as int?,
        assessmentId: map['assessment_id'] as int,
        studentId: map['student_id'] as int,
        score: (map['score'] as num).toDouble(),
        remarks: map['remarks'] as String?,
        remoteId: map['remote_id'] as String?,
        deleted: (map['deleted'] as int?) ?? 0,
        recordedAt: map['recorded_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  AssessmentScore copyWith({
    int? id,
    int? assessmentId,
    int? studentId,
    double? score,
    String? remarks,
    String? remoteId,
    int? deleted,
    String? updatedAt,
  }) =>
      AssessmentScore(
        id: id ?? this.id,
        assessmentId: assessmentId ?? this.assessmentId,
        studentId: studentId ?? this.studentId,
        score: score ?? this.score,
        remarks: remarks ?? this.remarks,
        remoteId: remoteId ?? this.remoteId,
        deleted: deleted ?? this.deleted,
        recordedAt: recordedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
