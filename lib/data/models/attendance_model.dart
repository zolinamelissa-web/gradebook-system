class Attendance {
  final int? id;
  final int studentId;
  final int classId;
  final int gradingPeriodId;
  final String date;
  final String status;
  final String? remarks;
  final String createdAt;
  String? studentName;

  Attendance({
    this.id,
    required this.studentId,
    required this.classId,
    required this.gradingPeriodId,
    required this.date,
    required this.status,
    this.remarks,
    required this.createdAt,
    this.studentName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'grading_period_id': gradingPeriodId,
        'date': date,
        'status': status,
        'remarks': remarks,
        'created_at': createdAt,
      };

  factory Attendance.fromMap(Map<String, dynamic> map) => Attendance(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        classId: map['class_id'] as int,
        gradingPeriodId: map['grading_period_id'] as int,
        date: map['date'] as String,
        status: map['status'] as String,
        remarks: map['remarks'] as String?,
        createdAt: map['created_at'] as String,
        studentName: map['student_name'] as String?,
      );

  Attendance copyWith({
    int? id,
    String? status,
    String? remarks,
  }) =>
      Attendance(
        id: id ?? this.id,
        studentId: studentId,
        classId: classId,
        gradingPeriodId: gradingPeriodId,
        date: date,
        status: status ?? this.status,
        remarks: remarks ?? this.remarks,
        createdAt: createdAt,
        studentName: studentName,
      );
}
