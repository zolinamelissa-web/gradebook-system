class GradingAssessment {
  final int? id;
  final int classId;
  final int gradingPeriodId;
  final int categoryId;
  final String name;
  final double maxScore;
  final int orderNum;
  final String? remoteId;
  final int deleted;
  final String createdAt;
  final String updatedAt;

  GradingAssessment({
    this.id,
    required this.classId,
    required this.gradingPeriodId,
    required this.categoryId,
    required this.name,
    required this.maxScore,
    required this.orderNum,
    this.remoteId,
    this.deleted = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'class_id': classId,
        'grading_period_id': gradingPeriodId,
        'category_id': categoryId,
        'name': name,
        'max_score': maxScore,
        'order_num': orderNum,
        'remote_id': remoteId,
        'deleted': deleted,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GradingAssessment.fromMap(Map<String, dynamic> map) => GradingAssessment(
        id: map['id'] as int?,
        classId: map['class_id'] as int,
        gradingPeriodId: map['grading_period_id'] as int,
        categoryId: map['category_id'] as int,
        name: map['name'] as String,
        maxScore: (map['max_score'] as num).toDouble(),
        orderNum: (map['order_num'] as int?) ?? 0,
        remoteId: map['remote_id'] as String?,
        deleted: (map['deleted'] as int?) ?? 0,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  GradingAssessment copyWith({
    int? id,
    int? classId,
    int? gradingPeriodId,
    int? categoryId,
    String? name,
    double? maxScore,
    int? orderNum,
    String? remoteId,
    int? deleted,
    String? updatedAt,
  }) =>
      GradingAssessment(
        id: id ?? this.id,
        classId: classId ?? this.classId,
        gradingPeriodId: gradingPeriodId ?? this.gradingPeriodId,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        maxScore: maxScore ?? this.maxScore,
        orderNum: orderNum ?? this.orderNum,
        remoteId: remoteId ?? this.remoteId,
        deleted: deleted ?? this.deleted,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
