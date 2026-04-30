class GradingPeriod {
  final int? id;
  final int classId;
  final String name;
  final int orderNum;
  final bool isActive;
  final bool isLocked;
  final String? startDate;
  final String? endDate;
  final String createdAt;
  final String updatedAt;

  GradingPeriod({
    this.id,
    required this.classId,
    required this.name,
    required this.orderNum,
    this.isActive = false,
    this.isLocked = false,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'class_id': classId,
        'name': name,
        'order_num': orderNum,
        'is_active': isActive ? 1 : 0,
        'is_locked': isLocked ? 1 : 0,
        'start_date': startDate,
        'end_date': endDate,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GradingPeriod.fromMap(Map<String, dynamic> map) => GradingPeriod(
        id: map['id'] as int?,
        classId: map['class_id'] as int,
        name: map['name'] as String,
        orderNum: map['order_num'] as int,
        isActive: (map['is_active'] as int? ?? 0) == 1,
        isLocked: (map['is_locked'] as int? ?? 0) == 1,
        startDate: map['start_date'] as String?,
        endDate: map['end_date'] as String?,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  GradingPeriod copyWith({
    int? id,
    int? classId,
    String? name,
    int? orderNum,
    bool? isActive,
    bool? isLocked,
    String? startDate,
    String? endDate,
    String? updatedAt,
  }) =>
      GradingPeriod(
        id: id ?? this.id,
        classId: classId ?? this.classId,
        name: name ?? this.name,
        orderNum: orderNum ?? this.orderNum,
        isActive: isActive ?? this.isActive,
        isLocked: isLocked ?? this.isLocked,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
