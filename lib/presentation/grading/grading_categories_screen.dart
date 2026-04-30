import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/grading_category_model.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/grading_repository.dart';
import '../home/home_screen.dart';

class GradingCategoriesScreen extends StatefulWidget {
  final ClassModel classModel;
  final GradingPeriod period;

  const GradingCategoriesScreen({
    super.key,
    required this.classModel,
    required this.period,
  });

  @override
  State<GradingCategoriesScreen> createState() =>
      _GradingCategoriesScreenState();
}

class _CategoryDialogResult {
  final String name;
  final double weight;

  const _CategoryDialogResult({required this.name, required this.weight});
}

class _CategoryDialog extends StatefulWidget {
  final GradingCategory? existing;

  const _CategoryDialog({required this.existing});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _weightController = TextEditingController(
      text: widget.existing?.weight.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final weight = double.parse(_weightController.text.trim());
    Navigator.pop(context, _CategoryDialogResult(name: name, weight: weight));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.existing == null ? 'Add Category' : 'Edit Category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name *',
                hintText: 'e.g. Quiz, Exam, Project',
              ),
              autofocus: true,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Weight (%) *',
                hintText: 'e.g. 30',
                suffixText: '%',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final d = double.tryParse(v.trim());
                if (d == null || d <= 0 || d > 100) return 'Enter 1-100';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _GradingCategoriesScreenState extends State<GradingCategoriesScreen> {
  final GradingRepository _repo = GradingRepository();
  List<GradingCategory> _categories = [];
  double _totalWeight = 0;

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final cats = await _repo.getCategoriesByPeriod(widget.period.id!);
      final total = await _repo.getTotalWeight(widget.period.id!);
      print(
        '[GradingCategoriesScreen] Loaded ${cats.length} categories, total=$total%',
      );
      if (mounted) {
        setState(() {
          _categories = cats;
          _totalWeight = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[GradingCategoriesScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addCategory() async {
    if (widget.period.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grading period is locked. Cannot add categories.'),
        ),
      );
      return;
    }
    await _showCategoryDialog();
  }

  Future<void> _showCategoryDialog({GradingCategory? existing}) async {
    final result = await showDialog<_CategoryDialogResult>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing),
    );

    if (result != null) {
      try {
        final newWeight = result.weight;
        final otherTotal = _totalWeight - (existing?.weight ?? 0);
        if (otherTotal + newWeight > 100.001) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Total weight would exceed 100%. Remaining: ${(100 - otherTotal).toStringAsFixed(1)}%',
                ),
                backgroundColor: AppTheme.danger,
              ),
            );
          }
          return;
        }
        final now = DateTime.now().toIso8601String();
        if (existing != null) {
          await _repo.updateCategory(
            existing.copyWith(
              name: result.name,
              weight: newWeight,
              updatedAt: now,
            ),
          );
          print('[GradingCategoriesScreen] Updated category id=${existing.id}');
        } else {
          final cat = GradingCategory(
            gradingPeriodId: widget.period.id!,
            name: result.name,
            weight: newWeight,
            createdAt: now,
            updatedAt: now,
          );
          await _repo.insertCategory(cat);
          print('[GradingCategoriesScreen] Inserted new category');
        }
        _load();
      } catch (e) {
        print('[GradingCategoriesScreen] Category save error: $e');
      }
    }
  }

  Future<void> _deleteCategory(GradingCategory cat) async {
    if (widget.period.isLocked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Category'),
        content: Text('Delete "${cat.name}"? All related grades will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.deleteCategory(cat.id!);
      _load();
    }
  }

  Color _weightColor() {
    if (_totalWeight < 99.9) return AppTheme.warning;
    if (_totalWeight > 100.01) return AppTheme.danger;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Grade Categories',
            subtitle:
                '${widget.period.name} • ${widget.classModel.displayName}',
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
          ),
          // Scrollable Grade Categories Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _categories.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PlatformIcons.category,
                            size: 64,
                            color: AppTheme.textLight.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No categories yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add categories and assign percentage weights.\nTotal must equal 100%.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      child: Column(
                        children: [
                          // Weight Summary Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _weightColor().withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _weightColor().withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _totalWeight >= 99.9 && _totalWeight <= 100.01
                                      ? PlatformIcons.checkCircleOutline
                                      : PlatformIcons.info,
                                  color: _weightColor(),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _totalWeight >= 99.9 &&
                                            _totalWeight <= 100.01
                                        ? 'Total weight is 100% ✓'
                                        : _totalWeight > 100.01
                                        ? 'Total weight exceeds 100%!'
                                        : 'Remaining weight: ${(100 - _totalWeight).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: _weightColor(),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (widget.period.isLocked) ...[
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warning.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          PlatformIcons.lock,
                                          size: 14,
                                          color: AppTheme.warning,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Locked',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.warning,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Category Cards
                          ...List.generate(
                            _categories.length,
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CategoryCard(
                                category: _categories[i],
                                isLocked: widget.period.isLocked,
                                onEdit: () => _showCategoryDialog(
                                  existing: _categories[i],
                                ),
                                onDelete: () => _deleteCategory(_categories[i]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: widget.period.isLocked
          ? null
          : FloatingActionButton(
              onPressed: _addCategory,
              backgroundColor: const Color(0xFF0F766E),
              child: Icon(PlatformIcons.add, color: Colors.white),
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

class _CategoryCard extends StatelessWidget {
  final GradingCategory category;
  final bool isLocked;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
    required this.isLocked,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${category.weight.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Weight: ${category.weight.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: category.weight / 100,
                backgroundColor: AppTheme.divider,
                color: AppTheme.primary,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isLocked)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
