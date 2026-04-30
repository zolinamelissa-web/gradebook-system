class Lesson {
  final int? id;
  final int classId;
  final int weekNumber;
  final String title;
  final String? pdfPath;
  final String? content;
  final String? objectives;
  final String? references;
  final String? remoteId;
  final int deleted;
  final String createdAt;
  final String updatedAt;

  Lesson({
    this.id,
    required this.classId,
    required this.weekNumber,
    required this.title,
    this.pdfPath,
    this.content,
    this.objectives,
    this.references,
    this.remoteId,
    this.deleted = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'class_id': classId,
      'week_number': weekNumber,
      'title': title,
      'pdf_path': pdfPath,
      'content': content,
      'objectives': objectives,
      'refs': references,
      'remote_id': remoteId,
      'deleted': deleted,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Lesson.fromMap(Map<String, dynamic> map) {
    return Lesson(
      id: map['id'] as int?,
      classId: map['class_id'] as int,
      weekNumber: map['week_number'] as int,
      title: map['title'] as String,
      pdfPath: map['pdf_path'] as String?,
      content: map['content'] as String?,
      objectives: map['objectives'] as String?,
      references: map['refs'] as String?,
      remoteId: map['remote_id'] as String?,
      deleted: map['deleted'] as int? ?? 0,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Lesson copyWith({
    int? id,
    int? classId,
    int? weekNumber,
    String? title,
    String? pdfPath,
    String? content,
    String? objectives,
    String? references,
    String? remoteId,
    int? deleted,
    String? createdAt,
    String? updatedAt,
  }) {
    return Lesson(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      weekNumber: weekNumber ?? this.weekNumber,
      title: title ?? this.title,
      pdfPath: pdfPath ?? this.pdfPath,
      content: content ?? this.content,
      objectives: objectives ?? this.objectives,
      references: references ?? this.references,
      remoteId: remoteId ?? this.remoteId,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
