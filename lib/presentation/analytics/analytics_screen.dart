import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/subject_model.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/risk_repository.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final SubjectRepository _subjectRepo = SubjectRepository();
  final GradingRepository _gradingRepo = GradingRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final AttendanceRepository _attRepo = AttendanceRepository();
  final RiskRepository _riskRepo = RiskRepository();

  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  List<GradingPeriod> _periods = [];
  GradingPeriod? _selectedPeriod;

  List<_StudentStat> _stats = [];
  double _classAverage = 0;
  int _atRiskCount = 0;
  bool _isLoading = false;
  bool _classesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _classesLoading = true);
    try {
      if (kIsWeb) {
        await _loadWebClasses();
      } else {
        final classes = await _subjectRepo.getAllClasses();
        print('[AnalyticsScreen] Loaded ${classes.length} classes');
        if (mounted) {
          setState(() {
            _classes = classes;
            _selectedClass = classes.firstOrNull;
            _classesLoading = false;
          });
          if (_selectedClass != null) {
            _loadPeriods();
          }
        }
      }
    } catch (e) {
      print('[AnalyticsScreen] Error loading classes: $e');
      if (mounted) setState(() => _classesLoading = false);
    }
  }

  Future<void> _loadWebClasses() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      print('[AnalyticsScreen] Web classes load skipped: no Firebase user');
      if (mounted) {
        setState(() {
          _classesLoading = false;
        });
      }
      return;
    }

    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/classes')
          .get();

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return ClassModel(
          id: int.tryParse(doc.id),
          subjectId: data['subject_id'] ?? 0,
          section: data['section'] ?? '',
          schoolYear: data['school_year'] ?? '',
          semester: data['semester'],
          room: data['room'],
          schedule: data['schedule'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
          subject: data['subject_name'] != null
              ? Subject(
                  id: data['subject_id'],
                  code: data['subject_code'] ?? 'SUBJ',
                  name: data['subject_name'],
                  createdAt:
                      data['created_at'] ?? DateTime.now().toIso8601String(),
                  updatedAt:
                      data['updated_at'] ?? DateTime.now().toIso8601String(),
                )
              : null,
        );
      }).toList();

      print('[AnalyticsScreen] Web loaded ${classes.length} classes');
      if (mounted) {
        setState(() {
          _classes = classes;
          _selectedClass = classes.firstOrNull;
          _classesLoading = false;
        });
        if (_selectedClass != null) {
          _loadPeriods();
        }
      }
    } catch (e) {
      print('[AnalyticsScreen] Error loading web classes: $e');
      if (mounted) {
        setState(() {
          _classesLoading = false;
        });
      }
    }
  }

  Future<void> _loadPeriods() async {
    if (_selectedClass == null) return;

    if (kIsWeb) {
      await _loadWebPeriods();
    } else {
      final periods = await _gradingRepo.getPeriodsByClass(_selectedClass!.id!);
      if (mounted) {
        setState(() {
          _periods = periods;
          _selectedPeriod =
              periods.where((p) => p.isActive).firstOrNull ??
              periods.firstOrNull;
        });
        if (_selectedPeriod != null) _loadAnalytics();
      }
    }
  }

  Future<void> _loadWebPeriods() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || _selectedClass == null) {
      print(
        '[AnalyticsScreen] Web periods load skipped: no Firebase user or class',
      );
      return;
    }

    try {
      final periodsSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/grading_periods')
          .where('class_id', isEqualTo: _selectedClass!.id)
          .get();

      final periods = periodsSnapshot.docs.map((doc) {
        final data = doc.data();
        return GradingPeriod(
          id: int.tryParse(doc.id),
          classId: data['class_id'] ?? 0,
          name: data['name'] ?? '',
          orderNum: data['order_num'] ?? 1,
          isActive: data['is_active'] ?? false,
          isLocked: data['is_locked'] ?? false,
          startDate: data['start_date'],
          endDate: data['end_date'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _periods = periods;
          _selectedPeriod =
              periods.where((p) => p.isActive).firstOrNull ??
              periods.firstOrNull;
        });
        if (_selectedPeriod != null) _loadAnalytics();
      }
    } catch (e) {
      print('[AnalyticsScreen] Error loading web periods: $e');
    }
  }

  Future<void> _loadAnalytics() async {
    if (_selectedClass == null || _selectedPeriod == null) return;
    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        await _loadWebAnalytics();
      } else {
        final students = await _studentRepo.getStudentsByClass(
          _selectedClass!.id!,
        );
        final studentIds = students.map((s) => s.id!).toList();
        final gradeMap = await _gradingRepo.computePeriodGradesTeacherFormula(
          classId: _selectedClass!.id!,
          periodId: _selectedPeriod!.id!,
          studentIds: studentIds,
        );
        final attMap = await _attRepo.getClassAttendancePercentages(
          classId: _selectedClass!.id!,
          periodId: _selectedPeriod!.id!,
          studentIds: studentIds,
        );

        final stats =
            students
                .map(
                  (s) => _StudentStat(
                    student: s,
                    grade: gradeMap[s.id] ?? 0,
                    attendance: attMap[s.id] ?? 100,
                  ),
                )
                .toList()
              ..sort((a, b) => b.grade.compareTo(a.grade));

        final gradesWithValue = stats.where((s) => s.grade > 0).toList();
        final avg = gradesWithValue.isEmpty
            ? 0.0
            : gradesWithValue.fold(0.0, (sum, s) => sum + s.grade) /
                  gradesWithValue.length;
        final atRisk = await _riskRepo.getAtRiskCount(_selectedClass!.id!);

        print(
          '[AnalyticsScreen] Analytics loaded: avg=${avg.toStringAsFixed(1)} atRisk=$atRisk students=${students.length}',
        );
        if (mounted) {
          setState(() {
            _stats = stats;
            _classAverage = avg;
            _atRiskCount = atRisk;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('[AnalyticsScreen] Error loading analytics: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWebAnalytics() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null ||
        _selectedClass == null ||
        _selectedPeriod == null) {
      print(
        '[AnalyticsScreen] Web analytics load skipped: missing user, class, or period',
      );
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Load students for the selected class
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/students')
          .where('class_id', isEqualTo: _selectedClass!.id)
          .get();

      final students = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Student(
          id: int.tryParse(doc.id),
          studentId: data['student_id'] ?? '',
          firstName: data['first_name'] ?? '',
          lastName: data['last_name'] ?? '',
          email: data['email'],
          createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
          updatedAt: data['updated_at'] ?? DateTime.now().toIso8601String(),
        );
      }).toList();

      final studentIds = students.map((s) => s.id!).toList();

      // Load grades for the selected period
      final gradesSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/grades')
          .where('class_id', isEqualTo: _selectedClass!.id)
          .where('period_id', isEqualTo: _selectedPeriod!.id)
          .get();

      final gradeMap = <String, double>{};
      for (final doc in gradesSnapshot.docs) {
        final data = doc.data();
        final studentId = data['student_id'] as String?;
        final score = (data['score'] as num?)?.toDouble() ?? 0.0;
        if (studentId != null) {
          gradeMap[studentId] = score;
        }
      }

      // Load attendance for the selected period
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/attendance')
          .where('class_id', isEqualTo: _selectedClass!.id)
          .where('period_id', isEqualTo: _selectedPeriod!.id)
          .get();

      final attMap = <String, double>{};
      for (final doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final studentId = data['student_id'] as String?;
        final percentage = (data['percentage'] as num?)?.toDouble() ?? 100.0;
        if (studentId != null) {
          attMap[studentId] = percentage;
        }
      }

      // Load at-risk count
      final riskSnapshot = await FirebaseFirestore.instance
          .collection('users/${firebaseUser.uid}/risk_flags')
          .where('class_id', isEqualTo: _selectedClass!.id)
          .get();
      final atRisk = riskSnapshot.docs.length;

      final stats =
          students
              .map(
                (s) => _StudentStat(
                  student: s,
                  grade: gradeMap[s.id] ?? 0,
                  attendance: attMap[s.id] ?? 100,
                ),
              )
              .toList()
            ..sort((a, b) => b.grade.compareTo(a.grade));

      final gradesWithValue = stats.where((s) => s.grade > 0).toList();
      final avg = gradesWithValue.isEmpty
          ? 0.0
          : gradesWithValue.fold(0.0, (sum, s) => sum + s.grade) /
                gradesWithValue.length;

      print(
        '[AnalyticsScreen] Web analytics loaded: avg=${avg.toStringAsFixed(1)} atRisk=$atRisk students=${students.length}',
      );
      if (mounted) {
        setState(() {
          _stats = stats;
          _classAverage = avg;
          _atRiskCount = atRisk;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[AnalyticsScreen] Error loading web analytics: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_StudentStat> get _topStudents =>
      _stats.where((s) => s.grade > 0).take(5).toList();
  List<_StudentStat> get _bottomStudents {
    final withGrades = _stats.where((s) => s.grade > 0).toList();
    return withGrades.reversed.take(5).toList();
  }

  Map<String, int> get _gradeDistribution {
    final dist = {
      '90-100': 0,
      '80-89': 0,
      '75-79': 0,
      '60-74': 0,
      'Below 60': 0,
    };
    for (final s in _stats.where((s) => s.grade > 0)) {
      if (s.grade >= 90) {
        dist['90-100'] = (dist['90-100'] ?? 0) + 1;
      } else if (s.grade >= 80) {
        dist['80-89'] = (dist['80-89'] ?? 0) + 1;
      } else if (s.grade >= 75) {
        dist['75-79'] = (dist['75-79'] ?? 0) + 1;
      } else if (s.grade >= 60) {
        dist['60-74'] = (dist['60-74'] ?? 0) + 1;
      } else {
        dist['Below 60'] = (dist['Below 60'] ?? 0) + 1;
      }
    }
    return dist;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: _classesLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Fixed Header with Wave
                WaveHeader(
                  title: 'Analytics',
                  subtitle: 'Performance Overview',
                  gradientColors: gradientColors,
                  actions: [
                    IconButton(
                      tooltip: 'Logout',
                      icon: Icon(PlatformIcons.logout, color: Colors.white),
                      onPressed: () => AuthService.signOutAndGoToLogin(context),
                    ),
                  ],
                  chips: _classes.isEmpty
                      ? null
                      : [
                          _buildClassSelector(),
                          if (_periods.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            _buildPeriodSelector(),
                          ],
                        ],
                ),
                // Scrollable Content
                Expanded(
                  child: _classes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PlatformIcons.analytics,
                                size: 72,
                                color: AppTheme.textLight.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No data to display',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create classes and enroll students to view analytics.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textLight,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          child: _isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SummaryRow(
                                      classAverage: _classAverage,
                                      totalStudents: _stats.length,
                                      atRiskCount: _atRiskCount,
                                    ),
                                    const SizedBox(height: 20),
                                    if (_stats.isNotEmpty &&
                                        _stats.any((s) => s.grade > 0)) ...[
                                      _SectionHeader('Grade Distribution'),
                                      const SizedBox(height: 12),
                                      _GradeDistributionChart(
                                        distribution: _gradeDistribution,
                                      ),
                                      const SizedBox(height: 20),
                                      _SectionHeader('Top 5 Performers'),
                                      const SizedBox(height: 12),
                                      ..._topStudents.asMap().entries.map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _RankRow(
                                            rank: e.key + 1,
                                            stat: e.value,
                                            isTop: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      _SectionHeader(
                                        'Needs Attention (Lowest 5)',
                                      ),
                                      const SizedBox(height: 12),
                                      ..._bottomStudents.asMap().entries.map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _RankRow(
                                            rank: _stats.length - e.key,
                                            stat: e.value,
                                            isTop: false,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      _SectionHeader('All Students'),
                                      const SizedBox(height: 12),
                                      _AllStudentsTable(stats: _stats),
                                    ] else
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: AppTheme.divider,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'No grade data available for this period.',
                                            style: TextStyle(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildClassSelector() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ClassModel>(
          value: _selectedClass,
          isExpanded: true,
          dropdownColor: primary,
          icon: Icon(PlatformIcons.dropdown, color: Colors.white),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          items: _classes
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(
                    c.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
              .toList(),
          onChanged: (c) {
            setState(() {
              _selectedClass = c;
              _periods = [];
              _stats = [];
            });
            _loadPeriods();
          },
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _periods.map((p) {
          final sel = _selectedPeriod?.id == p.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() => _selectedPeriod = p);
                _loadAnalytics();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.name,
                  style: TextStyle(
                    color: sel ? primary : Colors.white,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final double classAverage;
  final int totalStudents;
  final int atRiskCount;
  const _SummaryRow({
    required this.classAverage,
    required this.totalStudents,
    required this.atRiskCount,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _SummaryCard(
        value: classAverage > 0 ? '${classAverage.toStringAsFixed(1)}%' : '—',
        label: 'Class Average',
        icon: PlatformIcons.grade,
        color: classAverage >= 75
            ? AppTheme.success
            : classAverage > 0
            ? AppTheme.danger
            : AppTheme.textLight,
      ),
      const SizedBox(width: 10),
      _SummaryCard(
        value: '$totalStudents',
        label: 'Students',
        icon: PlatformIcons.people,
        color: AppTheme.primary,
      ),
      const SizedBox(width: 10),
      _SummaryCard(
        value: '$atRiskCount',
        label: 'At-Risk',
        icon: PlatformIcons.warning,
        color: atRiskCount > 0 ? AppTheme.danger : AppTheme.success,
      ),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _SummaryCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 17,
      color: AppTheme.textPrimary,
    ),
  );
}

class _GradeDistributionChart extends StatelessWidget {
  final Map<String, int> distribution;
  const _GradeDistributionChart({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppTheme.success,
      AppTheme.primary,
      AppTheme.secondary,
      AppTheme.warning,
      AppTheme.danger,
    ];
    final entries = distribution.entries.toList();
    final total = entries.fold(0, (sum, e) => sum + e.value);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY:
                    entries
                        .map((e) => e.value.toDouble())
                        .reduce((a, b) => a > b ? a : b) +
                    1,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final labels = ['90+', '80s', '75-79', '60-74', '<60'];
                        final idx = val.toInt();
                        if (idx >= 0 && idx < labels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              labels[idx],
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (val, meta) => Text(
                        val.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: AppTheme.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  entries.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: entries[i].value.toDouble(),
                        color: colors[i % colors.length],
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(
              entries.length,
              (i) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entries[i].key}: ${entries[i].value}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final _StudentStat stat;
  final bool isTop;
  const _RankRow({required this.rank, required this.stat, required this.isTop});

  Color _gradeColor(double g) {
    if (g >= 90) return AppTheme.success;
    if (g >= 75) return AppTheme.primary;
    if (g >= 60) return AppTheme.warning;
    return AppTheme.danger;
  }

  ImageProvider? _photoProvider() {
    final data = stat.student.photoPath;
    if (data == null || data.isEmpty) return null;
    try {
      final bytes = base64Decode(data);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (e) {
      print('[AnalyticsScreen] Invalid student photo, ignoring: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = '${stat.student.firstName[0]}${stat.student.lastName[0]}'
        .toUpperCase();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final gradientColors = themeProvider.getGradientColors();
    final photo = _photoProvider();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rank <= 3 && isTop
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: rank <= 3 && isTop
                    ? AppTheme.accent
                    : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: photo == null
                  ? LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              image: photo != null
                  ? DecorationImage(image: photo, fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: photo == null
                ? Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              stat.student.fullName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            stat.grade > 0 ? '${stat.grade.toStringAsFixed(1)}%' : '—',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: stat.grade > 0
                  ? _gradeColor(stat.grade)
                  : AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllStudentsTable extends StatelessWidget {
  final List<_StudentStat> stats;
  const _AllStudentsTable({required this.stats});

  Color _gradeColor(double g) {
    if (g >= 90) return AppTheme.success;
    if (g >= 75) return AppTheme.primary;
    if (g >= 60) return AppTheme.warning;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Student',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Grade',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Attend.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...stats.asMap().entries.map(
            (e) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          e.value.student.fullName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value.grade > 0
                              ? '${e.value.grade.toStringAsFixed(1)}%'
                              : '—',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: e.value.grade > 0
                                ? _gradeColor(e.value.grade)
                                : AppTheme.textLight,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${e.value.attendance.toStringAsFixed(0)}%',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: e.value.attendance >= 80
                                ? AppTheme.success
                                : AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (e.key < stats.length - 1) const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentStat {
  final Student student;
  final double grade;
  final double attendance;
  _StudentStat({
    required this.student,
    required this.grade,
    required this.attendance,
  });
}
