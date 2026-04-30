class Subject {
  final int? id;
  final String code;
  final String name;
  final String? description;
  final int units;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  Subject({
    this.id,
    required this.code,
    required this.name,
    this.description,
    this.units = 3,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'units': units,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Subject.fromMap(Map<String, dynamic> map) => Subject(
        id: map['id'] as int?,
        code: map['code'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        units: map['units'] as int? ?? 3,
        isArchived: (map['is_archived'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Subject copyWith({
    int? id,
    String? code,
    String? name,
    String? description,
    int? units,
    bool? isArchived,
    String? updatedAt,
  }) =>
      Subject(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        description: description ?? this.description,
        units: units ?? this.units,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
