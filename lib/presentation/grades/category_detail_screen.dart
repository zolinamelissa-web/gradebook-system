import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/grading_category_model.dart';
import '../../core/utils/platform_icons.dart';
import '../home/home_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final GradingCategory category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late GradingCategory _category;

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.category;
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('quiz')) return PlatformIcons.quiz;
    if (name.contains('exam') || name.contains('test'))
      return PlatformIcons.assignment;
    if (name.contains('project')) return PlatformIcons.folderSpecial;
    if (name.contains('activity') || name.contains('performance'))
      return PlatformIcons.taskAlt;
    if (name.contains('homework') || name.contains('assignment'))
      return PlatformIcons.edit;
    if (name.contains('participation')) return PlatformIcons.people;
    if (name.contains('attendance')) return PlatformIcons.factCheck;
    return PlatformIcons.category;
  }

  Color _getCategoryColor(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('quiz')) return const Color(0xFF8B5CF6);
    if (name.contains('exam') || name.contains('test')) return AppTheme.danger;
    if (name.contains('project')) return const Color(0xFF10B981);
    if (name.contains('activity') || name.contains('performance'))
      return AppTheme.secondary;
    if (name.contains('homework') || name.contains('assignment'))
      return AppTheme.primary;
    if (name.contains('participation')) return const Color(0xFFF59E0B);
    if (name.contains('attendance')) return AppTheme.success;
    return const Color(0xFF6366F1);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();
    final categoryColor = _getCategoryColor(_category.name);
    final categoryIcon = _getCategoryIcon(_category.name);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          WaveHeader(
            title: _category.name,
            subtitle: 'Category Details',
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                children: [
                  _CategoryInfoCard(
                    category: _category,
                    color: categoryColor,
                    icon: categoryIcon,
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle('Category Statistics'),
                  const SizedBox(height: 12),
                  _StatisticsCard(category: _category, color: categoryColor),
                  const SizedBox(height: 18),
                  _SectionTitle('Assessments'),
                  const SizedBox(height: 12),
                  _DevelopmentPlaceholder(
                    icon: categoryIcon,
                    color: categoryColor,
                    title: 'Feature in Development',
                    message:
                        'Assessment management and detailed analytics for this category are currently being developed.',
                  ),
                ],
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

class _CategoryInfoCard extends StatelessWidget {
  final GradingCategory category;
  final Color color;
  final IconData icon;

  const _CategoryInfoCard({
    required this.category,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            category.name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Weight: ${category.weight.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsCard extends StatelessWidget {
  final GradingCategory category;
  final Color color;

  const _StatisticsCard({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Category Information',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          _StatRow(
            icon: PlatformIcons.percent,
            label: 'Weight Percentage',
            value: '${category.weight.toStringAsFixed(1)}%',
            color: color,
          ),
          const SizedBox(height: 12),
          _StatRow(
            icon: PlatformIcons.calculate,
            label: 'Contribution to Final Grade',
            value: '${category.weight.toStringAsFixed(0)}% of total',
            color: color,
          ),
          const SizedBox(height: 12),
          _StatRow(
            icon: PlatformIcons.category,
            label: 'Category Type',
            value: category.name,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DevelopmentPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _DevelopmentPlaceholder({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(PlatformIcons.construction, size: 56, color: color),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PlatformIcons.info, size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  'Coming Soon',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
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
