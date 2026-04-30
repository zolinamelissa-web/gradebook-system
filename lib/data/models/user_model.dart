class User {
  final int? id;
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String provider;
  final bool isActive;
  final String userRole; // 'teacher' or 'student'
  final int? linkedStudentId; // Local student.id (for student accounts)
  final String createdAt;
  final String updatedAt;

  User({
    this.id,
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    required this.provider,
    this.isActive = true,
    this.userRole = 'teacher',
    this.linkedStudentId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'uid': uid,
    'email': email,
    'display_name': displayName,
    'photo_url': photoUrl,
    'provider': provider,
    'is_active': isActive ? 1 : 0,
    'user_role': userRole,
    'linked_student_id': linkedStudentId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory User.fromMap(Map<String, dynamic> map) => User(
    id: map['id'] as int?,
    uid: map['uid'] as String,
    email: map['email'] as String?,
    displayName: map['display_name'] as String?,
    photoUrl: map['photo_url'] as String?,
    provider: map['provider'] as String,
    isActive: (map['is_active'] as int?) == 1,
    userRole: map['user_role'] as String? ?? 'teacher',
    linkedStudentId: map['linked_student_id'] as int?,
    createdAt: map['created_at'] as String,
    updatedAt: map['updated_at'] as String,
  );

  User copyWith({
    int? id,
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? provider,
    bool? isActive,
    String? userRole,
    int? linkedStudentId,
    String? updatedAt,
  }) => User(
    id: id ?? this.id,
    uid: uid ?? this.uid,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    photoUrl: photoUrl ?? this.photoUrl,
    provider: provider ?? this.provider,
    isActive: isActive ?? this.isActive,
    userRole: userRole ?? this.userRole,
    linkedStudentId: linkedStudentId ?? this.linkedStudentId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
