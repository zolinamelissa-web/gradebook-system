import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/intervention_model.dart';
import '../../data/models/grade_equivalency.dart';
import '../../data/models/grading_system_config.dart';
import '../../data/repositories/intervention_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../home/home_screen.dart';
import '../../data/repositories/risk_repository.dart';
import '../../data/repositories/grading_repository.dart';

class InterventionScreen extends StatefulWidget {
  final ClassModel classModel;
  final Student student;

  const InterventionScreen({
    super.key,
    required this.classModel,
    required this.student,
  });

  @override
  State<InterventionScreen> createState() => _InterventionScreenState();
}

class _InterventionScreenState extends State<InterventionScreen> {
  final InterventionRepository _repo = InterventionRepository();
  final RiskRepository _riskRepo = RiskRepository();
  final GradingRepository _gradingRepo = GradingRepository();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  List<Intervention> _interventions = [];
  List<Map<String, dynamic>> _counselingReasons = [];
  List<Map<String, dynamic>> _failingSubjects = [];
  Map<String, dynamic>? _riskSummary;
  String? _periodName;
  double? _subjectPeriodGrade;
  bool? _isSubjectFailing;
  bool _isSubjectNearFailing = false;
  double? _subjectEquivalentGrade;
  String? _subjectEquivalentDescriptor;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      await _loadCounselingReasons();

      final list = await _repo.getInterventionsByStudent(
        studentId: widget.student.id!,
        classId: widget.classModel.id!,
      );
      print('[InterventionScreen] Loaded ${list.length} interventions');

      final risk = await _riskRepo.getLatestRiskFlagForStudent(
        studentId: widget.student.id!,
        classId: widget.classModel.id!,
      );
      print(
        '[InterventionScreen] Loaded risk summary: ${risk == null ? 'none' : (risk['risk_level'] ?? '-')}',
      );

      final periodIdFromRisk = (risk?['grading_period_id'] as num?)?.toInt();
      final periods = await _gradingRepo.getPeriodsByClass(
        widget.classModel.id!,
      );
      final activePeriod = periods.where((p) => p.isActive).isNotEmpty
          ? periods.firstWhere((p) => p.isActive)
          : (periods.isNotEmpty ? periods.first : null);
      final selectedPeriodId = periodIdFromRisk ?? activePeriod?.id;
      final selectedPeriod = selectedPeriodId == null
          ? null
          : await _gradingRepo.getPeriodById(selectedPeriodId);

      if (selectedPeriod != null) {
        print(
          '[InterventionScreen] Selected period for performance: ${selectedPeriod.name} (id=${selectedPeriod.id})',
        );
      } else {
        print('[InterventionScreen] No grading period found for performance');
      }

      final gradingSystem = await _loadGradingSystem();
      final eqTable = await _loadEquivalencyTable(gradingSystem);
      final subjectGrade = selectedPeriodId == null
          ? null
          : await _gradingRepo.computeStudentPeriodGrade(
              studentId: widget.student.id!,
              classId: widget.classModel.id!,
              periodId: selectedPeriodId,
            );

      // Equivalency: below 75 is Failed.
      final subjectFailing = subjectGrade == null
          ? null
          : _isFailedByEquivalencyPercent(subjectGrade);
      final subjectNearFailing = subjectGrade == null
          ? false
          : _isNearFailingByEquivalencyPercent(subjectGrade);

      final subjectEq = subjectGrade == null
          ? null
          : (eqTable.isEmpty
                ? null
                : eqTable.convertPercentageToNumerical(subjectGrade));
      final subjectEqDesc = subjectGrade == null
          ? null
          : (eqTable.isEmpty ? null : eqTable.getDescriptor(subjectGrade));

      print(
        '[InterventionScreen] Subject grade: $subjectGrade, equivalent: $subjectEq, descriptor: $subjectEqDesc',
      );

      // Get failing subjects information
      final failingSubjects = await _getFailingSubjects(
        periodId: selectedPeriodId,
      );
      print(
        '[InterventionScreen] Loaded ${failingSubjects.length} failing subjects',
      );

      if (mounted) {
        setState(() {
          _interventions = list;
          _failingSubjects = failingSubjects;
          _riskSummary = risk;
          _periodName = selectedPeriod?.name;
          _subjectPeriodGrade = subjectGrade;
          _isSubjectFailing = subjectFailing;
          _isSubjectNearFailing = subjectNearFailing;
          _subjectEquivalentGrade = subjectEq;
          _subjectEquivalentDescriptor = subjectEqDesc;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[InterventionScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCounselingReasons() async {
    try {
      final teacherUid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (teacherUid == null || teacherUid.trim().isEmpty) {
        print('[InterventionScreen] Counseling reasons skipped: not logged in');
        _counselingReasons = const [];
        return;
      }

      final db = await DatabaseHelper.instance.database;
      final classRows = await db.query(
        'classes',
        columns: ['remote_id'],
        where: 'id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [widget.classModel.id!],
        limit: 1,
      );
      final classRemoteId =
          (classRows.isNotEmpty ? classRows.first['remote_id'] : null)
              ?.toString()
              .trim() ??
          '';
      if (classRemoteId.isEmpty) {
        print(
          '[InterventionScreen] Counseling reasons skipped: missing local classes.remote_id classId=${widget.classModel.id}',
        );
        _counselingReasons = const [];
        return;
      }

      final studentId = widget.student.studentId.trim();
      if (studentId.isEmpty) {
        print(
          '[InterventionScreen] Counseling reasons skipped: missing widget.student.studentId localStudentPk=${widget.student.id}',
        );
        _counselingReasons = const [];
        return;
      }

      final rows = await db.query(
        'counseling_reasons',
        where:
            'teacher_uid = ? AND class_remote_id = ? AND student_id = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [teacherUid, classRemoteId, studentId],
        orderBy: 'created_at DESC',
      );

      _counselingReasons = rows;
      print(
        '[InterventionScreen] Counseling reasons loaded count=${rows.length} teacherUid=$teacherUid classId=${widget.classModel.id} classRemoteId=$classRemoteId studentId=$studentId',
      );
    } catch (e) {
      print('[InterventionScreen] Counseling reasons load error: $e');
      _counselingReasons = const [];
    }
  }

  Future<GradingSystemConfig> _loadGradingSystem() async {
    final gradingSystemJson = await DatabaseHelper.instance.getSetting(
      'grading_system',
    );
    GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
    if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
      try {
        final config = jsonDecode(gradingSystemJson) as Map<String, dynamic>;
        gradingSystem = GradingSystemConfig.fromJson(config);
      } catch (e) {
        print('[InterventionScreen] Error parsing grading system: $e');
      }
    }
    return gradingSystem;
  }

  Future<GradeEquivalencyTable> _loadEquivalencyTable(
    GradingSystemConfig gradingSystem,
  ) async {
    final eqJson = await DatabaseHelper.instance.getSetting(
      'grade_equivalency_table',
    );
    print('[InterventionScreen] Equivalency table JSON: ${eqJson ?? 'null'}');
    GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
      equivalencies: [],
    );

    if (eqJson != null && eqJson.isNotEmpty) {
      try {
        eqTable = GradeEquivalencyTable.fromJson(
          jsonDecode(eqJson) as Map<String, dynamic>,
        );
        print(
          '[InterventionScreen] Loaded equivalency table with ${eqTable.equivalencies.length} entries',
        );
      } catch (e) {
        print('[InterventionScreen] Error parsing equivalency table: $e');
      }
    }

    // If no table configured, use defaults similar to StudentRecordsScreen.
    if (eqTable.isEmpty) {
      print(
        '[InterventionScreen] Using default equivalency table for ${gradingSystem.type}',
      );
      if (gradingSystem.type == GradingSystemType.college4point0) {
        eqTable = GradeEquivalencyTable.depedTo4point0;
      } else if (gradingSystem.type == GradingSystemType.college1to5) {
        eqTable = GradeEquivalencyTable.depedTo1to5;
      }
    }
    return eqTable;
  }

  bool _isFailedByEquivalencyPercent(double percent) {
    return percent < 75.0;
  }

  bool _isNearFailingByEquivalencyPercent(double percent) {
    return percent >= 75.0 && percent < 80.0;
  }

  bool _isFailingBySystem(double score, GradingSystemConfig cfg) {
    final isCollege =
        cfg.type == GradingSystemType.college1to5 ||
        cfg.type == GradingSystemType.college4point0;

    // computeStudentPeriodGrade returns a percentage grade.
    // If the grading system is college but the score looks like a percentage,
    // treat it as percentage.
    final looksLikePercent = score > cfg.maxScore + 0.01;
    if (isCollege && !looksLikePercent) {
      return score > cfg.passingScore;
    }
    return score < cfg.passingScore;
  }

  Color _riskColor(String level) {
    if (level == 'high') return AppTheme.danger;
    if (level == 'medium') return AppTheme.warning;
    return AppTheme.success;
  }

  Widget _buildRiskSummarySection() {
    final risk = _riskSummary;
    final level = (risk?['risk_level'] as String?)?.trim() ?? 'low';
    final color = _riskColor(level);
    final grade = (risk?['grade_score'] as num?)?.toDouble();
    final att = (risk?['attendance_percentage'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PlatformIcons.info, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Risk Summary',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  level.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Grade: ${grade == null ? '-' : grade.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Attendance: ${att == null ? '-' : '${att.toStringAsFixed(0)}%'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (risk == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No risk record found for this student yet. Open Risk screen to compute it for the current period.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getFailingSubjects({
    int? periodId,
  }) async {
    try {
      if (periodId == null) return [];

      // Get categories for the period
      final categories = await _gradingRepo
          .getCategoriesWithAssessmentsInPeriod(periodId);
      print(
        '[InterventionScreen] Found ${categories.length} categories with assessments',
      );
      for (final cat in categories) {
        print(
          '[InterventionScreen] Category: id=${cat.id}, name="${cat.name}"',
        );
      }
      final gradingSystem = await _loadGradingSystem();

      // Identify failing subjects using assessment totals (true category percentage)
      final byCategory = <String, Map<String, dynamic>>{};
      for (final category in categories) {
        // Get detailed assessment info for debugging
        final hasItems = await _gradingRepo.hasAssessments(
          classId: widget.classModel.id!,
          periodId: periodId,
          categoryId: category.id!,
        );
        print(
          '[InterventionScreen] Category "${category.name}" has assessments: $hasItems',
        );

        final totals = await _gradingRepo.getEffectiveCategoryTotal(
          studentId: widget.student.id!,
          classId: widget.classModel.id!,
          periodId: periodId,
          categoryId: category.id!,
        );
        final score = totals.score;
        final maxScore = totals.maxScore;
        if (maxScore <= 0) continue;

        final percentage = (score / maxScore) * 100;
        print(
          '[InterventionScreen] FailingSubject calc cat=${category.name.trim()} score=$score max=$maxScore weight=${category.weight} pct=${percentage.toStringAsFixed(2)} hasAssessments=$hasItems',
        );

        final isFailing = _isFailingBySystem(percentage, gradingSystem);

        if (isFailing) {
          final name = category.name.trim();
          print(
            '[InterventionScreen] Failing subject category name: "$name" (raw: "${category.name}")',
          );
          final current = byCategory[name];
          final row = {
            'category_name': name,
            'score': score,
            'maxScore': maxScore,
            'percentage': percentage,
            'isFailing': true,
          };

          // Keep the WORST (lowest) percentage for this category.
          if (current == null) {
            byCategory[name] = row;
          } else {
            final currentPct = (current['percentage'] as num?)?.toDouble() ?? 0;
            if (percentage < currentPct) {
              byCategory[name] = row;
            }
          }
        }
      }

      final failingSubjects = byCategory.values.toList();
      failingSubjects.sort((a, b) {
        final ap = (a['percentage'] as num?)?.toDouble() ?? 0;
        final bp = (b['percentage'] as num?)?.toDouble() ?? 0;
        return ap.compareTo(bp);
      });
      return failingSubjects;
    } catch (e) {
      print('[InterventionScreen] Error getting failing subjects: $e');
      return [];
    }
  }

  Widget _buildSubjectPerformanceSection() {
    final subjectLabel = widget.classModel.subject == null
        ? widget.classModel.displayName
        : '${widget.classModel.subject!.code} - ${widget.classModel.subject!.name}';
    final grade = _subjectPeriodGrade;
    final isFailing = _isSubjectFailing;
    final nearFailing = _isSubjectNearFailing;
    final eq = _subjectEquivalentGrade;
    final eqDesc = _subjectEquivalentDescriptor;

    Color accent = AppTheme.success;
    String badge = 'PASSED';
    if (isFailing == true) {
      accent = AppTheme.danger;
      badge = 'FAILING';
    } else if (nearFailing) {
      accent = AppTheme.warning;
      badge = 'NEAR FAIL';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PlatformIcons.school, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Subject Performance${_periodName == null ? '' : ' (${_periodName!})'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subjectLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Grade: ${grade == null ? '-' : grade.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          if (grade != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Equivalent: ${eq == null ? '-' : eq.toStringAsFixed(2)}${eqDesc == null || eqDesc.trim().isEmpty ? '' : ' ($eqDesc)'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          if (grade == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No grade computed yet for this period. Add assessments/scores or open Risk screen to recompute.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addIntervention() async {
    await _showForm();
  }

  Future<void> _showForm({Intervention? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final followUpCtrl = TextEditingController(
      text: existing?.followUpDate ?? '',
    );
    String selectedDate =
        existing?.interventionDate ??
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    String selectedStatus = existing?.status ?? 'open';

    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        existing == null
                            ? 'Add Intervention'
                            : 'Edit Intervention',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: Icon(PlatformIcons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.student.fullName,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Title *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Academic Counseling',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Description *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Describe the intervention...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Date',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: DateTime.parse(selectedDate),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (d != null) {
                                  setModalState(
                                    () => selectedDate = DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(d),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppTheme.divider),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      PlatformIcons.calendar,
                                      size: 16,
                                      color: AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      selectedDate,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (existing != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: selectedStatus,
                                icon: Icon(PlatformIcons.dropdown),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'open',
                                    child: Text('Open'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'in_progress',
                                    child: Text('In Progress'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'resolved',
                                    child: Text('Resolved'),
                                  ),
                                ],
                                onChanged: (v) => setModalState(
                                  () => selectedStatus = v ?? 'open',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Follow-up Date (optional)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      DateTime initial = DateTime.now();
                      final v = followUpCtrl.text.trim();
                      if (v.isNotEmpty) {
                        try {
                          initial = DateTime.parse(v);
                        } catch (_) {}
                      }
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: initial,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setModalState(() {
                          followUpCtrl.text = DateFormat(
                            'yyyy-MM-dd',
                          ).format(d);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            PlatformIcons.event,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              followUpCtrl.text.trim().isEmpty
                                  ? 'Select date'
                                  : followUpCtrl.text.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                color: followUpCtrl.text.trim().isEmpty
                                    ? AppTheme.textSecondary
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (followUpCtrl.text.trim().isNotEmpty)
                            InkWell(
                              onTap: () {
                                setModalState(() {
                                  followUpCtrl.clear();
                                });
                              },
                              child: Icon(
                                PlatformIcons.close,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (titleCtrl.text.trim().isEmpty ||
                            descCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Title and description are required.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        existing == null ? 'Add Intervention' : 'Save Changes',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (result == true) {
        final now = DateTime.now().toIso8601String();
        if (existing != null) {
          final updated = Intervention(
            id: existing.id,
            studentId: existing.studentId,
            classId: existing.classId,
            gradingPeriodId: existing.gradingPeriodId,
            title: titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
            interventionDate: selectedDate,
            followUpDate: followUpCtrl.text.trim().isEmpty
                ? null
                : followUpCtrl.text.trim(),
            status: selectedStatus,
            createdAt: existing.createdAt,
            updatedAt: now,
          );
          await _repo.updateIntervention(updated);
          print('[InterventionScreen] Updated intervention id=${existing.id}');
        } else {
          final intervention = Intervention(
            studentId: widget.student.id!,
            classId: widget.classModel.id!,
            title: titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
            interventionDate: selectedDate,
            followUpDate: followUpCtrl.text.trim().isEmpty
                ? null
                : followUpCtrl.text.trim(),
            createdAt: now,
            updatedAt: now,
          );
          await _repo.insertIntervention(intervention);
          print('[InterventionScreen] Added new intervention');
        }
        _load();
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleCtrl.dispose();
        descCtrl.dispose();
        followUpCtrl.dispose();
      });
    }
  }

  Future<void> _delete(Intervention intervention) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Intervention'),
        content: Text('Delete "${intervention.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.deleteIntervention(intervention.id!);
      _load();
    }
  }

  Widget _buildFailingSubjectsSection() {
    if (_failingSubjects.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PlatformIcons.warning, color: AppTheme.danger, size: 20),
              const SizedBox(width: 8),
              Text(
                'Failing Categories',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: (_failingSubjects.length / 2).ceil() * 84.0,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              itemCount: _failingSubjects.length,
              itemBuilder: (_, i) {
                final subject = _failingSubjects[i];
                final name = (subject['category_name'] as String?) ?? 'Unknown';
                final score = (subject['score'] as num).toDouble();
                final maxScore = (subject['maxScore'] as num).toDouble();
                final pct = (subject['percentage'] as num).toDouble();
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${score.toStringAsFixed(1)}/${maxScore.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.danger,
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.danger.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
          WaveHeader(
            title: 'Interventions',
            subtitle: widget.student.fullName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _buildRiskSummarySection(),
                      _buildSubjectPerformanceSection(),
                      _buildFailingSubjectsSection(),
                      if (_counselingReasons.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Needs Counseling',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ..._counselingReasons.map((r) {
                                final subjectCode =
                                    (r['subject_code']?.toString() ?? '')
                                        .trim();
                                final reason = (r['reason']?.toString() ?? '')
                                    .trim();
                                final header = subjectCode.isNotEmpty
                                    ? subjectCode
                                    : 'Reason';
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger.withValues(
                                      alpha: 0.06,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.danger.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        header,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1A237E),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        reason,
                                        style: const TextStyle(
                                          color: Color(0xFF3C4B68),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                      Expanded(
                        child: _interventions.isEmpty
                            ? Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        PlatformIcons.editNote,
                                        size: 64,
                                        color: AppTheme.textLight.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No interventions recorded',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    100,
                                  ),
                                  itemCount: _interventions.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _InterventionCard(
                                    intervention: _interventions[i],
                                    onEdit: () =>
                                        _showForm(existing: _interventions[i]),
                                    onDelete: () => _delete(_interventions[i]),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addIntervention,
        backgroundColor: themeProvider.primaryColor,
        child: Icon(PlatformIcons.add, color: Colors.white),
      ),
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

class _InterventionCard extends StatelessWidget {
  final Intervention intervention;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InterventionCard({
    required this.intervention,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (intervention.status) {
      case 'resolved':
        return AppTheme.success;
      case 'in_progress':
        return AppTheme.warning;
      default:
        return AppTheme.primary;
    }
  }

  String get _statusLabel {
    switch (intervention.status) {
      case 'resolved':
        return 'Resolved';
      case 'in_progress':
        return 'In Progress';
      default:
        return 'Open';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  intervention.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            intervention.description,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                PlatformIcons.calendarToday,
                size: 12,
                color: AppTheme.textLight,
              ),
              const SizedBox(width: 6),
              Text(
                intervention.interventionDate,
                style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
              if (intervention.followUpDate != null) ...[
                const SizedBox(width: 12),
                Icon(PlatformIcons.event, size: 12, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Text(
                  'Follow-up: ${intervention.followUpDate}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
