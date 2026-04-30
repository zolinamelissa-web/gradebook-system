import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/lesson_model.dart';
import 'lesson_form_screen.dart';

class LessonDetailScreen extends StatefulWidget {
  final Lesson lesson;

  const LessonDetailScreen({super.key, required this.lesson});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  late Lesson _lesson;

  @override
  void initState() {
    super.initState();
    _lesson = widget.lesson;
  }

  Future<void> _edit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LessonFormScreen(classId: _lesson.classId, lesson: _lesson),
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: WaveHeader(
              title: _lesson.title,
              subtitle: 'Week ${_lesson.weekNumber}',
              gradientColors: gradientColors,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(PlatformIcons.back, color: Colors.white),
              ),
              actions: [
                IconButton(
                  onPressed: _edit,
                  icon: Icon(PlatformIcons.edit, color: Colors.white),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_lesson.pdfPath != null) ...[
                  _buildCard(
                    title: 'PDF Document',
                    icon: PlatformIcons.pictureAsPdf,
                    iconColor: AppTheme.danger,
                    child: Row(
                      children: [
                        Icon(
                          PlatformIcons.pictureAsPdf,
                          color: AppTheme.danger,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _lesson.pdfPath!.split('/').last,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_lesson.content != null && _lesson.content!.isNotEmpty) ...[
                  _buildCard(
                    title: 'Lesson Content',
                    icon: PlatformIcons.article,
                    iconColor: AppTheme.primary,
                    child: Text(
                      _lesson.content!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_lesson.objectives != null &&
                    _lesson.objectives!.isNotEmpty) ...[
                  _buildCard(
                    title: 'Learning Objectives (ABCD Format)',
                    icon: PlatformIcons.flag,
                    iconColor: const Color(0xFF0891B2),
                    child: Text(
                      _lesson.objectives!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_lesson.references != null &&
                    _lesson.references!.isNotEmpty) ...[
                  _buildCard(
                    title: 'References',
                    icon: PlatformIcons.libraryBooks,
                    iconColor: const Color(0xFF8B5CF6),
                    child: Text(
                      _lesson.references!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
