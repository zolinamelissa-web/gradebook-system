import 'package:flutter/material.dart';

class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static T value<T>({
    required BuildContext context,
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }

  static double curveHeight(BuildContext context) {
    return value(
      context: context,
      mobile: 220,
      tablet: 260,
      desktop: 300,
    );
  }

  static double curveBottomSpacing(BuildContext context) {
    final screenHeight = height(context);
    if (screenHeight < 700) {
      return 60;
    } else if (screenHeight < 900) {
      return 80;
    } else {
      return 100;
    }
  }

  static double horizontalPadding(BuildContext context) {
    return value(
      context: context,
      mobile: 20,
      tablet: 40,
      desktop: 60,
    );
  }

  static double verticalPadding(BuildContext context) {
    return value(
      context: context,
      mobile: 16,
      tablet: 24,
      desktop: 32,
    );
  }

  static double fontSize(BuildContext context, double baseSize) {
    return value(
      context: context,
      mobile: baseSize,
      tablet: baseSize * 1.1,
      desktop: baseSize * 1.2,
    );
  }

  static int gridCrossAxisCount(BuildContext context, {int mobile = 2}) {
    return value(
      context: context,
      mobile: mobile,
      tablet: mobile + 1,
      desktop: mobile + 2,
    );
  }

  static double maxContentWidth(BuildContext context) {
    return value(
      context: context,
      mobile: double.infinity,
      tablet: 800,
      desktop: 1200,
    );
  }

  static EdgeInsets screenPadding(BuildContext context) {
    final horizontal = horizontalPadding(context);
    final vertical = verticalPadding(context);
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  static EdgeInsets cardPadding(BuildContext context) {
    return EdgeInsets.all(value(
      context: context,
      mobile: 16,
      tablet: 20,
      desktop: 24,
    ));
  }

  static double iconSize(BuildContext context, double baseSize) {
    return value(
      context: context,
      mobile: baseSize,
      tablet: baseSize * 1.15,
      desktop: baseSize * 1.3,
    );
  }

  static double spacing(BuildContext context, double baseSpacing) {
    return value(
      context: context,
      mobile: baseSpacing,
      tablet: baseSpacing * 1.2,
      desktop: baseSpacing * 1.5,
    );
  }
}
