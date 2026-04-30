import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/wave_header.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/grading_category_model.dart';
import '../../data/models/grading_assessment_model.dart';
import '../../data/models/assessment_score_model.dart';
import '../../data/models/grade_model.dart';
import '../../data/models/grading_system_config.dart';
import '../../data/models/grade_equivalency.dart';
import '../../data/models/student_model.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/student_repository.dart';
import 'student_records_screen.dart';
import '../home/home_screen.dart';

class GradesScreen extends StatefulWidget {
  final ClassModel classModel;

  const GradesScreen({super.key, required this.classModel});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  final GradingRepository _gradingRepo = GradingRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  final ScrollController _modalScrollController = ScrollController();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  GradingSystemConfig _gradingSystem = GradingSystemConfig.percentage100;
  GradeEquivalencyTable _eqTable = const GradeEquivalencyTable(
    equivalencies: [],
  );

  List<GradingPeriod> _periods = [];
  GradingPeriod? _selectedPeriod;
  List<GradingCategory> _categories = [];
  List<Student> _students = [];
  Map<int, Map<int, Grade>> _grades = {};
  Map<int, List<GradingAssessment>> _assessmentsByCategory = {};
  Map<int, List<AssessmentScore>> _scoresByAssessment = {};
  bool _isLoading = true;

  static List<TextInputFormatter> _scoreInputFormatters(double maxScore) {
    return <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*$')),
      _MaxValueTextInputFormatter(maxValue: maxScore),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  @override
  void dispose() {
    _modalScrollController.dispose();
    super.dispose();
  }

  void _autoScrollToNextEmpty(
    List<GradingAssessment> items,
    Map<int, TextEditingController> scoreControllers,
  ) {
    if (_modalScrollController.hasClients && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_modalScrollController.hasClients) return;

        for (int i = 0; i < items.length; i++) {
          final assessment = items[i];
          final controller = scoreControllers[assessment.id!];
          if (controller != null && controller.text.trim().isEmpty) {
            // Calculate the position to scroll to
            // Each score row is approximately 80px high, scroll to the empty field
            final scrollPosition = (i * 80.0) + 200; // Add offset for header
            if (_modalScrollController.hasClients) {
              try {
                _modalScrollController.animateTo(
                  scrollPosition,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              } catch (_) {}
            }
            break;
          }
        }
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final db = DatabaseHelper.instance;
      final gradingSystemJson = await db.getSetting('grading_system');
      if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
        _gradingSystem = GradingSystemConfig.fromJson(
          jsonDecode(gradingSystemJson) as Map<String, dynamic>,
        );
      }

      final eqJson = await db.getSetting('grade_equivalency_table');
      if (eqJson != null && eqJson.isNotEmpty) {
        _eqTable = GradeEquivalencyTable.fromJson(
          jsonDecode(eqJson) as Map<String, dynamic>,
        );
      }

      if (_eqTable.isNotEmpty) {
        final filtered = _eqTable.equivalencies
            .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
            .toList();
        _eqTable = _eqTable.copyWith(equivalencies: filtered);
      }

      if (_eqTable.isEmpty) {
        _eqTable = GradeEquivalencyTable.depedTo1to5;
      }

      print(
        '[GradesScreen] Loaded settings gradingSystem=${_gradingSystem.typeString} eqRows=${_eqTable.equivalencies.length}',
      );
    } catch (e) {
      _gradingSystem = GradingSystemConfig.percentage100;
      _eqTable = GradeEquivalencyTable.depedTo1to5;
      print('[GradesScreen] Settings load error: $e');
    }
  }

  Future<void> _loadPeriods() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await _loadSettings();
      final periods = kIsWeb
          ? await _loadWebPeriods()
          : await _gradingRepo.getPeriodsByClass(widget.classModel.id!);
      print('[GradesScreen] Loaded ${periods.length} periods');
      if (!mounted) return;

      setState(() {
        _periods = periods;
        _selectedPeriod =
            periods.where((p) => p.isActive).firstOrNull ?? periods.firstOrNull;
      });

      if (_selectedPeriod != null) {
        await _loadData();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('[GradesScreen] Error loading grading periods: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_selectedPeriod == null) return;
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await _loadWebData();
        return;
      }
      final configuredCats = await _gradingRepo.getCategoriesByPeriod(
        _selectedPeriod!.id!,
      );
      final catsWithAssessments = await _gradingRepo
          .getCategoriesWithAssessmentsInPeriod(_selectedPeriod!.id!);

      final byId = <int, GradingCategory>{};
      for (final c in configuredCats) {
        if (c.id != null) byId[c.id!] = c;
      }
      for (final c in catsWithAssessments) {
        if (c.id != null) byId[c.id!] = c;
      }
      final cats = byId.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      print(
        '[GradesScreen] Categories for periodId=${_selectedPeriod!.id}: configured=${configuredCats.length} withAssessments=${catsWithAssessments.length} merged=${cats.length}',
      );
      final students = await _studentRepo.getStudentsByClass(
        widget.classModel.id!,
      );

      final gradeMap = <int, Map<int, Grade>>{};
      final assessmentsByCategory = <int, List<GradingAssessment>>{};
      final scoresByAssessment = <int, List<AssessmentScore>>{};

      // Cache assessments by category
      for (final cat in cats) {
        final assessments = await _gradingRepo.getAssessments(
          classId: widget.classModel.id!,
          periodId: _selectedPeriod!.id!,
          categoryId: cat.id!,
        );
        assessmentsByCategory[cat.id!] = assessments;

        // Cache scores for each assessment
        for (final assessment in assessments) {
          final scores = await _gradingRepo.getScoresByAssessment(
            assessment.id!,
          );
          scoresByAssessment[assessment.id!] = scores;
        }
      }

      for (final student in students) {
        gradeMap[student.id!] = {};
        final gradesList = await _gradingRepo.getEffectiveGradesByStudent(
          studentId: student.id!,
          classId: widget.classModel.id!,
          periodId: _selectedPeriod!.id!,
        );
        for (final g in gradesList) {
          gradeMap[student.id!]![g.categoryId] = g;
        }
      }

      print(
        '[GradesScreen] Loaded grades for ${students.length} students, ${cats.length} categories',
      );
      if (mounted) {
        setState(() {
          _categories = cats;
          _students = students;
          _grades = gradeMap;
          _assessmentsByCategory = assessmentsByCategory;
          _scoresByAssessment = scoresByAssessment;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[GradesScreen] Error: $e');
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

  Future<List<GradingPeriod>> _loadWebPeriods() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[GradesScreen] Web periods skipped: no Firebase user');
      return <GradingPeriod>[];
    }

    final classRemoteId = (widget.classModel.remoteId ?? '').trim();
    final classLocalId = widget.classModel.id;
    final snap = classRemoteId.isNotEmpty
        ? await _firestore
              .collection('users/${firebaseUser.uid}/grading_periods')
              .where('class_remote_id', isEqualTo: classRemoteId)
              .get()
        : await _firestore
              .collection('users/${firebaseUser.uid}/grading_periods')
              .where('class_id', isEqualTo: classLocalId)
              .get();

    final now = DateTime.now().toIso8601String();
    final periods = snap.docs.where((doc) => !_isDeleted(doc.data())).map((
      doc,
    ) {
      final data = doc.data();
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
      return GradingPeriod(
        id: data['id'] is int ? data['id'] as int : null,
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

    print('[GradesScreen] Web periods loaded count=${periods.length}');
    return periods;
  }

  Future<void> _loadWebData() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null || _selectedPeriod == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final classRemoteId = (widget.classModel.remoteId ?? '').trim();
    final classLocalId = widget.classModel.id;
    final selectedPeriod = _selectedPeriod!;

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
    final assessmentsFuture = _firestore
        .collection('users/${firebaseUser.uid}/grading_assessments')
        .get();
    final scoresFuture = _firestore
        .collection('users/${firebaseUser.uid}/assessment_scores')
        .get();

    final results = await Future.wait([
      studentsFuture,
      classStudentsFuture,
      periodsFuture,
      categoriesFuture,
      assessmentsFuture,
      scoresFuture,
    ]);

    final studentsSnap = results[0];
    final classStudentsSnap = results[1];
    final periodsSnap = results[2];
    final categoriesSnap = results[3];
    final assessmentsSnap = results[4];
    final scoresSnap = results[5];

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
      if (remoteId.isNotEmpty) studentsByRemoteId[remoteId] = student;
      if (localId.isNotEmpty) studentsByLocalId[localId] = student;
      if (studentId.isNotEmpty) studentsByStudentId[studentId] = student;
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
      final key = student.studentId.isNotEmpty
          ? student.studentId
          : studentRemoteId.isNotEmpty
          ? studentRemoteId
          : studentLocalId;
      if (seenStudentKeys.add(key)) {
        enrolledStudents.add(student);
      }
    }
    enrolledStudents.sort((a, b) {
      final last = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
      if (last != 0) return last;
      return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });

    final periodRemoteIdsByLocalId = <String, String>{};
    final periodDocIds = <String>{};
    for (final doc in periodsSnap.docs) {
      final data = doc.data();
      periodDocIds.add(doc.id);
      final localId = data['id']?.toString() ?? '';
      if (localId.isNotEmpty) {
        periodRemoteIdsByLocalId[localId] = doc.id;
      }
    }
    final selectedPeriodRemoteId = selectedPeriod.id == null
        ? ''
        : (periodRemoteIdsByLocalId[selectedPeriod.id.toString()] ?? '');

    final categories =
        categoriesSnap.docs
            .map((doc) => doc.data())
            .where((data) => !_isDeleted(data))
            .where((data) {
              final remotePeriodId =
                  data['grading_period_remote_id']?.toString() ?? '';
              final rawPeriodId = data['grading_period_id']?.toString() ?? '';
              if (selectedPeriodRemoteId.isNotEmpty &&
                  remotePeriodId.isNotEmpty) {
                return remotePeriodId == selectedPeriodRemoteId;
              }
              if (rawPeriodId == selectedPeriod.id?.toString()) {
                return true;
              }
              if (selectedPeriodRemoteId.isNotEmpty &&
                  rawPeriodId == selectedPeriodRemoteId) {
                return true;
              }
              if (periodDocIds.contains(rawPeriodId) &&
                  selectedPeriodRemoteId.isNotEmpty &&
                  rawPeriodId == selectedPeriodRemoteId) {
                return true;
              }
              return false;
            })
            .map((data) {
              final weightRaw = data['weight'];
              final weight = weightRaw is num
                  ? weightRaw.toDouble()
                  : double.tryParse(weightRaw?.toString() ?? '') ?? 0;
              return GradingCategory(
                id: data['id'] is int ? data['id'] as int : null,
                gradingPeriodId: selectedPeriod.id ?? 0,
                name: data['name']?.toString() ?? '',
                weight: weight,
                createdAt: data['created_at']?.toString() ?? now,
                updatedAt: data['updated_at']?.toString() ?? now,
              );
            })
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final categoryRemoteIdsByLocalId = <String, String>{};
    for (final doc in categoriesSnap.docs) {
      final data = doc.data();
      final localId = data['id']?.toString() ?? '';
      if (localId.isNotEmpty) {
        categoryRemoteIdsByLocalId[localId] = doc.id;
      }
    }

    final assessmentsByCategory = <int, List<GradingAssessment>>{};
    for (final category in categories) {
      final categoryRemoteId = category.id == null
          ? ''
          : (categoryRemoteIdsByLocalId[category.id.toString()] ?? '');
      final items =
          assessmentsSnap.docs
              .map((doc) => doc.data())
              .where((data) => !_isDeleted(data))
              .where((data) {
                final assessmentClassRemoteId =
                    data['class_remote_id']?.toString() ?? '';
                final assessmentPeriodRemoteId =
                    data['grading_period_remote_id']?.toString() ?? '';
                final assessmentCategoryRemoteId =
                    data['category_remote_id']?.toString() ?? '';
                final rawAssessmentPeriodId =
                    data['grading_period_id']?.toString() ?? '';
                final rawAssessmentCategoryId =
                    data['category_id']?.toString() ?? '';
                final classMatches =
                    classRemoteId.isNotEmpty &&
                        assessmentClassRemoteId.isNotEmpty
                    ? assessmentClassRemoteId == classRemoteId
                    : data['class_id']?.toString() == classLocalId?.toString();
                final periodMatches =
                    (selectedPeriodRemoteId.isNotEmpty &&
                        assessmentPeriodRemoteId.isNotEmpty &&
                        assessmentPeriodRemoteId == selectedPeriodRemoteId) ||
                    rawAssessmentPeriodId == selectedPeriod.id?.toString() ||
                    (selectedPeriodRemoteId.isNotEmpty &&
                        rawAssessmentPeriodId == selectedPeriodRemoteId);
                final categoryMatches =
                    (categoryRemoteId.isNotEmpty &&
                        assessmentCategoryRemoteId.isNotEmpty &&
                        assessmentCategoryRemoteId == categoryRemoteId) ||
                    rawAssessmentCategoryId == category.id?.toString() ||
                    (categoryRemoteId.isNotEmpty &&
                        rawAssessmentCategoryId == categoryRemoteId);
                return classMatches && periodMatches && categoryMatches;
              })
              .map((data) {
                final maxScoreRaw = data['max_score'];
                final maxScore = maxScoreRaw is num
                    ? maxScoreRaw.toDouble()
                    : double.tryParse(maxScoreRaw?.toString() ?? '') ?? 0;
                final orderNumRaw = data['order_num'];
                final orderNum = orderNumRaw is int
                    ? orderNumRaw
                    : int.tryParse(orderNumRaw?.toString() ?? '') ?? 0;
                return GradingAssessment(
                  id: data['id'] is int ? data['id'] as int : null,
                  classId: classLocalId ?? 0,
                  gradingPeriodId: selectedPeriod.id ?? 0,
                  categoryId: category.id ?? 0,
                  name: data['name']?.toString() ?? '',
                  maxScore: maxScore,
                  orderNum: orderNum,
                  remoteId: data['remote_id']?.toString(),
                  deleted: 0,
                  createdAt: data['created_at']?.toString() ?? now,
                  updatedAt: data['updated_at']?.toString() ?? now,
                );
              })
              .toList()
            ..sort((a, b) => a.orderNum.compareTo(b.orderNum));
      if (category.id != null) {
        assessmentsByCategory[category.id!] = items;
      }
    }

    final scoresByAssessment = <int, List<AssessmentScore>>{};
    final gradeMap = <int, Map<int, Grade>>{};
    for (final category in categories) {
      final assessments = category.id == null
          ? <GradingAssessment>[]
          : (assessmentsByCategory[category.id!] ?? <GradingAssessment>[]);
      final assessmentRemoteIds = assessments
          .map((a) => (a.remoteId ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final assessment in assessments) {
        final relatedScores = scoresSnap.docs
            .map((doc) => doc.data())
            .where((data) => !_isDeleted(data))
            .where((data) {
              final assessmentRemoteId =
                  data['assessment_remote_id']?.toString() ?? '';
              if (assessment.remoteId != null &&
                  assessment.remoteId!.isNotEmpty &&
                  assessmentRemoteId.isNotEmpty) {
                return assessmentRemoteId == assessment.remoteId;
              }
              return data['assessment_id']?.toString() ==
                  assessment.id?.toString();
            })
            .map((data) {
              final scoreRaw = data['score'];
              final score = scoreRaw is num
                  ? scoreRaw.toDouble()
                  : double.tryParse(scoreRaw?.toString() ?? '') ?? 0;
              return AssessmentScore(
                id: data['id'] is int ? data['id'] as int : null,
                assessmentId: assessment.id ?? 0,
                studentId: data['student_id'] is int
                    ? data['student_id'] as int
                    : 0,
                score: score,
                remarks: data['remarks']?.toString(),
                remoteId: data['remote_id']?.toString(),
                deleted: 0,
                recordedAt: data['recorded_at']?.toString() ?? now,
                updatedAt: data['updated_at']?.toString() ?? now,
              );
            })
            .toList();
        if (assessment.id != null) {
          scoresByAssessment[assessment.id!] = relatedScores;
        }
      }

      for (final student in enrolledStudents) {
        if (student.id == null || category.id == null) continue;
        gradeMap[student.id!] ??= <int, Grade>{};
        double totalScore = 0;
        double totalMax = 0;

        for (final assessment in assessments) {
          if (assessment.id == null) continue;
          final assessmentScores =
              scoresByAssessment[assessment.id!] ?? <AssessmentScore>[];
          final scoreEntry = assessmentScores.firstWhere(
            (score) => score.studentId == student.id,
            orElse: () => AssessmentScore(
              assessmentId: assessment.id!,
              studentId: student.id!,
              score: 0,
              recordedAt: now,
              updatedAt: now,
            ),
          );
          totalScore += scoreEntry.score;
          totalMax += assessment.maxScore;
        }

        gradeMap[student.id!]![category.id!] = Grade(
          studentId: student.id!,
          classId: classLocalId ?? 0,
          gradingPeriodId: selectedPeriod.id ?? 0,
          categoryId: category.id!,
          score: totalScore,
          maxScore: totalMax,
          recordedAt: now,
          updatedAt: now,
          categoryName: category.name,
          categoryWeight: category.weight,
        );
      }
    }

    print(
      '[GradesScreen] Web grade data loaded period=${selectedPeriod.name} students=${enrolledStudents.length} categories=${categories.length}',
    );
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _students = enrolledStudents;
      _grades = gradeMap;
      _assessmentsByCategory = assessmentsByCategory;
      _scoresByAssessment = scoresByAssessment;
      _isLoading = false;
    });
  }

  Future<void> _editGrade(Student student, GradingCategory category) async {
    if (_selectedPeriod?.isLocked == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grading period is locked.')),
      );
      return;
    }
    final result = await _openAssessmentSheet(
      student: student,
      category: category,
    );
    if (result == true) _loadData();
  }

  Future<bool?> _openAssessmentSheet({
    required Student student,
    required GradingCategory category,
  }) async {
    if (_selectedPeriod == null) return false;

    final classId = widget.classModel.id!;
    final periodId = _selectedPeriod!.id!;
    final categoryId = category.id!;

    List<GradingAssessment> items = await _gradingRepo.getAssessments(
      classId: classId,
      periodId: periodId,
      categoryId: categoryId,
    );

    final scoreControllers = <int, TextEditingController>{};
    final focusNodes = <int, FocusNode>{};
    final newNameCtrl = TextEditingController();
    final newMaxCtrl = TextEditingController(text: '10');

    bool disposed = false;
    void disposeLocalControllers() {
      if (disposed) return;
      disposed = true;
      for (final c in scoreControllers.values) {
        try {
          c.dispose();
        } catch (_) {}
      }
      for (final f in focusNodes.values) {
        try {
          f.dispose();
        } catch (_) {}
      }
      try {
        newNameCtrl.dispose();
      } catch (_) {}
      try {
        newMaxCtrl.dispose();
      } catch (_) {}
    }

    try {
      return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          Future<void> refreshScores(StateSetter setModalState) async {
            if (!ctx.mounted) return;
            items = await _gradingRepo.getAssessments(
              classId: classId,
              periodId: periodId,
              categoryId: categoryId,
            );
            final scores = await _gradingRepo.getAssessmentScoresForStudent(
              studentId: student.id!,
              assessmentIds: items.map((e) => e.id!).toList(),
            );

            for (final a in items) {
              scoreControllers[a.id!] ??= TextEditingController();
              focusNodes[a.id!] ??= FocusNode();
              final s = scores[a.id!];
              scoreControllers[a.id!]!.text = s?.score.toStringAsFixed(0) ?? '';
            }

            if (ctx.mounted) {
              setModalState(() {});
              if (ctx.mounted) {
                _autoScrollToNextEmpty(items, scoreControllers);
              }
            }
          }

          return StatefulBuilder(
            builder: (ctx, setModalState) {
              // first load controllers
              if (items.isNotEmpty && scoreControllers.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  refreshScores(setModalState);
                });
              }

              final padding = MediaQuery.of(ctx).viewInsets;

              final totalMax = items.fold<double>(
                0,
                (acc, a) => acc + a.maxScore,
              );
              final totalScore = items.fold<double>(0, (acc, a) {
                final v = double.tryParse(scoreControllers[a.id!]?.text ?? '');
                return acc + (v ?? 0);
              });

              return Padding(
                padding: EdgeInsets.only(bottom: padding.bottom),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      controller: _modalScrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      student.fullName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.pop(ctx, false),
                                icon: Icon(PlatformIcons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Add Item (Quiz / Activity)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: newNameCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Item name',
                                          hintText: 'Quiz 1',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: newMaxCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Perfect',
                                          hintText: '10',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final name = newNameCtrl.text.trim();
                                      final max =
                                          double.tryParse(newMaxCtrl.text) ?? 0;
                                      if (name.isEmpty || max <= 0) {
                                        if (!ctx.mounted) return;
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Enter item name and perfect score.',
                                            ),
                                            backgroundColor: AppTheme.danger,
                                          ),
                                        );
                                        return;
                                      }
                                      final now = DateTime.now()
                                          .toIso8601String();
                                      final nextOrder = items.isEmpty
                                          ? 0
                                          : (items
                                                    .map((e) => e.orderNum)
                                                    .reduce(
                                                      (a, b) => a > b ? a : b,
                                                    ) +
                                                1);
                                      final a = GradingAssessment(
                                        classId: classId,
                                        gradingPeriodId: periodId,
                                        categoryId: categoryId,
                                        name: name,
                                        maxScore: max,
                                        orderNum: nextOrder,
                                        createdAt: now,
                                        updatedAt: now,
                                      );
                                      await _gradingRepo.insertAssessment(a);
                                      print(
                                        '[GradesScreen] Added assessment item name=$name max=$max',
                                      );
                                      newNameCtrl.clear();
                                      await refreshScores(setModalState);
                                      _autoScrollToNextEmpty(
                                        items,
                                        scoreControllers,
                                      );
                                    },
                                    icon: Icon(PlatformIcons.add),
                                    label: const Text('Add'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Scores',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      items.isEmpty
                                          ? 'No items yet'
                                          : '${totalScore.toStringAsFixed(0)}/${totalMax.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (items.isEmpty)
                                  const Text(
                                    'Add at least one item above (e.g., Quiz 1..4).',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  )
                                else
                                  Column(
                                    children: items.map((a) {
                                      final ctrl =
                                          scoreControllers[a.id!] ??
                                          TextEditingController();
                                      scoreControllers[a.id!] ??= ctrl;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    a.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          AppTheme.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Max: ${a.maxScore.toStringAsFixed(0)}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller: ctrl,
                                                focusNode: focusNodes[a.id!],
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters:
                                                    _scoreInputFormatters(
                                                      a.maxScore,
                                                    ),
                                                textInputAction:
                                                    TextInputAction.next,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Score',
                                                      hintText: '0',
                                                    ),
                                                onTap: () {
                                                  // Clear "0" when user taps on the field
                                                  if (ctrl.text == '0') {
                                                    ctrl.clear();
                                                  }
                                                },
                                                onSubmitted: (value) {
                                                  // Navigate to next field when user presses Next/Done
                                                  if (!ctx.mounted) return;

                                                  final currentIndex = items
                                                      .indexWhere(
                                                        (item) =>
                                                            item.id == a.id,
                                                      );
                                                  if (currentIndex != -1 &&
                                                      currentIndex <
                                                          items.length - 1) {
                                                    final nextAssessment =
                                                        items[currentIndex + 1];
                                                    final nextController =
                                                        scoreControllers[nextAssessment
                                                            .id!];
                                                    // Clear "0" from next field before focusing
                                                    if (nextController?.text ==
                                                        '0') {
                                                      nextController?.clear();
                                                    }
                                                    if (ctx.mounted) {
                                                      focusNodes[nextAssessment
                                                              .id!]
                                                          ?.requestFocus();
                                                    }
                                                  } else {
                                                    // Last field, unfocus
                                                    if (ctx.mounted) {
                                                      focusNodes[a.id!]
                                                          ?.unfocus();
                                                    }
                                                  }
                                                },
                                                onChanged: (value) {
                                                  if (ctx.mounted) {
                                                    setModalState(() {});
                                                    // Auto-scroll to next empty field when current field is filled
                                                    if (value
                                                        .trim()
                                                        .isNotEmpty) {
                                                      _autoScrollToNextEmpty(
                                                        items,
                                                        scoreControllers,
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            PopupMenuButton<String>(
                                              onSelected: (value) async {
                                                if (value == 'edit') {
                                                  final editNameCtrl =
                                                      TextEditingController(
                                                        text: a.name,
                                                      );
                                                  final editMaxCtrl =
                                                      TextEditingController(
                                                        text: a.maxScore
                                                            .toStringAsFixed(0),
                                                      );
                                                  final result = await showDialog<bool>(
                                                    context: ctx,
                                                    builder: (dialogCtx) => AlertDialog(
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      title: const Text(
                                                        'Edit Item',
                                                      ),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          TextField(
                                                            controller:
                                                                editNameCtrl,
                                                            decoration:
                                                                const InputDecoration(
                                                                  labelText:
                                                                      'Item name',
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          TextField(
                                                            controller:
                                                                editMaxCtrl,
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration:
                                                                const InputDecoration(
                                                                  labelText:
                                                                      'Perfect Score',
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dialogCtx,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dialogCtx,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            'Save',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (result == true) {
                                                    final newName = editNameCtrl
                                                        .text
                                                        .trim();
                                                    final newMax =
                                                        double.tryParse(
                                                          editMaxCtrl.text,
                                                        ) ??
                                                        0;
                                                    if (newName.isNotEmpty &&
                                                        newMax > 0) {
                                                      await _gradingRepo
                                                          .updateAssessment(
                                                            a.copyWith(
                                                              name: newName,
                                                              maxScore: newMax,
                                                              updatedAt:
                                                                  DateTime.now()
                                                                      .toIso8601String(),
                                                            ),
                                                          );
                                                      print(
                                                        '[GradesScreen] Updated assessment id=${a.id}',
                                                      );
                                                      await refreshScores(
                                                        setModalState,
                                                      );
                                                    }
                                                  }
                                                  try {
                                                    editNameCtrl.dispose();
                                                  } catch (_) {}
                                                  try {
                                                    editMaxCtrl.dispose();
                                                  } catch (_) {}
                                                } else if (value == 'delete') {
                                                  final confirmed = await showDialog<bool>(
                                                    context: ctx,
                                                    builder: (dialogCtx) => AlertDialog(
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      title: const Text(
                                                        'Delete Item',
                                                      ),
                                                      content: Text(
                                                        'Delete "${a.name}"? All student scores for this item will be lost.',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dialogCtx,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dialogCtx,
                                                                true,
                                                              ),
                                                          style:
                                                              ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    AppTheme
                                                                        .danger,
                                                              ),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirmed == true) {
                                                    await _gradingRepo
                                                        .deleteAssessment(
                                                          a.id!,
                                                        );
                                                    print(
                                                      '[GradesScreen] Deleted assessment id=${a.id}',
                                                    );
                                                    await refreshScores(
                                                      setModalState,
                                                    );
                                                  }
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        PlatformIcons.edit,
                                                        size: 18,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text('Edit'),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        PlatformIcons.delete,
                                                        size: 18,
                                                        color: AppTheme.danger,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                          color:
                                                              AppTheme.danger,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              icon: Icon(
                                                PlatformIcons.moreVert,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: items.isEmpty
                                  ? null
                                  : () async {
                                      for (final a in items) {
                                        final entered =
                                            double.tryParse(
                                              scoreControllers[a.id!]!.text,
                                            ) ??
                                            0;
                                        if (entered < 0 ||
                                            entered > a.maxScore) {
                                          if (!ctx.mounted) return;
                                          ScaffoldMessenger.of(
                                            ctx,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Invalid score for ${a.name}. Must be 0-${a.maxScore.toStringAsFixed(0)}.',
                                              ),
                                              backgroundColor: AppTheme.danger,
                                            ),
                                          );
                                          return;
                                        }
                                      }

                                      final now = DateTime.now()
                                          .toIso8601String();
                                      for (final a in items) {
                                        final entered =
                                            double.tryParse(
                                              scoreControllers[a.id!]!.text,
                                            ) ??
                                            0;
                                        final s = AssessmentScore(
                                          assessmentId: a.id!,
                                          studentId: student.id!,
                                          score: entered,
                                          recordedAt: now,
                                          updatedAt: now,
                                        );
                                        await _gradingRepo
                                            .upsertAssessmentScore(s);
                                      }
                                      print(
                                        '[GradesScreen] Saved assessment scores student=${student.id} category=$categoryId items=${items.length}',
                                      );
                                      if (!ctx.mounted) return;
                                      // Defer disposal to the next frame so the sheet can finish
                                      // closing before controllers are disposed.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            Navigator.pop(ctx, true);
                                          });
                                      // Ensure any controllers added dynamically (e.g., via refreshScores) are disposed
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            disposeLocalControllers();
                                          });
                                    },
                              child: const Text('Save Scores'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      // Defer disposal to the next frame to avoid disposing while the
      // bottom-sheet is still animating / rebuilding during swipe dismiss.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        disposeLocalControllers();
      });
    }
  }

  Future<void> _showTaskManagement() async {
    if (_selectedPeriod == null || _categories.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFFF4F6FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'Manage Tasks',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _loadAllTasks(),
                            builder: (ctx, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data!.isNotEmpty) {
                                final tasks = snapshot.data!;
                                final incompleteTasks = tasks.where((task) {
                                  final completedCount =
                                      task['completedCount'] as int;
                                  return completedCount < _students.length;
                                }).length;

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: incompleteTasks == 0
                                        ? AppTheme.success
                                        : AppTheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${tasks.length - incompleteTasks}/${tasks.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(PlatformIcons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadAllTasks(),
                  builder: (ctx, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tasks = snapshot.data!;
                    if (tasks.isEmpty) {
                      return const Center(
                        child: Text(
                          'No tasks created yet.\nCreate a task using "Record Scores" button.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        final assessment =
                            task['assessment'] as GradingAssessment;
                        final category = task['category'] as GradingCategory;
                        final completedCount = task['completedCount'] as int;
                        final totalStudents = _students.length;
                        final isComplete = completedCount == totalStudents;

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  assessment.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (isComplete)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.success
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        PlatformIcons
                                                            .checkCircle,
                                                        size: 12,
                                                        color: AppTheme.success,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Complete',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              AppTheme.success,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${category.name} • Max: ${assessment.maxScore.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child:
                                                      LinearProgressIndicator(
                                                        value: totalStudents > 0
                                                            ? completedCount /
                                                                  totalStudents
                                                            : 0,
                                                        backgroundColor:
                                                            AppTheme.divider,
                                                        color: isComplete
                                                            ? AppTheme.success
                                                            : AppTheme.primary,
                                                        minHeight: 6,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '$completedCount/$totalStudents',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!(_selectedPeriod?.isLocked ?? false))
                                Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: AppTheme.divider),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            await _resumeTaskBulkEntry(
                                              assessment: assessment,
                                            );
                                            _loadData();
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                PlatformIcons.editNote,
                                                size: 16,
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                isComplete
                                                    ? 'Update'
                                                    : 'Resume',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: AppTheme.divider,
                                      ),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () async {
                                            final result =
                                                await showDialog<String>(
                                                  context: ctx,
                                                  builder: (_) =>
                                                      _RenameTaskDialog(
                                                        currentName:
                                                            assessment.name,
                                                      ),
                                                );

                                            final newName =
                                                result?.trim() ?? '';
                                            if (newName.isEmpty ||
                                                newName == assessment.name) {
                                              return;
                                            }

                                            final updatedAssessment = assessment
                                                .copyWith(
                                                  name: newName,
                                                  updatedAt: DateTime.now()
                                                      .toIso8601String(),
                                                );
                                            await _gradingRepo.updateAssessment(
                                              updatedAssessment,
                                            );
                                            print(
                                              '[GradesScreen] Renamed task id=${assessment.id} from="${assessment.name}" to="$newName"',
                                            );

                                            if (!ctx.mounted) return;
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Renamed task to "$newName"',
                                                ),
                                                backgroundColor:
                                                    AppTheme.success,
                                              ),
                                            );
                                            _loadData();
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                PlatformIcons.driveFileRename,
                                                size: 16,
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Rename',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: AppTheme.divider,
                                      ),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () async {
                                            GradingPeriod? selectedPeriod;
                                            final currentPeriodId =
                                                assessment.gradingPeriodId;

                                            final newPeriod = await showDialog<GradingPeriod>(
                                              context: ctx,
                                              builder: (dialogCtx) => StatefulBuilder(
                                                builder: (dialogCtx, setDialogState) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  title: const Text(
                                                    'Change Grading Period',
                                                  ),
                                                  content: SingleChildScrollView(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Move "${assessment.name}" to a different grading period:',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        ..._periods.map((
                                                          period,
                                                        ) {
                                                          final isCurrent =
                                                              period.id ==
                                                              currentPeriodId;
                                                          final dateRange =
                                                              period.startDate !=
                                                                      null &&
                                                                  period.endDate !=
                                                                      null
                                                              ? '${period.startDate} - ${period.endDate}'
                                                              : 'Dates not set';

                                                          return RadioListTile<
                                                            GradingPeriod
                                                          >(
                                                            title: Text(
                                                              period.name,
                                                            ),
                                                            subtitle: Text(
                                                              dateRange,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                            ),
                                                            value: period,
                                                            groupValue:
                                                                selectedPeriod,
                                                            onChanged:
                                                                period.isLocked
                                                                ? null
                                                                : (val) {
                                                                    setDialogState(
                                                                      () {
                                                                        selectedPeriod =
                                                                            val;
                                                                      },
                                                                    );
                                                                  },
                                                            secondary: isCurrent
                                                                ? Icon(
                                                                    Icons
                                                                        .check_circle,
                                                                    color: AppTheme
                                                                        .success,
                                                                  )
                                                                : period
                                                                      .isLocked
                                                                ? Icon(
                                                                    PlatformIcons
                                                                        .lock,
                                                                    color: AppTheme
                                                                        .textLight,
                                                                  )
                                                                : null,
                                                          );
                                                        }),
                                                      ],
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            dialogCtx,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed:
                                                          selectedPeriod != null
                                                          ? () => Navigator.pop(
                                                              dialogCtx,
                                                              selectedPeriod,
                                                            )
                                                          : null,
                                                      child: const Text('Move'),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );

                                            if (newPeriod != null &&
                                                newPeriod.id !=
                                                    assessment
                                                        .gradingPeriodId) {
                                              final updatedAssessment =
                                                  assessment.copyWith(
                                                    gradingPeriodId:
                                                        newPeriod.id,
                                                  );
                                              await _gradingRepo
                                                  .updateAssessment(
                                                    updatedAssessment,
                                                  );
                                              print(
                                                '[GradesScreen] Moved task "${assessment.name}" to period "${newPeriod.name}"',
                                              );
                                              if (ctx.mounted) {
                                                Navigator.pop(ctx);
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Moved "${assessment.name}" to ${newPeriod.name}',
                                                    ),
                                                    backgroundColor:
                                                        AppTheme.success,
                                                  ),
                                                );
                                              }
                                              _loadData();
                                            }
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                PlatformIcons.swapHoriz,
                                                size: 16,
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Period',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: AppTheme.divider,
                                      ),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () async {
                                            final confirmed = await showDialog<bool>(
                                              context: ctx,
                                              builder: (dialogCtx) => AlertDialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                title: const Text(
                                                  'Delete Task',
                                                ),
                                                content: Text(
                                                  'Delete "${assessment.name}"?\n\nThis will remove the task and all student scores for this assessment. This action cannot be undone.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialogCtx,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialogCtx,
                                                          true,
                                                        ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              AppTheme.danger,
                                                        ),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirmed == true) {
                                              await _gradingRepo
                                                  .deleteAssessment(
                                                    assessment.id!,
                                                  );
                                              print(
                                                '[GradesScreen] Deleted task id=${assessment.id} name=${assessment.name}',
                                              );
                                              if (ctx.mounted) {
                                                Navigator.pop(ctx);
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Deleted "${assessment.name}"',
                                                    ),
                                                    backgroundColor:
                                                        AppTheme.success,
                                                  ),
                                                );
                                              }
                                              _loadData();
                                            }
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                PlatformIcons.delete,
                                                size: 16,
                                                color: AppTheme.danger,
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: AppTheme.danger,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllTasks() async {
    final tasks = <Map<String, dynamic>>[];

    for (final category in _categories) {
      final assessments = await _gradingRepo.getAssessments(
        classId: widget.classModel.id!,
        periodId: _selectedPeriod!.id!,
        categoryId: category.id!,
      );

      for (final assessment in assessments) {
        final scores = await _gradingRepo.getScoresByAssessment(assessment.id!);
        final completedCount = scores.where((s) => s.score > 0).length;

        tasks.add({
          'assessment': assessment,
          'category': category,
          'completedCount': completedCount,
        });
      }
    }

    return tasks;
  }

  Future<void> _resumeTaskBulkEntry({
    required GradingAssessment assessment,
  }) async {
    final scoreControllers = <int, TextEditingController>{};

    final existingScores = await _gradingRepo.getScoresByAssessment(
      assessment.id!,
    );
    final scoreMap = {for (var s in existingScores) s.studentId: s};

    for (final student in _students) {
      final ctrl = TextEditingController();
      final existing = scoreMap[student.id!];
      if (existing != null) {
        ctrl.text = existing.score.toStringAsFixed(0);
      }
      scoreControllers[student.id!] = ctrl;
    }

    final result = await _showBulkScoreEntry(
      assessmentId: assessment.id!,
      title: assessment.name,
      maxScore: assessment.maxScore,
      existingControllers: scoreControllers,
    );

    if (result == true) {
      await _loadData();
    }

    scoreControllers.clear();
  }

  Future<void> _openBulkScoreRecording() async {
    if (_selectedPeriod == null) return;

    final taskData = await _showTaskCreationDialog();
    if (taskData == null) return;

    final title = taskData['title'] as String;
    final categoryId = taskData['categoryId'] as int;
    final maxScore = taskData['maxScore'] as double;
    final mode = taskData['mode'] as String;

    final now = DateTime.now().toIso8601String();
    final items = await _gradingRepo.getAssessments(
      classId: widget.classModel.id!,
      periodId: _selectedPeriod!.id!,
      categoryId: categoryId,
    );
    final nextOrder = items.isEmpty
        ? 0
        : (items.map((e) => e.orderNum).reduce((a, b) => a > b ? a : b) + 1);

    final assessment = GradingAssessment(
      classId: widget.classModel.id!,
      gradingPeriodId: _selectedPeriod!.id!,
      categoryId: categoryId,
      name: title,
      maxScore: maxScore,
      orderNum: nextOrder,
      createdAt: now,
      updatedAt: now,
    );

    final assessmentId = await _gradingRepo.insertAssessment(assessment);
    print('[GradesScreen] Created assessment id=$assessmentId title=$title');

    if (!mounted) return;

    bool? result;
    if (mode == 'bulk') {
      result = await _showBulkScoreEntry(
        assessmentId: assessmentId,
        title: title,
        maxScore: maxScore,
      );
    } else {
      result = await _showSequentialScoreEntry(
        assessmentId: assessmentId,
        title: title,
        maxScore: maxScore,
      );
    }

    if (result == true) {
      await _loadData();
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<Map<String, dynamic>?> _showTaskCreationDialog() async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TaskCreationDialog(categories: _categories),
    );
  }

  Future<bool?> _showBulkScoreEntry({
    required int assessmentId,
    required String title,
    required double maxScore,
    Map<int, TextEditingController>? existingControllers,
  }) async {
    final scoreControllers =
        existingControllers ?? <int, TextEditingController>{};
    final focusNodes = <int, FocusNode>{};

    if (existingControllers == null) {
      for (final student in _students) {
        scoreControllers[student.id!] = TextEditingController();
        focusNodes[student.id!] = FocusNode();
      }
    } else {
      // Create focus nodes for existing controllers
      for (final student in _students) {
        focusNodes[student.id!] = FocusNode();
      }
    }

    bool? result;
    try {
      result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final padding = MediaQuery.of(ctx).viewInsets;

          return Padding(
            padding: EdgeInsets.only(bottom: padding.bottom),
            child: Container(
              height: MediaQuery.of(ctx).size.height * 0.8,
              decoration: BoxDecoration(
                color: Color(0xFFF4F6FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Perfect Score: ${maxScore.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: Icon(PlatformIcons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _students.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final student = _students[i];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    student.fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: scoreControllers[student.id!],
                                    focusNode: focusNodes[student.id!],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: _scoreInputFormatters(
                                      maxScore,
                                    ),
                                    textAlign: TextAlign.center,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      suffix: Text(
                                        '/${maxScore.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      final controller =
                                          scoreControllers[student.id!];
                                      if (controller?.text == '0') {
                                        controller?.clear();
                                      }
                                    },
                                    onSubmitted: (value) {
                                      if (!ctx.mounted) return;

                                      final currentIndex = _students.indexWhere(
                                        (s) => s.id == student.id,
                                      );
                                      if (currentIndex != -1 &&
                                          currentIndex < _students.length - 1) {
                                        final nextStudent =
                                            _students[currentIndex + 1];
                                        final nextController =
                                            scoreControllers[nextStudent.id!];
                                        if (nextController?.text == '0') {
                                          nextController?.clear();
                                        }
                                        if (ctx.mounted) {
                                          focusNodes[nextStudent.id!]
                                              ?.requestFocus();
                                        }
                                      } else {
                                        if (ctx.mounted) {
                                          focusNodes[student.id!]?.unfocus();
                                        }
                                      }
                                    },
                                    onChanged: (value) {
                                      // Field value changed
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final now = DateTime.now().toIso8601String();
                            for (final student in _students) {
                              final scoreText = scoreControllers[student.id!]!
                                  .text
                                  .trim();
                              final score = double.tryParse(scoreText) ?? 0;
                              if (score < 0 || score > maxScore) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Invalid score for ${student.fullName}. Must be 0-${maxScore.toStringAsFixed(0)}.',
                                    ),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                                return;
                              }
                            }

                            for (final student in _students) {
                              final scoreText = scoreControllers[student.id!]!
                                  .text
                                  .trim();
                              final score = double.tryParse(scoreText) ?? 0;
                              final s = AssessmentScore(
                                assessmentId: assessmentId,
                                studentId: student.id!,
                                score: score,
                                recordedAt: now,
                                updatedAt: now,
                              );
                              await _gradingRepo.upsertAssessmentScore(s);
                            }
                            print(
                              '[GradesScreen] Saved bulk scores for ${_students.length} students',
                            );
                            if (!ctx.mounted) return;
                            // Defer disposal to the next frame so the sheet can finish
                            // closing before controllers are disposed.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              Navigator.pop(ctx, true);
                            });
                          },
                          child: Text('Save All Scores'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      // Defer disposal to the next frame to avoid disposing while the
      // bottom-sheet is still animating / rebuilding during swipe dismiss.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final f in focusNodes.values) {
          try {
            f.dispose();
          } catch (_) {}
        }
        if (existingControllers == null) {
          for (final c in scoreControllers.values) {
            try {
              c.dispose();
            } catch (_) {}
          }
        }
      });
    }

    return result;
  }

  Future<bool?> _showSequentialScoreEntry({
    required int assessmentId,
    required String title,
    required double maxScore,
  }) async {
    int currentIndex = 0;
    final now = DateTime.now().toIso8601String();

    while (currentIndex < _students.length) {
      final student = _students[currentIndex];
      final scoreCtrl = TextEditingController();

      try {
        final result = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Student ${currentIndex + 1} of ${_students.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: scoreCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: _scoreInputFormatters(maxScore),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Score',
                      hintText: '0',
                      suffix: Text(
                        '/${maxScore.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (currentIndex > 0)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'back'),
                    child: Text('Back'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final score = double.tryParse(scoreCtrl.text) ?? 0;
                    if (score < 0 || score > maxScore) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Score must be between 0 and ${maxScore.toStringAsFixed(0)}.',
                          ),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, scoreCtrl.text);
                  },
                  child: Text(
                    currentIndex == _students.length - 1 ? 'Finish' : 'Next',
                  ),
                ),
              ],
            );
          },
        );

        if (result == 'cancel') {
          return false;
        } else if (result == 'back') {
          currentIndex--;
        } else if (result != null) {
          final score = double.tryParse(result) ?? 0;
          final s = AssessmentScore(
            assessmentId: assessmentId,
            studentId: student.id!,
            score: score,
            recordedAt: now,
            updatedAt: now,
          );
          await _gradingRepo.upsertAssessmentScore(s);
          print(
            '[GradesScreen] Saved sequential score for student=${student.id} score=$score',
          );
          currentIndex++;
        }
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            scoreCtrl.dispose();
          } catch (_) {}
        });
      }
    }

    return true;
  }

  double _computePeriodGrade(int studentId) {
    // Excel formula (teacher grades):
    // =IF(OR(U17="",X17=""),"",IF(ROUND((100-((5/8)*(100-SUM(U17,X17)))),0)>70,
    //   ROUND((100-((5/8)*(100-SUM(U17,X17)))),0),70))
    // Where:
    // - U17 = SUM of all category averages aside from Exam
    // - X17 = AVERAGE of Exam category averages
    //
    // In-app mapping:
    // - "category average" here uses the weighted contribution per category (same values shown on the cards)
    //   i.e. (categoryPercentage * (weight/100)).

    double uSumNonExam = 0;
    final examAverages = <double>[];

    for (final cat in _categories) {
      try {
        final assessments = _assessmentsByCategory[cat.id!] ?? [];
        if (assessments.isEmpty) continue;

        final catAvg = _computeCategoryWeightedGrade(studentId, cat);
        final isExam = cat.name.toLowerCase().contains('exam');

        if (isExam) {
          examAverages.add(catAvg);
        } else {
          uSumNonExam += catAvg;
        }
      } catch (e) {
        print(
          '[GradesScreen] Error calculating period formula parts for category ${cat.id}: $e',
        );
        continue;
      }
    }

    final xExamAvg = examAverages.isEmpty
        ? 0.0
        : (examAverages.reduce((a, b) => a + b) / examAverages.length);

    // Mirror the Excel blank checks.
    if (uSumNonExam <= 0 || xExamAvg <= 0) {
      print(
        '[GradesScreen] Period grade: missing U/X (U=$uSumNonExam, X=$xExamAvg) for studentId=$studentId',
      );
      return 0.0;
    }

    final sumUx = uSumNonExam + xExamAvg;
    final raw = 100 - ((5 / 8) * (100 - sumUx));
    final rounded = raw.roundToDouble();

    // Excel enforces minimum 70.
    final minApplied = rounded > 70 ? rounded : 70.0;

    // Prevent impossible >100 outputs (e.g. if U/X already include weights and sum > 100).
    final clamped = minApplied.clamp(0.0, 100.0).toDouble();

    print(
      '[GradesScreen] Period grade formula studentId=$studentId U=$uSumNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$clamped',
    );

    return clamped;
  }

  Map<int, double> _computeAllCategoryWeightedGrades(int studentId) {
    final weightedGrades = <int, double>{};

    for (final cat in _categories) {
      weightedGrades[cat.id!] = _computeCategoryWeightedGrade(studentId, cat);
    }

    return weightedGrades;
  }

  double _computeCategoryWeightedGrade(
    int studentId,
    GradingCategory category,
  ) {
    try {
      // Get cached assessments for this category
      final assessments = _assessmentsByCategory[category.id!] ?? [];

      if (assessments.isEmpty) return 0.0;

      // Sum all student scores and all perfect scores for this category
      double totalStudentScore = 0;
      double totalPerfectScore = 0;

      for (final assessment in assessments) {
        // Get cached scores for this assessment
        final scores = _scoresByAssessment[assessment.id!] ?? [];
        final studentScore = scores.firstWhere(
          (s) => s.studentId == studentId,
          orElse: () => AssessmentScore(
            assessmentId: assessment.id!,
            studentId: studentId,
            score: 0,
            recordedAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );

        totalStudentScore += studentScore.score;
        totalPerfectScore += assessment.maxScore;
      }

      // Calculate category percentage: (sum of student scores ÷ sum of perfect scores) × 100
      if (totalPerfectScore > 0) {
        final categoryPercentage =
            (totalStudentScore / totalPerfectScore) * 100;
        // Apply category weight to get weighted average
        return categoryPercentage * (category.weight / 100);
      }
    } catch (e) {
      print(
        '[GradesScreen] Error calculating weighted grade for category ${category.id}: $e',
      );
    }

    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Grades',
            subtitle: widget.classModel.displayName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              if (_selectedPeriod != null && _categories.isNotEmpty)
                Stack(
                  children: [
                    IconButton(
                      onPressed: _showTaskManagement,
                      icon: Icon(PlatformIcons.assignment, color: Colors.white),
                      tooltip: 'Manage Tasks',
                    ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadAllTasks(),
                      builder: (ctx, snapshot) {
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final tasks = snapshot.data!;
                          final incompleteTasks = tasks.where((task) {
                            final completedCount =
                                task['completedCount'] as int;
                            return completedCount < _students.length;
                          }).length;

                          // Only show badge if there are incomplete tasks
                          if (incompleteTasks > 0) {
                            return Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$incompleteTasks',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          StudentRecordsScreen(classModel: widget.classModel),
                    ),
                  );
                },
                icon: Icon(PlatformIcons.tableChart, color: Colors.white),
                tooltip: 'View Table',
              ),
            ],
          ),
          // Scrollable Grades Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _periods.isEmpty
                ? const Center(
                    child: Text(
                      'No grading periods set up.\nGo to Grading Periods first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  )
                : _students.isEmpty
                ? const Center(
                    child: Text(
                      'No students enrolled.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  )
                : _categories.isEmpty
                ? const Center(
                    child: Text(
                      'No grade categories configured.\nSet up categories in Grading Periods.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      child: Column(
                        children: [
                          // Period Info Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.divider),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: gradientColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    PlatformIcons.dateRange,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Grading Period',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _selectedPeriod?.name ?? 'No Period',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_selectedPeriod?.isActive == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.success.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.success.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.success,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.textSecondary
                                            .withValues(alpha: 0.20),
                                      ),
                                    ),
                                    child: const Text(
                                      'INACTIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.textSecondary,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                if (_selectedPeriod?.isLocked == true) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.danger.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'LOCKED',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.danger,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Student Grade Cards
                          ...List.generate(
                            _students.length,
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _StudentGradeCard(
                                student: _students[i],
                                categories: _categories,
                                grades: _grades[_students[i].id!] ?? {},
                                weightedGrades:
                                    _computeAllCategoryWeightedGrades(
                                      _students[i].id!,
                                    ),
                                periodGrade: _computePeriodGrade(
                                  _students[i].id!,
                                ),
                                gradingSystem: _gradingSystem,
                                eqTable: _eqTable,
                                isLocked: _selectedPeriod?.isLocked ?? false,
                                onEdit: (cat) => _editGrade(_students[i], cat),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton:
          _selectedPeriod != null &&
              !(_selectedPeriod!.isLocked) &&
              _categories.isNotEmpty &&
              _students.isNotEmpty
          ? FloatingActionButton(
              onPressed: _openBulkScoreRecording,
              backgroundColor: themeProvider.primaryColor,
              child: Icon(PlatformIcons.editNote, color: Colors.white),
            )
          : null,
      bottomNavigationBar: _BottomNav(
        selectedIndex: 2,
        items: _navItems,
        onTap: (i) {
          if (i == 2) {
            Navigator.maybePop(context);
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => HomeScreen(initialIndex: i)),
              (route) => false,
            );
          }
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> items;
  final void Function(int) onTap;

  const _BottomNav({
    required this.selectedIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Material(
          color: Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 70,
                child: Row(
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final selected = selectedIndex == i;
                    return Expanded(
                      child: InkWell(
                        onTap: () => onTap(i),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? LinearGradient(
                                          colors: [primary, secondary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: selected ? null : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFFB0BAC9),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selected
                                      ? primary
                                      : const Color(0xFFB0BAC9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _MaxValueTextInputFormatter extends TextInputFormatter {
  final double maxValue;

  _MaxValueTextInputFormatter({required this.maxValue});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty || text == '.') return newValue;

    final value = double.tryParse(text);
    if (value == null) return oldValue;

    double clamped = value;
    if (clamped < 0) clamped = 0;
    if (clamped > maxValue) clamped = maxValue;

    if (clamped == value) return newValue;

    final isInt = clamped % 1 == 0;
    final newText = isInt ? clamped.toStringAsFixed(0) : clamped.toString();
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class _StudentGradeCard extends StatelessWidget {
  final Student student;
  final List<GradingCategory> categories;
  final Map<int, Grade> grades;
  final Map<int, double> weightedGrades;
  final double periodGrade;
  final GradingSystemConfig gradingSystem;
  final GradeEquivalencyTable eqTable;
  final bool isLocked;
  final void Function(GradingCategory) onEdit;

  const _StudentGradeCard({
    required this.student,
    required this.categories,
    required this.grades,
    required this.weightedGrades,
    required this.periodGrade,
    required this.gradingSystem,
    required this.eqTable,
    required this.isLocked,
    required this.onEdit,
  });

  Color _gradeColor(double g) {
    if (g >= 90) return AppTheme.success;
    if (g >= 75) return AppTheme.primary;
    return AppTheme.danger;
  }

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
      } else if (photoData.length > 100) {
        // Try to detect if it's valid base64 by checking characters
        try {
          base64Decode(photoData);
          isBase64 = true;
        } catch (e) {
          isBase64 = false;
        }
      }

      if (!isBase64 && !kIsWeb) {
        hasFilePhoto = File(photoData).existsSync();
      }
    }

    final hasPhoto = isBase64 || hasFilePhoto;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primary, secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: hasPhoto
                        ? Builder(
                            builder: (context) {
                              if (isBase64) {
                                try {
                                  String base64String;
                                  if (photoData.startsWith('data:image/')) {
                                    base64String = photoData.split(',').last;
                                  } else {
                                    base64String = photoData;
                                  }

                                  final bytes = base64Decode(base64String);

                                  return Image.memory(
                                    bytes,
                                    fit: BoxFit.cover,
                                    width: 36,
                                    height: 36,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          initials,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                } catch (e) {
                                  return Center(
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                final file = File(photoData);
                                return Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  width: 36,
                                  height: 36,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
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
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    student.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _gradeColor(periodGrade).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Builder(
                        builder: (context) {
                          if (periodGrade <= 0) {
                            return const Text(
                              '—',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            );
                          }

                          final eq = eqTable.convertPercentageToNumerical(
                            periodGrade,
                          );
                          final desc = eqTable.getDescriptor(periodGrade);
                          final value = eq != null
                              ? '${periodGrade.toStringAsFixed(1)}% • ${eq.toStringAsFixed(2)}'
                              : '${periodGrade.toStringAsFixed(1)}%';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                value,
                                style: TextStyle(
                                  color: _gradeColor(periodGrade),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if ((desc ?? '').trim().isNotEmpty)
                                Text(
                                  desc!.trim(),
                                  style: TextStyle(
                                    color: _gradeColor(
                                      periodGrade,
                                    ).withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((cat) {
                final grade = grades[cat.id!];
                final hasValue = grade != null && grade.maxScore > 0;
                final Grade? g = hasValue ? grade : null;
                final pct = g != null ? (g.score / g.maxScore) * 100 : null;

                // Get weighted grade for this category
                final weightedGrade = weightedGrades[cat.id!] ?? 0.0;

                return SizedBox(
                  width: 100,
                  height: 82,
                  child: InkWell(
                    onTap: isLocked ? null : () => onEdit(cat),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            hasValue
                                ? '${g!.score.toStringAsFixed(0)}/${g.maxScore.toStringAsFixed(0)}'
                                : '—',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: hasValue
                                  ? AppTheme.textPrimary
                                  : AppTheme.textLight,
                            ),
                          ),
                          Text(
                            hasValue && weightedGrade > 0
                                ? '${weightedGrade.toStringAsFixed(1)}'
                                : '',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: hasValue && weightedGrade > 0
                                  ? AppTheme.primary
                                  : AppTheme.textLight,
                            ),
                          ),
                          Text(
                            pct != null ? '${pct.toStringAsFixed(0)}%' : '',
                            style: TextStyle(
                              fontSize: 8,
                              color: pct != null
                                  ? _gradeColor(pct)
                                  : Colors.transparent,
                            ),
                          ),
                          Text(
                            '${cat.weight.toStringAsFixed(0)}% wt',
                            style: const TextStyle(
                              fontSize: 7,
                              color: AppTheme.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom dialog widget that properly manages TextEditingController lifecycle
class _TaskCreationDialog extends StatefulWidget {
  final List<GradingCategory> categories;

  const _TaskCreationDialog({required this.categories});

  @override
  State<_TaskCreationDialog> createState() => _TaskCreationDialogState();
}

class _TaskCreationDialogState extends State<_TaskCreationDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _maxScoreController;
  GradingCategory? _selectedCategory;
  String _selectedMode = 'bulk';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _maxScoreController = TextEditingController(text: '100');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _maxScoreController.dispose();
    super.dispose();
  }

  void _createTask() {
    final title = _titleController.text.trim();
    final maxScore = double.tryParse(_maxScoreController.text.trim()) ?? 0;

    if (title.isEmpty || _selectedCategory == null || maxScore <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    Navigator.of(context).pop({
      'title': title,
      'categoryId': _selectedCategory!.id!,
      'maxScore': maxScore,
      'mode': _selectedMode,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Create Grading Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Quiz 1',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<GradingCategory>(
              value: _selectedCategory,
              icon: Icon(PlatformIcons.dropdown),
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat.name));
              }).toList(),
              onChanged: (cat) {
                setState(() => _selectedCategory = cat);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxScoreController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Maximum Score',
                hintText: '100',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Entry Mode',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Bulk Entry'),
                    value: 'bulk',
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('One-by-One'),
                    value: 'individual',
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _createTask, child: const Text('Next')),
      ],
    );
  }
}

// Custom dialog widget for renaming tasks
class _RenameTaskDialog extends StatefulWidget {
  final String currentName;

  const _RenameTaskDialog({required this.currentName});

  @override
  State<_RenameTaskDialog> createState() => _RenameTaskDialogState();
}

class _RenameTaskDialogState extends State<_RenameTaskDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _rename() {
    final newName = _nameController.text.trim();
    Navigator.of(context).pop(newName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Rename Task'),
      content: TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Task name',
          hintText: 'Quiz 1',
        ),
        onSubmitted: (_) => _rename(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _rename, child: const Text('Save')),
      ],
    );
  }
}
