import 'subject_model.dart';

class ClassModel {
  final int? id;
  final int subjectId;
  final String section;
  final String schoolYear;
  final String? semester;
  final String? schedule;
  final String? room;
  final bool isArchived;
  final String? remoteId;
  final String createdAt;
  final String updatedAt;
  Subject? subject;

  ClassModel({
    this.id,
    required this.subjectId,
    required this.section,
    required this.schoolYear,
    this.semester,
    this.schedule,
    this.room,
    this.isArchived = false,
    this.remoteId,
    required this.createdAt,
    required this.updatedAt,
    this.subject,
  });

  String get displayName {
    final subjectName = subject?.name ?? 'Unknown Subject';
    return '$subjectName - $section';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'subject_id': subjectId,
    'section': section,
    'school_year': schoolYear,
    'semester': semester,
    'schedule': schedule,
    'room': room,
    'is_archived': isArchived ? 1 : 0,
    'remote_id': remoteId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory ClassModel.fromMap(Map<String, dynamic> map) => ClassModel(
    id: map['id'] as int?,
    subjectId: map['subject_id'] as int,
    section: map['section'] as String,
    schoolYear: map['school_year'] as String,
    semester: map['semester'] as String?,
    schedule: map['schedule'] as String?,
    room: map['room'] as String?,
    isArchived: (map['is_archived'] as int? ?? 0) == 1,
    remoteId: map['remote_id'] as String?,
    createdAt: map['created_at'] as String,
    updatedAt: map['updated_at'] as String,
  );

  ClassModel copyWith({
    int? id,
    int? subjectId,
    String? section,
    String? schoolYear,
    String? semester,
    String? schedule,
    String? room,
    bool? isArchived,
    String? remoteId,
    String? updatedAt,
  }) => ClassModel(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    section: section ?? this.section,
    schoolYear: schoolYear ?? this.schoolYear,
    semester: semester ?? this.semester,
    schedule: schedule ?? this.schedule,
    room: room ?? this.room,
    isArchived: isArchived ?? this.isArchived,
    remoteId: remoteId ?? this.remoteId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    subject: subject,
  );
}
