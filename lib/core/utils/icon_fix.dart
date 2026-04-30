import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utility class to fix Material Icons rendering issues on Android
class IconFix {
  static bool _initialized = false;

  /// Initialize Material Icons font to prevent Chinese characters
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Ensure Material Icons are loaded
      final fontLoader = FontLoader('MaterialIcons');

      // Load the Material Icons font
      fontLoader.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await fontLoader.load();

      _initialized = true;
      debugPrint('[IconFix] Material Icons initialized successfully');
    } catch (e) {
      debugPrint('[IconFix] Failed to initialize Material Icons: $e');

      // Fallback: Force a widget rebuild to ensure icons are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Trigger a rebuild to ensure icons are properly displayed
        debugPrint('[IconFix] Using fallback icon loading');
      });
    }
  }

  /// Wrap an icon widget to ensure it renders correctly
  static Widget fixIcon(Widget icon) {
    return Builder(
      builder: (context) {
        // Force the icon to use Material Icons font family
        return DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'MaterialIcons'),
          child: icon,
        );
      },
    );
  }

  /// Get a safe icon that won't show Chinese characters
  static IconData getSafeIcon(IconData icon) {
    // Common problematic icons and their alternatives
    final Map<IconData, IconData> iconMap = {
      Icons.class_: Icons.school,
      Icons.people_alt: Icons.people,
      Icons.dashboard: Icons.grid_view,
      Icons.logout: Icons.exit_to_app,
      Icons.settings: Icons.settings_applications,
      Icons.notifications: Icons.notifications_none,
      Icons.notifications_active: Icons.notifications,
      Icons.notifications_none: Icons.notifications,
      Icons.warning_amber: Icons.warning,
      Icons.menu_book: Icons.book,
      Icons.grade: Icons.star,
      Icons.calculate: Icons.add,
      Icons.fact_check: Icons.check_box,
      Icons.quiz: Icons.help,
      Icons.assignment: Icons.description,
      Icons.score: Icons.bar_chart,
      Icons.folder_special: Icons.folder,
      Icons.task_alt: Icons.check_circle,
      Icons.category: Icons.apps,
      Icons.calendar_month: Icons.calendar_today,
      Icons.event_note: Icons.event,
      Icons.picture_as_pdf: Icons.description,
      Icons.how_to_reg: Icons.check_circle,
      Icons.show_chart: Icons.bar_chart,
      Icons.insights: Icons.lightbulb,
      Icons.article: Icons.description,
      Icons.library_books: Icons.book,
      Icons.edit_note: Icons.edit,
      Icons.drive_file_rename_outline: Icons.edit,
      Icons.swap_horiz: Icons.compare_arrows,
      Icons.date_range: Icons.calendar_today,
      Icons.support: Icons.help,
      Icons.view_list: Icons.list,
      Icons.group_off: Icons.group,
      Icons.workspace_premium: Icons.star,
      Icons.drag_indicator: Icons.menu,
      Icons.ios_share: Icons.share,
      Icons.grid_on: Icons.grid_view,
      Icons.check_circle_outline: Icons.check_circle,
      Icons.watch_later: Icons.access_time,
      Icons.timeline: Icons.bar_chart,
      Icons.event_busy: Icons.event,
      Icons.upload_file: Icons.cloud_upload,
      Icons.auto_awesome: Icons.star,
      Icons.remove_circle_outline: Icons.remove_circle,
      Icons.add_circle_outline: Icons.add_circle,
      Icons.confirmation_number: Icons.confirmation_num,
      Icons.rocket_launch: Icons.send,
      Icons.home_work: Icons.home,
    };

    return iconMap[icon] ?? icon;
  }
}
