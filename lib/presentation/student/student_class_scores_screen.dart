import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/student_data_repository.dart';
import '../../data/models/intervention_model.dart';
import 'student_lessons_screen.dart';
import 'student_coming_soon_screen.dart';
import 'student_interventions_screen.dart';
import 'student_home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class StudentClassScoresScreen extends StatefulWidget {
  final String teacherUid;
  final String classRemoteId;
  final String title;

  const StudentClassScoresScreen({
    super.key,
    required this.teacherUid,
    required this.classRemoteId,
    required this.title,
  });

  @override
  State<StudentClassScoresScreen> createState() =>
      _StudentClassScoresScreenState();
}

class _StudentInterventionsCard extends StatelessWidget {
  final List<Intervention> interventions;
  final bool showDueTodayChip;
  final bool Function(Intervention i) isDueToday;

  const _StudentInterventionsCard({
    required this.interventions,
    required this.showDueTodayChip,
    required this.isDueToday,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return AppTheme.success;
      case 'in_progress':
        return AppTheme.warning;
      default:
        return AppTheme.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
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
    if (interventions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: const Text(
          'No interventions recorded for this class.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: List.generate(interventions.length, (index) {
          final i = interventions[index];
          final status = (i.status).trim();
          final statusColor = _statusColor(status);
          final followUp = (i.followUpDate ?? '').trim();
          final dueToday = showDueTodayChip && isDueToday(i);

          return Padding(
            padding: EdgeInsets.only(
              bottom: index == interventions.length - 1 ? 0 : 12,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (dueToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.warning.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Text(
                            'Due Today',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.warning,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    i.description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PlatformIcons.calendarToday,
                            size: 12,
                            color: AppTheme.textLight,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            i.interventionDate,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textLight,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (followUp.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PlatformIcons.event,
                              size: 12,
                              color: AppTheme.textLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Follow-up: $followUp',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textLight,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _StudentClassScoresScreenState extends State<StudentClassScoresScreen>
    with SingleTickerProviderStateMixin {
  final StudentDataRepository _repo = StudentDataRepository();
  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Statistics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  final TextEditingController _counselReasonController =
      TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _attendance = const [];
  List<Map<String, dynamic>> _periodGrades = const [];
  List<String> _categoryNames = const [];
  List<Intervention> _interventions = const [];
  bool _followUpNotifiedForToday = false;
  Map<String, dynamic>? _existingCounselingReason;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _load();
  }

  String? get _overallDescriptor {
    final periodEntries = _periodGrades
        .map((p) {
          final pct = (p['percent'] is num)
              ? (p['percent'] as num).toDouble()
              : double.tryParse(p['percent']?.toString() ?? '') ?? 0.0;
          final desc = (p['descriptor']?.toString() ?? '').trim();
          return {'pct': pct, 'desc': desc};
        })
        .where((e) => (e['pct'] as double) > 0)
        .toList();

    // If the student only has one period grade, use its descriptor directly.
    // This avoids misleading labels like "Satisfactory" when the teacher's
    // equivalency table says the score is "Failed".
    if (periodEntries.length == 1) {
      final desc = (periodEntries.first['desc'] as String?) ?? '';
      if (desc.isNotEmpty) {
        print(
          '[StudentClassScoresScreen] Overall descriptor source=single_period desc=$desc',
        );
        return desc;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _counselReasonController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  bool get _isAtRisk {
    final d = (_overallDescriptor ?? '').toLowerCase();
    if (d.contains('fail')) return true;
    return _overallAverage > 0 && _overallAverage < 75;
  }

  String get _subjectCodeForSave {
    final parts = widget.title.split('•');
    return parts.isEmpty ? widget.title.trim() : parts.first.trim();
  }

  Future<void> _loadExistingCounselingReason() async {
    try {
      final studentId =
          (await DatabaseHelper.instance.getSetting('student_id'))?.trim() ??
          '';
      if (studentId.isEmpty) {
        print(
          '[StudentClassScoresScreen] Load existing counseling reason skipped: missing local student_id setting',
        );
        _existingCounselingReason = null;
        return;
      }
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'counseling_reasons',
        where:
            'teacher_uid = ? AND student_id = ? AND class_remote_id = ? AND subject_code = ? AND COALESCE(deleted, 0) = 0',
        whereArgs: [
          widget.teacherUid,
          studentId,
          widget.classRemoteId,
          _subjectCodeForSave,
        ],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        _existingCounselingReason = rows.first;
        print(
          '[StudentClassScoresScreen] Loaded existing counseling reason localId=${_existingCounselingReason!['id']}',
        );
      } else {
        _existingCounselingReason = null;
        print(
          '[StudentClassScoresScreen] No existing counseling reason found for this class/subject',
        );
      }
    } catch (e) {
      print(
        '[StudentClassScoresScreen] Error loading existing counseling reason: $e',
      );
      _existingCounselingReason = null;
    }
  }

  Future<void> _openAddReasonModal() async {
    await _loadExistingCounselingReason();
    _counselReasonController.text =
        _existingCounselingReason?['reason']?.toString() ?? '';
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Reason',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _counselReasonController,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText:
                      'Enter reason (e.g., low performance, missed tasks)...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEEF1F6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEEF1F6)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final reason = _counselReasonController.text.trim();
                        if (reason.isEmpty) return;

                        final studentId =
                            (await DatabaseHelper.instance.getSetting(
                              'student_id',
                            ))?.trim() ??
                            '';
                        if (studentId.isEmpty) {
                          print(
                            '[StudentClassScoresScreen] Counseling reason save blocked: missing local student_id setting',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Student ID missing. Please set up your PIN first.',
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        try {
                          final db = await DatabaseHelper.instance.database;
                          final now = DateTime.now().toIso8601String();
                          String operation = '';

                          if (_existingCounselingReason != null) {
                            // Update existing record
                            await db.update(
                              'counseling_reasons',
                              {'reason': reason, 'updated_at': now},
                              where: 'id = ?',
                              whereArgs: [_existingCounselingReason!['id']],
                            );
                            operation = 'updated';
                            print(
                              '[StudentClassScoresScreen] Counseling reason updated localId=${_existingCounselingReason!['id']} teacherUid=${widget.teacherUid} classRemoteId=${widget.classRemoteId} studentId=$studentId subjectCode=${_subjectCodeForSave}',
                            );
                          } else {
                            // Insert new record
                            final id = await db.insert('counseling_reasons', {
                              'teacher_uid': widget.teacherUid,
                              'student_id': studentId,
                              'student_remote_id': '',
                              'class_remote_id': widget.classRemoteId,
                              'subject_code': _subjectCodeForSave,
                              'reason': reason,
                              'remote_id': null,
                              'deleted': 0,
                              'created_at': now,
                              'updated_at': now,
                            });
                            operation = 'created';
                            print(
                              '[StudentClassScoresScreen] Counseling reason created localId=$id teacherUid=${widget.teacherUid} classRemoteId=${widget.classRemoteId} studentId=$studentId subjectCode=${_subjectCodeForSave}',
                            );
                          }

                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Reason $operation. It will sync on next upload.',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          print(
                            '[StudentClassScoresScreen] Counseling reason save error: $e',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Save failed: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeController.reset();

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) throw Exception('Not logged in');

      final res = await Future.wait([
        _repo.getStudentClassScoresGroupedByCategorySmart(
          firebaseUid: firebaseUser.uid,
          teacherUid: widget.teacherUid,
          classRemoteId: widget.classRemoteId,
        ),
        _repo.getStudentClassAttendanceSmart(
          firebaseUid: firebaseUser.uid,
          teacherUid: widget.teacherUid,
          classRemoteId: widget.classRemoteId,
        ),
        _repo.getStudentPeriodGradesForClassSmart(
          firebaseUid: firebaseUser.uid,
          teacherUid: widget.teacherUid,
          classRemoteId: widget.classRemoteId,
        ),
        _repo.getTeacherCategoryNamesForClassSmart(
          teacherUid: widget.teacherUid,
          classRemoteId: widget.classRemoteId,
        ),
        _repo.getStudentInterventionsForClassSmart(
          firebaseUid: firebaseUser.uid,
          teacherUid: widget.teacherUid,
          classRemoteId: widget.classRemoteId,
        ),
      ]);

      final groups = (res[0] as List).cast<Map<String, dynamic>>();
      final attendance = (res[1] as List).cast<Map<String, dynamic>>();
      final periodGrades = (res[2] as List).cast<Map<String, dynamic>>();
      final categoryNames = (res[3] as List).cast<String>();
      final interventions = (res[4] as List).cast<Intervention>();

      setState(() {
        _groups = groups;
        _attendance = attendance;
        _periodGrades = periodGrades;
        _categoryNames = categoryNames;
        _interventions = interventions;
        _isLoading = false;
      });
      _fadeController.forward();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifyFollowUpsIfDueToday();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _fadeController.forward();
    }
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isFollowUpDueToday(Intervention i) {
    final raw = (i.followUpDate ?? '').trim();
    if (raw.isEmpty) return false;
    final v = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return v == _todayYmd();
  }

  Future<void> _showFollowUpDueTodayModal({required int count}) async {
    if (count <= 0) return;
    if (!mounted) return;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final gradientColors = themeProvider.getGradientColors();
    print(
      '[StudentClassScoresScreen] Showing follow-up due today modal count=$count classRemoteId=${widget.classRemoteId}',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        PlatformIcons.notificationsActive,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Follow-up Due Today',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You have $count follow-up intervention(s) scheduled today. Please check your interventions.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(PlatformIcons.close),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          side: const BorderSide(color: Color(0xFFE8ECF4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentInterventionsScreen(
                                teacherUid: widget.teacherUid,
                                classRemoteId: widget.classRemoteId,
                                classTitle: widget.title,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gradientColors.first,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'View',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _notifyFollowUpsIfDueToday() {
    if (_followUpNotifiedForToday) return;
    if (!_isAtRisk) return;

    final due = _interventions.where(_isFollowUpDueToday).toList();
    if (due.isEmpty) return;

    _followUpNotifiedForToday = true;
    print(
      '[StudentClassScoresScreen] Follow-up due today count=${due.length} classRemoteId=${widget.classRemoteId}',
    );

    _showFollowUpDueTodayModal(count: due.length);
  }

  double get _overallAverage {
    final periodPcts = _periodGrades
        .map(
          (p) => (p['percent'] is num)
              ? (p['percent'] as num).toDouble()
              : double.tryParse(p['percent']?.toString() ?? '') ?? 0.0,
        )
        .where((pct) => pct > 0)
        .toList();

    if (periodPcts.isNotEmpty) {
      final avg = periodPcts.reduce((a, b) => a + b) / periodPcts.length;
      print(
        '[StudentClassScoresScreen] Overall average source=period_grades included=${periodPcts.length} values=${periodPcts.map((e) => e.toStringAsFixed(2)).join(',')}',
      );
      return avg;
    }

    if (_groups.isEmpty) return 0;
    final avgs = _groups
        .map(
          (g) => (g['average_pct'] is num)
              ? (g['average_pct'] as num).toDouble()
              : double.tryParse(g['average_pct']?.toString() ?? '') ?? 0.0,
        )
        .where((pct) => pct > 0)
        .toList();
    if (avgs.isEmpty) return 0;
    final avg = avgs.reduce((a, b) => a + b) / avgs.length;
    print(
      '[StudentClassScoresScreen] Overall average source=category_groups included=${avgs.length} values=${avgs.map((e) => e.toStringAsFixed(2)).join(',')}',
    );
    return avg;
  }

  Map<String, int> get _attendanceSummary {
    int present = 0, absent = 0;
    for (final a in _attendance) {
      final s = (a['status']?.toString() ?? '').trim().toLowerCase();
      if (s == 'present') present++;
      if (s == 'absent') absent++;
    }
    return {'present': present, 'absent': absent};
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        color: primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ModernHeader(
                title: widget.title,
                overallAverage: _overallAverage,
                overallDescriptor: _overallDescriptor,
                isLoading: _isLoading,
                onClose: () => Navigator.of(context).pop(),
                onLessons: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudentLessonsScreen(
                      teacherUid: widget.teacherUid,
                      classRemoteId: widget.classRemoteId,
                      classTitle: widget.title,
                    ),
                  ),
                ),
                categoryNames: _categoryNames,
                onCategoryTap: (name) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudentComingSoonScreen(title: name),
                  ),
                ),
                onRefresh: _load,
                showNeedsCounseling: _isAtRisk,
                onAddReason: _openAddReasonModal,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 24 : 16,
                0,
                isTablet ? 24 : 16,
                40,
              ),
              sliver: _isLoading
                  ? const SliverToBoxAdapter(child: _LoadingShimmer())
                  : _error != null
                  ? SliverToBoxAdapter(child: _ErrorCard(error: _error!))
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              _AttendanceSummaryRow(
                                summary: _attendanceSummary,
                              ),
                              const SizedBox(height: 16),
                              _SectionLabel(label: 'Period Grades'),
                              const SizedBox(height: 8),
                              _PeriodGradesCard(periodGrades: _periodGrades),
                              if (_isAtRisk) ...[
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: _SectionLabel(
                                        label: 'Interventions',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        print(
                                          '[StudentClassScoresScreen] Open interventions list screen classRemoteId=${widget.classRemoteId}',
                                        );
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                StudentInterventionsScreen(
                                                  teacherUid: widget.teacherUid,
                                                  classRemoteId:
                                                      widget.classRemoteId,
                                                  classTitle: widget.title,
                                                ),
                                          ),
                                        );
                                      },
                                      child: const Text('View All'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _StudentInterventionsCard(
                                  interventions: _interventions,
                                  showDueTodayChip: true,
                                  isDueToday: _isFollowUpDueToday,
                                ),
                              ],
                              const SizedBox(height: 24),
                              _SectionLabel(label: 'Attendance Calendar'),
                              const SizedBox(height: 8),
                              _AttendanceCard(attendance: _attendance),
                              const SizedBox(height: 24),
                              _SectionLabel(label: 'Score Breakdown'),
                              const SizedBox(height: 8),
                              if (_groups.isEmpty)
                                const _EmptyState(
                                  message:
                                      'No recorded scores found for this class yet.',
                                )
                              else
                                ...List.generate(
                                  _groups.length,
                                  (i) => _CategoryCard(
                                    group: _groups[i],
                                    index: i,
                                    isTablet: isTablet,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: 1,
        items: _navItems,
        onTap: (i) {
          if (i == 1) {
            Navigator.maybePop(context);
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => StudentHomeScreen(initialIndex: i),
              ),
              (route) => false,
            );
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Modern Header
// ─────────────────────────────────────────────────────────────────────────────

class _ModernHeader extends StatelessWidget {
  final String title;
  final double overallAverage;
  final String? overallDescriptor;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onLessons;
  final List<String> categoryNames;
  final void Function(String name) onCategoryTap;
  final Future<void> Function() onRefresh;

  const _ModernHeader({
    required this.title,
    required this.overallAverage,
    this.overallDescriptor,
    required this.isLoading,
    required this.onClose,
    required this.onLessons,
    required this.categoryNames,
    required this.onCategoryTap,
    required this.onRefresh,
    this.onAddReason,
    this.showNeedsCounseling = false,
  });

  final VoidCallback? onAddReason;
  final bool showNeedsCounseling;

  Color _gradeColor(double pct) {
    if (pct >= 90) return const Color(0xFF00D4AA);
    if (pct >= 75) return const Color(0xFF4FC3F7);
    if (pct >= 60) return const Color(0xFFFFB74D);
    return const Color(0xFFEF5350);
  }

  String _gradeLabel(double pct) {
    if (pct >= 97) return 'Outstanding';
    if (pct >= 90) return 'Excellent';
    if (pct >= 80) return 'Very Good';
    if (pct >= 75) return 'Good';
    if (pct >= 60) return 'Satisfactory';
    return 'Needs Improvement';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final primary = Theme.of(context).colorScheme.primary;
    final grade = _gradeColor(overallAverage);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientColors.first, gradientColors.last, primary],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -40,
            child: _Circle(size: 160, opacity: 0.06),
          ),
          Positioned(
            bottom: -20,
            left: 40,
            child: _Circle(size: 100, opacity: 0.05),
          ),
          Positioned(
            top: 70,
            right: 90,
            child: _Circle(size: 50, opacity: 0.08),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nav row
                Row(
                  children: [
                    _HeaderButton(icon: PlatformIcons.back, onTap: onClose),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'My Academic Progress',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _HeaderButton(
                      icon: PlatformIcons.refresh,
                      onTap: onRefresh,
                    ),
                  ],
                ),

                if (!isLoading) ...[
                  const SizedBox(height: 20),
                  // Overall Average + Quick Actions grid (equal height)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: grade.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: grade, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${overallAverage.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Overall Average',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        overallDescriptor ??
                                            _gradeLabel(overallAverage),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),

                                      if (showNeedsCounseling &&
                                          onAddReason != null) ...[
                                        const SizedBox(height: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              height: 30,
                                              child: OutlinedButton(
                                                onPressed: onAddReason,
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Add Reason',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'Needs Counseling',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 11,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _QuickActionsGrid(
                            onLessons: onLessons,
                            categoryNames: categoryNames,
                            onCategoryTap: onCategoryTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onLessons;
  final List<String> categoryNames;
  final void Function(String name) onCategoryTap;

  const _QuickActionsGrid({
    required this.onLessons,
    required this.categoryNames,
    required this.onCategoryTap,
  });

  IconData _iconForCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('quiz')) return PlatformIcons.quiz;
    if (n.contains('exam')) return PlatformIcons.factCheck;
    if (n.contains('test')) return PlatformIcons.factCheck;
    if (n.contains('assign')) return PlatformIcons.assignment;
    if (n.contains('activity')) return PlatformIcons.taskAlt;
    if (n.contains('project')) return PlatformIcons.rocketLaunch;
    return PlatformIcons.category;
  }

  @override
  Widget build(BuildContext context) {
    final c1 = categoryNames.isNotEmpty ? categoryNames[0] : 'Category';
    final c2 = categoryNames.length > 1 ? categoryNames[1] : 'Category';
    final c3 = categoryNames.length > 2 ? categoryNames[2] : 'Category';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: _iconForCategory(c1),
                    label: c1,
                    onTap: () => onCategoryTap(c1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionTile(
                    icon: _iconForCategory(c2),
                    label: c2,
                    onTap: () => onCategoryTap(c2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: _iconForCategory(c3),
                    label: c3,
                    onTap: () => onCategoryTap(c3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionTile(
                    icon: PlatformIcons.book,
                    label: 'Lessons',
                    onTap: onLessons,
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

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double opacity;
  const _Circle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: Colors.white, size: 17),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance Summary Row
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceSummaryRow extends StatelessWidget {
  final Map<String, int> summary;
  const _AttendanceSummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final present = summary['present'] ?? 0;
    final absent = summary['absent'] ?? 0;
    final total = present + absent;
    final rate = total == 0 ? 0.0 : present / total;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.checkCircleOutline,
            label: 'Present',
            value: '$present',
            suffix: 'days',
            color: const Color(0xFF00C897),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.cancel,
            label: 'Absent',
            value: '$absent',
            suffix: 'days',
            color: const Color(0xFFFF5C72),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.timeline,
            label: 'Attendance',
            value: '${(rate * 100).toStringAsFixed(0)}',
            suffix: '%',
            color: const Color(0xFF5B8AF5),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String suffix;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                TextSpan(
                  text: ' $suffix',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9AA3B0),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A237E),
          letterSpacing: 0.3,
        ),
      ),
    ],
  );
}

class _PeriodGradesCard extends StatelessWidget {
  final List<Map<String, dynamic>> periodGrades;

  const _PeriodGradesCard({required this.periodGrades});

  @override
  Widget build(BuildContext context) {
    if (periodGrades.isEmpty) {
      return const _EmptyState(
        message: 'No period grades found for this class yet.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            ...List.generate(periodGrades.length, (i) {
              final p = periodGrades[i];
              final name =
                  ((p['period_name'] ?? p['name'])?.toString() ?? 'Period')
                      .trim();
              final percent = (p['percent'] is num)
                  ? (p['percent'] as num).toDouble()
                  : double.tryParse(p['percent']?.toString() ?? '') ?? 0.0;
              final eq = (p['equivalent'] is num)
                  ? (p['equivalent'] as num).toDouble()
                  : double.tryParse(p['equivalent']?.toString() ?? '');
              final descriptor = (p['descriptor']?.toString() ?? '').trim();

              final gradeColor = percent >= 90
                  ? const Color(0xFF00C897)
                  : percent >= 75
                  ? const Color(0xFF5B8AF5)
                  : percent >= 60
                  ? const Color(0xFFFFB74D)
                  : const Color(0xFFFF5C72);

              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == periodGrades.length - 1 ? 0 : 10,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEEF1F6)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          PlatformIcons.school,
                          color: gradeColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Color(0xFF1A237E),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (descriptor.isNotEmpty)
                              Text(
                                descriptor,
                                style: const TextStyle(
                                  color: Color(0xFF9AA3B0),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              )
                            else
                              const Text(
                                'Percentage grade',
                                style: TextStyle(
                                  color: Color(0xFF9AA3B0),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: gradeColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          eq != null
                              ? '${percent.toStringAsFixed(1)}% • ${eq.toStringAsFixed(2)}'
                              : '${percent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: gradeColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance Card
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final List<Map<String, dynamic>> attendance;
  const _AttendanceCard({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 320,
              child: _AttendanceCalendar(attendance: attendance),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFF),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              border: Border(top: BorderSide(color: Color(0xFFEEF1F6))),
            ),
            child: Row(
              children: [
                _LegendChip(
                  color: AppTheme.success,
                  label: 'Present',
                  icon: PlatformIcons.checkCircle,
                ),
                const SizedBox(width: 12),
                _LegendChip(
                  color: AppTheme.danger,
                  label: 'Absent',
                  icon: PlatformIcons.cancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const _LegendChip({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Category Card
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final Map<String, dynamic> group;
  final int index;
  final bool isTablet;

  const _CategoryCard({
    required this.group,
    required this.index,
    required this.isTablet,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = true;

  static const _palette = [
    Color(0xFF5B8AF5),
    Color(0xFF9C6FE4),
    Color(0xFFFF8A65),
    Color(0xFF26C6DA),
    Color(0xFF66BB6A),
    Color(0xFFFFCA28),
  ];

  Color get _accent => _palette[widget.index % _palette.length];

  double get _avg {
    final g = widget.group;
    return (g['average_pct'] is num)
        ? (g['average_pct'] as num).toDouble()
        : double.tryParse(g['average_pct']?.toString() ?? '') ?? 0.0;
  }

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.contains('quiz')) return PlatformIcons.quiz;
    if (n.contains('exam') || n.contains('test'))
      return PlatformIcons.assignment;
    if (n.contains('project')) return PlatformIcons.folderSpecial;
    if (n.contains('activity') || n.contains('seatwork'))
      return PlatformIcons.editNote;
    if (n.contains('recit') || n.contains('oral'))
      return PlatformIcons.recordVoiceOver;
    if (n.contains('homework') || n.contains('hw'))
      return PlatformIcons.homeWork;
    return PlatformIcons.analytics;
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = (widget.group['category_name']?.toString() ?? '')
        .trim();
    final items =
        (widget.group['assessments'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        _icon(categoryName),
                        color: _accent,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName.isNotEmpty ? categoryName : 'Category',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A237E),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _ProgressBar(
                                  value: _avg / 100,
                                  color: _accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_avg.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: Icon(
                        PlatformIcons.dropdown,
                        color: _accent,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expanded items
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: const Color(0xFFEEF1F6),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        // Column headers
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: const [
                              SizedBox(width: 32),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'ASSESSMENT',
                                  style: TextStyle(
                                    color: Color(0xFFB0BAD0),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              Text(
                                'SCORE',
                                style: TextStyle(
                                  color: Color(0xFFB0BAD0),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...List.generate(items.length, (i) {
                          final it = items[i];
                          final name =
                              it['assessment_name']?.toString() ?? 'Assessment';
                          final score = it['score'];
                          final max = it['max_score'];
                          final scoreText = score == null
                              ? '—'
                              : (max == null || max.toString().isEmpty)
                              ? score.toString()
                              : '${score.toString()}/${max.toString()}';
                          final pct = (score != null && max != null)
                              ? (double.tryParse(score.toString()) ?? 0) /
                                    (double.tryParse(max.toString()) ?? 1)
                              : null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: i.isEven
                                  ? const Color(0xFFF8FAFF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFEEF1F6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: _accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Color(0xFF2E3A5C),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _ScoreBadge(text: scoreText, pct: pct),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 280),
              firstCurve: Curves.easeIn,
              secondCurve: Curves.easeOut,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Score Badge
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  final String text;
  final double? pct;

  const _ScoreBadge({required this.text, required this.pct});

  Color get _color {
    if (pct == null) return const Color(0xFFB0BAD0);
    if (pct! >= 0.9) return const Color(0xFF00C897);
    if (pct! >= 0.75) return const Color(0xFF5B8AF5);
    if (pct! >= 0.6) return const Color(0xFFFFB74D);
    return const Color(0xFFFF5C72);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _color.withValues(alpha: 0.3)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: _color,
        fontWeight: FontWeight.w900,
        fontSize: 12,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress Bar
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    height: 5,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.7), color],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final opacity = 0.5 + 0.5 * math.sin(_anim.value * math.pi);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: List.generate(
            4,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              height: i == 0 ? 80 : 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error Card
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFD6DA)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFFF5C72).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEF0),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            PlatformIcons.errorOutline,
            color: Color(0xFFFF5C72),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Color(0xFF2E3A5C),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                error,
                style: const TextStyle(color: Color(0xFF9AA3B0), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1A237E).withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFEEF3FF),
            shape: BoxShape.circle,
          ),
          child: Icon(PlatformIcons.inbox, color: Color(0xFF5B8AF5), size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9AA3B0),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance Calendar
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceCalendar extends StatelessWidget {
  final List<Map<String, dynamic>> attendance;
  const _AttendanceCalendar({required this.attendance});

  @override
  Widget build(BuildContext context) =>
      _AttendanceCalendarStateful(attendance: attendance);
}

class _AttendanceCalendarStateful extends StatefulWidget {
  final List<Map<String, dynamic>> attendance;
  const _AttendanceCalendarStateful({required this.attendance});

  @override
  State<_AttendanceCalendarStateful> createState() =>
      _AttendanceCalendarStatefulState();
}

class _AttendanceCalendarStatefulState
    extends State<_AttendanceCalendarStateful> {
  final CalendarController _controller = CalendarController();

  DateTime _displayDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _displayDate = DateTime.now();
    _controller.displayDate = _displayDate;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, String> get _statusByDay {
    final map = <DateTime, String>{};
    for (final a in widget.attendance) {
      final status = (a['status']?.toString() ?? '').trim().toLowerCase();
      if (status != 'present' && status != 'absent') continue;
      final dateObj = a['date_obj'];
      if (dateObj is! DateTime) continue;

      final key = _dateKey(dateObj);
      final existing = map[key];

      if (existing == 'absent') {
        continue;
      }
      if (status == 'absent') {
        map[key] = 'absent';
      } else {
        map.putIfAbsent(key, () => 'present');
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final statusByDay = _statusByDay;

    final monthTitle =
        '${_displayDate.year}-${_displayDate.month.toString().padLeft(2, '0')}';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  final d = DateTime(_displayDate.year, _displayDate.month - 1);
                  setState(() {
                    _displayDate = d;
                    _controller.displayDate = d;
                  });
                },
                icon: const Icon(CupertinoIcons.chevron_left),
              ),
              Expanded(
                child: Text(
                  monthTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final d = DateTime(_displayDate.year, _displayDate.month + 1);
                  setState(() {
                    _displayDate = d;
                    _controller.displayDate = d;
                  });
                },
                icon: const Icon(CupertinoIcons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: SfCalendar(
            controller: _controller,
            view: CalendarView.month,
            headerHeight: 0,
            viewHeaderStyle: const ViewHeaderStyle(
              dayTextStyle: TextStyle(
                color: Color(0xFF9AA3B0),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            todayHighlightColor: primary,
            todayTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
            monthViewSettings: const MonthViewSettings(
              showAgenda: false,
              appointmentDisplayMode: MonthAppointmentDisplayMode.none,
            ),
            onViewChanged: (details) {
              if (details.visibleDates.isEmpty) return;
              final mid =
                  details.visibleDates[details.visibleDates.length ~/ 2];
              final nextDisplay = DateTime(mid.year, mid.month, 1);
              if (nextDisplay.year == _displayDate.year &&
                  nextDisplay.month == _displayDate.month) {
                return;
              }
              setState(() => _displayDate = nextDisplay);
            },
            monthCellBuilder: (context, details) {
              final date = details.date;
              final key = _dateKey(date);
              final status = statusByDay[key];
              final isToday = DateUtils.isSameDay(date, DateTime.now());

              Color? bg;
              if (status == 'present') bg = AppTheme.success;
              if (status == 'absent') bg = AppTheme.danger;

              final isInMonth =
                  details.visibleDates.any(
                    (d) => DateUtils.isSameDay(d, date),
                  ) &&
                  date.month == _displayDate.month;

              final textColor = bg != null
                  ? Colors.white
                  : isInMonth
                  ? const Color(0xFF2E3A5C)
                  : const Color(0xFF9AA3B0);

              return Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: bg?.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: isToday
                      ? Border.all(color: primary, width: 1.5)
                      : null,
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
