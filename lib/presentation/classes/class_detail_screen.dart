import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/grading_category_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/risk_repository.dart';
import '../../core/utils/platform_icons.dart';

import '../grading/grading_periods_screen.dart';
import '../attendance/attendance_screen.dart';
import '../grades/grades_screen.dart';
import '../grades/final_grades_overview_screen.dart';
import '../grades/category_detail_screen.dart';
import '../risk/risk_screen.dart';
import '../lessons/lessons_list_screen.dart';
import '../announcements/announcements_screen.dart';
import 'class_form_screen.dart';
import 'enroll_students_screen.dart';

class ClassDetailScreen extends StatefulWidget {
  final ClassModel classModel;
  final VoidCallback? onBackPressed;

  const ClassDetailScreen({
    super.key,
    required this.classModel,
    this.onBackPressed,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late ClassModel _class;
  List<Student> _students = [];
  GradingPeriod? _activePeriod;
  List<GradingCategory> _categories = [];
  int _atRiskCount = 0;
  double? _classFinalAverage;
  bool _isLoading = true;
  final StudentRepository _studentRepo = StudentRepository();
  final SubjectRepository _subjectRepo = SubjectRepository();
  final GradingRepository _gradingRepo = GradingRepository();
  final RiskRepository _riskRepo = RiskRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _class = widget.classModel;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await _loadWeb();
        return;
      }
      final students = await _studentRepo.getStudentsByClass(_class.id!);
      final cls = await _subjectRepo.getClassById(_class.id!);
      final periods = await _gradingRepo.getPeriodsByClass(_class.id!);
      final activePeriod = periods.where((p) => p.isActive).firstOrNull;
      final displayPeriod = activePeriod ?? periods.firstOrNull;
      final atRiskCount = await _riskRepo.getAtRiskCount(_class.id!);
      final classFinalAverage = await _computeClassFinalAverage(
        classId: _class.id!,
        students: students,
        periods: periods,
      );

      final categories = displayPeriod != null
          ? await _gradingRepo.getCategoriesByPeriod(displayPeriod.id!)
          : <GradingCategory>[];

      print(
        '[ClassDetailScreen] Loaded ${students.length} students for class ${_class.id}',
      );
      print(
        '[ClassDetailScreen] Periods loaded=${periods.length} active=${activePeriod?.name ?? '-'} display=${displayPeriod?.name ?? '-'}',
      );
      print(
        '[ClassDetailScreen] Categories loaded=${categories.length} for period ${displayPeriod?.id}',
      );
      print(
        '[ClassDetailScreen] At-risk count classId=${_class.id} count=$atRiskCount',
      );
      print(
        '[ClassDetailScreen] Class final average classId=${_class.id} avg=${classFinalAverage?.toStringAsFixed(2) ?? '-'}',
      );
      if (mounted) {
        setState(() {
          _students = students;
          if (cls != null) _class = cls;
          _activePeriod = displayPeriod;
          _categories = categories;
          _atRiskCount = atRiskCount;
          _classFinalAverage = classFinalAverage;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ClassDetailScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isDeleted(Map<String, dynamic> data) {
    final deleted = data['deleted'];
    if (deleted is bool) return deleted;
    if (deleted is int) return deleted == 1;
    if (deleted is String) {
      final normalized = deleted.toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  Future<void> _loadWeb() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print(
        '[ClassDetailScreen] Web class detail load skipped: no Firebase user',
      );
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final classRemoteId = (_class.remoteId ?? '').trim();
    final classLocalId = _class.id;
    print(
      '[ClassDetailScreen] Loading web class detail classLocalId=$classLocalId classRemoteId=$classRemoteId uid=${firebaseUser.uid}',
    );

    final studentsFuture = _firestore
        .collection('users/${firebaseUser.uid}/students')
        .get();
    final classStudentsFuture = classRemoteId.isNotEmpty
        ? _firestore
              .collection('users/${firebaseUser.uid}/class_students')
              .where('class_remote_id', isEqualTo: classRemoteId)
              .get()
        : _firestore
              .collection('users/${firebaseUser.uid}/class_students')
              .where('class_id', isEqualTo: classLocalId)
              .get();
    final periodsFuture = classRemoteId.isNotEmpty
        ? _firestore
              .collection('users/${firebaseUser.uid}/grading_periods')
              .where('class_remote_id', isEqualTo: classRemoteId)
              .get()
        : _firestore
              .collection('users/${firebaseUser.uid}/grading_periods')
              .where('class_id', isEqualTo: classLocalId)
              .get();
    final categoriesFuture = _firestore
        .collection('users/${firebaseUser.uid}/grading_categories')
        .get();
    final riskFlagsFuture = _firestore
        .collection('users/${firebaseUser.uid}/risk_flags')
        .get();

    final results = await Future.wait([
      studentsFuture,
      classStudentsFuture,
      periodsFuture,
      categoriesFuture,
      riskFlagsFuture,
    ]);

    final studentsSnap = results[0];
    final classStudentsSnap = results[1];
    final periodsSnap = results[2];
    final categoriesSnap = results[3];
    final riskFlagsSnap = results[4];

    final now = DateTime.now().toIso8601String();
    final studentsByRemoteId = <String, Student>{};
    final studentsByLocalId = <String, Student>{};
    final studentsByStudentId = <String, Student>{};
    for (final doc in studentsSnap.docs) {
      final data = doc.data();
      if (_isDeleted(data)) continue;
      final student = Student(
        id: data['id'] is int ? data['id'] as int : null,
        studentId: data['student_id']?.toString() ?? '',
        firstName: data['first_name']?.toString() ?? '',
        lastName: data['last_name']?.toString() ?? '',
        middleName: data['middle_name']?.toString(),
        email: data['email']?.toString(),
        phone: data['phone']?.toString(),
        gender: data['gender']?.toString(),
        birthDate: data['birth_date']?.toString(),
        address: data['address']?.toString(),
        photoPath: data['photo_path']?.toString(),
        createdAt: data['created_at']?.toString() ?? now,
        updatedAt: data['updated_at']?.toString() ?? now,
      );
      final remoteId = (data['remote_id']?.toString() ?? '').trim().isNotEmpty
          ? data['remote_id']?.toString() ?? ''
          : doc.id;
      final localId = data['id']?.toString() ?? '';
      final studentId = data['student_id']?.toString() ?? '';
      if (remoteId.isNotEmpty) {
        studentsByRemoteId[remoteId] = student;
      }
      if (localId.isNotEmpty) {
        studentsByLocalId[localId] = student;
      }
      if (studentId.isNotEmpty) {
        studentsByStudentId[studentId] = student;
      }
    }

    final enrolledStudents = <Student>[];
    final seenStudentKeys = <String>{};
    for (final doc in classStudentsSnap.docs) {
      final data = doc.data();
      final studentRemoteId = data['student_remote_id']?.toString() ?? '';
      final studentLocalId = data['student_id']?.toString() ?? '';
      final student = studentRemoteId.isNotEmpty
          ? studentsByRemoteId[studentRemoteId] ??
                studentsByLocalId[studentRemoteId] ??
                studentsByStudentId[studentRemoteId]
          : studentsByLocalId[studentLocalId] ??
                studentsByRemoteId[studentLocalId] ??
                studentsByStudentId[studentLocalId];
      if (student == null) continue;
      final uniqueKey = student.studentId.isNotEmpty
          ? 'student:${student.studentId}'
          : studentRemoteId.isNotEmpty
          ? 'remote:$studentRemoteId'
          : 'local:$studentLocalId';
      if (seenStudentKeys.add(uniqueKey)) {
        enrolledStudents.add(student);
      }
    }
    enrolledStudents.sort(
      (a, b) =>
          a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase()) != 0
          ? a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase())
          : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()),
    );

    final periodRemoteIdsByLocalId = <String, String>{};
    final periods =
        periodsSnap.docs.where((doc) => !_isDeleted(doc.data())).map((doc) {
          final data = doc.data();
          final id = data['id'] is int ? data['id'] as int : null;
          final orderNumRaw = data['order_num'];
          final orderNum = orderNumRaw is int
              ? orderNumRaw
              : int.tryParse(orderNumRaw?.toString() ?? '') ?? 0;
          final activeRaw = data['is_active'];
          final isActive = activeRaw is bool
              ? activeRaw
              : activeRaw is int
              ? activeRaw == 1
              : activeRaw is String
              ? activeRaw == '1' || activeRaw.toLowerCase() == 'true'
              : false;
          final lockedRaw = data['is_locked'];
          final isLocked = lockedRaw is bool
              ? lockedRaw
              : lockedRaw is int
              ? lockedRaw == 1
              : lockedRaw is String
              ? lockedRaw == '1' || lockedRaw.toLowerCase() == 'true'
              : false;
          if (id != null) {
            periodRemoteIdsByLocalId[id.toString()] = doc.id;
          }
          return GradingPeriod(
            id: id,
            classId: classLocalId ?? 0,
            name: data['name']?.toString() ?? '',
            orderNum: orderNum,
            isActive: isActive,
            isLocked: isLocked,
            startDate: data['start_date']?.toString(),
            endDate: data['end_date']?.toString(),
            createdAt: data['created_at']?.toString() ?? now,
            updatedAt: data['updated_at']?.toString() ?? now,
          );
        }).toList()..sort((a, b) => a.orderNum.compareTo(b.orderNum));

    final activePeriod = periods.where((p) => p.isActive).firstOrNull;
    final displayPeriod = activePeriod ?? periods.firstOrNull;

    final categories = displayPeriod == null
        ? <GradingCategory>[]
        : categoriesSnap.docs
              .map((doc) => doc.data())
              .where((data) => !_isDeleted(data))
              .where((data) {
                final periodRemoteId =
                    data['grading_period_remote_id']?.toString() ?? '';
                final displayPeriodRemoteId = displayPeriod.id == null
                    ? ''
                    : (periodRemoteIdsByLocalId[displayPeriod.id.toString()] ??
                          '');
                if (periodRemoteId.isNotEmpty &&
                    displayPeriodRemoteId.isNotEmpty) {
                  return periodRemoteId == displayPeriodRemoteId;
                }
                return data['grading_period_id']?.toString() ==
                    displayPeriod.id?.toString();
              })
              .map((data) {
                final weightRaw = data['weight'];
                final weight = weightRaw is num
                    ? weightRaw.toDouble()
                    : double.tryParse(weightRaw?.toString() ?? '') ?? 0;
                return GradingCategory(
                  id: data['id'] is int ? data['id'] as int : null,
                  gradingPeriodId: displayPeriod.id ?? 0,
                  name: data['name']?.toString() ?? '',
                  weight: weight,
                  createdAt: data['created_at']?.toString() ?? now,
                  updatedAt: data['updated_at']?.toString() ?? now,
                );
              })
              .toList();

    final enrolledStudentRemoteIds = classStudentsSnap.docs
        .map((doc) => doc.data()['student_remote_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final enrolledStudentLocalIds = classStudentsSnap.docs
        .map((doc) => doc.data()['student_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final atRiskCount = riskFlagsSnap.docs
        .map((doc) => doc.data())
        .where((data) => !_isDeleted(data))
        .where((data) {
          final level = (data['risk_level']?.toString() ?? '').toLowerCase();
          if (level != 'high' && level != 'medium') return false;
          final classIdMatches = classRemoteId.isNotEmpty
              ? data['class_remote_id']?.toString() == classRemoteId
              : data['class_id']?.toString() == classLocalId?.toString();
          if (classIdMatches) return true;
          final studentRemoteId = data['student_remote_id']?.toString() ?? '';
          final studentLocalId = data['student_id']?.toString() ?? '';
          return enrolledStudentRemoteIds.contains(studentRemoteId) ||
              enrolledStudentLocalIds.contains(studentLocalId);
        })
        .map((data) {
          final studentRemoteId = data['student_remote_id']?.toString() ?? '';
          final studentLocalId = data['student_id']?.toString() ?? '';
          return studentRemoteId.isNotEmpty
              ? 'remote:$studentRemoteId'
              : 'local:$studentLocalId';
        })
        .toSet()
        .length;

    print(
      '[ClassDetailScreen] Web class detail loaded students=${enrolledStudents.length} periods=${periods.length} categories=${categories.length} atRisk=$atRiskCount classId=$classLocalId classRemoteId=$classRemoteId',
    );

    if (!mounted) return;
    setState(() {
      _students = enrolledStudents;
      _activePeriod = displayPeriod;
      _categories = categories;
      _atRiskCount = atRiskCount;
      _classFinalAverage = null;
      _isLoading = false;
    });
  }

  Future<double?> _computeClassFinalAverage({
    required int classId,
    required List<Student> students,
    required List<GradingPeriod> periods,
  }) async {
    if (students.isEmpty) return null;
    if (periods.isEmpty) return null;

    final periodCount = periods.length;
    double total = 0;
    int count = 0;

    for (final s in students) {
      if (s.id == null) continue;
      double sum = 0;
      for (final p in periods) {
        if (p.id == null) continue;
        final pg = await _gradingRepo.computeStudentPeriodGrade(
          studentId: s.id!,
          classId: classId,
          periodId: p.id!,
        );
        // NOTE: Treat missing/empty grade as 0, but still count the period.
        sum += pg;
      }

      final overall = sum / periodCount;
      print(
        '[ClassDetailScreen] Overall final grade studentId=${s.id} name=${s.fullName} sum=${sum.toStringAsFixed(2)} periods=$periodCount overall=${overall.toStringAsFixed(2)}',
      );
      total += overall;
      count++;
    }

    return count > 0 ? total / count : null;
  }

  Future<void> _editClass() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ClassFormScreen(classModel: _class)),
    );
    if (!mounted) return;
    if (result == true) {
      _load();
      Navigator.pop(context, true);
    }
  }

  Future<void> _toggleArchiveClass() async {
    final willArchive = !_class.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(willArchive ? 'Archive Class' : 'Unarchive Class'),
        content: Text(
          willArchive
              ? 'Archive this class? It will be moved to archived classes.'
              : 'Unarchive this class? It will be moved back to active classes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: willArchive
                  ? AppTheme.warning
                  : AppTheme.success,
            ),
            child: Text(willArchive ? 'Archive' : 'Unarchive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final now = DateTime.now().toIso8601String();
    final updated = _class.copyWith(isArchived: willArchive, updatedAt: now);
    final count = await _subjectRepo.updateClass(updated);
    print(
      '[ClassDetailScreen] ${willArchive ? 'Archived' : 'Unarchived'} class id=${_class.id} rowsUpdated=$count',
    );

    if (!mounted) return;
    setState(() {
      _class = updated;
    });
    Navigator.pop(context, true);
  }

  Future<void> _enrollStudents() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EnrollStudentsScreen(classModel: _class),
      ),
    );
    if (result == true) _load();
  }

  void _navigateToAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnouncementsScreen(
          classId: _class.id!,
          className: (_class.subject?.code.isNotEmpty ?? false)
              ? '${_class.subject!.code} - ${_class.section}'
              : '${_class.subject?.name ?? 'Class'} - ${_class.section}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: (_class.subject?.code.isNotEmpty ?? false)
                ? _class.subject!.code
                : (_class.subject?.name ?? 'Class'),
            subtitle:
                (_class.subject?.description != null &&
                    _class.subject!.description!.trim().isNotEmpty)
                ? _class.subject!.description!.trim()
                : null,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () {
                if (widget.onBackPressed != null) {
                  widget.onBackPressed!();
                } else {
                  Navigator.pop(context);
                }
              },
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _navigateToAnnouncements,
                icon: Icon(PlatformIcons.notifications, color: Colors.white),
                tooltip: 'Announcements',
              ),
              IconButton(
                onPressed: _editClass,
                icon: Icon(PlatformIcons.edit, color: Colors.white),
              ),
              IconButton(
                tooltip: _class.isArchived ? 'Unarchive' : 'Archive',
                onPressed: _toggleArchiveClass,
                icon: Icon(
                  _class.isArchived
                      ? PlatformIcons.unarchive
                      : PlatformIcons.archive,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          // Scrollable Class Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      child: Column(
                        children: [
                          _ClassDetailsCard(
                            studentCount: _students.length,
                            section: _class.section,
                            schoolYear: _class.schoolYear,
                            periodName: _activePeriod?.name,
                            schedule: _class.schedule,
                            room: _class.room,
                          ),
                          const SizedBox(height: 18),
                          _SectionTitle('Quick Actions'),
                          const SizedBox(height: 12),
                          kIsWeb
                              ? SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.book,
                                          label: 'Lessons',
                                          color: const Color(0xFF8B5CF6),
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => LessonsScreen(
                                                classId: _class.id!,
                                              ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.grade,
                                          label: 'Grades',
                                          color: AppTheme.primary,
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => GradesScreen(
                                                classModel: _class,
                                              ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.calendarMonth,
                                          label: 'Grading Periods',
                                          color: AppTheme.secondary,
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  GradingPeriodsScreen(
                                                    classModel: _class,
                                                  ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.factCheck,
                                          label: 'Attendance',
                                          color: AppTheme.success,
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AttendanceScreen(
                                                classModel: _class,
                                              ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.warning,
                                          label: 'At-Risk',
                                          color: AppTheme.danger,
                                          statValue: _atRiskCount,
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => RiskScreen(
                                                classModel: _class,
                                              ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.calculate,
                                          label: 'Final Grade',
                                          color: AppTheme.primary,
                                          showBadge: false,
                                          statText: _classFinalAverage == null
                                              ? '-'
                                              : '${_classFinalAverage!.toStringAsFixed(2)}%',
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  FinalGradesOverviewScreen(
                                                    classModel: _class,
                                                  ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: SizedBox(
                                          width: 140,
                                          child: _ActionTile(
                                            icon: PlatformIcons.book,
                                            label: 'Lessons',
                                            color: const Color(0xFF8B5CF6),
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => LessonsScreen(
                                                  classId: _class.id!,
                                                ),
                                              ),
                                            ).then((_) => _load()),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: SizedBox(
                                          width: 140,
                                          child: _ActionTile(
                                            icon: PlatformIcons.grade,
                                            label: 'Grades',
                                            color: AppTheme.primary,
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => GradesScreen(
                                                  classModel: _class,
                                                ),
                                              ),
                                            ).then((_) => _load()),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: SizedBox(
                                          width: 140,
                                          child: _ActionTile(
                                            icon: PlatformIcons.calendarMonth,
                                            label: 'Grading Periods',
                                            color: AppTheme.secondary,
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    GradingPeriodsScreen(
                                                      classModel: _class,
                                                    ),
                                              ),
                                            ).then((_) => _load()),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: SizedBox(
                                          width: 140,
                                          child: _ActionTile(
                                            icon: PlatformIcons.factCheck,
                                            label: 'Attendance',
                                            color: AppTheme.success,
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AttendanceScreen(
                                                      classModel: _class,
                                                    ),
                                              ),
                                            ).then((_) => _load()),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: SizedBox(
                                          width: 140,
                                          child: _ActionTile(
                                            icon: PlatformIcons.warning,
                                            label: 'At-Risk',
                                            color: AppTheme.danger,
                                            statValue: _atRiskCount,
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => RiskScreen(
                                                  classModel: _class,
                                                ),
                                              ),
                                            ).then((_) => _load()),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: _ActionTile(
                                          icon: PlatformIcons.calculate,
                                          label: 'Final Grade',
                                          color: AppTheme.primary,
                                          showBadge: false,
                                          statText: _classFinalAverage == null
                                              ? '-'
                                              : '${_classFinalAverage!.toStringAsFixed(2)}%',
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  FinalGradesOverviewScreen(
                                                    classModel: _class,
                                                  ),
                                            ),
                                          ).then((_) => _load()),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          const SizedBox(height: 24),
                          _SectionTitle('Assessment'),
                          const SizedBox(height: 12),
                          if (_categories.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE8ECF4),
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      PlatformIcons.category,
                                      size: 40,
                                      color: const Color(0xFF90A0B7),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No categories configured',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF90A0B7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 1.75,
                                  ),
                              itemCount: _categories.length,
                              itemBuilder: (context, i) =>
                                  _CategoryCard(category: _categories[i]),
                            ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _SectionTitle('Enrolled Students'),
                              TextButton.icon(
                                onPressed: _enrollStudents,
                                icon: Icon(PlatformIcons.personAdd, size: 16),
                                label: const Text('Manage'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_students.isEmpty)
                            _EmptyStudents(onEnroll: _enrollStudents)
                          else
                            ...List.generate(
                              _students.length,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _StudentRow(student: _students[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClassDetailsCard extends StatelessWidget {
  final int studentCount;
  final String section;
  final String schoolYear;
  final String? periodName;
  final String? schedule;
  final String? room;

  const _ClassDetailsCard({
    required this.studentCount,
    required this.section,
    required this.schoolYear,
    required this.periodName,
    required this.schedule,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
      bool isWarning = false,
    }) {
      final valueColor = isWarning ? AppTheme.warning : const Color(0xFF111827);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Class Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: tile(
                    icon: PlatformIcons.people,
                    label: 'Students',
                    value: '$studentCount',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: tile(
                    icon: PlatformIcons.class_,
                    label: 'Section',
                    value: section,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: tile(
                    icon: PlatformIcons.calendar,
                    label: 'School Year',
                    value: schoolYear,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: tile(
                    icon: PlatformIcons.eventNote,
                    label: 'Grading Period',
                    value: periodName ?? '-',
                    isWarning: periodName == null,
                  ),
                ),
              ],
            ),
            if ((schedule != null && schedule!.trim().isNotEmpty) ||
                (room != null && room!.trim().isNotEmpty)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: tile(
                      icon: PlatformIcons.schedule,
                      label: 'Schedule',
                      value: (schedule == null || schedule!.trim().isEmpty)
                          ? '-'
                          : schedule!.trim(),
                      isWarning: schedule == null || schedule!.trim().isEmpty,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: tile(
                      icon: PlatformIcons.room,
                      label: 'Room',
                      value: (room == null || room!.trim().isEmpty)
                          ? '-'
                          : room!.trim(),
                      isWarning: room == null || room!.trim().isEmpty,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: Color(0xFF1A2340),
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? statValue;
  final String? statText;
  final bool showBadge;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    this.statValue,
    this.statText,
    this.showBadge = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF4)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (showBadge && (statValue != null || statText != null))
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      statText ?? '${statValue ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final Student student;
  const _StudentRow({required this.student});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.primaryColor;
    final secondary = themeProvider.secondaryColor;

    final initials = '${student.firstName[0]}${student.lastName[0]}'
        .toUpperCase();
    final photoData = (student.photoPath ?? '').trim();

    // Check if photoData is base64 or file path
    bool isBase64 = false;
    bool hasFilePhoto = false;

    if (photoData.isNotEmpty) {
      // Check if it's base64
      if (photoData.startsWith('data:image/')) {
        isBase64 = true;
        print('[ClassDetailScreen] Detected data URI format');
      } else if (photoData.length > 100) {
        // Try to detect if it's valid base64 by checking characters
        try {
          base64Decode(photoData);
          isBase64 = true;
          print('[ClassDetailScreen] Detected plain base64 format');
        } catch (e) {
          print('[ClassDetailScreen] Not valid base64: $e');
          isBase64 = false;
        }
      }

      if (!isBase64 && !kIsWeb) {
        hasFilePhoto = File(photoData).existsSync();
        print('[ClassDetailScreen] Checking file path: $hasFilePhoto');
      }
    }

    final hasPhoto = isBase64 || hasFilePhoto;

    // Debug logging for Cuenca specifically
    if (student.lastName.toLowerCase() == 'cuenca') {
      print('[ClassDetailScreen] Cuenca photo debug:');
      print('  - photoData: "$photoData"');
      print('  - isNotEmpty: ${photoData.isNotEmpty}');
      print('  - isWeb: ${kIsWeb}');
      print('  - isBase64: $isBase64');
      print('  - hasFilePhoto: $hasFilePhoto');
      print('  - hasPhoto: $hasPhoto');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [primary, secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ClipOval(
              child: hasPhoto
                  ? Builder(
                      builder: (context) {
                        if (isBase64) {
                          try {
                            String base64String;
                            if (photoData.startsWith('data:image/')) {
                              // Data URI format: data:image/jpeg;base64,/9j/4AAQ...
                              base64String = photoData.split(',').last;
                              print(
                                '[ClassDetailScreen] Processing data URI, base64 length: ${base64String.length}',
                              );
                            } else {
                              // Plain base64 format
                              base64String = photoData;
                              print(
                                '[ClassDetailScreen] Processing plain base64, length: ${base64String.length}',
                              );
                            }

                            final bytes = base64Decode(base64String);
                            print(
                              '[ClassDetailScreen] Successfully decoded ${bytes.length} bytes for ${student.lastName}',
                            );

                            return Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              width: 36,
                              height: 36,
                              errorBuilder: (context, error, stackTrace) {
                                print(
                                  '[ClassDetailScreen] Memory image load error: $error',
                                );
                                return Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              },
                            );
                          } catch (e) {
                            print(
                              '[ClassDetailScreen] Base64 decode error for ${student.lastName}: $e',
                            );
                            return Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }
                        } else {
                          final file = File(photoData);
                          print(
                            '[ClassDetailScreen] Loading file image: ${file.path}',
                          );
                          return Image.file(
                            file,
                            fit: BoxFit.cover,
                            width: 36,
                            height: 36,
                            errorBuilder: (context, error, stackTrace) {
                              print(
                                '[ClassDetailScreen] File image load error: $error',
                              );
                              print(
                                '[ClassDetailScreen] Stack trace: $stackTrace',
                              );
                              return Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      },
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'ID: ${student.studentId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStudents extends StatelessWidget {
  final VoidCallback onEnroll;
  const _EmptyStudents({required this.onEnroll});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(
      children: [
        Icon(
          PlatformIcons.peopleOutline,
          size: 48,
          color: AppTheme.textLight.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        const Text(
          'No students enrolled',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: onEnroll,
          icon: Icon(PlatformIcons.personAdd, size: 16),
          label: const Text('Enroll Students'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    ),
  );
}

class _CategoryCard extends StatelessWidget {
  final GradingCategory category;
  const _CategoryCard({required this.category});

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('quiz')) return PlatformIcons.quiz;
    if (name.contains('exam') || name.contains('test'))
      return PlatformIcons.assignment;
    if (name.contains('project')) return PlatformIcons.folderSpecial;
    if (name.contains('activity') || name.contains('performance'))
      return PlatformIcons.taskAlt;
    if (name.contains('homework') || name.contains('assignment'))
      return PlatformIcons.edit;
    if (name.contains('participation')) return PlatformIcons.people;
    if (name.contains('attendance')) return PlatformIcons.factCheck;
    return PlatformIcons.category;
  }

  Color _getCategoryColor(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('quiz')) return const Color(0xFF8B5CF6);
    if (name.contains('exam') || name.contains('test')) return AppTheme.danger;
    if (name.contains('project')) return const Color(0xFF10B981);
    if (name.contains('activity') || name.contains('performance'))
      return AppTheme.secondary;
    if (name.contains('homework') || name.contains('assignment'))
      return AppTheme.primary;
    if (name.contains('participation')) return const Color(0xFFF59E0B);
    if (name.contains('attendance')) return AppTheme.success;
    return const Color(0xFF6366F1);
  }

  @override
  Widget build(BuildContext context) {
    final icon = _getCategoryIcon(category.name);
    final color = _getCategoryColor(category.name);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(category: category),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF4)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      category.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    '${category.weight.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
