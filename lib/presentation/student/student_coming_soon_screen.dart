import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import 'student_home_screen.dart';

class StudentComingSoonScreen extends StatefulWidget {
  final String title;
  final String subtitle;

  const StudentComingSoonScreen({
    super.key,
    required this.title,
    this.subtitle = 'Coming Soon',
  });

  @override
  State<StudentComingSoonScreen> createState() =>
      _StudentComingSoonScreenState();
}

class _StudentComingSoonScreenState extends State<StudentComingSoonScreen> {
  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Statistics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: WaveHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              gradientColors: gradientColors,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(PlatformIcons.back, color: Colors.white),
              ),
              actions: const [],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8ECF4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        PlatformIcons.construction,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'This feature is under development.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'We are working on this screen to match your teacher\'s setup and class configuration.',
                      style: TextStyle(
                        height: 1.5,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
