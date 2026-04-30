import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/icon_fix.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';

class StudentLessonDetailScreen extends StatelessWidget {
  final Map<String, dynamic> lesson;
  final List<Color>? gradientColors;

  const StudentLessonDetailScreen({
    super.key,
    required this.lesson,
    this.gradientColors,
  });

  String get _title {
    final t = (lesson['title']?.toString() ?? '').trim();
    return t.isNotEmpty ? t : 'Lesson';
  }

  int get _week {
    final v = lesson['week_number'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get _pdfPath => (lesson['pdf_path']?.toString() ?? '').trim();
  String get _content => (lesson['content']?.toString() ?? '').trim();
  String get _objectives => (lesson['objectives']?.toString() ?? '').trim();
  String get _references => (lesson['refs']?.toString() ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradient = gradientColors ?? themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: WaveHeader(
              title: _title,
              subtitle: _week > 0 ? 'Week $_week' : 'Lesson',
              gradientColors: gradient,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: PlatformIcons.isIOS
                    ? Icon(PlatformIcons.back, color: Colors.white)
                    : IconFix.fixIcon(
                        Icon(PlatformIcons.back, color: Colors.white),
                      ),
              ),
              actions: const [],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_pdfPath.isNotEmpty) ...[
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
                            _pdfPath.split('/').last,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_content.isNotEmpty) ...[
                  _buildCard(
                    title: 'Lesson Content',
                    icon: PlatformIcons.article,
                    iconColor: AppTheme.primary,
                    child: Text(
                      _content,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_objectives.isNotEmpty) ...[
                  _buildCard(
                    title: 'Learning Objectives (ABCD Format)',
                    icon: PlatformIcons.flag,
                    iconColor: const Color(0xFF0891B2),
                    child: Text(
                      _objectives,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_references.isNotEmpty) ...[
                  _buildCard(
                    title: 'References',
                    icon: PlatformIcons.libraryBooks,
                    iconColor: const Color(0xFF8B5CF6),
                    child: Text(
                      _references,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
                if (_pdfPath.isEmpty &&
                    _content.isEmpty &&
                    _objectives.isEmpty &&
                    _references.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'No lesson content available.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
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
