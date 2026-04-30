class Student {
  final int? id;
  final String studentId;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? email;
  final String? phone;
  final String? gender;
  final String? birthDate;
  final String? address;
  final String? photoPath;
  final String createdAt;
  final String updatedAt;

  Student({
    this.id,
    required this.studentId,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.email,
    this.phone,
    this.gender,
    this.birthDate,
    this.address,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$lastName, $firstName ${middleName![0]}.';
    }
    return '$lastName, $firstName';
  }

  String get displayName => '$firstName $lastName';

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'first_name': firstName,
        'last_name': lastName,
        'middle_name': middleName,
        'email': email,
        'phone': phone,
        'gender': gender,
        'birth_date': birthDate,
        'address': address,
        'photo_path': photoPath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Student.fromMap(Map<String, dynamic> map) => Student(
        id: map['id'] as int?,
        studentId: map['student_id'] as String,
        firstName: map['first_name'] as String,
        lastName: map['last_name'] as String,
        middleName: map['middle_name'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        gender: map['gender'] as String?,
        birthDate: map['birth_date'] as String?,
        address: map['address'] as String?,
        photoPath: map['photo_path'] as String?,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Student copyWith({
    int? id,
    String? studentId,
    String? firstName,
    String? lastName,
    String? middleName,
    String? email,
    String? phone,
    String? gender,
    String? birthDate,
    String? address,
    String? photoPath,
    String? updatedAt,
  }) =>
      Student(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        middleName: middleName ?? this.middleName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        gender: gender ?? this.gender,
        birthDate: birthDate ?? this.birthDate,
        address: address ?? this.address,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
