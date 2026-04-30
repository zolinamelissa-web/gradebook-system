class GradingCategory {
  final int? id;
  final int gradingPeriodId;
  final String name;
  final double weight;
  final String createdAt;
  final String updatedAt;

  GradingCategory({
    this.id,
    required this.gradingPeriodId,
    required this.name,
    required this.weight,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'grading_period_id': gradingPeriodId,
        'name': name,
        'weight': weight,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GradingCategory.fromMap(Map<String, dynamic> map) => GradingCategory(
        id: map['id'] as int?,
        gradingPeriodId: map['grading_period_id'] as int,
        name: map['name'] as String,
        weight: (map['weight'] as num).toDouble(),
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  GradingCategory copyWith({
    int? id,
    int? gradingPeriodId,
    String? name,
    double? weight,
    String? updatedAt,
  }) =>
      GradingCategory(
        id: id ?? this.id,
        gradingPeriodId: gradingPeriodId ?? this.gradingPeriodId,
        name: name ?? this.name,
        weight: weight ?? this.weight,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
