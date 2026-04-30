class StudentAccount {
  final String studentId;           // "2021-12345" - Student ID used for registration
  final String studentRemoteId;     // Firestore remote_id for students collection
  final String teacherUid;          // Which teacher owns this student
  final String? firebaseUid;        // Firebase Auth UID (null until registered)
  final bool isRegistered;          // Whether student has created account
  final String? email;              // Student's email (when registered)
  final DateTime? registeredAt;     // When student registered
  final DateTime createdAt;         // When teacher added student
  final DateTime updatedAt;         // Last update time

  StudentAccount({
    required this.studentId,
    required this.studentRemoteId,
    required this.teacherUid,
    this.firebaseUid,
    this.isRegistered = false,
    this.email,
    this.registeredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'student_id': studentId,
        'student_remote_id': studentRemoteId,
        'teacher_uid': teacherUid,
        'firebase_uid': firebaseUid,
        'is_registered': isRegistered ? 1 : 0,
        'email': email,
        'registered_at': registeredAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StudentAccount.fromMap(Map<String, dynamic> map) => StudentAccount(
        studentId: map['student_id'] as String,
        studentRemoteId: map['student_remote_id'] as String,
        teacherUid: map['teacher_uid'] as String,
        firebaseUid: map['firebase_uid'] as String?,
        isRegistered: (map['is_registered'] as int?) == 1,
        email: map['email'] as String?,
        registeredAt: map['registered_at'] != null
            ? DateTime.parse(map['registered_at'] as String)
            : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  StudentAccount copyWith({
    String? studentId,
    String? studentRemoteId,
    String? teacherUid,
    String? firebaseUid,
    bool? isRegistered,
    String? email,
    DateTime? registeredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      StudentAccount(
        studentId: studentId ?? this.studentId,
        studentRemoteId: studentRemoteId ?? this.studentRemoteId,
        teacherUid: teacherUid ?? this.teacherUid,
        firebaseUid: firebaseUid ?? this.firebaseUid,
        isRegistered: isRegistered ?? this.isRegistered,
        email: email ?? this.email,
        registeredAt: registeredAt ?? this.registeredAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() {
    return 'StudentAccount(studentId: $studentId, studentRemoteId: $studentRemoteId, teacherUid: $teacherUid, isRegistered: $isRegistered)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudentAccount &&
        other.studentId == studentId &&
        other.studentRemoteId == studentRemoteId &&
        other.teacherUid == teacherUid;
  }

  @override
  int get hashCode =>
      studentId.hashCode ^ studentRemoteId.hashCode ^ teacherUid.hashCode;
}
