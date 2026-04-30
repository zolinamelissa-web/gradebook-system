import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/attendance_model.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/student_repository.dart';
import 'attendance_table_screen.dart';
import '../home/home_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final ClassModel classModel;

  const AttendanceScreen({super.key, required this.classModel});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceRepository _attRepo = AttendanceRepository();
  final GradingRepository _gradingRepo = GradingRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final ScrollController _scrollController = ScrollController();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  List<GradingPeriod> _periods = [];
  GradingPeriod? _selectedPeriod;
  List<Student> _students = [];
  List<Attendance> _todayAttendance = [];
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      print('[AttendanceScreen] Error loading grading periods: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatYmd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  ({String startDate, String endDate}) _monthRange(DateTime anyDayInMonth) {
    final start = DateTime(anyDayInMonth.year, anyDayInMonth.month, 1);
    final end = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1, 0);
    return (startDate: _formatYmd(start), endDate: _formatYmd(end));
  }

  String _statusLabel(String s) {
    if (s == 'present') return 'Present';
    if (s == 'absent') return 'Absent';
    if (s == 'late') return 'Late';
    return s;
  }

  Color _statusColor(String s) {
    if (s == 'present') return AppTheme.success;
    if (s == 'absent') return AppTheme.danger;
    if (s == 'late') return AppTheme.warning;
    return AppTheme.textSecondary;
  }

  Future<DateTime?> _pickMonth(DateTime initialMonth) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F6FB),
      builder: (ctx) {
        DateTime displayMonth = DateTime(
          initialMonth.year,
          initialMonth.month,
          1,
        );

        return StatefulBuilder(
          builder: (context, setModalState) {
            final themeProvider = Provider.of<ThemeProvider>(context);
            final monthLabel = DateFormat(
              'MMMM yyyy',
              'en',
            ).format(displayMonth);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF1A237E,
                            ).withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final prev = DateTime(
                                displayMonth.year,
                                displayMonth.month - 1,
                                1,
                              );
                              setModalState(() => displayMonth = prev);
                            },
                            icon: const Icon(CupertinoIcons.chevron_left),
                            tooltip: 'Previous month',
                          ),
                          Expanded(
                            child: Text(
                              monthLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final next = DateTime(
                                displayMonth.year,
                                displayMonth.month + 1,
                                1,
                              );
                              if (next.isAfter(DateTime.now())) return;
                              setModalState(() => displayMonth = next);
                            },
                            icon: const Icon(CupertinoIcons.chevron_right),
                            tooltip: 'Next month',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            DateTime(displayMonth.year, displayMonth.month, 1),
                          );
                        },
                        icon: const Icon(CupertinoIcons.check_mark),
                        label: const Text('Select'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeProvider.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMonthlyHistory() async {
    if (_selectedPeriod == null) return;

    final initial = DateTime.parse(_selectedDate);
    final pickedMonth = await _pickMonth(
      DateTime(initial.year, initial.month, 1),
    );
    if (pickedMonth == null || !mounted) return;

    final initialMonth = DateTime(pickedMonth.year, pickedMonth.month, 1);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F6FB),
      builder: (ctx) {
        DateTime selectedMonth = initialMonth;
        bool isLoading = true;
        Object? loadError;
        List<Attendance> rows = [];

        Future<void> load() async {
          if (_selectedPeriod == null) return;
          final range = _monthRange(selectedMonth);
          print(
            '[AttendanceScreen] Loading monthly history start=${range.startDate} end=${range.endDate}',
          );
          try {
            final data = await _attRepo.getAttendanceByDateRange(
              classId: widget.classModel.id!,
              periodId: _selectedPeriod!.id!,
              startDate: range.startDate,
              endDate: range.endDate,
            );
            rows = data;
            loadError = null;
          } catch (e) {
            loadError = e;
            rows = [];
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> ensureLoaded() async {
              setModalState(() {
                isLoading = true;
                loadError = null;
              });
              await load();
              setModalState(() => isLoading = false);
            }

            if (isLoading && rows.isEmpty && loadError == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ensureLoaded();
              });
            }

            final monthLabel = DateFormat(
              'MMMM yyyy',
              'en',
            ).format(selectedMonth);
            final grouped = <String, List<Attendance>>{};
            for (final r in rows) {
              grouped.putIfAbsent(r.date, () => []).add(r);
            }
            final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Attendance History',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final newPick = await showDatePicker(
                              context: context,
                              initialDate: selectedMonth,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              helpText: 'Select month',
                            );
                            if (newPick == null) return;
                            setModalState(() {
                              selectedMonth = DateTime(
                                newPick.year,
                                newPick.month,
                                1,
                              );
                            });
                            await ensureLoaded();
                          },
                          icon: Icon(PlatformIcons.calendarMonth),
                          label: Text(monthLabel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (loadError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'Failed to load attendance: $loadError',
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (dates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            'No attendance records for this month.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: dates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final date = dates[i];
                            final dayLabel = DateFormat(
                              'MMM d, yyyy',
                            ).format(DateTime.parse(date));
                            final items = grouped[date] ?? const [];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dayLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...items.map((r) {
                                    final label = _statusLabel(r.status);
                                    final color = _statusColor(r.status);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              r.studentName ??
                                                  'Student #${r.studentId}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadData() async {
    if (_selectedPeriod == null) return;
    setState(() => _isLoading = true);
    try {
      final students = await _studentRepo.getStudentsByClass(
        widget.classModel.id!,
      );
      final attendance = await _attRepo.getAttendanceByDate(
        classId: widget.classModel.id!,
        periodId: _selectedPeriod!.id!,
        date: _selectedDate,
      );
      print(
        '[AttendanceScreen] Loaded ${students.length} students, ${attendance.length} records for $_selectedDate',
      );
      if (mounted) {
        setState(() {
          _students = students;
          _todayAttendance = attendance;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[AttendanceScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _getStatus(int studentId) {
    return _todayAttendance
        .where((a) => a.studentId == studentId)
        .firstOrNull
        ?.status;
  }

  bool _hasAttendance(int studentId) {
    return _todayAttendance.any((a) => a.studentId == studentId);
  }

  void _scrollToNextUnrecorded() {
    final currentIndex = _students.indexWhere((s) => !_hasAttendance(s.id!));
    if (currentIndex != -1 && _scrollController.hasClients) {
      final itemHeight = 62.0; // Row height + separator
      final offset = currentIndex * itemHeight;
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _setStatus(Student student, String status) async {
    if (_selectedPeriod == null) return;
    final now = DateTime.now().toIso8601String();
    final att = Attendance(
      studentId: student.id!,
      classId: widget.classModel.id!,
      gradingPeriodId: _selectedPeriod!.id!,
      date: _selectedDate,
      status: status,
      createdAt: now,
    );
    await _attRepo.upsertAttendance(att);
    print(
      '[AttendanceScreen] Set ${student.fullName} -> $status on $_selectedDate',
    );
    await _loadData();

    // Auto-scroll to next student without attendance
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToNextUnrecorded();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
      _loadData();
    }
  }

  Future<void> _markAll(String status) async {
    for (final s in _students) {
      await _setStatus(s, status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final displayDate = DateFormat(
      'MMM d, yyyy',
    ).format(DateTime.parse(_selectedDate));
    final subjectTitle = (widget.classModel.subject?.code.isNotEmpty ?? false)
        ? widget.classModel.subject!.code
        : (widget.classModel.subject?.name ?? widget.classModel.displayName);
    final subjectDescription =
        (widget.classModel.subject?.description != null &&
            widget.classModel.subject!.description!.trim().isNotEmpty)
        ? widget.classModel.subject!.description!.trim()
        : null;
    final headerSubtitle = subjectDescription != null
        ? '$subjectTitle • $displayDate\n$subjectDescription'
        : '$subjectTitle • $displayDate';
    final presentCount = _todayAttendance
        .where((a) => a.status == 'present')
        .length;
    final absentCount = _todayAttendance
        .where((a) => a.status == 'absent')
        .length;
    final lateCount = _todayAttendance.where((a) => a.status == 'late').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Attendance',
            subtitle: headerSubtitle,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _pickDate,
                icon: Icon(PlatformIcons.calendarMonth, color: Colors.white),
                tooltip: 'Pick date',
              ),
              IconButton(
                onPressed: () {
                  if (_selectedPeriod == null) return;
                  print(
                    '[AttendanceScreen] Opening AttendanceTableScreen classId=${widget.classModel.id} periodId=${_selectedPeriod!.id} periodName=${_selectedPeriod!.name}',
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AttendanceTableScreen(
                        classModel: widget.classModel,
                        periodId: _selectedPeriod!.id!,
                        periodName: _selectedPeriod!.name,
                      ),
                    ),
                  );
                },
                icon: Icon(PlatformIcons.tableChart, color: Colors.white),
                tooltip: 'Attendance table',
              ),
              IconButton(
                onPressed: _openMonthlyHistory,
                icon: Icon(PlatformIcons.viewList, color: Colors.white),
                tooltip: 'Monthly attendance list',
              ),
            ],
          ),
          // Scrollable Attendance Content
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
                : _students.isEmpty
                ? const Center(
                    child: Text(
                      'No students enrolled.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : Column(
                    children: [
                      _TodayAttendanceCard(
                        presentCount: presentCount,
                        absentCount: absentCount,
                        lateCount: lateCount,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            const Text(
                              'Mark All:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _MarkAllButton(
                              label: 'Present',
                              color: AppTheme.success,
                              onTap: () => _markAll('present'),
                            ),
                            const SizedBox(width: 6),
                            _MarkAllButton(
                              label: 'Absent',
                              color: AppTheme.danger,
                              onTap: () => _markAll('absent'),
                            ),
                            const SizedBox(width: 6),
                            _MarkAllButton(
                              label: 'Late',
                              color: AppTheme.warning,
                              onTap: () => _markAll('late'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                            itemCount: _students.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _AttendanceRow(
                              student: _students[i],
                              status: _getStatus(_students[i].id!),
                              hasAttendance: _hasAttendance(_students[i].id!),
                              onChanged: (s) => _setStatus(_students[i], s),
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _TodayAttendanceCard extends StatelessWidget {
  final int presentCount;
  final int absentCount;
  final int lateCount;

  const _TodayAttendanceCard({
    required this.presentCount,
    required this.absentCount,
    required this.lateCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget attendanceTile({
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

    return SizedBox(
      width: double.infinity,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
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
              'Today’s Attendance',
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
                attendanceTile(
                  label: 'Present',
                  value: presentCount,
                  color: AppTheme.success,
                ),
                attendanceTile(
                  label: 'Absent',
                  value: absentCount,
                  color: AppTheme.danger,
                ),
                attendanceTile(
                  label: 'Late',
                  value: lateCount,
                  color: AppTheme.warning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkAllButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MarkAllButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _AttendanceRow extends StatelessWidget {
  final Student student;
  final String? status;
  final bool hasAttendance;
  final void Function(String) onChanged;

  const _AttendanceRow({
    required this.student,
    required this.status,
    required this.hasAttendance,
    required this.onChanged,
  });

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !hasAttendance
              ? AppTheme.divider
              : status == 'absent'
              ? AppTheme.danger.withValues(alpha: 0.3)
              : status == 'late'
              ? AppTheme.warning.withValues(alpha: 0.3)
              : AppTheme.success.withValues(alpha: 0.3),
          width: 1.5,
        ),
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
          _StatusToggle(
            status: status,
            hasAttendance: hasAttendance,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusToggle extends StatelessWidget {
  final String? status;
  final bool hasAttendance;
  final void Function(String) onChanged;
  const _StatusToggle({
    required this.status,
    required this.hasAttendance,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleBtn(
          label: 'P',
          status: 'present',
          current: status,
          hasAttendance: hasAttendance,
          color: AppTheme.success,
          onTap: () => onChanged('present'),
        ),
        const SizedBox(width: 4),
        _ToggleBtn(
          label: 'A',
          status: 'absent',
          current: status,
          hasAttendance: hasAttendance,
          color: AppTheme.danger,
          onTap: () => onChanged('absent'),
        ),
        const SizedBox(width: 4),
        _ToggleBtn(
          label: 'L',
          status: 'late',
          current: status,
          hasAttendance: hasAttendance,
          color: AppTheme.warning,
          onTap: () => onChanged('late'),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final String status;
  final String? current;
  final bool hasAttendance;
  final Color color;
  final VoidCallback onTap;
  const _ToggleBtn({
    required this.label,
    required this.status,
    required this.current,
    required this.hasAttendance,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == status;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: !hasAttendance
              ? Colors.transparent
              : selected
              ? color
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: !hasAttendance
                ? AppTheme.divider
                : color.withValues(alpha: selected ? 1 : 0.3),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: !hasAttendance
                ? AppTheme.textSecondary
                : selected
                ? Colors.white
                : color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
