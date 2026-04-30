import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/subject_model.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/risk_repository.dart';
import 'class_form_screen.dart';
import 'class_detail_screen.dart';

class ClassListScreen extends StatefulWidget {
  final void Function(ClassModel)? onClassSelected;
  final ClassModel? selectedClass;
  final VoidCallback? onBackToList;

  const ClassListScreen({
    super.key,
    this.onClassSelected,
    this.selectedClass,
    this.onBackToList,
  });

  @override
  State<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<ClassListScreen>
    with SingleTickerProviderStateMixin {
  final SubjectRepository _repo = SubjectRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final RiskRepository _riskRepo = RiskRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  List<ClassModel> _classes = [];
  List<ClassModel> _filteredClasses = [];
  bool _isLoading = true;
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    // No longer need to load archived separately since all classes load by default
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = kIsWeb
          ? await _loadWebClasses()
          : await _repo.getAllClasses(includeArchived: true);
      print(
        '[ClassListScreen] Loaded ${list.length} total classes (including archived)',
      );
      if (mounted) {
        setState(() {
          _classes = list;
          _filteredClasses = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ClassListScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<ClassModel>> _loadWebClasses() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[ClassListScreen] Web class load skipped: no Firebase user');
      return <ClassModel>[];
    }

    final classesSnap = await _firestore
        .collection('users/${firebaseUser.uid}/classes')
        .get();

    final now = DateTime.now().toIso8601String();
    final list =
        classesSnap.docs
            .where((doc) {
              final data = doc.data();
              final deleted = data['deleted'];
              if (deleted is bool) return !deleted;
              if (deleted is int) return deleted != 1;
              if (deleted is String) {
                final normalized = deleted.toLowerCase();
                return normalized != '1' && normalized != 'true';
              }
              return true;
            })
            .map((doc) {
              final data = doc.data();
              final archivedRaw = data['is_archived'];
              final isArchived = archivedRaw is bool
                  ? archivedRaw
                  : archivedRaw is int
                  ? archivedRaw == 1
                  : archivedRaw is String
                  ? archivedRaw == '1' || archivedRaw.toLowerCase() == 'true'
                  : false;

              final subjectIdRaw = data['subject_id'];
              final parsedSubjectId = subjectIdRaw is int
                  ? subjectIdRaw
                  : int.tryParse(subjectIdRaw?.toString() ?? '') ?? 0;

              final subject = Subject(
                id: parsedSubjectId == 0 ? null : parsedSubjectId,
                code: data['subject_code']?.toString() ?? '',
                name: data['subject_name']?.toString() ?? '',
                description: data['subject_description']?.toString(),
                createdAt: '',
                updatedAt: '',
              );

              return ClassModel(
                id: data['id'] is int ? data['id'] as int : null,
                subjectId: parsedSubjectId,
                section: data['section']?.toString() ?? '',
                schoolYear: data['school_year']?.toString() ?? '',
                semester: data['semester']?.toString(),
                schedule: data['schedule']?.toString(),
                room: data['room']?.toString(),
                isArchived: isArchived,
                remoteId:
                    (data['remote_id']?.toString() ?? '').trim().isNotEmpty
                    ? data['remote_id']?.toString()
                    : doc.id,
                createdAt: data['created_at']?.toString() ?? now,
                updatedAt: data['updated_at']?.toString() ?? now,
                subject: subject.name.isEmpty && subject.code.isEmpty
                    ? null
                    : subject,
              );
            })
            .where(
              (cls) =>
                  cls.section.trim().isNotEmpty &&
                  cls.schoolYear.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    print(
      '[ClassListScreen] Web classes loaded uid=${firebaseUser.uid} count=${list.length}',
    );
    return list;
  }

  void _search(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredClasses = _classes;
      } else {
        _filteredClasses = _classes.where((cls) {
          final q = query.toLowerCase();
          final subjectCode = cls.subject?.code.toLowerCase() ?? '';
          final subjectName = cls.subject?.name.toLowerCase() ?? '';
          final description = cls.subject?.description?.toLowerCase() ?? '';
          final section = cls.section.toLowerCase();
          final schoolYear = cls.schoolYear.toLowerCase();
          final semester = cls.semester?.toLowerCase() ?? '';

          return subjectCode.contains(q) ||
              subjectName.contains(q) ||
              description.contains(q) ||
              section.contains(q) ||
              schoolYear.contains(q) ||
              semester.contains(q);
        }).toList();
      }
    });
  }

  List<ClassModel> get _active =>
      _filteredClasses.where((c) => !c.isArchived).toList();
  List<ClassModel> get _archived =>
      _filteredClasses.where((c) => c.isArchived).toList();

  Future<void> _addClass() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClassFormScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _openClass(ClassModel cls) async {
    // Use the callback if provided (for nested navigation with bottom nav)
    if (widget.onClassSelected != null) {
      widget.onClassSelected!(cls);
      return;
    }
    // Fallback to traditional navigation
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ClassDetailScreen(classModel: cls)),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    // Show ClassDetailScreen if a class is selected
    if (widget.selectedClass != null) {
      return ClassDetailScreen(
        classModel: widget.selectedClass!,
        onBackPressed: widget.onBackToList,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Classes',
            subtitle: '${_active.length} active classes',
            gradientColors: gradientColors,
            actions: [
              IconButton(
                tooltip: 'Logout',
                icon: Icon(PlatformIcons.logout, color: Colors.white),
                onPressed: () => AuthService.signOutAndGoToLogin(context),
              ),
            ],
            chips: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(PlatformIcons.search, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _search,
                        style: TextStyle(
                          color: themeProvider.primaryColor,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search classes...',
                          hintStyle: TextStyle(
                            color: themeProvider.primaryColor.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(color: Colors.white, width: 3),
                    insets: EdgeInsets.symmetric(horizontal: 24),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Active'),
                    Tab(text: 'Archived'),
                  ],
                ),
              ),
            ],
          ),
          // Scrollable Class List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _ClassGrid(
                        classes: _active,
                        onAdd: _addClass,
                        onTap: _openClass,
                        emptyMessage: 'No active classes',
                        studentRepo: _studentRepo,
                        riskRepo: _riskRepo,
                      ),
                      _ClassGrid(
                        classes: _archived,
                        onAdd: null,
                        onTap: _openClass,
                        emptyMessage: 'No archived classes',
                        studentRepo: _studentRepo,
                        riskRepo: _riskRepo,
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_classes_add',
        onPressed: _addClass,
        backgroundColor: themeProvider.primaryColor,
        child: Icon(PlatformIcons.add, color: Colors.white),
      ),
    );
  }
}

class _ClassGrid extends StatelessWidget {
  final List<ClassModel> classes;
  final VoidCallback? onAdd;
  final void Function(ClassModel) onTap;
  final String emptyMessage;
  final StudentRepository studentRepo;
  final RiskRepository riskRepo;

  const _ClassGrid({
    required this.classes,
    required this.onAdd,
    required this.onTap,
    required this.emptyMessage,
    required this.studentRepo,
    required this.riskRepo,
  });

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PlatformIcons.classes,
              size: 64,
              color: AppTheme.textLight.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {},
      child: kIsWeb
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: classes.length,
              itemBuilder: (_, i) => _ClassGridCard(
                cls: classes[i],
                onTap: onTap,
                studentRepo: studentRepo,
                riskRepo: riskRepo,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              itemCount: classes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ClassCard(
                cls: classes[i],
                onTap: onTap,
                studentRepo: studentRepo,
                riskRepo: riskRepo,
              ),
            ),
    );
  }
}

class _ClassGridCard extends StatelessWidget {
  final ClassModel cls;
  final void Function(ClassModel) onTap;
  final StudentRepository studentRepo;
  final RiskRepository riskRepo;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  _ClassGridCard({
    required this.cls,
    required this.onTap,
    required this.studentRepo,
    required this.riskRepo,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _getClassStats(),
      builder: (_, snapshot) {
        final totalStudents = snapshot.data?['total'] ?? 0;
        final atRiskStudents = snapshot.data?['atRisk'] ?? 0;

        final colors = [
          [AppTheme.primary, AppTheme.primaryLight],
          [AppTheme.secondary, const Color(0xFF0E7490)],
          [AppTheme.success, const Color(0xFF059669)],
          [const Color(0xFF7C3AED), const Color(0xFF6D28D9)],
        ];
        final colorPair = colors[cls.id != null ? cls.id! % colors.length : 0];

        return InkWell(
          onTap: () => onTap(cls),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(kIsWeb ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon
                Container(
                  width: kIsWeb ? 32 : 40,
                  height: kIsWeb ? 32 : 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorPair[0], colorPair[1]],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(kIsWeb ? 8 : 10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PlatformIcons.classes,
                    color: Colors.white,
                    size: kIsWeb ? 16 : 20,
                  ),
                ),
                SizedBox(height: kIsWeb ? 8 : 12),

                // Subject name/code
                Text(
                  (cls.subject?.code.isNotEmpty ?? false)
                      ? cls.subject!.code
                      : (cls.subject?.name ?? 'Unknown Subject'),
                  style: AppTheme.responsiveCardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Section and school year
                const SizedBox(height: 4),
                Text(
                  '${cls.section} • ${cls.schoolYear}',
                  style: AppTheme.responsiveCardSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Semester if available
                if (cls.semester != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    cls.semester!,
                    style: AppTheme.responsiveCardCaption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const Spacer(),

                // Stats row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: kIsWeb ? 4 : 6,
                        vertical: kIsWeb ? 1 : 2,
                      ),
                      decoration: BoxDecoration(
                        color: atRiskStudents > 0
                            ? AppTheme.danger.withValues(alpha: 0.1)
                            : AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(kIsWeb ? 4 : 6),
                      ),
                      child: Text(
                        '$atRiskStudents',
                        style: AppTheme.getResponsiveTextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: atRiskStudents > 0
                              ? AppTheme.danger
                              : AppTheme.success,
                          webScale: 0.8,
                        ),
                      ),
                    ),
                    SizedBox(width: kIsWeb ? 4 : 6),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: kIsWeb ? 4 : 6,
                        vertical: kIsWeb ? 1 : 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(kIsWeb ? 4 : 6),
                      ),
                      child: Text(
                        '$totalStudents',
                        style: AppTheme.getResponsiveTextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                          webScale: 0.8,
                        ),
                      ),
                    ),
                    if (cls.isArchived) ...[
                      SizedBox(width: kIsWeb ? 4 : 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: kIsWeb ? 4 : 6,
                          vertical: kIsWeb ? 1 : 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.textLight.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(kIsWeb ? 4 : 6),
                        ),
                        child: Text(
                          'Arch',
                          style: AppTheme.getResponsiveTextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textLight,
                            webScale: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _getClassStats() async {
    try {
      if (kIsWeb) {
        return await _getWebClassStats();
      }

      // Get total students
      final students = await studentRepo.getStudentsByClass(cls.id!);
      final totalStudents = students.length;

      // Get at-risk students
      final atRiskCount = await _getAtRiskCount();

      return {'total': totalStudents, 'atRisk': atRiskCount};
    } catch (e) {
      print('[_ClassGridCard] Error getting class stats: $e');
      return {'total': 0, 'atRisk': 0};
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

  Future<Map<String, int>> _getWebClassStats() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[_ClassGridCard] Web stats skipped: no Firebase user');
      return {'total': 0, 'atRisk': 0};
    }

    final classRemoteId = (cls.remoteId ?? '').trim();
    final classLocalId = cls.id;

    // Use remoteId when available, otherwise fall back to localId
    QuerySnapshot<Map<String, dynamic>> classStudentsSnap;
    if (classRemoteId.isNotEmpty) {
      classStudentsSnap = await _firestore
          .collection('users/${firebaseUser.uid}/class_students')
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
    } else if (classLocalId != null) {
      classStudentsSnap = await _firestore
          .collection('users/${firebaseUser.uid}/class_students')
          .where('class_id', isEqualTo: classLocalId)
          .get();
    } else {
      print('[_ClassGridCard] No valid class ID found for web stats loading');
      return {'total': 0, 'atRisk': 0};
    }
    final riskFlagsSnap = await _firestore
        .collection('users/${firebaseUser.uid}/risk_flags')
        .get();

    final enrolledKeys = <String>{
      ...classStudentsSnap.docs
          .map((doc) => doc.data()['student_remote_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => 'remote:$id'),
      ...classStudentsSnap.docs
          .map((doc) => doc.data()['student_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => 'local:$id'),
    };

    final atRiskCount = riskFlagsSnap.docs
        .map((doc) => doc.data())
        .where((data) => !_isDeleted(data))
        .where((data) {
          final level = (data['risk_level']?.toString() ?? '').toLowerCase();
          if (level != 'high' && level != 'medium') return false;
          final classMatches = classRemoteId.isNotEmpty
              ? data['class_remote_id']?.toString() == classRemoteId
              : data['class_id']?.toString() == classLocalId?.toString();
          if (classMatches) return true;
          final studentRemoteId = data['student_remote_id']?.toString() ?? '';
          final studentLocalId = data['student_id']?.toString() ?? '';
          return enrolledKeys.contains('remote:$studentRemoteId') ||
              enrolledKeys.contains('local:$studentLocalId');
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
      '[_ClassGridCard] Web stats loaded classId=${cls.id} classRemoteId=$classRemoteId total=${enrolledKeys.length} atRisk=$atRiskCount',
    );
    return {'total': enrolledKeys.length, 'atRisk': atRiskCount};
  }

  Future<int> _getAtRiskCount() async {
    try {
      // Get all students in this class
      final students = await studentRepo.getStudentsByClass(cls.id!);

      if (students.isEmpty) return 0;

      int atRiskCount = 0;

      // Check each student for at-risk status
      for (final student in students) {
        final riskFlag = await riskRepo.getLatestRiskFlagForStudent(
          studentId: student.id!,
          classId: cls.id!,
        );

        if (riskFlag != null &&
            (riskFlag['risk_level'] == 'high' ||
                riskFlag['risk_level'] == 'medium')) {
          atRiskCount++;
        }
      }

      return atRiskCount;
    } catch (e) {
      print('[_ClassGridCard] Error getting at-risk count: $e');
      return 0;
    }
  }
}

class _ClassCard extends StatelessWidget {
  final ClassModel cls;
  final void Function(ClassModel) onTap;
  final StudentRepository studentRepo;
  final RiskRepository riskRepo;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  _ClassCard({
    required this.cls,
    required this.onTap,
    required this.studentRepo,
    required this.riskRepo,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _getClassStats(),
      builder: (_, snapshot) {
        final totalStudents = snapshot.data?['total'] ?? 0;
        final atRiskStudents = snapshot.data?['atRisk'] ?? 0;

        final colors = [
          [AppTheme.primary, AppTheme.primaryLight],
          [AppTheme.secondary, const Color(0xFF0E7490)],
          [AppTheme.success, const Color(0xFF059669)],
          [const Color(0xFF7C3AED), const Color(0xFF6D28D9)],
        ];
        final colorPair = colors[cls.id != null ? cls.id! % colors.length : 0];

        return InkWell(
          onTap: () => onTap(cls),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorPair[0], colorPair[1]],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PlatformIcons.classes,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (cls.subject?.code.isNotEmpty ?? false)
                            ? cls.subject!.code
                            : (cls.subject?.name ?? 'Unknown Subject'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (cls.subject?.description != null &&
                          cls.subject!.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          cls.subject!.description!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        '${cls.section} • ${cls.schoolYear}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (cls.semester != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          cls.semester!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: atRiskStudents > 0
                                  ? AppTheme.danger.withValues(alpha: 0.1)
                                  : AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$atRiskStudents At-Risk',
                              style: TextStyle(
                                fontSize: 10,
                                color: atRiskStudents > 0
                                    ? AppTheme.danger
                                    : AppTheme.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$totalStudents Total',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (cls.isArchived)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.textLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Archived',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  PlatformIcons.chevronRight,
                  color: AppTheme.textLight,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _getClassStats() async {
    try {
      if (kIsWeb) {
        return await _getWebClassStats();
      }

      // Get total students
      final students = await studentRepo.getStudentsByClass(cls.id!);
      final totalStudents = students.length;

      // Get at-risk students
      final atRiskCount = await _getAtRiskCount();

      return {'total': totalStudents, 'atRisk': atRiskCount};
    } catch (e) {
      print('[_ClassCard] Error getting class stats: $e');
      return {'total': 0, 'atRisk': 0};
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

  Future<Map<String, int>> _getWebClassStats() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[_ClassCard] Web stats skipped: no Firebase user');
      return {'total': 0, 'atRisk': 0};
    }

    final classRemoteId = (cls.remoteId ?? '').trim();
    final classLocalId = cls.id;

    // Use remoteId when available, otherwise fall back to localId
    QuerySnapshot<Map<String, dynamic>> classStudentsSnap;
    if (classRemoteId.isNotEmpty) {
      classStudentsSnap = await _firestore
          .collection('users/${firebaseUser.uid}/class_students')
          .where('class_remote_id', isEqualTo: classRemoteId)
          .get();
    } else if (classLocalId != null) {
      classStudentsSnap = await _firestore
          .collection('users/${firebaseUser.uid}/class_students')
          .where('class_id', isEqualTo: classLocalId)
          .get();
    } else {
      print('[_ClassCard] No valid class ID found for web stats loading');
      return {'total': 0, 'atRisk': 0};
    }
    final riskFlagsSnap = await _firestore
        .collection('users/${firebaseUser.uid}/risk_flags')
        .get();

    final enrolledKeys = <String>{
      ...classStudentsSnap.docs
          .map((doc) => doc.data()['student_remote_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => 'remote:$id'),
      ...classStudentsSnap.docs
          .map((doc) => doc.data()['student_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => 'local:$id'),
    };

    final atRiskCount = riskFlagsSnap.docs
        .map((doc) => doc.data())
        .where((data) => !_isDeleted(data))
        .where((data) {
          final level = (data['risk_level']?.toString() ?? '').toLowerCase();
          if (level != 'high' && level != 'medium') return false;
          final classMatches = classRemoteId.isNotEmpty
              ? data['class_remote_id']?.toString() == classRemoteId
              : data['class_id']?.toString() == classLocalId?.toString();
          if (classMatches) return true;
          final studentRemoteId = data['student_remote_id']?.toString() ?? '';
          final studentLocalId = data['student_id']?.toString() ?? '';
          return enrolledKeys.contains('remote:$studentRemoteId') ||
              enrolledKeys.contains('local:$studentLocalId');
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
      '[_ClassCard] Web stats loaded classId=${cls.id} classRemoteId=$classRemoteId total=${enrolledKeys.length} atRisk=$atRiskCount',
    );
    return {'total': enrolledKeys.length, 'atRisk': atRiskCount};
  }

  Future<int> _getAtRiskCount() async {
    try {
      // Get all students in this class
      final students = await studentRepo.getStudentsByClass(cls.id!);

      if (students.isEmpty) return 0;

      int atRiskCount = 0;

      // Check each student for at-risk status
      for (final student in students) {
        final riskFlag = await riskRepo.getLatestRiskFlagForStudent(
          studentId: student.id!,
          classId: cls.id!,
        );

        if (riskFlag != null &&
            (riskFlag['risk_level'] == 'high' ||
                riskFlag['risk_level'] == 'medium')) {
          atRiskCount++;
        }
      }

      return atRiskCount;
    } catch (e) {
      print('[_ClassCard] Error getting at-risk count: $e');
      return 0;
    }
  }
}
