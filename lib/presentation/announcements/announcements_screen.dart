import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/announcement_model.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../classes/class_detail_screen.dart';
import '../home/home_screen.dart';
import '../../data/models/class_model.dart';
import 'add_edit_announcement_modal.dart';

class _ResponsiveHelper {
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= 768;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  static double getCardWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isDesktop(context)) {
      return (screenWidth - 48) / 3; // 3 columns
    } else if (isTablet(context)) {
      return (screenWidth - 32) / 2; // 2 columns
    }
    return screenWidth - 32; // 1 column
  }

  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isDesktop(context)) {
      return const EdgeInsets.all(24.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(20.0);
    }
    return const EdgeInsets.all(16.0);
  }

  static double getFontSize(
    BuildContext context,
    double mobileSize, {
    double? tabletSize,
    double? desktopSize,
  }) {
    if (isDesktop(context)) {
      return desktopSize ?? tabletSize ?? mobileSize;
    } else if (isTablet(context)) {
      return tabletSize ?? mobileSize;
    }
    return mobileSize;
  }
}

class AnnouncementsScreen extends StatefulWidget {
  final int classId;
  final String className;

  const AnnouncementsScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _isLoading = false;
  List<Announcement> _announcements = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get class remote ID for Firebase queries
      final classInfo = await SubjectRepository().getClassById(widget.classId);
      if (classInfo?.remoteId == null) {
        throw Exception('Class information not found');
      }

      final announcements = await AnnouncementRepository.instance
          .getAnnouncementsForClass(classInfo!.remoteId!);

      setState(() {
        _announcements = announcements;
      });
    } catch (e) {
      print('[AnnouncementsScreen] Error loading announcements: $e');
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditAnnouncementModal({
    Announcement? announcement,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEditAnnouncementModal(
        classId: widget.classId,
        className: widget.className,
        announcement: announcement,
      ),
    );

    if (result == true) {
      _loadAnnouncements();
    }
  }

  Future<void> _deleteAnnouncement(Announcement announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: Text(
          'Are you sure you want to delete "${announcement.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AnnouncementRepository.instance.deleteAnnouncement(
          announcement.remoteId!,
        );
        _loadAnnouncements();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting announcement: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.primaryColor;
    final secondary = themeProvider.secondaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Announcements',
            subtitle: widget.className,
            gradientColors: [primary, secondary],
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: () => _showAddEditAnnouncementModal(),
                icon: Icon(PlatformIcons.add, color: Colors.white),
              ),
            ],
          ),

          // Content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: _buildContent(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: 2, // Classes tab
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

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: _ResponsiveHelper.getScreenPadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PlatformIcons.error, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Error loading announcements',
                style: TextStyle(
                  fontSize: _ResponsiveHelper.getFontSize(
                    context,
                    18,
                    tabletSize: 20,
                    desktopSize: 22,
                  ),
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAnnouncements,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_announcements.isEmpty) {
      return Center(
        child: Padding(
          padding: _ResponsiveHelper.getScreenPadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PlatformIcons.notifications,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Announcements',
                style: TextStyle(
                  fontSize: _ResponsiveHelper.getFontSize(
                    context,
                    18,
                    tabletSize: 20,
                    desktopSize: 22,
                  ),
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the + button to create your first announcement',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _ResponsiveHelper.getFontSize(
                    context,
                    14,
                    tabletSize: 15,
                    desktopSize: 16,
                  ),
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnnouncements,
      child: _ResponsiveHelper.isTablet(context)
          ? _buildGridView()
          : _buildListView(),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final announcement = _announcements[index];
        return _AnnouncementCard(
          announcement: announcement,
          onEdit: () =>
              _showAddEditAnnouncementModal(announcement: announcement),
          onDelete: () => _deleteAnnouncement(announcement),
        );
      },
    );
  }

  Widget _buildGridView() {
    final crossAxisCount = _ResponsiveHelper.isDesktop(context) ? 3 : 2;
    final childAspectRatio = _ResponsiveHelper.isDesktop(context) ? 1.2 : 1.0;

    return GridView.builder(
      padding: _ResponsiveHelper.getScreenPadding(context),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final announcement = _announcements[index];
        return _AnnouncementCard(
          announcement: announcement,
          onEdit: () =>
              _showAddEditAnnouncementModal(announcement: announcement),
          onDelete: () => _deleteAnnouncement(announcement),
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AnnouncementCard({
    required this.announcement,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _ResponsiveHelper.isTablet(context);

    return Card(
      margin: isTablet
          ? const EdgeInsets.only(bottom: 16)
          : const EdgeInsets.only(bottom: 12),
      elevation: isTablet ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
      ),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    announcement.title,
                    style: TextStyle(
                      fontSize: _ResponsiveHelper.getFontSize(
                        context,
                        16,
                        tabletSize: 18,
                        desktopSize: 20,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(PlatformIcons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            PlatformIcons.delete,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  child: Icon(PlatformIcons.moreVert),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Text(
              announcement.content,
              style: TextStyle(
                fontSize: _ResponsiveHelper.getFontSize(
                  context,
                  14,
                  tabletSize: 15,
                  desktopSize: 16,
                ),
                color: Colors.grey[600],
                height: 1.4,
              ),
              maxLines: isTablet ? 4 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isTablet ? 16 : 12),
            Row(
              children: [
                Icon(PlatformIcons.schedule, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  _formatDate(announcement.createdAt),
                  style: TextStyle(
                    fontSize: _ResponsiveHelper.getFontSize(
                      context,
                      12,
                      tabletSize: 13,
                      desktopSize: 14,
                    ),
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// Navigation items for bottom navigation (matching home screen)
final List<_NavItem> _navItems = [
  _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
  _NavItem(icon: PlatformIcons.students, label: 'Students'),
  _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
  _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
  _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
];

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
        padding: EdgeInsets.fromLTRB(
          _ResponsiveHelper.isTablet(context) ? 20 : 14,
          0,
          _ResponsiveHelper.isTablet(context) ? 20 : 14,
          _ResponsiveHelper.isTablet(context) ? 16 : 12,
        ),
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
                height: _ResponsiveHelper.isTablet(context) ? 80 : 70,
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
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
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
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 2),
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
