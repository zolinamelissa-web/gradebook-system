import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_account_repository.dart';
import '../../data/repositories/student_data_repository.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/models/student_model.dart';
import '../auth/login_screen.dart';
import 'student_announcements_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final StudentDataRepository _studentRepo = StudentDataRepository();

  bool _isLoading = true;
  bool _isSyncing = false;

  Map<String, dynamic>? _studentProfile;
  Map<String, dynamic>? _gradeSummary;
  Map<String, dynamic>? _attendanceSummary;
  List<Map<String, dynamic>>? _recentGrades;
  List<Map<String, dynamic>>? _recentAttendance;
  List<Map<String, dynamic>>? _classes;
  List<Map<String, dynamic>>? _followUpsDueToday;
  int _announcementCount = 0;

  bool _followUpDueTodayModalShown = false;

  String? _syncError;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _showFollowUpDueTodayModal({required int count}) async {
    if (count <= 0) return;
    if (!mounted) return;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final gradientColors = themeProvider.getGradientColors();
    print(
      '[StudentDashboardScreen] Showing follow-up due today modal count=$count',
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
                        PlatformIcons.eventAvailable,
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
                            'You have $count follow-up intervention(s) scheduled today.',
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gradientColors.first,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFollowUpsDueTodayCard(List<Map<String, dynamic>> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PlatformIcons.eventAvailable, color: AppTheme.warning),
                const SizedBox(width: 10),
                Text(
                  'Follow-ups Scheduled Today',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...rows.take(3).map((r) {
              final title = (r['title']?.toString() ?? '').trim();
              final desc = (r['description']?.toString() ?? '').trim();
              final subjectCode = (r['subject_code']?.toString() ?? '').trim();
              final subjectName = (r['subject_name']?.toString() ?? '').trim();
              final followUpDate = (r['follow_up_date']?.toString() ?? '')
                  .trim();
              final status = (r['status']?.toString() ?? '').trim();

              final subtitleParts = <String>[];
              if (subjectCode.isNotEmpty) subtitleParts.add(subjectCode);
              if (subjectName.isNotEmpty) subtitleParts.add(subjectName);
              if (followUpDate.isNotEmpty) subtitleParts.add(followUpDate);
              if (status.isNotEmpty) subtitleParts.add(status);
              final subtitle = subtitleParts.join(' • ');

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Intervention',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const Divider(height: 18),
                  ],
                ),
              );
            }).toList(),
            if (rows.length > 3)
              Text(
                'and ${rows.length - 3} more...',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadStudentData() async {
    setState(() {
      _isLoading = true;
      _syncError = null;
    });

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Not logged in');
      }

      // Load all student data
      final results = await Future.wait([
        _studentRepo.getCurrentStudentProfile(firebaseUser.uid),
        _studentRepo.getStudentDashboardStats(firebaseUser.uid),
        _studentRepo.getStudentClassesSmart(firebaseUser.uid),
        _studentRepo.getStudentFollowUpsDueTodaySmart(
          firebaseUid: firebaseUser.uid,
        ),
      ]);

      // Load announcement count
      await _loadAnnouncementCount(firebaseUser.uid);

      setState(() {
        final student = results[0] as Student?;
        _studentProfile = student != null
            ? {
                'name': '${student.firstName} ${student.lastName}',
                'studentId': student.studentId,
                'email': student.email,
              }
            : null;

        final stats = results[1] as Map<String, dynamic>;
        _gradeSummary = stats['gradeSummary'] as Map<String, dynamic>?;
        _attendanceSummary =
            stats['attendanceSummary'] as Map<String, dynamic>?;

        _recentGrades = (stats['recentGrades'] as List<Map<String, dynamic>>?)
            ?.take(5)
            .toList();
        _recentAttendance =
            (stats['recentAttendance'] as List<Map<String, dynamic>>?)
                ?.take(5)
                .toList();

        _classes = results[2] as List<Map<String, dynamic>>;

        _followUpsDueToday = (results[3] as List).cast<Map<String, dynamic>>();
        print(
          '[StudentDashboardScreen] Follow-ups due today loaded count=${_followUpsDueToday?.length ?? 0}',
        );

        _lastSyncTime = DateTime.now();
        _isLoading = false;
      });

      final dueCount = _followUpsDueToday?.length ?? 0;
      if (!_followUpDueTodayModalShown && dueCount > 0) {
        _followUpDueTodayModalShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFollowUpDueTodayModal(count: dueCount);
        });
      }
    } catch (e) {
      print('[StudentDashboardScreen] Load student data error: $e');
      setState(() {
        _syncError = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncData() async {
    setState(() {
      _isSyncing = true;
      _syncError = null;
    });

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Not logged in');
      }

      final result = await _studentRepo.syncStudentData(
        firebaseUid: firebaseUser.uid,
      );

      if (result.error != null) {
        throw Exception(result.error);
      }

      // Reload data after sync
      await _loadStudentData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync complete: ${result.summary()}'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _syncError = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _loadAnnouncementCount(String firebaseUid) async {
    try {
      final classes = await _studentRepo.getStudentClassesSmart(firebaseUid);
      int totalCount = 0;

      for (final classData in classes) {
        final classRemoteId = classData['remote_id'] as String?;
        if (classRemoteId == null) continue;

        try {
          final announcements = await AnnouncementRepository.instance
              .getAnnouncementsForClass(classRemoteId);
          totalCount += announcements.length;
        } catch (e) {
          print('[StudentDashboard] Error loading announcements for class: $e');
        }
      }

      setState(() {
        _announcementCount = totalCount;
      });
    } catch (e) {
      print('[StudentDashboard] Error loading announcement count: $e');
    }
  }

  void _navigateToAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentAnnouncementsScreen()),
    ).then((_) => _loadStudentData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          _studentProfile != null
              ? 'Welcome, ${_studentProfile!['name']}!'
              : 'Student Dashboard',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'Announcements',
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.textPrimary,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const StudentAnnouncementsScreen(),
                      ),
                    );
                  },
                ),
                if (_announcementCount > 0)
                  Positioned(
                    right: 4,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        _announcementCount > 99 ? '99+' : '$_announcementCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(PlatformIcons.logout),
            onPressed: () async {
              try {
                await StudentAccountRepository.clearActiveTeacherContext();
                print(
                  '[StudentDashboardScreen] Cleared active teacher context',
                );
              } catch (e) {
                print(
                  '[StudentDashboardScreen] Clear teacher context error: $e',
                );
              }
              if (!mounted) return;

              final pinHash = await DatabaseHelper.instance.getSetting(
                'student_pin_hash',
              );
              final hasPin = pinHash != null && pinHash.trim().isNotEmpty;
              print(
                '[StudentDashboardScreen] Logout lock redirect hasStudentPin=$hasPin',
              );

              if (hasPin) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(isStudent: true),
                  ),
                  (_) => false,
                );
                return;
              }

              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/auth', (_) => false);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStudentData,
        color: AppTheme.primary,
        child: Column(
          children: [
            // Fixed Header
            WaveHeader(
              title: 'Student Dashboard',
              subtitle: 'View your academic records',
              actions: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InkWell(
                      onTap: _navigateToAnnouncements,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(16),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withAlpha(28)),
                        ),
                        child: Icon(
                          _announcementCount > 0
                              ? PlatformIcons.notificationsActive
                              : PlatformIcons.notifications,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    if (_announcementCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            _announcementCount > 99
                                ? '99+'
                                : '$_announcementCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Scrollable Content
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_syncError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PlatformIcons.error, size: 64, color: AppTheme.danger),
              const SizedBox(height: 16),
              Text(
                'Error loading data',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _syncError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadStudentData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_followUpsDueToday != null && _followUpsDueToday!.isNotEmpty) ...[
            _buildFollowUpsDueTodayCard(_followUpsDueToday!),
            const SizedBox(height: 24),
          ],
          // Student Info Card
          if (_studentProfile != null) ...[
            _buildStudentInfoCard(),
            const SizedBox(height: 24),
          ],

          _buildClassesSection(),
          const SizedBox(height: 24),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Grades',
                  '${_gradeSummary?['totalGrades'] ?? 0}',
                  PlatformIcons.grade,
                  AppTheme.primary,
                  () => _navigateToGrades(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Attendance',
                  '${_attendanceSummary?['attendanceRate']?.toStringAsFixed(1) ?? 0}%',
                  PlatformIcons.calendarToday,
                  AppTheme.secondary,
                  () => _navigateToAttendance(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Avg Score',
                  '${_gradeSummary?['averageScore']?.toStringAsFixed(1) ?? 0}',
                  PlatformIcons.analytics,
                  AppTheme.accent,
                  () => _navigateToGrades(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Subjects',
                  '${_gradeSummary?['subjectsCount'] ?? 0}',
                  PlatformIcons.school,
                  AppTheme.success,
                  () => _navigateToGrades(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Recent Activity
          _buildRecentActivity(),
          const SizedBox(height: 32),

          // Sync Status
          _buildSyncStatus(),
        ],
      ),
    );
  }

  Widget _buildClassesSection() {
    final classes = _classes ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Classes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (classes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No enrolled classes found.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          ...classes.map((c) {
            final teacherName = (c['teacher_name']?.toString() ?? '').trim();
            final subjectCode = (c['subject_code']?.toString() ?? '').trim();
            final section = (c['section']?.toString() ?? '').trim();
            final schoolYear = (c['school_year']?.toString() ?? '').trim();
            final subtitleParts = <String>[];
            if (subjectCode.isNotEmpty) subtitleParts.add(subjectCode);
            if (section.isNotEmpty) subtitleParts.add(section);
            if (schoolYear.isNotEmpty) subtitleParts.add(schoolYear);
            final subtitle = subtitleParts.join(' • ');

            return Card(
              child: ListTile(
                leading: Icon(PlatformIcons.class_, color: AppTheme.primary),
                title: Text(
                  subtitle.isNotEmpty ? subtitle : 'Class',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: teacherName.isNotEmpty
                    ? Text(
                        teacherName,
                        style: TextStyle(color: AppTheme.textSecondary),
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStudentInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary,
              child: Text(
                _studentProfile!['name']
                    .toString()
                    .split(' ')
                    .map((e) => e[0])
                    .take(2)
                    .join()
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _studentProfile!['name'],
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${_studentProfile!['studentId']}',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  if (_studentProfile!['email'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _studentProfile!['email'],
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        // Recent Grades
        if (_recentGrades != null && _recentGrades!.isNotEmpty) ...[
          _buildActivitySection(
            'Recent Grades',
            _recentGrades!,
            'subject_name',
            'score',
          ),
          const SizedBox(height: 16),
        ],

        // Recent Attendance
        if (_recentAttendance != null && _recentAttendance!.isNotEmpty) ...[
          _buildActivitySection(
            'Recent Attendance',
            _recentAttendance!,
            'subject_name',
            'status',
          ),
        ],

        // No activity
        if ((_recentGrades == null || _recentGrades!.isEmpty) &&
            (_recentAttendance == null || _recentAttendance!.isEmpty)) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No recent activity',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your recent grades, attendance, and assessment scores will appear here.',
                    style: TextStyle(color: AppTheme.textLight, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActivitySection(
    String title,
    List<Map<String, dynamic>> items,
    String titleField,
    String valueField,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item[titleField] ?? 'Unknown',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                        Text(
                          item[valueField]?.toString() ?? 'N/A',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: valueField == 'score'
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isSyncing
                  ? PlatformIcons.cloudSync
                  : PlatformIcons.cloudDownload,
              color: _isSyncing ? AppTheme.primary : AppTheme.success,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSyncing ? 'Syncing...' : 'Data Sync',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    _lastSyncTime != null
                        ? 'Last synced: ${_formatDateTime(_lastSyncTime!)}'
                        : 'Never synced',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _isSyncing ? null : _syncData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _navigateToGrades() {
    // TODO: Navigate to grades screen
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Grades screen coming soon!')));
  }

  void _navigateToAttendance() {
    // TODO: Navigate to attendance screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance screen coming soon!')),
    );
  }
}
