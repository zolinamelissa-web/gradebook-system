import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dart:convert';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/intervention_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/repositories/risk_repository.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/class_model.dart';
import '../students/student_list_screen.dart';
import '../classes/class_list_screen.dart';
import '../analytics/analytics_screen.dart';
import '../settings/settings_screen.dart';
import '../interventions/intervention_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _FollowUpDueTodayCard extends StatelessWidget {
  final int count;
  final List<Map<String, dynamic>> previewRows;
  final VoidCallback onOpen;

  const _FollowUpDueTodayCard({
    required this.count,
    required this.previewRows,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$count follow-up intervention(s) due today',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              TextButton(onPressed: onOpen, child: const Text('View')),
            ],
          ),
          const SizedBox(height: 10),
          ...previewRows.map((r) {
            final title = (r['title'] as String?)?.trim() ?? 'Follow-up';
            final studentName = (r['student_name'] as String?)?.trim() ?? '-';
            final subjectCode = (r['subject_code'] as String?)?.trim() ?? '';

            final parts = <String>[];
            if (studentName.isNotEmpty) parts.add(studentName);
            if (subjectCode.isNotEmpty) parts.add(subjectCode);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          parts.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  ClassModel? _selectedClass;
  int _selectedIndex = 0;
  int _refreshToken = 0;
  String _teacherName = 'Teacher';
  String _schoolName = '';
  int _totalStudents = 0;
  int _totalClasses = 0;
  int _atRiskCount = 0;
  List<Map<String, dynamic>> _atRiskStudents = [];
  List<Map<String, dynamic>> _followUpsDueToday = const [];
  bool _followUpSnackShown = false;
  bool _isLoading = true;

  final StudentRepository _studentRepo = StudentRepository();
  final SubjectRepository _subjectRepo = SubjectRepository();
  final RiskRepository _riskRepo = RiskRepository();
  final InterventionRepository _interventionRepo = InterventionRepository();

  Future<void> _logout() async {
    print('[HomeScreen] Logout pressed');
    await AuthService.signOutAndGoToLogin(context);
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadData();
  }

  Future<void> _showFollowUpDueTodayModal({required int count}) async {
    if (count <= 0) return;
    if (!mounted) return;

    final primary = Theme.of(context).colorScheme.primary;
    print('[HomeScreen] Showing follow-up due today modal count=$count');

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
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        PlatformIcons.notificationsActive,
                        color: AppTheme.warning,
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
                          _openNotifications();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await _loadWebData();
        return;
      }

      final db = DatabaseHelper.instance;
      final name = await db.getSetting('teacher_name');
      final school = await db.getSetting('school_name');
      final students = await _studentRepo.getTotalStudents();
      final classes = await _subjectRepo.getTotalClasses();

      final atRiskStudents = await _riskRepo.getAtRiskStudents();
      print(
        '[HomeScreen] Loaded at-risk students for notifications: ${atRiskStudents.length}',
      );

      final followUps = await _interventionRepo
          .getFollowUpInterventionsDueToday();
      print(
        '[HomeScreen] Loaded follow-up interventions due today: ${followUps.length}',
      );

      final allClasses = await _subjectRepo.getAllClasses();
      int riskTotal = 0;
      for (final cls in allClasses) {
        if (cls.id != null) {
          riskTotal += await _riskRepo.getAtRiskCount(cls.id!);
        }
      }

      if (mounted) {
        setState(() {
          _teacherName = name ?? 'Teacher';
          _schoolName = school ?? '';
          _totalStudents = students;
          _totalClasses = classes;
          _atRiskCount = riskTotal;
          _atRiskStudents = atRiskStudents;
          _followUpsDueToday = followUps;
          _isLoading = false;
        });

        if (!_followUpSnackShown && followUps.isNotEmpty) {
          _followUpSnackShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showFollowUpDueTodayModal(count: followUps.length);
          });
        }
      }
    } catch (e) {
      print('[HomeScreen] _loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isDeleted(Map<String, dynamic> data) {
    final deleted = data['deleted'];
    if (deleted is int) return deleted == 1;
    if (deleted is bool) return deleted;
    if (deleted is String)
      return deleted == '1' || deleted.toLowerCase() == 'true';
    return false;
  }

  Future<void> _loadWebData() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[HomeScreen] Web data load skipped: no Firebase user');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final uid = firebaseUser.uid;
    print(
      '[HomeScreen] Loading web dashboard data for uid=$uid email=${firebaseUser.email}',
    );

    try {
      final teacherDocFuture = _firestore.collection('users').doc(uid).get();
      final studentsFuture = _firestore.collection('users/$uid/students').get();
      final classesFuture = _firestore.collection('users/$uid/classes').get();
      final riskFlagsFuture = _firestore
          .collection('users/$uid/risk_flags')
          .get();
      final interventionsFuture = _firestore
          .collection('users/$uid/interventions')
          .get();

      final results = await Future.wait([
        teacherDocFuture,
        studentsFuture,
        classesFuture,
        riskFlagsFuture,
        interventionsFuture,
      ]);

      final teacherDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final studentsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final classesSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final riskFlagsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
      final interventionsSnap =
          results[4] as QuerySnapshot<Map<String, dynamic>>;

      final teacherData = teacherDoc.data() ?? <String, dynamic>{};
      final teacherSettings =
          teacherData['settings'] as Map<String, dynamic>? ??
          <String, dynamic>{};

      final activeStudents = studentsSnap.docs
          .map((d) => d.data())
          .where((d) => !_isDeleted(d))
          .toList();
      final activeClasses = classesSnap.docs
          .map((d) => d.data())
          .where((d) => !_isDeleted(d))
          .where((d) {
            final archived = d['is_archived'];
            if (archived is int) return archived != 1;
            if (archived is bool) return !archived;
            return true;
          })
          .toList();

      final studentsByLocalId = <String, Map<String, dynamic>>{};
      for (final student in activeStudents) {
        final localId = student['id']?.toString() ?? '';
        if (localId.isNotEmpty) {
          studentsByLocalId[localId] = student;
        }
      }

      final riskRows = riskFlagsSnap.docs
          .map((d) => d.data())
          .where((d) => !_isDeleted(d))
          .toList();

      final atRiskRows = riskRows.where((row) {
        final level = (row['risk_level']?.toString() ?? '').toLowerCase();
        return level == 'high' || level == 'medium';
      }).toList();

      final uniqueAtRiskStudents = <String>{};
      final atRiskPreview = <Map<String, dynamic>>[];
      for (final row in atRiskRows) {
        final studentLocalId = row['student_id']?.toString() ?? '';
        if (studentLocalId.isNotEmpty) {
          uniqueAtRiskStudents.add(studentLocalId);
        }

        final student = studentsByLocalId[studentLocalId];
        final firstName = (student?['first_name']?.toString() ?? '').trim();
        final lastName = (student?['last_name']?.toString() ?? '').trim();
        final fullName = '$firstName $lastName'.trim();

        atRiskPreview.add({
          'student_name': fullName.isNotEmpty ? fullName : 'Student',
          'student_code': student?['student_id']?.toString() ?? '',
          'risk_level': row['risk_level']?.toString() ?? 'medium',
        });
      }

      final today = _todayYmd();
      final followUps =
          interventionsSnap.docs
              .map((d) => d.data())
              .where((d) => !_isDeleted(d))
              .where((d) {
                final followUpDate = d['follow_up_date']?.toString() ?? '';
                return followUpDate.isNotEmpty &&
                    followUpDate.startsWith(today);
              })
              .map((d) {
                final studentLocalId = d['student_id']?.toString() ?? '';
                final student = studentsByLocalId[studentLocalId];
                final firstName = (student?['first_name']?.toString() ?? '')
                    .trim();
                final lastName = (student?['last_name']?.toString() ?? '')
                    .trim();
                final fullName = '$firstName $lastName'.trim();
                return <String, dynamic>{
                  'title': d['title']?.toString() ?? 'Follow-up',
                  'student_name': fullName.isNotEmpty ? fullName : '-',
                  'subject_code': '',
                  'follow_up_date': d['follow_up_date']?.toString() ?? '',
                };
              })
              .toList()
            ..sort(
              (a, b) => (a['follow_up_date'] as String).compareTo(
                b['follow_up_date'] as String,
              ),
            );

      final resolvedTeacherName =
          (teacherData['display_name']?.toString() ?? '').trim().isNotEmpty
          ? teacherData['display_name'].toString().trim()
          : (firebaseUser.displayName?.trim().isNotEmpty == true
                ? firebaseUser.displayName!.trim()
                : 'Teacher');
      final resolvedSchoolName =
          (teacherSettings['school_name']?.toString() ?? '').trim().isNotEmpty
          ? teacherSettings['school_name'].toString().trim()
          : (teacherData['school_name']?.toString() ?? '').trim();

      print(
        '[HomeScreen] Web data loaded teacher=$resolvedTeacherName students=${activeStudents.length} classes=${activeClasses.length} atRisk=${uniqueAtRiskStudents.length} followUps=${followUps.length}',
      );

      if (!mounted) return;
      setState(() {
        _teacherName = resolvedTeacherName;
        _schoolName = resolvedSchoolName;
        _totalStudents = activeStudents.length;
        _totalClasses = activeClasses.length;
        _atRiskCount = uniqueAtRiskStudents.length;
        _atRiskStudents = atRiskPreview;
        _followUpsDueToday = followUps;
        _isLoading = false;
      });

      if (!_followUpSnackShown && followUps.isNotEmpty) {
        _followUpSnackShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFollowUpDueTodayModal(count: followUps.length);
        });
      }
    } catch (e) {
      print('[HomeScreen] Web data load error: $e');
      if (mounted) {
        setState(() {
          _teacherName = firebaseUser.displayName?.trim().isNotEmpty == true
              ? firebaseUser.displayName!.trim()
              : 'Teacher';
          _isLoading = false;
        });
      }
    }
  }

  void _onAppDataChanged() {
    _loadData();
    setState(() => _refreshToken++);
  }

  void _openClass(ClassModel cls) {
    setState(() {
      _selectedClass = cls;
    });
  }

  void _closeClassDetail() {
    setState(() {
      _selectedClass = null;
    });
  }

  void _openNotifications() {
    final items = _atRiskStudents;
    final followUps = _followUpsDueToday;
    final rootContext = context;
    print(
      '[HomeScreen] Open notifications atRisk=${items.length} followUpsToday=${followUps.length}',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final primary = Theme.of(context).colorScheme.primary;
        return SafeArea(
          top: true,
          bottom: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(PlatformIcons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Follow-up Interventions (Today)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (followUps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No follow-up interventions due today.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: followUps.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = followUps[i];
                            final title =
                                (row['title'] as String?)?.trim() ??
                                'Follow-up';
                            final studentName =
                                (row['student_name'] as String?)?.trim() ?? '-';
                            final subjectCode =
                                (row['subject_code'] as String?)?.trim() ?? '';
                            final section =
                                (row['class_section'] as String?)?.trim() ?? '';
                            final followUpDate =
                                (row['follow_up_date'] as String?)?.trim() ??
                                '';
                            final studentId =
                                (row['student_id'] as num?)?.toInt() ?? 0;
                            final classId =
                                (row['class_id'] as num?)?.toInt() ?? 0;

                            final subtitleParts = <String>[];
                            if (studentName.isNotEmpty)
                              subtitleParts.add(studentName);
                            if (subjectCode.isNotEmpty)
                              subtitleParts.add(subjectCode);
                            if (section.isNotEmpty) subtitleParts.add(section);
                            if (followUpDate.isNotEmpty) {
                              subtitleParts.add(
                                'Due: ${followUpDate.length >= 10 ? followUpDate.substring(0, 10) : followUpDate}',
                              );
                            }

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                subtitleParts.join(' • '),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Icon(PlatformIcons.chevronRight),
                              onTap: () async {
                                Navigator.pop(context);

                                if (studentId <= 0 || classId <= 0) {
                                  print(
                                    '[HomeScreen] Follow-up tap missing ids studentId=$studentId classId=$classId',
                                  );
                                  if (!rootContext.mounted) return;
                                  ScaffoldMessenger.of(
                                    rootContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to open intervention (missing data).',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  final student = await _studentRepo
                                      .getStudentById(studentId);
                                  final classModel = await _subjectRepo
                                      .getClassById(classId);

                                  print(
                                    '[HomeScreen] Follow-up tap -> intervention studentId=$studentId classId=$classId student=${student?.fullName ?? '-'}',
                                  );

                                  if (!rootContext.mounted) return;
                                  if (student == null || classModel == null) {
                                    ScaffoldMessenger.of(
                                      rootContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Unable to open intervention (student/class not found).',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  await Navigator.push(
                                    rootContext,
                                    MaterialPageRoute(
                                      builder: (_) => InterventionScreen(
                                        classModel: classModel,
                                        student: student,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  print(
                                    '[HomeScreen] Follow-up navigate error: $e',
                                  );
                                  if (!rootContext.mounted) return;
                                  ScaffoldMessenger.of(
                                    rootContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to open: $e'),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      'At-Risk Students',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No at-risk students right now.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = items[i];
                            final name =
                                (row['student_name'] as String?)?.trim() ?? '-';
                            final code =
                                (row['student_code'] as String?)?.trim() ?? '';
                            final studentId =
                                (row['student_id'] as num?)?.toInt() ?? 0;
                            final classId =
                                (row['class_id'] as num?)?.toInt() ?? 0;
                            final level =
                                (row['risk_level'] as String?)?.trim() ?? 'low';
                            final levelColor = level == 'high'
                                ? AppTheme.danger
                                : level == 'medium'
                                ? AppTheme.warning
                                : AppTheme.success;
                            final photoData =
                                (row['photo_path'] as String?)?.trim() ?? '';

                            // Photo detection logic
                            bool isBase64 = false;
                            bool hasFilePhoto = false;
                            if (photoData.isNotEmpty) {
                              if (photoData.startsWith('data:image/')) {
                                isBase64 = true;
                              } else if (photoData.length > 100) {
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

                            // Generate initials for fallback
                            final nameParts = name.split(' ');
                            final initials = nameParts.length >= 2
                                ? '${nameParts[0][0]}${nameParts[1][0]}'
                                      .toUpperCase()
                                : name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?';

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () async {
                                Navigator.pop(context);

                                if (studentId <= 0 || classId <= 0) {
                                  print(
                                    '[HomeScreen] Notification tap missing ids studentId=$studentId classId=$classId',
                                  );
                                  if (!rootContext.mounted) return;
                                  ScaffoldMessenger.of(
                                    rootContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to open intervention (missing data).',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  final student = await _studentRepo
                                      .getStudentById(studentId);
                                  final classModel = await _subjectRepo
                                      .getClassById(classId);

                                  print(
                                    '[HomeScreen] Notification tap -> intervention studentId=$studentId classId=$classId student=${student?.fullName ?? '-'}',
                                  );

                                  if (!rootContext.mounted) return;

                                  if (student == null || classModel == null) {
                                    ScaffoldMessenger.of(
                                      rootContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Unable to open intervention (student/class not found).',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  await Navigator.push(
                                    rootContext,
                                    MaterialPageRoute(
                                      builder: (_) => InterventionScreen(
                                        classModel: classModel,
                                        student: student,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  print(
                                    '[HomeScreen] Notification navigate error: $e',
                                  );
                                  if (!rootContext.mounted) return;
                                  ScaffoldMessenger.of(
                                    rootContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to open: $e'),
                                    ),
                                  );
                                }
                              },
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: levelColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: ClipOval(
                                  child: hasPhoto
                                      ? Builder(
                                          builder: (context) {
                                            if (isBase64) {
                                              final bytes = base64Decode(
                                                photoData.startsWith(
                                                      'data:image/',
                                                    )
                                                    ? photoData.split(',').last
                                                    : photoData,
                                              );
                                              return Image.memory(
                                                bytes,
                                                width: 36,
                                                height: 36,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Center(
                                                        child: Text(
                                                          initials,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: levelColor,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                              );
                                            } else {
                                              return Image.file(
                                                File(photoData),
                                                width: 36,
                                                height: 36,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Center(
                                                        child: Text(
                                                          initials,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: levelColor,
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
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: levelColor,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: code.isEmpty
                                  ? Text(
                                      'Risk: ${level.toUpperCase()}',
                                      style: TextStyle(
                                        color: levelColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    )
                                  : Text(
                                      'ID: $code • Risk: ${level.toUpperCase()}',
                                      style: TextStyle(
                                        color: levelColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
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
          ),
        );
      },
    );
  }

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          RefreshIndicator(
            onRefresh: () async => _loadData(),
            color: AppTheme.primary,
            child: _DashboardTab(
              teacherName: _teacherName,
              schoolName: _schoolName,
              totalStudents: _totalStudents,
              totalClasses: _totalClasses,
              atRiskCount: _atRiskCount,
              followUpsDueToday: _followUpsDueToday,
              isLoading: _isLoading,
              onRefresh: _loadData,
              onNavigate: (i) => setState(() => _selectedIndex = i),
              onOpenNotifications: _openNotifications,
              notificationCount:
                  _atRiskStudents.length + _followUpsDueToday.length,
              onLogout: () {
                _logout();
              },
            ),
          ),
          StudentListScreen(key: ValueKey('students_$_refreshToken')),
          ClassListScreen(
            key: ValueKey('classes_$_refreshToken'),
            onClassSelected: _openClass,
            selectedClass: _selectedClass,
            onBackToList: _closeClassDetail,
          ),
          AnalyticsScreen(key: ValueKey('analytics_$_refreshToken')),
          SettingsScreen(onSettingsChanged: _onAppDataChanged),
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

    Widget bottomNavContent = Padding(
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

// ─────────────────────────────────────────────────────────────
//  DASHBOARD TAB  (no CurvedBackground — layout rebuilt clean)
// ─────────────────────────────────────────────────────────────
class _DashboardTab extends StatelessWidget {
  final String teacherName;
  final String schoolName;
  final int totalStudents;
  final int totalClasses;
  final int atRiskCount;
  final List<Map<String, dynamic>> followUpsDueToday;
  final bool isLoading;
  final VoidCallback onRefresh;
  final void Function(int) onNavigate;
  final VoidCallback onOpenNotifications;
  final int notificationCount;
  final VoidCallback onLogout;

  const _DashboardTab({
    required this.teacherName,
    required this.schoolName,
    required this.totalStudents,
    required this.totalClasses,
    required this.atRiskCount,
    required this.followUpsDueToday,
    required this.isLoading,
    required this.onRefresh,
    required this.onNavigate,
    required this.onOpenNotifications,
    required this.notificationCount,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Fixed Hero Header - completely fixed
        _HeroHeader(
          teacherName: teacherName,
          schoolName: schoolName,
          totalStudents: totalStudents,
          totalClasses: totalClasses,
          atRiskCount: atRiskCount,
          notificationCount: notificationCount,
          onOpenNotifications: onOpenNotifications,
          onLogout: onLogout,
        ),
        // Scrollable Body Content
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (followUpsDueToday.isNotEmpty) ...[
                  _SectionLabel(label: 'Follow-ups Due Today'),
                  const SizedBox(height: 14),
                  _FollowUpDueTodayCard(
                    count: followUpsDueToday.length,
                    previewRows: followUpsDueToday.take(3).toList(),
                    onOpen: onOpenNotifications,
                  ),
                  const SizedBox(height: 28),
                ],
                _SectionLabel(label: 'Quick Actions'),
                const SizedBox(height: 14),
                _QuickActionsGrid(onNavigate: onNavigate),
                const SizedBox(height: 28),
                _SectionLabel(label: 'Overview'),
                const SizedBox(height: 14),
                _OverviewCard(
                  totalStudents: totalStudents,
                  totalClasses: totalClasses,
                  atRiskCount: atRiskCount,
                  isLoading: isLoading,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HERO HEADER  — gradient + wave + stat chips all in one block
// ─────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String teacherName;
  final String schoolName;
  final int totalStudents;
  final int totalClasses;
  final int atRiskCount;
  final int notificationCount;
  final VoidCallback onOpenNotifications;
  final VoidCallback onLogout;

  const _HeroHeader({
    required this.teacherName,
    required this.schoolName,
    required this.totalStudents,
    required this.totalClasses,
    required this.atRiskCount,
    required this.notificationCount,
    required this.onOpenNotifications,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return ClipPath(
      clipper: _BottomWaveClipper(),
      child: Container(
        // gradient background
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primary, secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // decorative circle top-right
            Positioned(
              top: -30,
              right: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: 40,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            // content
            SafeArea(
              bottom: false,
              child: Padding(
                // extra bottom padding to account for wave clip
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // top row: greeting + notification bell
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, $teacherName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (schoolName.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      PlatformIcons.school,
                                      color: Colors.white70,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        schoolName,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
                                          ),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Logout',
                          onPressed: () {
                            print(
                              '[HomeScreen] Teacher dashboard logout tapped',
                            );
                            onLogout();
                          },
                          icon: Icon(PlatformIcons.logout, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        _NotificationBell(
                          count: notificationCount,
                          onTap: onOpenNotifications,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // stat chips row
                    Row(
                      children: [
                        _StatChip(
                          value: '$totalStudents',
                          label: 'Students',
                          icon: PlatformIcons.people,
                        ),
                        const SizedBox(width: 10),
                        _StatChip(
                          value: '$totalClasses',
                          label: 'Classes',
                          icon: PlatformIcons.classes,
                        ),
                        const SizedBox(width: 10),
                        _StatChip(
                          value: '$atRiskCount',
                          label: 'At-Risk',
                          icon: PlatformIcons.warning,
                          isWarning: atRiskCount > 0,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuts a gentle wave at the bottom of the header
class _BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 36);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height - 20,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 40,
      size.width,
      size.height - 16,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BottomWaveClipper old) => false;
}

class _NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NotificationBell({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = Colors.white.withValues(alpha: 0.15);
    final border = Colors.white.withValues(alpha: 0.25);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Icon(
                PlatformIcons.notifications,
                color: Colors.white,
                size: 22,
              ),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
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
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool isWarning;

  const _StatChip({
    required this.value,
    required this.label,
    required this.icon,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isWarning ? const Color(0xFFFFE082) : Colors.white,
              size: 18,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SECTION LABEL
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
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

// ─────────────────────────────────────────────────────────────
//  QUICK ACTIONS GRID
// ─────────────────────────────────────────────────────────────
class _QuickActionsGrid extends StatelessWidget {
  final void Function(int) onNavigate;
  const _QuickActionsGrid({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final actions = [
      _ActionData(
        icon: PlatformIcons.personAdd,
        label: 'Add Student',
        subtitle: 'Enroll new learner',
        color: primary,
        navIndex: 1,
      ),
      _ActionData(
        icon: PlatformIcons.classes,
        label: 'Manage Classes',
        subtitle: 'Sections & subjects',
        color: AppTheme.success,
        navIndex: 2,
      ),
      _ActionData(
        icon: PlatformIcons.analytics,
        label: 'Analytics',
        subtitle: 'View performance',
        color: const Color(0xFF6A1B9A),
        navIndex: 3,
      ),
      _ActionData(
        icon: PlatformIcons.warning,
        label: 'At-Risk',
        subtitle: 'Review flagged',
        color: const Color(0xFFB71C1C),
        navIndex: 2,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: actions.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              right: index < actions.length - 1 ? 12 : 0,
            ),
            child: SizedBox(
              width:
                  (MediaQuery.of(context).size.width - 36) /
                  4, // 4 cards with spacing
              child: _QuickActionCard(
                data: action,
                onTap: () => onNavigate(action.navIndex),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionData {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final int navIndex;
  const _ActionData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.navIndex,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _ActionData data;
  final VoidCallback onTap;
  const _QuickActionCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8ECF4)),
            boxShadow: [
              BoxShadow(
                color: data.color.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: data.color,
                    ),
                  ),
                  Text(
                    data.subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF90A0B7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  OVERVIEW CARD
// ─────────────────────────────────────────────────────────────
class _OverviewCard extends StatelessWidget {
  final int totalStudents;
  final int totalClasses;
  final int atRiskCount;
  final bool isLoading;

  const _OverviewCard({
    required this.totalStudents,
    required this.totalClasses,
    required this.atRiskCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              children: [
                _OverviewRow(
                  label: 'Total Students Enrolled',
                  value: '$totalStudents',
                  icon: PlatformIcons.people,
                  color: primary,
                  isFirst: true,
                ),
                _OverviewDivider(),
                _OverviewRow(
                  label: 'Active Classes',
                  value: '$totalClasses',
                  icon: PlatformIcons.classes,
                  color: const Color(0xFF00897B),
                ),
                _OverviewDivider(),
                _OverviewRow(
                  label: 'At-Risk Students',
                  value: '$atRiskCount',
                  icon: PlatformIcons.warning,
                  color: atRiskCount > 0
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF2E7D32),
                  isLast: true,
                  badge: atRiskCount > 0 ? 'Needs Attention' : 'All Good',
                  badgeIsWarning: atRiskCount > 0,
                ),
              ],
            ),
    );
  }
}

class _OverviewDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, color: const Color(0xFFEEF1F8)),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final String? badge;
  final bool badgeIsWarning;

  const _OverviewRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isFirst = false,
    this.isLast = false,
    this.badge,
    this.badgeIsWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, isFirst ? 20 : 16, 20, isLast ? 20 : 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6B7A99),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeIsWarning
                          ? const Color(0xFFFFEBEE)
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: badgeIsWarning
                            ? const Color(0xFFB71C1C)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
