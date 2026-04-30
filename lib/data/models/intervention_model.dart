class Intervention {
  final int? id;
  final int studentId;
  final int classId;
  final int? gradingPeriodId;
  final String title;
  final String description;
  final String interventionDate;
  final String? followUpDate;
  final String status;
  final String createdAt;
  final String updatedAt;
  String? studentName;

  Intervention({
    this.id,
    required this.studentId,
    required this.classId,
    this.gradingPeriodId,
    required this.title,
    required this.description,
    required this.interventionDate,
    this.followUpDate,
    this.status = 'open',
    required this.createdAt,
    required this.updatedAt,
    this.studentName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'grading_period_id': gradingPeriodId,
        'title': title,
        'description': description,
        'intervention_date': interventionDate,
        'follow_up_date': followUpDate,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Intervention.fromMap(Map<String, dynamic> map) => Intervention(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        classId: map['class_id'] as int,
        gradingPeriodId: map['grading_period_id'] as int?,
        title: map['title'] as String,
        description: map['description'] as String,
        interventionDate: map['intervention_date'] as String,
        followUpDate: map['follow_up_date'] as String?,
        status: map['status'] as String? ?? 'open',
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
        studentName: map['student_name'] as String?,
      );
}
