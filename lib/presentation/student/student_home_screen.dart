import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/login_screen.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_account_repository.dart';
import '../../data/repositories/student_data_repository.dart';
import 'student_class_scores_screen.dart';
import 'student_settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Root Screen  (bottom nav shell)
// ─────────────────────────────────────────────────────────────────────────────

class StudentHomeScreen extends StatefulWidget {
  final int initialIndex;
  const StudentHomeScreen({super.key, this.initialIndex = 0});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _selectedIndex = 0;

  final _studentRepo = StudentDataRepository();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Statistics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _DashboardTab(
            studentRepo: _studentRepo,
            onNavigateToTab: (i) => setState(() => _selectedIndex = i),
          ),
          _ClassesTab(studentRepo: _studentRepo),
          _StatisticsTab(studentRepo: _studentRepo),
          const StudentSettingsScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedIndex,
        items: _navItems,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sign-out helper
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _signOut(BuildContext context) async {
  try {
    await StudentAccountRepository.clearActiveTeacherContext();
    print('[StudentHomeScreen] Cleared active teacher context');
  } catch (e) {
    print('[StudentHomeScreen] Clear teacher context error: $e');
  }
  if (!context.mounted) return;

  final pinHash = await DatabaseHelper.instance.getSetting('student_pin_hash');
  final hasPin = pinHash != null && pinHash.trim().isNotEmpty;
  print('[StudentHomeScreen] Logout lock redirect hasStudentPin=$hasPin');

  if (hasPin) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen(isStudent: true)),
      (_) => false,
    );
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared Header
// ─────────────────────────────────────────────────────────────────────────────

class _SharedHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? bottom;
  final VoidCallback? onSignOut;

  const _SharedHeader({
    required this.title,
    required this.subtitle,
    this.bottom,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final primary = Theme.of(context).colorScheme.primary;

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
          // Decorative circles
          Positioned(
            top: -30,
            right: -30,
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
            padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 24),
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
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onSignOut != null)
                      _HeaderIconButton(
                        icon: PlatformIcons.logout,
                        onTap: onSignOut!,
                        tooltip: 'Sign out',
                      ),
                  ],
                ),
                if (bottom != null) ...[const SizedBox(height: 18), bottom!],
              ],
            ),
          ),
        ],
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ),
  );
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

// ─────────────────────────────────────────────────────────────────────────────
//  DASHBOARD TAB
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardTab extends StatefulWidget {
  final StudentDataRepository studentRepo;
  final void Function(int index)? onNavigateToTab;
  const _DashboardTab({required this.studentRepo, this.onNavigateToTab});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  Student? _student;
  StudentAccountInfo? _accountInfo;
  Map<String, dynamic>? _gradeSummary;
  Map<String, dynamic>? _attendanceSummary;

  List<Map<String, dynamic>> _classes = const [];
  String? _selectedAttendanceClassKey;
  Map<String, dynamic>? _filteredAttendanceSummary;
  bool _attendanceFilterLoading = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeCtrl.reset();

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final res = await Future.wait([
        widget.studentRepo.getCurrentStudentProfile(user.uid),
        StudentAccountRepository.getStudentAccountByUid(user.uid),
        widget.studentRepo.getStudentDashboardStats(user.uid),
        widget.studentRepo.getStudentClassesSmart(user.uid),
      ]);

      final student = res[0] as Student?;
      final accountInfo = res[1] as StudentAccountInfo?;
      final stats = res[2] as Map<String, dynamic>;
      final classes = (res[3] as List).cast<Map<String, dynamic>>();

      final displayName = student != null
          ? '${student.firstName} ${student.lastName}'.trim()
          : (accountInfo?.displayName ?? '').trim();
      final displayId = student?.studentId ?? accountInfo?.studentId ?? '';
      print(
        '[StudentDashboard] Loaded profile name=$displayName studentId=$displayId',
      );

      setState(() {
        _student = student;
        _accountInfo = accountInfo;
        _gradeSummary = stats['gradeSummary'] as Map<String, dynamic>?;
        _attendanceSummary =
            stats['attendanceSummary'] as Map<String, dynamic>?;
        _classes = classes;
        _isLoading = false;
      });
      _fadeCtrl.forward();

      if (_selectedAttendanceClassKey != null) {
        await _loadAttendanceForSelectedClass();
      }
    } catch (e) {
      print('[StudentDashboard] Load error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _fadeCtrl.forward();
    }
  }

  Future<void> _loadAttendanceForSelectedClass() async {
    final key = _selectedAttendanceClassKey;
    if (key == null) return;
    final parts = key.split('|');
    if (parts.length != 2) return;
    final teacherUid = parts[0];
    final classRemoteId = parts[1];

    setState(() {
      _attendanceFilterLoading = true;
      _filteredAttendanceSummary = null;
    });

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final records = await widget.studentRepo.getStudentClassAttendanceSmart(
        firebaseUid: user.uid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );

      DateTime parseMaybeDate(dynamic v) {
        if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        return DateTime.tryParse(v.toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }

      final dayStatus = <String, String>{};
      for (final r in records) {
        final d = parseMaybeDate(r['date'] ?? r['created_at']);
        final dayKey =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final s = (r['status']?.toString() ?? '').trim().toLowerCase();

        final prev = dayStatus[dayKey];
        if (prev == 'absent') continue;
        if (s == 'absent') {
          dayStatus[dayKey] = 'absent';
        } else if (s == 'present') {
          dayStatus[dayKey] = prev ?? 'present';
        }
      }

      var present = 0;
      var absent = 0;
      for (final s in dayStatus.values) {
        if (s == 'absent') absent++;
        if (s == 'present') present++;
      }
      final total = dayStatus.length;
      final rate = total == 0 ? 0.0 : (present / total) * 100.0;

      print(
        '[StudentDashboard] Attendance filter key=$key rawRecords=${records.length} uniqueDays=$total present=$present absent=$absent',
      );

      setState(() {
        _filteredAttendanceSummary = {
          'totalRecords': total,
          'presentCount': present,
          'absentCount': absent,
          'attendanceRate': rate,
        };
      });
    } catch (_) {
      setState(() {
        _filteredAttendanceSummary = {
          'totalRecords': 0,
          'presentCount': 0,
          'absentCount': 0,
          'attendanceRate': 0.0,
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _attendanceFilterLoading = false;
        });
      }
    }
  }

  Widget _buildAttendanceFilterRow() {
    if (_classes.isEmpty) return const SizedBox.shrink();

    String labelFor(Map<String, dynamic> c) {
      final subject = (c['subject_code']?.toString() ?? '').trim();
      final section = (c['section']?.toString() ?? '').trim();
      final teacher = (c['teacher_name']?.toString() ?? '').trim();
      final base = [subject, section].where((v) => v.isNotEmpty).join(' - ');
      if (teacher.isEmpty) return base.isNotEmpty ? base : 'Class';
      return base.isNotEmpty ? '$base ($teacher)' : teacher;
    }

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('Overall Attendance')),
      ..._classes
          .map((c) {
            final teacherUid = (c['teacher_uid']?.toString() ?? '').trim();
            final classRemoteId = (c['class_remote_id']?.toString() ?? '')
                .trim();
            if (teacherUid.isEmpty || classRemoteId.isEmpty) return null;
            final key = '$teacherUid|$classRemoteId';
            return DropdownMenuItem<String?>(
              value: key,
              child: Text(labelFor(c), overflow: TextOverflow.ellipsis),
            );
          })
          .whereType<DropdownMenuItem<String?>>()
          .toList(),
    ];

    return Row(
      children: [
        const Text(
          'Attendance:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedAttendanceClassKey,
                      icon: Icon(
                        PlatformIcons.dropdown,
                        color: const Color(0xFF1A237E),
                        size: 20,
                      ),
                      items: items,
                      isExpanded: true,
                      onChanged: (v) async {
                        setState(() {
                          _selectedAttendanceClassKey = v;
                        });
                        if (v == null) {
                          setState(() {
                            _filteredAttendanceSummary = null;
                          });
                          return;
                        }
                        await _loadAttendanceForSelectedClass();
                      },
                    ),
                  ),
                ),
                if (_attendanceFilterLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final summaryToUse = _selectedAttendanceClassKey == null
        ? _attendanceSummary
        : _filteredAttendanceSummary;
    final attendanceRate =
        (summaryToUse?['attendanceRate'] as num?)?.toDouble() ?? 0;
    final generalAvg = (_gradeSummary?['generalAverageScore'] is num)
        ? (_gradeSummary?['generalAverageScore'] as num).toDouble()
        : double.tryParse(
                _gradeSummary?['generalAverageScore']?.toString() ?? '',
              ) ??
              0.0;
    final generalEq = (_gradeSummary?['generalAverageEquivalent'] is num)
        ? (_gradeSummary?['generalAverageEquivalent'] as num).toDouble()
        : double.tryParse(
            _gradeSummary?['generalAverageEquivalent']?.toString() ?? '',
          );

    return RefreshIndicator(
      onRefresh: () async => _load(),
      color: AppTheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: _SharedHeader(
              title: _isLoading
                  ? 'Student Dashboard'
                  : (_student != null
                        ? 'Hi, ${_student!.firstName}!'
                        : (_accountInfo != null &&
                                  _accountInfo!.firstName.isNotEmpty
                              ? 'Hi, ${_accountInfo!.firstName}!'
                              : 'Student Dashboard')),
              subtitle: _isLoading
                  ? 'Loading your profile…'
                  : (_student != null
                        ? 'ID: ${_student!.studentId}'
                        : (_accountInfo != null &&
                                  _accountInfo!.studentId.isNotEmpty
                              ? 'ID: ${_accountInfo!.studentId}'
                              : 'View your academic records')),
              onSignOut: () => _signOut(context),
              bottom: _isLoading
                  ? const _HeaderLoadingBar()
                  : _error != null
                  ? null
                  : _DashboardHeaderStats(
                      generalAverage: generalAvg,
                      generalEquivalent: generalEq,
                      attendanceRate: attendanceRate,
                    ),
            ),
          ),

          // Body
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 16,
              20,
              isTablet ? 24 : 16,
              40,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_error != null)
                  _ErrorCard(error: _error!)
                else
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(label: 'Quick Overview'),
                        const SizedBox(height: 12),
                        _buildAttendanceFilterRow(),
                        const SizedBox(height: 10),
                        _OverviewCard(
                          student: _student,
                          fallbackName: (_student == null
                              ? (_accountInfo?.displayName ?? '')
                              : ''),
                          fallbackStudentId: (_student == null
                              ? (_accountInfo?.studentId ?? '')
                              : ''),
                          gradeSummary: _gradeSummary,
                          attendanceSummary: summaryToUse,
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(label: 'Quick Actions'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickActionTile(
                                icon: PlatformIcons.class_,
                                label: 'My Classes',
                                color: const Color(0xFF5B8AF5),
                                onTap: () => widget.onNavigateToTab?.call(1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionTile(
                                icon: PlatformIcons.analytics,
                                label: 'Statistics',
                                color: const Color(0xFF9C6FE4),
                                onTap: () => widget.onNavigateToTab?.call(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionTile(
                                icon: PlatformIcons.settings,
                                label: 'Settings',
                                color: const Color(0xFF26C6DA),
                                onTap: () => widget.onNavigateToTab?.call(3),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderLoadingBar extends StatefulWidget {
  const _HeaderLoadingBar();

  @override
  State<_HeaderLoadingBar> createState() => _HeaderLoadingBarState();
}

class _HeaderLoadingBarState extends State<_HeaderLoadingBar>
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
      final opacity = 0.3 + 0.4 * math.sin(_anim.value * math.pi);
      return Row(
        children: List.generate(
          2,
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == 0 ? 12 : 0),
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DashboardHeaderStats extends StatelessWidget {
  final double generalAverage;
  final double? generalEquivalent;
  final double attendanceRate;

  const _DashboardHeaderStats({
    required this.generalAverage,
    required this.generalEquivalent,
    required this.attendanceRate,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _HeaderStatTile(
          label: 'General Average',
          value: generalAverage > 0
              ? (generalEquivalent != null
                    ? '${generalAverage.toStringAsFixed(1)}% • ${generalEquivalent!.toStringAsFixed(2)}'
                    : '${generalAverage.toStringAsFixed(1)}%')
              : '—',
          icon: PlatformIcons.grade,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _HeaderStatTile(
          label: 'Attendance Rate',
          value: '${attendanceRate.toStringAsFixed(1)}%',
          icon: PlatformIcons.howToReg,
        ),
      ),
    ],
  );
}

class _HeaderStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeaderStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OverviewCard extends StatelessWidget {
  final Student? student;
  final String fallbackName;
  final String fallbackStudentId;
  final Map<String, dynamic>? gradeSummary;
  final Map<String, dynamic>? attendanceSummary;

  const _OverviewCard({
    required this.student,
    this.fallbackName = '',
    this.fallbackStudentId = '',
    required this.gradeSummary,
    required this.attendanceSummary,
  });

  @override
  Widget build(BuildContext context) {
    final name = student != null
        ? '${student!.firstName} ${student!.lastName}'
        : (fallbackName.trim().isNotEmpty ? fallbackName.trim() : '—');
    final studentId = student != null
        ? (student!.studentId)
        : (fallbackStudentId.trim().isNotEmpty
              ? fallbackStudentId.trim()
              : '—');
    final rate =
        (attendanceSummary?['attendanceRate'] as num?)?.toDouble() ?? 0;
    final present = attendanceSummary?['presentCount'] ?? 0;
    final absent = attendanceSummary?['absentCount'] ?? 0;

    final avgScore = (gradeSummary?['generalAverageScore'] is num)
        ? (gradeSummary?['generalAverageScore'] as num).toDouble()
        : double.tryParse(
                gradeSummary?['generalAverageScore']?.toString() ?? '',
              ) ??
              0.0;
    final avgEq = (gradeSummary?['generalAverageEquivalent'] is num)
        ? (gradeSummary?['generalAverageEquivalent'] as num).toDouble()
        : double.tryParse(
            gradeSummary?['generalAverageEquivalent']?.toString() ?? '',
          );
    final avgDesc =
        (gradeSummary?['generalAverageDescriptor']?.toString() ?? '').trim();

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
      child: Column(
        children: [
          // Student identity row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3949AB), Color(0xFF5B8AF5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      student != null
                          ? (student!.firstName.isNotEmpty
                                ? student!.firstName[0].toUpperCase()
                                : '?')
                          : (fallbackName.trim().isNotEmpty
                                ? fallbackName.trim()[0].toUpperCase()
                                : '?'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF1A237E),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF3FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ID: $studentId',
                              style: const TextStyle(
                                color: Color(0xFF3949AB),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
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
                    color: const Color(0xFF00C897).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00C897).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFF00C897),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFFEEF1F6),
          ),

          // Attendance mini-stats
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Average Grade',
                      style: TextStyle(
                        color: Color(0xFF9AA3B0),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      avgEq != null
                          ? '${avgScore.toStringAsFixed(1)}% • ${avgEq.toStringAsFixed(2)}'
                          : '${avgScore.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFF9C6FE4),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  avgDesc.isNotEmpty ? avgDesc : 'Percentage grade',
                  style: const TextStyle(
                    color: Color(0xFF9AA3B0),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attendance Overview',
                      style: TextStyle(
                        color: Color(0xFF9AA3B0),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      '${rate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFF5B8AF5),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _AttendanceBar(rate: rate / 100),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniStat(
                      label: 'Present',
                      value: '$present',
                      color: const Color(0xFF00C897),
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      label: 'Absent',
                      value: '$absent',
                      color: const Color(0xFFFF5C72),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceBar extends StatelessWidget {
  final double rate; // 0–1
  const _AttendanceBar({required this.rate});

  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    decoration: BoxDecoration(
      color: const Color(0xFFEEF1F6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: rate.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C897), Color(0xFF5B8AF5)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        '$value $label',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2E3A5C),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  CLASSES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ClassesTab extends StatefulWidget {
  final StudentDataRepository studentRepo;
  const _ClassesTab({required this.studentRepo});

  @override
  State<_ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<_ClassesTab>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _classes = const [];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeCtrl.reset();

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final items = await widget.studentRepo.getStudentClassesSmart(user.uid);
      setState(() {
        _classes = items;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      print('[StudentStatisticsTab] Load error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _fadeCtrl.forward();
    }
  }

  static const _palette = [
    Color(0xFF5B8AF5),
    Color(0xFF9C6FE4),
    Color(0xFFFF8A65),
    Color(0xFF26C6DA),
    Color(0xFF66BB6A),
    Color(0xFFFFCA28),
  ];

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return RefreshIndicator(
      onRefresh: () async => _load(),
      color: AppTheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _SharedHeader(
              title: 'My Classes',
              subtitle: _isLoading
                  ? 'Loading…'
                  : '${_classes.length} enrolled class${_classes.length == 1 ? '' : 'es'}',
              onSignOut: () => _signOut(context),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 16,
              20,
              isTablet ? 24 : 16,
              40,
            ),
            sliver: _isLoading
                ? const SliverToBoxAdapter(child: _ClassesShimmer())
                : _error != null
                ? SliverToBoxAdapter(child: _ErrorCard(error: _error!))
                : _classes.isEmpty
                ? SliverToBoxAdapter(
                    child: _EmptyState(
                      icon: PlatformIcons.school,
                      message: 'No enrolled classes found.',
                    ),
                  )
                : SliverList(
                    delegate: SliverChildListDelegate([
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(label: 'Enrolled Classes'),
                            const SizedBox(height: 12),
                            ...List.generate(
                              _classes.length,
                              (i) => _ClassCard(
                                classData: _classes[i],
                                index: i,
                                accent: _palette[i % _palette.length],
                                onTap: () => _onClassTap(
                                  _classes[i],
                                  _buildClassTitle(_classes[i]),
                                ),
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
    );
  }

  String _buildClassTitle(Map<String, dynamic> c) {
    final parts = <String>[
      if ((c['subject_code']?.toString() ?? '').trim().isNotEmpty)
        c['subject_code'].toString().trim(),
      if ((c['section']?.toString() ?? '').trim().isNotEmpty)
        c['section'].toString().trim(),
      if ((c['school_year']?.toString() ?? '').trim().isNotEmpty)
        c['school_year'].toString().trim(),
    ];
    return parts.isNotEmpty ? parts.join(' • ') : 'Class';
  }

  void _onClassTap(Map<String, dynamic> c, String title) {
    final teacherUid = (c['teacher_uid']?.toString() ?? '').trim();
    final classRemoteId = (c['class_remote_id']?.toString() ?? '').trim();
    if (teacherUid.isEmpty || classRemoteId.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentClassScoresScreen(
          teacherUid: teacherUid,
          classRemoteId: classRemoteId,
          title: title,
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> classData;
  final int index;
  final Color accent;
  final VoidCallback onTap;

  const _ClassCard({
    required this.classData,
    required this.index,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subjectCode = (classData['subject_code']?.toString() ?? '').trim();
    final section = (classData['section']?.toString() ?? '').trim();
    final schoolYear = (classData['school_year']?.toString() ?? '').trim();
    final teacherName = (classData['teacher_name']?.toString() ?? '').trim();
    final riskLevel = (classData['risk_level']?.toString() ?? '').trim();

    final title = [
      if (subjectCode.isNotEmpty) subjectCode,
      if (section.isNotEmpty) section,
    ].join(' • ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // Accent strip + icon
            Container(
              width: 64,
              height: 80,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(PlatformIcons.class_, color: accent, size: 19),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title.isNotEmpty ? title : 'Class',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1A237E),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RiskBadge(riskLevel: riskLevel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (schoolYear.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            PlatformIcons.calendarToday,
                            size: 11,
                            color: Color(0xFF9AA3B0),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            schoolYear,
                            style: const TextStyle(
                              color: Color(0xFF9AA3B0),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    if (teacherName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            PlatformIcons.person,
                            size: 11,
                            color: Color(0xFF9AA3B0),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              teacherName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9AA3B0),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Chevron
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(PlatformIcons.forward, color: accent, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final String riskLevel;

  const _RiskBadge({required this.riskLevel});

  @override
  Widget build(BuildContext context) {
    final level = riskLevel.trim().toLowerCase();
    final atRisk = level == 'high' || level == 'medium';

    final bg = atRisk
        ? AppTheme.danger.withValues(alpha: 0.12)
        : AppTheme.success.withValues(alpha: 0.12);
    final fg = atRisk ? AppTheme.danger : AppTheme.success;
    final text = atRisk ? 'AT RISK' : 'SAFE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassesShimmer extends StatefulWidget {
  const _ClassesShimmer();

  @override
  State<_ClassesShimmer> createState() => _ClassesShimmerState();
}

class _ClassesShimmerState extends State<_ClassesShimmer>
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.5 + 0.5 * math.sin(_anim.value * math.pi);
        return Column(
          children: List.generate(
            4,
            (_) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATISTICS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _StatisticsTab extends StatefulWidget {
  final StudentDataRepository studentRepo;
  const _StatisticsTab({required this.studentRepo});

  @override
  State<_StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends State<_StatisticsTab>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _gradeSummary = const {};
  Map<String, dynamic> _attendanceSummary = const {};
  List<Map<String, dynamic>> _recentGradeTrendScores = const [];
  bool _trendIsAssessmentScores = false;
  List<Map<String, dynamic>> _recentAttendance = const [];

  List<Map<String, dynamic>> _classes = const [];
  String? _selectedAttendanceClassKey;
  Map<String, dynamic>? _filteredAttendanceSummary;
  bool _attendanceFilterLoading = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeCtrl.reset();

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final res = await Future.wait([
        widget.studentRepo.getStudentDashboardStats(user.uid),
        widget.studentRepo.getStudentClassesSmart(user.uid),
        widget.studentRepo.getStudentAssessmentScoresSmart(user.uid),
      ]);

      final stats = res[0] as Map<String, dynamic>;
      final classes = (res[1] as List).cast<Map<String, dynamic>>();
      final assessmentScores = (res[2] as List).cast<Map<String, dynamic>>();

      final gradeSummary =
          (stats['gradeSummary'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final attendanceSummary =
          (stats['attendanceSummary'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final recentGrades =
          (stats['recentGrades'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];
      final recentAttendance =
          (stats['recentAttendance'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];

      final trendScores = [...assessmentScores];
      trendScores.sort((a, b) {
        final ad =
            DateTime.tryParse(
              (a['recorded_at'] ?? a['updated_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse(
              (b['recorded_at'] ?? b['updated_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

      print(
        '[StudentStatisticsTab] Stats loaded gradeSummaryKeys=${gradeSummary.keys.length} attendanceSummaryKeys=${attendanceSummary.keys.length} recentGrades=${recentGrades.length} recentAttendance=${recentAttendance.length} trendScores=${trendScores.length}',
      );

      setState(() {
        _gradeSummary = gradeSummary;
        _attendanceSummary = attendanceSummary;
        _trendIsAssessmentScores = trendScores.isNotEmpty;
        _recentGradeTrendScores = trendScores.isNotEmpty
            ? trendScores
            : recentGrades;
        _recentAttendance = recentAttendance;
        _classes = classes;
        _isLoading = false;
      });
      _fadeCtrl.forward();

      if (_selectedAttendanceClassKey != null) {
        await _loadAttendanceForSelectedClass();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _fadeCtrl.forward();
    }
  }

  Future<void> _loadAttendanceForSelectedClass() async {
    final key = _selectedAttendanceClassKey;
    if (key == null) return;
    final parts = key.split('|');
    if (parts.length != 2) return;
    final teacherUid = parts[0];
    final classRemoteId = parts[1];

    setState(() {
      _attendanceFilterLoading = true;
      _filteredAttendanceSummary = null;
    });

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final records = await widget.studentRepo.getStudentClassAttendanceSmart(
        firebaseUid: user.uid,
        teacherUid: teacherUid,
        classRemoteId: classRemoteId,
      );

      DateTime parseMaybeDate(dynamic v) {
        if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        return DateTime.tryParse(v.toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }

      final dayStatus = <String, String>{};
      for (final r in records) {
        final d = parseMaybeDate(r['date'] ?? r['created_at']);
        final dayKey =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final s = (r['status']?.toString() ?? '').trim().toLowerCase();

        final prev = dayStatus[dayKey];
        if (prev == 'absent') continue;
        if (s == 'absent') {
          dayStatus[dayKey] = 'absent';
        } else if (s == 'present') {
          dayStatus[dayKey] = prev ?? 'present';
        }
      }

      var present = 0;
      var absent = 0;
      for (final s in dayStatus.values) {
        if (s == 'absent') absent++;
        if (s == 'present') present++;
      }
      final total = dayStatus.length;
      final rate = total == 0 ? 0.0 : (present / total) * 100.0;

      print(
        '[StudentStatisticsTab] Attendance filter key=$key rawRecords=${records.length} uniqueDays=$total present=$present absent=$absent',
      );

      setState(() {
        _filteredAttendanceSummary = {
          'totalRecords': total,
          'presentCount': present,
          'absentCount': absent,
          'attendanceRate': rate,
        };
      });
    } catch (_) {
      setState(() {
        _filteredAttendanceSummary = {
          'totalRecords': 0,
          'presentCount': 0,
          'absentCount': 0,
          'attendanceRate': 0.0,
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _attendanceFilterLoading = false;
        });
      }
    }
  }

  Widget _buildAttendanceFilterRow() {
    if (_classes.isEmpty) return const SizedBox.shrink();

    String labelFor(Map<String, dynamic> c) {
      final subject = (c['subject_code']?.toString() ?? '').trim();
      final section = (c['section']?.toString() ?? '').trim();
      final teacher = (c['teacher_name']?.toString() ?? '').trim();
      final base = [subject, section].where((v) => v.isNotEmpty).join(' - ');
      if (teacher.isEmpty) return base.isNotEmpty ? base : 'Class';
      return base.isNotEmpty ? '$base ($teacher)' : teacher;
    }

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('Overall Attendance')),
      ..._classes
          .map((c) {
            final teacherUid = (c['teacher_uid']?.toString() ?? '').trim();
            final classRemoteId = (c['class_remote_id']?.toString() ?? '')
                .trim();
            if (teacherUid.isEmpty || classRemoteId.isEmpty) return null;
            final key = '$teacherUid|$classRemoteId';
            return DropdownMenuItem<String?>(
              value: key,
              child: Text(labelFor(c), overflow: TextOverflow.ellipsis),
            );
          })
          .whereType<DropdownMenuItem<String?>>()
          .toList(),
    ];

    return Row(
      children: [
        const Text(
          'Attendance:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedAttendanceClassKey,
                      icon: Icon(
                        PlatformIcons.dropdown,
                        color: const Color(0xFF1A237E),
                        size: 20,
                      ),
                      items: items,
                      isExpanded: true,
                      onChanged: (v) async {
                        setState(() {
                          _selectedAttendanceClassKey = v;
                        });
                        if (v == null) {
                          setState(() {
                            _filteredAttendanceSummary = null;
                          });
                          return;
                        }
                        await _loadAttendanceForSelectedClass();
                      },
                    ),
                  ),
                ),
                if (_attendanceFilterLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  double get _avgScore {
    final v = _gradeSummary['generalAverageScore'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  double? get _avgEquivalent {
    final v = _gradeSummary['generalAverageEquivalent'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  String get _avgDescriptor {
    return (_gradeSummary['generalAverageDescriptor']?.toString() ?? '').trim();
  }

  int get _totalGrades {
    final v = _gradeSummary['totalGrades'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _presentCount {
    final source = _selectedAttendanceClassKey == null
        ? _attendanceSummary
        : (_filteredAttendanceSummary ?? const <String, dynamic>{});
    final v = source['presentCount'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _totalAttendance {
    final source = _selectedAttendanceClassKey == null
        ? _attendanceSummary
        : (_filteredAttendanceSummary ?? const <String, dynamic>{});
    final v = source['totalRecords'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _absentCount => (_totalAttendance - _presentCount).clamp(0, 1 << 30);

  double get _attendanceRate {
    final source = _selectedAttendanceClassKey == null
        ? _attendanceSummary
        : (_filteredAttendanceSummary ?? const <String, dynamic>{});
    final v = source['attendanceRate'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return RefreshIndicator(
      onRefresh: () async => _load(),
      color: AppTheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _SharedHeader(
              title: 'Statistics',
              subtitle: 'Academic performance insights',
              onSignOut: () => _signOut(context),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 24 : 16,
              20,
              isTablet ? 24 : 16,
              40,
            ),
            sliver: _isLoading
                ? const SliverToBoxAdapter(child: _StatsShimmer())
                : _error != null
                ? SliverToBoxAdapter(child: _ErrorCard(error: _error!))
                : SliverList(
                    delegate: SliverChildListDelegate([
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(label: 'Overview'),
                            const SizedBox(height: 12),
                            _StatsOverviewRow(
                              avgScore: _avgScore,
                              avgEquivalent: _avgEquivalent,
                              avgDescriptor: _avgDescriptor,
                              totalGrades: _totalGrades,
                              attendanceRate: _attendanceRate,
                            ),
                            const SizedBox(height: 18),
                            _SectionLabel(label: 'Attendance'),
                            const SizedBox(height: 12),
                            _buildAttendanceFilterRow(),
                            const SizedBox(height: 10),
                            _AttendanceDonutCard(
                              present: _presentCount,
                              absent: _absentCount,
                              total: _totalAttendance,
                            ),
                            const SizedBox(height: 18),
                            _SectionLabel(label: 'Recent Grade Trend'),
                            const SizedBox(height: 12),
                            _RecentGradesLineCard(
                              recentGrades: _recentGradeTrendScores,
                              isAssessmentScores: _trendIsAssessmentScores,
                            ),
                            if (_recentAttendance.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              _SectionLabel(label: 'Recent Attendance'),
                              const SizedBox(height: 12),
                              _RecentAttendanceListCard(
                                recentAttendance: _recentAttendance,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatsShimmer extends StatefulWidget {
  const _StatsShimmer();

  @override
  State<_StatsShimmer> createState() => _StatsShimmerState();
}

class _StatsShimmerState extends State<_StatsShimmer>
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.5 + 0.5 * math.sin(_anim.value * math.pi);
        return Column(
          children: [
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatsOverviewRow extends StatelessWidget {
  final double avgScore;
  final double? avgEquivalent;
  final String avgDescriptor;
  final int totalGrades;
  final double attendanceRate;

  const _StatsOverviewRow({
    required this.avgScore,
    required this.avgEquivalent,
    required this.avgDescriptor,
    required this.totalGrades,
    required this.attendanceRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.percent,
            label: 'Average',
            value: avgEquivalent != null
                ? '${avgScore.toStringAsFixed(1)}% • ${avgEquivalent!.toStringAsFixed(2)}'
                : '${avgScore.toStringAsFixed(1)}%',
            suffix: avgDescriptor.isNotEmpty ? avgDescriptor : '',
            color: const Color(0xFF5B8AF5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.grade,
            label: 'Grades',
            value: '$totalGrades',
            suffix: 'items',
            color: const Color(0xFF9C6FE4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: PlatformIcons.howToReg,
            label: 'Attendance',
            value: attendanceRate.toStringAsFixed(0),
            suffix: '%',
            color: const Color(0xFF00C897),
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
      height: 110, // Fixed height for all cards
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14, // Reduced from 18 to prevent overflow
                      ),
                    ),
                    if (suffix.trim().isNotEmpty)
                      TextSpan(
                        text: ' $suffix',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w700,
                          fontSize: 9, // Reduced from 10
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
                  fontSize: 9, // Reduced from 10
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttendanceDonutCard extends StatelessWidget {
  final int present;
  final int absent;
  final int total;

  const _AttendanceDonutCard({
    required this.present,
    required this.absent,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final presentColor = AppTheme.success;
    final absentColor = AppTheme.danger;

    final safeTotal = total <= 0 ? 1 : total;
    final presentPct = (present / safeTotal) * 100.0;

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: presentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    PlatformIcons.calendarMonth,
                    color: presentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Attendance Distribution',
                    style: TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEF1F6)),
                  ),
                  child: Text(
                    '$total total',
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 0,
                          centerSpaceRadius: 44,
                          startDegreeOffset: -90,
                          sections: [
                            PieChartSectionData(
                              value: present.toDouble(),
                              color: presentColor,
                              showTitle: false,
                              radius: 16,
                            ),
                            PieChartSectionData(
                              value: absent.toDouble(),
                              color: absentColor,
                              showTitle: false,
                              radius: 16,
                            ),
                          ],
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              total == 0
                                  ? '0%'
                                  : '${presentPct.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Color(0xFF1A237E),
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const Text(
                              'present',
                              style: TextStyle(
                                color: Color(0xFF9AA3B0),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      _LegendRow(
                        color: presentColor,
                        label: 'Present',
                        value: '$present',
                      ),
                      const SizedBox(height: 10),
                      _LegendRow(
                        color: absentColor,
                        label: 'Absent',
                        value: '$absent',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF1F6)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2E3A5C),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentGradesLineCard extends StatelessWidget {
  final List<Map<String, dynamic>> recentGrades;
  final bool isAssessmentScores;

  const _RecentGradesLineCard({
    required this.recentGrades,
    required this.isAssessmentScores,
  });

  Future<void> _openFullscreenChart(
    BuildContext context,
    List<FlSpot> pts,
    Color primary,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final bg = Theme.of(dialogContext).scaffoldBackgroundColor;
        return Dialog(
          backgroundColor: bg,
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAssessmentScores
                              ? 'Assessment scores trend'
                              : 'Computed grades trend',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(PlatformIcons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AspectRatio(
                    aspectRatio: 1.4,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final pointSpacing = 34.0;
                        final minChartWidth = constraints.maxWidth;
                        final desiredWidth = pts.isEmpty
                            ? minChartWidth
                            : (pts.length - 1) * pointSpacing + 80;
                        final chartWidth = desiredWidth < minChartWidth
                            ? minChartWidth
                            : desiredWidth;

                        return ClipRect(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: chartWidth,
                              child: LineChart(
                                LineChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: const FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  minY: 0,
                                  maxY: 100,
                                  minX: 0,
                                  maxX: pts.isEmpty
                                      ? 1
                                      : (pts.length - 1).toDouble(),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: pts,
                                      isCurved: true,
                                      color: primary,
                                      barWidth: 3,
                                      dotData: const FlDotData(show: true),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: primary.withValues(alpha: 0.10),
                                      ),
                                    ),
                                  ],
                                  lineTouchData: LineTouchData(
                                    handleBuiltInTouches: true,
                                    touchTooltipData: LineTouchTooltipData(
                                      getTooltipColor: (group) =>
                                          const Color(0xFF1A237E),
                                      tooltipRoundedRadius: 10,
                                      getTooltipItems: (touchedSpots) {
                                        return touchedSpots.map((barSpot) {
                                          final idx = barSpot.x.round().clamp(
                                            0,
                                            recentGrades.length - 1,
                                          );
                                          final g = recentGrades[idx];

                                          final subject =
                                              (g['subject_code'] ??
                                                      g['subject_name'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final task =
                                              (g['assessment_name'] ??
                                                      g['category_name'] ??
                                                      g['descriptor'] ??
                                                      '')
                                                  .toString()
                                                  .trim();
                                          final pct = _pct(g);

                                          final titleParts = <String>[];
                                          if (subject.isNotEmpty) {
                                            titleParts.add(subject);
                                          }
                                          if (task.isNotEmpty) {
                                            titleParts.add(task);
                                          }
                                          final title = titleParts.isEmpty
                                              ? 'Score'
                                              : titleParts.join(' • ');

                                          return LineTooltipItem(
                                            '$title\n${pct.toStringAsFixed(1)}%',
                                            const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                              height: 1.25,
                                            ),
                                          );
                                        }).toList();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _pct(Map<String, dynamic> g) {
    final fromComputed = g['percent'];
    if (fromComputed is num) {
      final pct = fromComputed.toDouble();
      // Debug log for unusual values
      if (pct > 100 || pct < 0) {
        print('[StudentHomeScreen] Unusual percent value: $pct for grade: $g');
        // If percent is unrealistic, calculate from score/max_score
        final score = (g['score'] is num)
            ? (g['score'] as num).toDouble()
            : double.tryParse(g['score']?.toString() ?? '') ?? 0.0;
        final maxScore = (g['max_score'] is num)
            ? (g['max_score'] as num).toDouble()
            : double.tryParse(g['max_score']?.toString() ?? '') ?? 0.0;
        if (maxScore > 0) {
          final calculatedPct = (score / maxScore) * 100.0;
          print(
            '[StudentHomeScreen] Using calculated percentage: $calculatedPct% (score: $score, maxScore: $maxScore)',
          );
          return calculatedPct.clamp(0.0, 100.0);
        }
      }
      return pct.clamp(0.0, 100.0);
    }

    final score = (g['score'] is num)
        ? (g['score'] as num).toDouble()
        : double.tryParse(g['score']?.toString() ?? '') ?? 0.0;
    final maxScore = (g['max_score'] is num)
        ? (g['max_score'] as num).toDouble()
        : double.tryParse(g['max_score']?.toString() ?? '') ?? 0.0;

    // Handle invalid max_score
    if (maxScore <= 0) {
      print('[StudentHomeScreen] Invalid max_score: $maxScore for grade: $g');
      // If max_score is 0 or negative, try to infer a reasonable value
      // Common assessment max scores: 50, 100
      if (score > 0) {
        // If score is > 100, assume max should be 100
        if (score > 100) {
          print('[StudentHomeScreen] Assuming max_score=100 for score=$score');
          return (score / 100.0).clamp(0.0, 1.0) * 100.0;
        }
        // If score is <= 100 and > 50, assume max should be 100
        if (score > 50) {
          print('[StudentHomeScreen] Assuming max_score=100 for score=$score');
          return score; // score is already a percentage
        }
        // If score is <= 50, assume max should be 50
        print('[StudentHomeScreen] Assuming max_score=50 for score=$score');
        return (score / 50.0) * 100.0;
      }
      return 0.0;
    }

    final pct = (score / maxScore) * 100.0;
    // Debug log for unusual calculated percentages
    if (pct > 150) {
      // Increased threshold to avoid false positives
      print(
        '[StudentHomeScreen] Very high calculated percentage: $pct% (score: $score, maxScore: $maxScore)',
      );
      print('[StudentHomeScreen] This might indicate a data entry error');
    }
    return pct.clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final pts = recentGrades
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), _pct(e.value)))
        .toList();

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    PlatformIcons.showChart,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isAssessmentScores
                        ? 'Assessment scores trend'
                        : 'Computed grades trend',
                    style: const TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEF1F6)),
                  ),
                  child: Text(
                    '${recentGrades.length} pts',
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: pts.isEmpty
                      ? null
                      : () => _openFullscreenChart(context, pts, primary),
                  icon: Icon(
                    PlatformIcons.fullscreen,
                    color: const Color(0xFF9AA3B0),
                    size: 18,
                  ),
                  tooltip: 'Fullscreen',
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pts.isEmpty)
              _EmptyState(
                icon: PlatformIcons.insights,
                message: 'No records available yet.',
              )
            else
              SizedBox(
                height: 200,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pointSpacing = 28.0;
                    final minChartWidth = constraints.maxWidth;
                    final desiredWidth = pts.isEmpty
                        ? minChartWidth
                        : (pts.length - 1) * pointSpacing + 60;
                    final chartWidth = desiredWidth < minChartWidth
                        ? minChartWidth
                        : desiredWidth;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            child: LineChart(
                              LineChartData(
                                gridData: const FlGridData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                borderData: FlBorderData(show: false),
                                minY: 0,
                                maxY: 100,
                                minX: 0,
                                maxX: pts.isEmpty
                                    ? 1
                                    : (pts.length - 1).toDouble(),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: pts,
                                    isCurved: true,
                                    color: primary,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: primary.withValues(alpha: 0.10),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  handleBuiltInTouches: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (group) =>
                                        const Color(0xFF1A237E),
                                    tooltipRoundedRadius: 10,
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots.map((barSpot) {
                                        final idx = barSpot.x.round().clamp(
                                          0,
                                          recentGrades.length - 1,
                                        );
                                        final g = recentGrades[idx];

                                        final subject =
                                            (g['subject_code'] ??
                                                    g['subject_name'] ??
                                                    '')
                                                .toString()
                                                .trim();
                                        final task =
                                            (g['assessment_name'] ??
                                                    g['category_name'] ??
                                                    g['descriptor'] ??
                                                    '')
                                                .toString()
                                                .trim();
                                        final pct = _pct(g);

                                        final titleParts = <String>[];
                                        if (subject.isNotEmpty) {
                                          titleParts.add(subject);
                                        }
                                        if (task.isNotEmpty) {
                                          titleParts.add(task);
                                        }
                                        final title = titleParts.isEmpty
                                            ? 'Score'
                                            : titleParts.join(' • ');

                                        return LineTooltipItem(
                                          '$title\n${pct.toStringAsFixed(1)}%',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            height: 1.25,
                                          ),
                                        );
                                      }).toList();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (recentGrades.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...recentGrades.take(3).toList().asMap().entries.map((entry) {
                final i = entry.key;
                final g = entry.value;
                final pct = _pct(g);
                final eq = (g['equivalent'] is num)
                    ? (g['equivalent'] as num).toDouble()
                    : double.tryParse(g['equivalent']?.toString() ?? '');
                final desc = (g['descriptor']?.toString() ?? '').trim();
                final assessmentName = (g['assessment_name']?.toString() ?? '')
                    .trim();
                final categoryName = (g['category_name']?.toString() ?? '')
                    .trim();
                final subjectCode = (g['subject_code']?.toString() ?? '')
                    .trim();
                final labelParts = <String>[];
                if (assessmentName.isNotEmpty) {
                  labelParts.add(assessmentName);
                } else if (categoryName.isNotEmpty) {
                  labelParts.add(categoryName);
                } else if (subjectCode.isNotEmpty) {
                  labelParts.add(subjectCode);
                } else if (desc.isNotEmpty) {
                  labelParts.add(desc);
                } else {
                  labelParts.add('Score ${i + 1}');
                }
                final label = labelParts.join(' • ');
                final value = eq != null
                    ? '${pct.toStringAsFixed(1)}% • ${eq.toStringAsFixed(2)}'
                    : '${pct.toStringAsFixed(1)}%';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LegendRow(color: primary, label: label, value: value),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentAttendanceListCard extends StatelessWidget {
  final List<Map<String, dynamic>> recentAttendance;

  const _RecentAttendanceListCard({required this.recentAttendance});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    const presentColor = AppTheme.success;
    const absentColor = AppTheme.danger;

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    PlatformIcons.eventAvailable,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Latest attendance records',
                    style: TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEF1F6)),
                  ),
                  child: Text(
                    '${recentAttendance.length}',
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentAttendance.isEmpty)
              _EmptyState(
                icon: PlatformIcons.eventBusy,
                message: 'No attendance records available yet.',
              )
            else
              ...recentAttendance.take(10).map((a) {
                final status = (a['status']?.toString() ?? '')
                    .trim()
                    .toLowerCase();
                final isPresent = status == 'present';
                final color = isPresent ? presentColor : absentColor;
                final label = isPresent ? 'Present' : 'Absent';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEEF1F6)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF2E3A5C),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        (a['date'] ?? a['created_at'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9AA3B0),
                          fontSize: 11,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
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
          child: Icon(icon, color: const Color(0xFF5B8AF5), size: 30),
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
//  Bottom Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────

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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final primary = Theme.of(context).colorScheme.primary;

    Widget bottomNavContent = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final selected = selectedIndex == i;

            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? LinearGradient(
                                  colors: [
                                    gradientColors.first,
                                    gradientColors.last,
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? Colors.transparent
                                : const Color(0xFFE7EAF3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFFB0BAD0),
                              size: 21,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? const Color(0xFF1A237E)
                              : const Color(0xFFB0BAD0),
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
    );

    // Apply WebView-specific styling
    if (kIsWeb) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.25,
        ),
        child: bottomNavContent,
      );
    } else {
      return bottomNavContent;
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
