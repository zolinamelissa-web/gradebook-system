import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';

class TableSelectionDialog extends StatefulWidget {
  final String syncDirection;

  const TableSelectionDialog({super.key, required this.syncDirection});

  @override
  State<TableSelectionDialog> createState() => _TableSelectionDialogState();
}

class _TableSelectionDialogState extends State<TableSelectionDialog> {
  final Map<String, bool> _selectedTables = {
    'settings': true,
    'students': true,
    'subjects': true,
    'classes': true,
    'class_students': true,
    'grading_periods': true,
    'grading_categories': true,
    'grading_configurations': true,
    'grading_assessments': true,
    'assessment_scores': true,
    'grades': true,
    'attendance': true,
    'interventions': true,
    'risk_flags': true,
    'counseling_reasons': true,
    'lessons': true,
  };

  final Map<String, String> _tableLabels = {
    'settings': 'Settings',
    'students': 'Students',
    'subjects': 'Subjects',
    'classes': 'Classes',
    'class_students': 'Class Enrollments',
    'grading_periods': 'Grading Periods',
    'grading_categories': 'Grading Categories',
    'grading_configurations': 'Grading Configurations',
    'grading_assessments': 'Assessments',
    'assessment_scores': 'Assessment Scores',
    'grades': 'Period Grades',
    'attendance': 'Attendance Records',
    'interventions': 'Interventions',
    'risk_flags': 'Risk Flags',
    'counseling_reasons': 'Counseling Reasons',
    'lessons': 'Lessons',
  };

  final Map<String, IconData> _tableIcons = {
    'settings': CupertinoIcons.settings,
    'students': CupertinoIcons.person_2,
    'subjects': CupertinoIcons.book,
    'classes': CupertinoIcons.group,
    'class_students': CupertinoIcons.person_badge_plus,
    'grading_periods': CupertinoIcons.calendar,
    'grading_categories': CupertinoIcons.square_list,
    'grading_configurations': CupertinoIcons.slider_horizontal_3,
    'grading_assessments': CupertinoIcons.doc_text,
    'assessment_scores': CupertinoIcons.chart_bar,
    'grades': CupertinoIcons.star,
    'attendance': CupertinoIcons.checkmark_square,
    'interventions': CupertinoIcons.heart,
    'risk_flags': CupertinoIcons.exclamationmark_triangle,
    'counseling_reasons': CupertinoIcons.chat_bubble_text,
    'lessons': CupertinoIcons.book_circle,
  };

  bool get _allSelected => _selectedTables.values.every((v) => v);
  bool get _noneSelected => _selectedTables.values.every((v) => !v);

  void _toggleAll(bool value) {
    setState(() {
      _selectedTables.updateAll((key, _) => value);
    });
  }

  void _toggleTable(String table) {
    setState(() {
      _selectedTables[table] = !_selectedTables[table]!;
    });
  }

  List<String> get _selectedTableList {
    return _selectedTables.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primaryColor = themeProvider.primaryColor;
    final selectedCount = _selectedTables.values.where((v) => v).length;
    final totalCount = _selectedTables.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.syncDirection == 'upload'
                            ? CupertinoIcons.cloud_upload
                            : widget.syncDirection == 'download'
                            ? CupertinoIcons.cloud_download
                            : CupertinoIcons.arrow_2_circlepath,
                        color: primaryColor,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.syncDirection == 'upload'
                                  ? 'Select Tables to Upload'
                                  : widget.syncDirection == 'download'
                                  ? 'Select Tables to Download'
                                  : 'Select Tables to Sync',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$selectedCount of $totalCount tables selected',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _toggleAll(true),
                          icon: Icon(CupertinoIcons.checkmark_square, size: 18),
                          label: const Text('Select All'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            side: BorderSide(color: primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _toggleAll(false),
                          icon: Icon(CupertinoIcons.square, size: 18),
                          label: const Text('Clear All'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: AppTheme.divider),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Table list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _selectedTables.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = _selectedTables.entries.elementAt(index);
                  final table = entry.key;
                  final isSelected = entry.value;
                  final label = _tableLabels[table] ?? table;
                  final icon = _tableIcons[table] ?? CupertinoIcons.square_list;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleTable(table),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor.withValues(alpha: 0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.3)
                                : AppTheme.divider,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor.withValues(alpha: 0.1)
                                    : AppTheme.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                icon,
                                color: isSelected
                                    ? primaryColor
                                    : AppTheme.textSecondary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              color: isSelected
                                  ? primaryColor
                                  : AppTheme.textLight,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _noneSelected
                          ? null
                          : () => Navigator.pop(context, _selectedTableList),
                      icon: Icon(
                        widget.syncDirection == 'upload'
                            ? CupertinoIcons.cloud_upload
                            : widget.syncDirection == 'download'
                            ? CupertinoIcons.cloud_download
                            : CupertinoIcons.arrow_2_circlepath,
                        size: 20,
                      ),
                      label: Text(
                        widget.syncDirection == 'upload'
                            ? 'Upload Selected'
                            : widget.syncDirection == 'download'
                            ? 'Download Selected'
                            : 'Sync Selected',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        disabledBackgroundColor: AppTheme.textLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
