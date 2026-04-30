class Announcement {
  final String? id;
  final String teacherId;
  final String classId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final String? remoteId;

  Announcement({
    this.id,
    required this.teacherId,
    required this.classId,
    required this.title,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.remoteId,
  });

  Announcement copyWith({
    String? id,
    String? teacherId,
    String? classId,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? remoteId,
  }) {
    return Announcement(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      classId: classId ?? this.classId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'class_id': classId,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'remote_id': remoteId,
    };
  }

  factory Announcement.fromMap(Map<String, dynamic> map) {
    return Announcement(
      id: map['id']?.toString(),
      teacherId: map['teacher_id']?.toString() ?? '',
      classId: map['class_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      isActive: (map['is_active'] ?? 1) == 1,
      remoteId: map['remote_id']?.toString(),
    );
  }

  Map<String, dynamic> toFirebaseMap() {
    return {
      'teacherId': teacherId,
      'classId': classId,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory Announcement.fromFirebaseMap(String id, Map<String, dynamic> map) {
    return Announcement(
      id: id,
      remoteId: id,
      teacherId: map['teacherId']?.toString() ?? '',
      classId: map['classId']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      isActive: map['isActive'] ?? true,
    );
  }
}
