import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/grade_model.dart';
import '../../data/models/intervention_model.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/risk_repository.dart';
import '../../data/repositories/intervention_repository.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../home/home_screen.dart';
import '../interventions/intervention_screen.dart';

class RiskScreen extends StatefulWidget {
  final ClassModel classModel;

  const RiskScreen({super.key, required this.classModel});

  @override
  State<RiskScreen> createState() => _RiskScreenState();
}

class _RiskScreenState extends State<RiskScreen> {
  final GradingRepository _gradingRepo = GradingRepository();
  final AttendanceRepository _attRepo = AttendanceRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final RiskRepository _riskRepo = RiskRepository();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  List<GradingPeriod> _periods = [];
  GradingPeriod? _selectedPeriod;
  List<_StudentRisk> _risks = [];
  List<Map<String, dynamic>> _counselingReasons = const [];
  bool _isLoading = true;
  double _gradeThreshold = 75;
  double _attendanceThreshold = 80;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
  }

  Future<void> _loadThresholds() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final db = DatabaseHelper.instance;
      final g = await db.getSetting('grade_threshold');
      final a = await db.getSetting('attendance_threshold');
      if (!mounted) return;
      setState(() {
        _gradeThreshold = double.tryParse(g ?? '75') ?? 75;
        _attendanceThreshold = double.tryParse(a ?? '80') ?? 80;
      });
      await _loadPeriods();
    } catch (e) {
      print('[RiskScreen] Error loading thresholds: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPeriods() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final periods = await _gradingRepo.getPeriodsByClass(
        widget.classModel.id!,
      );
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
      print('[RiskScreen] Error loading grading periods: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_selectedPeriod == null) return;
    setState(() => _isLoading = true);
    try {
      final students = await _studentRepo.getStudentsByClass(
        widget.classModel.id!,
      );
      print(
        '[RiskScreen] Loaded ${students.length} students for classId=${widget.classModel.id}',
      );
      final studentIds = students.map((s) => s.id!).toList();

      if (students.isEmpty) {
        try {
          final db = await DatabaseHelper.instance.database;
          final csCount =
              Sqflite.firstIntValue(
                await db.rawQuery(
                  'SELECT COUNT(*) FROM class_students WHERE class_id = ?',
                  [widget.classModel.id!],
                ),
              ) ??
              0;
          final totalStudents =
              Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM students'),
              ) ??
              0;
          print(
            '[RiskScreen] Diagnostics: class_students count for classId=${widget.classModel.id} => $csCount; total students => $totalStudents',
          );
        } catch (e) {
          print('[RiskScreen] Diagnostics error: $e');
        }
        if (mounted) {
          setState(() {
            _risks = [];
            _isLoading = false;
          });
        }
        return;
      }

      final gradeMap = await _gradingRepo.computePeriodGradesTeacherFormula(
        classId: widget.classModel.id!,
        periodId: _selectedPeriod!.id!,
        studentIds: studentIds,
      );
      print(
        '[RiskScreen] Using teacher formula grades classId=${widget.classModel.id} periodId=${_selectedPeriod!.id} students=${studentIds.length}',
      );
      final attMap = await _attRepo.getClassAttendancePercentages(
        classId: widget.classModel.id!,
        periodId: _selectedPeriod!.id!,
        studentIds: studentIds,
      );

      await _riskRepo.computeAndSaveRiskFlags(
        classId: widget.classModel.id!,
        periodId: _selectedPeriod!.id!,
        studentIds: studentIds,
        gradeThreshold: _gradeThreshold,
        attendanceThreshold: _attendanceThreshold,
        grades: gradeMap,
        attendances: attMap,
      );

      final risks =
          students.map((s) {
            final grade = gradeMap[s.id] ?? 0;
            final att = attMap[s.id] ?? 100;
            String level = 'low';
            if (grade < _gradeThreshold && att < _attendanceThreshold) {
              level = 'high';
            } else if (grade < _gradeThreshold || att < _attendanceThreshold) {
              level = 'medium';
            }
            return _StudentRisk(
              student: s,
              grade: grade,
              attendance: att,
              riskLevel: level,
            );
          }).toList()..sort((a, b) {
            const order = {'high': 0, 'medium': 1, 'low': 2};
            return (order[a.riskLevel] ?? 3).compareTo(order[b.riskLevel] ?? 3);
          });

      print('[RiskScreen] Computed risk for ${students.length} students');

      await _loadCounselingReasons();
      if (mounted) {
        setState(() {
          _risks = risks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[RiskScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCounselingReasons() async {
    try {
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
          '[RiskScreen] Counseling reasons skipped: missing local classes.remote_id classId=${widget.classModel.id}',
        );
        _counselingReasons = const [];
        return;
      }

      final rows = await db.rawQuery(
        '''
        SELECT
          cr.id,
          cr.teacher_uid,
          cr.student_id,
          cr.class_remote_id,
          cr.subject_code,
          cr.reason,
          cr.created_at,
          cr.updated_at,
          s.first_name,
          s.last_name,
          s.middle_name,
          s.photo_path
        FROM counseling_reasons cr
        LEFT JOIN students s ON s.student_id = cr.student_id
        WHERE cr.class_remote_id = ?
          AND COALESCE(cr.deleted, 0) = 0
        ORDER BY cr.created_at DESC
      ''',
        [classRemoteId],
      );

      _counselingReasons = rows;
      print(
        '[RiskScreen] Counseling reasons loaded count=${rows.length} classId=${widget.classModel.id} classRemoteId=$classRemoteId',
      );
    } catch (e) {
      print('[RiskScreen] Counseling reasons load error: $e');
      _counselingReasons = const [];
    }
  }

  int get _highCount => _risks.where((r) => r.riskLevel == 'high').length;
  int get _medCount => _risks.where((r) => r.riskLevel == 'medium').length;

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
            title: 'At-Risk Students',
            subtitle: widget.classModel.displayName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _showThresholdDialog,
                icon: Icon(PlatformIcons.tune, color: Colors.white),
                tooltip: 'Set Thresholds',
              ),
            ],
          ),
          // Scrollable Risk Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _periods.isEmpty
                ? const Center(
                    child: Text(
                      'No grading periods found.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : _risks.isEmpty
                ? const Center(
                    child: Text(
                      'No students enrolled.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RiskSummaryCard(
                            highCount: _highCount,
                            mediumCount: _medCount,
                            lowCount: _risks.length - _highCount - _medCount,
                          ),
                          const SizedBox(height: 12),
                          if (_counselingReasons.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Needs Counseling',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ..._counselingReasons.map((r) {
                              final fn = (r['first_name']?.toString() ?? '')
                                  .trim();
                              final ln = (r['last_name']?.toString() ?? '')
                                  .trim();
                              final studentName = ('$fn $ln').trim();
                              final studentId =
                                  (r['student_id']?.toString() ?? '').trim();
                              final subjectCode =
                                  (r['subject_code']?.toString() ?? '').trim();
                              final reason = (r['reason']?.toString() ?? '')
                                  .trim();

                              final header = [
                                if (studentName.isNotEmpty) studentName,
                                if (studentId.isNotEmpty) studentId,
                                if (subjectCode.isNotEmpty) subjectCode,
                              ].join(' • ');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.divider),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.danger.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: AppTheme.danger.withValues(
                                                alpha: 0.30,
                                              ),
                                            ),
                                          ),
                                          child: const Text(
                                            'Needs Counseling',
                                            style: TextStyle(
                                              color: AppTheme.danger,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 10,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            header.isNotEmpty
                                                ? header
                                                : 'Student',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF1A237E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
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
                            const SizedBox(height: 6),
                          ],
                          ...List.generate(
                            _risks.length,
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RiskCard(
                                risk: _risks[i],
                                gradeThreshold: _gradeThreshold,
                                attendanceThreshold: _attendanceThreshold,
                                onIntervene: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InterventionScreen(
                                      classModel: widget.classModel,
                                      student: _risks[i].student,
                                    ),
                                  ),
                                ),
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

  Future<void> _showThresholdDialog() async {
    final gradeCtrl = TextEditingController(
      text: _gradeThreshold.toStringAsFixed(0),
    );
    final attCtrl = TextEditingController(
      text: _attendanceThreshold.toStringAsFixed(0),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Set Risk Thresholds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: gradeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Grade Threshold (%)',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: attCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Attendance Threshold (%)',
                suffixText: '%',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      final g = double.tryParse(gradeCtrl.text) ?? 75;
      final a = double.tryParse(attCtrl.text) ?? 80;
      await DatabaseHelper.instance.setSetting('grade_threshold', g.toString());
      await DatabaseHelper.instance.setSetting(
        'attendance_threshold',
        a.toString(),
      );
      print('[RiskScreen] Updated thresholds grade=$g att=$a');
      setState(() {
        _gradeThreshold = g;
        _attendanceThreshold = a;
      });
      _loadData();
    }
    gradeCtrl.dispose();
    attCtrl.dispose();
  }
}

class _StudentRisk {
  final Student student;
  final double grade;
  final double attendance;
  final String riskLevel;
  _StudentRisk({
    required this.student,
    required this.grade,
    required this.attendance,
    required this.riskLevel,
  });
}

class _RiskSummaryCard extends StatelessWidget {
  final int highCount;
  final int mediumCount;
  final int lowCount;

  const _RiskSummaryCard({
    required this.highCount,
    required this.mediumCount,
    required this.lowCount,
  });

  @override
  Widget build(BuildContext context) {
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Risk Summary',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _riskTile(
                  label: 'High Risk',
                  value: highCount,
                  color: AppTheme.danger,
                ),
                _riskTile(
                  label: 'Medium Risk',
                  value: mediumCount,
                  color: AppTheme.warning,
                ),
                _riskTile(
                  label: 'Low Risk',
                  value: lowCount,
                  color: AppTheme.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskTile({
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final _StudentRisk risk;
  final double gradeThreshold;
  final double attendanceThreshold;
  final VoidCallback onIntervene;

  const _RiskCard({
    required this.risk,
    required this.gradeThreshold,
    required this.attendanceThreshold,
    required this.onIntervene,
  });

  Color get _levelColor {
    if (risk.riskLevel == 'high') return AppTheme.danger;
    if (risk.riskLevel == 'medium') return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.primaryColor;
    final secondary = themeProvider.secondaryColor;

    final initials = '${risk.student.firstName[0]}${risk.student.lastName[0]}'
        .toUpperCase();
    final photoData = (risk.student.photoPath ?? '').trim();

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _levelColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: hasPhoto
                      ? LinearGradient(
                          colors: [primary, secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: hasPhoto ? null : _levelColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
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
                                  width: 40,
                                  height: 40,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Text(
                                        initials,
                                        style: TextStyle(
                                          color: _levelColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              } catch (e) {
                                return Center(
                                  child: Text(
                                    initials,
                                    style: TextStyle(
                                      color: _levelColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              final file = File(photoData);
                              return Image.file(
                                file,
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        color: _levelColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
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
                            style: TextStyle(
                              color: _levelColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
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
                      risk.student.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'ID: ${risk.student.studentId}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _levelColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  risk.riskLevel == 'high'
                      ? 'High'
                      : risk.riskLevel == 'medium'
                      ? 'Medium'
                      : 'Low',
                  style: TextStyle(
                    color: _levelColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricChip(
                label: 'Grade',
                value: risk.grade > 0
                    ? '${risk.grade.toStringAsFixed(1)}%'
                    : '—',
                below: risk.grade > 0 && risk.grade < gradeThreshold,
              ),
              const SizedBox(width: 8),
              _MetricChip(
                label: 'Attendance',
                value: '${risk.attendance.toStringAsFixed(1)}%',
                below: risk.attendance < attendanceThreshold,
              ),
              const Spacer(),
              if (risk.riskLevel != 'low')
                TextButton.icon(
                  onPressed: onIntervene,
                  icon: Icon(PlatformIcons.editNote, size: 16),
                  label: const Text(
                    'Intervene',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final bool below;
  const _MetricChip({
    required this.label,
    required this.value,
    required this.below,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: below ? AppTheme.danger.withValues(alpha: 0.08) : AppTheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: below
            ? AppTheme.danger.withValues(alpha: 0.3)
            : AppTheme.divider,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: below ? AppTheme.danger : AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: below ? AppTheme.danger : AppTheme.textPrimary,
          ),
        ),
      ],
    ),
  );
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
