import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/widgets/curved_background.dart';
import '../../core/utils/platform_icons.dart';
import '../auth/setup_pin_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingScreen({super.key, this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardPage> _pages = [
    _OnboardPage(
      icon: PlatformIcons.school,
      title: 'Welcome to\nGradeBook',
      subtitle:
          'Your all-in-one offline grade management system designed for teachers.',
      color1: Color(0xFF4F46E5),
      color2: Color(0xFF7C3AED),
    ),
    _OnboardPage(
      icon: PlatformIcons.grade,
      title: 'Configurable\nGrading System',
      subtitle:
          'Set custom categories, weights, and grading periods. Grades compute automatically.',
      color1: Color(0xFF0F766E),
      color2: Color(0xFF0891B2),
    ),
    _OnboardPage(
      icon: PlatformIcons.students,
      title: 'Monitor Every\nStudent',
      subtitle:
          'Track attendance, identify at-risk students, and record intervention notes.',
      color1: Color(0xFF7C3AED),
      color2: Color(0xFFDB2777),
    ),
    _OnboardPage(
      icon: PlatformIcons.analytics,
      title: 'Analytics\nDashboard',
      subtitle:
          'Visualize class performance, attendance trends, and grade distributions at a glance.',
      color1: Color(0xFFF59E0B),
      color2: Color(0xFFEF4444),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _goToSetup();
    }
  }

  void _goToSetup() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const SetupPinScreen(isOnboarding: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (_, i) => _OnboardPageWidget(page: _pages[i]),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SmoothPageIndicator(
                  controller: _controller,
                  count: _pages.length,
                  effect: WormEffect(
                    dotColor: Colors.white.withValues(alpha: 0.4),
                    activeDotColor: Colors.white,
                    dotHeight: 8,
                    dotWidth: 8,
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: TextButton(
                            onPressed: () => _controller.previousPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(
                                alpha: 0.8,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              'Back',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                inherit: true,
                              ),
                            ),
                          ),
                        ),
                      if (_currentPage > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _pages[_currentPage].color1,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _currentPage == _pages.length - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              inherit: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentPage < _pages.length - 1)
                  TextButton(
                    onPressed: _goToSetup,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.6),
                    ),
                    child: const Text('Skip'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color1;
  final Color color2;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color1,
    required this.color2,
  });
}

class _OnboardPageWidget extends StatelessWidget {
  final _OnboardPage page;

  const _OnboardPageWidget({required this.page});

  @override
  Widget build(BuildContext context) {
    return FullCurvedBackground(
      colors: [page.color1, page.color2, page.color2.withValues(alpha: 0.8)],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(page.icon, size: 72, color: Colors.white),
              ),
              const SizedBox(height: 48),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                page.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 17,
                  height: 1.6,
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
