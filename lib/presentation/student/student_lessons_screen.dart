import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/icon_fix.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/repositories/student_data_repository.dart';
import 'student_lesson_detail_screen.dart';

class StudentLessonsScreen extends StatefulWidget {
  final String teacherUid;
  final String classRemoteId;
  final String classTitle;

  const StudentLessonsScreen({
    super.key,
    required this.teacherUid,
    required this.classRemoteId,
    required this.classTitle,
  });

  @override
  State<StudentLessonsScreen> createState() => _StudentLessonsScreenState();
}

class _StudentLessonsScreenState extends State<StudentLessonsScreen> {
  final StudentDataRepository _repo = StudentDataRepository();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _lessons = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) throw Exception('Not logged in');

      final res = await _repo.getStudentLessonsForClassSmart(
        firebaseUid: firebaseUser.uid,
        teacherUid: widget.teacherUid,
        classRemoteId: widget.classRemoteId,
      );
      print(
        '[StudentLessonsScreen] Loaded lessons count=${res.length} teacherUid=${widget.teacherUid} classRemoteId=${widget.classRemoteId}',
      );
      if (mounted) {
        setState(() {
          _lessons = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[StudentLessonsScreen] Load error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _titleOf(Map<String, dynamic> l) =>
      (l['title']?.toString() ?? '').trim().isNotEmpty
      ? l['title'].toString().trim()
      : 'Lesson';

  int _weekOf(Map<String, dynamic> l) {
    final v = l['week_number'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  bool _hasPdf(Map<String, dynamic> l) {
    final p = (l['pdf_path']?.toString() ?? '').trim();
    return p.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = Theme.of(context).colorScheme.primary;
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: PlatformIcons.isIOS
              ? Icon(PlatformIcons.back, color: Colors.white)
              : IconFix.fixIcon(
                  Icon(PlatformIcons.back, color: Colors.white),
                ),
        ),
        title: const Text('Lessons'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!)
            : _lessons.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _lessons.length,
                itemBuilder: (context, i) {
                  final lesson = _lessons[i];
                  final week = _weekOf(lesson);
                  final title = _titleOf(lesson);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StudentLessonDetailScreen(
                              lesson: lesson,
                              gradientColors: gradientColors,
                            ),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8ECF4)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: gradientColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  week > 0 ? 'W$week' : '—',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (_hasPdf(lesson)) ...[
                                          Icon(
                                            PlatformIcons.pictureAsPdf,
                                            size: 14,
                                            color: AppTheme.danger,
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'PDF',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Icon(
                                          PlatformIcons.calendarToday,
                                          size: 14,
                                          color: AppTheme.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          week > 0 ? 'Week $week' : 'Week',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                PlatformIcons.chevronRight,
                                color: AppTheme.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(PlatformIcons.book, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          'No lessons yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your teacher hasn\'t added lessons for this class yet.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Failed to load lessons',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
