import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../data/database/database_helper.dart';

class ClearDataDialog extends StatefulWidget {
  const ClearDataDialog({super.key});

  @override
  State<ClearDataDialog> createState() => _ClearDataDialogState();
}

class _ClearDataDialogState extends State<ClearDataDialog> {
  final Map<String, bool> _selectedTables = {
    'users': false,
    'settings': false,
    'students': false,
    'subjects': false,
    'classes': false,
    'class_students': false,
    'grading_periods': false,
    'grading_categories': false,
    'grading_configurations': false,
    'grading_assessments': false,
    'assessment_scores': false,
    'grades': false,
    'attendance': false,
    'interventions': false,
    'risk_flags': false,
    'lessons': false,
  };

  final Map<String, String> _tableLabels = {
    'users': 'Users',
    'settings': 'Settings',
    'students': 'Students',
    'subjects': 'Subjects',
    'classes': 'Classes',
    'class_students': 'Class Enrollments',
    'grading_periods': 'Grading Periods',
    'grading_categories': 'Grading Categories',
    'grading_configurations': 'Grading Configurations',
    'grading_assessments': 'Grading Assessments',
    'assessment_scores': 'Assessment Scores',
    'grades': 'Grades',
    'attendance': 'Attendance Records',
    'interventions': 'Interventions',
    'risk_flags': 'Risk Flags',
    'lessons': 'Lessons',
  };

  final Map<String, IconData> _tableIcons = {
    'users': PlatformIcons.person,
    'settings': PlatformIcons.tune,
    'students': PlatformIcons.students,
    'subjects': PlatformIcons.book,
    'classes': PlatformIcons.classes,
    'class_students': PlatformIcons.groupAdd,
    'grading_periods': PlatformIcons.calendarMonth,
    'grading_categories': PlatformIcons.category,
    'grading_configurations': PlatformIcons.settings,
    'grading_assessments': PlatformIcons.assignment,
    'assessment_scores': PlatformIcons.score,
    'grades': PlatformIcons.grade,
    'attendance': PlatformIcons.checkCircle,
    'interventions': PlatformIcons.support,
    'risk_flags': PlatformIcons.flag,
    'lessons': PlatformIcons.book,
  };

  bool _isClearing = false;
  bool get _hasSelection => _selectedTables.values.any((selected) => selected);

  Future<void> _clearData() async {
    final selectedTables = _selectedTables.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedTables.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(PlatformIcons.warning, color: AppTheme.danger),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirm Clear Data',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete all local data from the selected tables. You can restore data by syncing with cloud.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Selected tables:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ...selectedTables.map(
              (table) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    Icon(
                      PlatformIcons.checkCircle,
                      size: 16,
                      color: AppTheme.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tableLabels[table] ?? table,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClearing = true);

    try {
      print('[ClearDataDialog] Clearing tables: $selectedTables');
      await DatabaseHelper.instance.clearSelectedTables(selectedTables);
      print(
        '[ClearDataDialog] Successfully cleared ${selectedTables.length} tables',
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cleared ${selectedTables.length} table(s) successfully',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      print('[ClearDataDialog] Error clearing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      PlatformIcons.deleteSweep,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clear Local Data',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select tables to clear',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(PlatformIcons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Table selection list
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: _selectedTables.keys.map((table) {
                  return _TableCheckbox(
                    label: _tableLabels[table] ?? table,
                    icon: _tableIcons[table] ?? PlatformIcons.tableChart,
                    value: _selectedTables[table]!,
                    onChanged: _isClearing
                        ? null
                        : (value) {
                            setState(() {
                              _selectedTables[table] = value ?? false;
                            });
                          },
                  );
                }).toList(),
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8ECF4))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isClearing
                          ? null
                          : () {
                              setState(() {
                                final allSelected = _selectedTables.values
                                    .every((v) => v);
                                _selectedTables.updateAll(
                                  (key, value) => !allSelected,
                                );
                              });
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _selectedTables.values.every((v) => v)
                            ? 'Deselect All'
                            : 'Select All',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isClearing || !_hasSelection
                          ? null
                          : _clearData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: _isClearing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Clear Data',
                              style: TextStyle(fontWeight: FontWeight.w600),
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

class _TableCheckbox extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _TableCheckbox({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFFFECACA) : const Color(0xFFE8ECF4),
          width: 1.5,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? AppTheme.danger.withValues(alpha: 0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: value ? AppTheme.danger : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                  color: value ? AppTheme.danger : AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        controlAffinity: ListTileControlAffinity.trailing,
        activeColor: AppTheme.danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
