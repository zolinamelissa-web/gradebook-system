import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/repositories/grading_repository.dart';
import 'grading_categories_screen.dart';
import '../home/home_screen.dart';

class GradingPeriodsScreen extends StatefulWidget {
  final ClassModel classModel;

  const GradingPeriodsScreen({super.key, required this.classModel});

  @override
  State<GradingPeriodsScreen> createState() => _GradingPeriodsScreenState();
}

class _GradingPeriodsScreenState extends State<GradingPeriodsScreen> {
  final GradingRepository _repo = GradingRepository();
  List<GradingPeriod> _periods = [];
  bool _isLoading = true;

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
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _repo.getPeriodsByClass(widget.classModel.id!);
      print('[GradingPeriodsScreen] Loaded ${list.length} periods');
      if (mounted) {
        setState(() {
          _periods = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[GradingPeriodsScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPeriod() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddPeriodDialog(
        classId: widget.classModel.id!,
        currentPeriodCount: _periods.length,
        onPeriodAdded: _load,
      ),
    );
  }

  Future<void> _editPeriod(GradingPeriod period) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditPeriodDialog(period: period, onPeriodUpdated: _load),
    );
  }

  Future<void> _toggleLock(GradingPeriod period) async {
    if (period.isLocked) {
      await _unlockPeriod(period);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Lock Grading Period'),
        content: Text(
          'Lock "${period.name}"? Grades and categories cannot be edited after locking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.lockPeriod(period.id!);
      print('[GradingPeriodsScreen] Locked period id=${period.id}');
      _load();
    }
  }

  Future<void> _unlockPeriod(GradingPeriod period) async {
    final storedPinHash = await DatabaseHelper.instance.getSetting('pin_hash');
    if (!mounted) return;
    if (storedPinHash == null || storedPinHash.isEmpty) {
      print('[GradingPeriodsScreen] Unlock failed: pin_hash is not set');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN is not set. Please set your PIN in Settings.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    while (true) {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogCtx) =>
            _PinDialog(periodName: period.name, storedPinHash: storedPinHash),
      );

      if (result == 'correct') {
        await _repo.unlockPeriod(period.id!);
        print('[GradingPeriodsScreen] Unlocked period id=${period.id}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unlocked "${period.name}"'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
        _load();
        break;
      } else if (result == 'incorrect') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect PIN'),
              backgroundColor: AppTheme.danger,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        break;
      }
    }
  }

  Future<void> _activate(GradingPeriod period) async {
    await _repo.activatePeriod(period.id!, widget.classModel.id!);
    print('[GradingPeriodsScreen] Activated period id=${period.id}');
    _load();
  }

  Future<void> _deletePeriod(GradingPeriod period) async {
    if (period.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete a locked period.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Period'),
        content: Text(
          'Delete "${period.name}"? All grades in this period will be lost.',
        ),
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
      await _repo.deletePeriod(period.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          WaveHeader(
            title: 'Grading Periods',
            subtitle: widget.classModel.displayName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _periods.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PlatformIcons.calendar,
                          size: 64,
                          color: AppTheme.textLight.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No grading periods yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      itemCount: _periods.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _PeriodCard(
                        period: _periods[i],
                        onEdit: _editPeriod,
                        onLock: _toggleLock,
                        onActivate: _activate,
                        onDelete: _deletePeriod,
                        onCategories: (p) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GradingCategoriesScreen(
                              classModel: widget.classModel,
                              period: p,
                            ),
                          ),
                        ).then((_) => _load()),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPeriod,
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

class _PeriodCard extends StatelessWidget {
  final GradingPeriod period;
  final void Function(GradingPeriod) onEdit;
  final void Function(GradingPeriod) onLock;
  final void Function(GradingPeriod) onActivate;
  final void Function(GradingPeriod) onDelete;
  final void Function(GradingPeriod) onCategories;

  const _PeriodCard({
    required this.period,
    required this.onEdit,
    required this.onLock,
    required this.onActivate,
    required this.onDelete,
    required this.onCategories,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: period.isActive ? const Color(0xFF0F766E) : AppTheme.divider,
          width: period.isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: period.isActive
                        ? const Color(0xFF0F766E).withValues(alpha: 0.1)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    period.isLocked
                        ? PlatformIcons.lock
                        : PlatformIcons.calendarMonth,
                    color: period.isActive
                        ? const Color(0xFF0F766E)
                        : AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            period.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (period.isActive)
                            _Badge(
                              label: 'Active',
                              color: const Color(0xFF0F766E),
                            ),
                          if (period.isLocked)
                            _Badge(label: 'Locked', color: AppTheme.warning),
                        ],
                      ),
                      Text(
                        'Period ${period.orderNum}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    PlatformIcons.moreVert,
                    color: AppTheme.textSecondary,
                  ),
                  onSelected: (v) {
                    if (v == 'edit') onEdit(period);
                    if (v == 'lock') onLock(period);
                    if (v == 'activate') onActivate(period);
                    if (v == 'delete') onDelete(period);
                  },
                  itemBuilder: (_) => [
                    if (!period.isLocked)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (!period.isActive)
                      const PopupMenuItem(
                        value: 'activate',
                        child: Text('Set Active'),
                      ),
                    if (!period.isLocked)
                      const PopupMenuItem(
                        value: 'lock',
                        child: Text('Lock Period'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'lock',
                        child: Text('Unlock Period'),
                      ),
                    if (!period.isLocked)
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
          ),
          const Divider(height: 1),
          InkWell(
            onTap: () => onCategories(period),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    PlatformIcons.category,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Manage Grade Categories',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    PlatformIcons.chevronRight,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _PinDialog extends StatefulWidget {
  final String periodName;
  final String storedPinHash;

  const _PinDialog({required this.periodName, required this.storedPinHash});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  late final TextEditingController _pinController;

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _checkPin() {
    final inputHash = _hashPin(_pinController.text);
    final ok = inputHash == widget.storedPinHash;
    print('[GradingPeriodsScreen] Unlock PIN match=$ok');
    if (ok) {
      Navigator.pop(context, 'correct');
    } else {
      Navigator.pop(context, 'incorrect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Unlock Grading Period'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter PIN to unlock "${widget.periodName}"',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            autofocus: true,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => _checkPin(),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your app PIN',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _checkPin,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

// Custom dialog widgets that properly manage TextEditingController lifecycle
class _AddPeriodDialog extends StatefulWidget {
  final int classId;
  final int currentPeriodCount;
  final VoidCallback onPeriodAdded;

  const _AddPeriodDialog({
    required this.classId,
    required this.currentPeriodCount,
    required this.onPeriodAdded,
  });

  @override
  State<_AddPeriodDialog> createState() => _AddPeriodDialogState();
}

class _AddPeriodDialogState extends State<_AddPeriodDialog> {
  late final TextEditingController _nameController;
  final GradingRepository _repo = GradingRepository();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addPeriod() async {
    if (_nameController.text.trim().isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final period = GradingPeriod(
      classId: widget.classId,
      name: _nameController.text.trim(),
      orderNum: widget.currentPeriodCount + 1,
      createdAt: now,
      updatedAt: now,
    );

    await _repo.insertPeriod(period);
    widget.onPeriodAdded();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Grading Period'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Period Name *',
          hintText: 'e.g. Prelim, Midterm, Finals',
        ),
        autofocus: true,
        onSubmitted: (_) => _addPeriod(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _addPeriod, child: const Text('Add')),
      ],
    );
  }
}

class _EditPeriodDialog extends StatefulWidget {
  final GradingPeriod period;
  final VoidCallback onPeriodUpdated;

  const _EditPeriodDialog({
    required this.period,
    required this.onPeriodUpdated,
  });

  @override
  State<_EditPeriodDialog> createState() => _EditPeriodDialogState();
}

class _EditPeriodDialogState extends State<_EditPeriodDialog> {
  late final TextEditingController _nameController;
  final GradingRepository _repo = GradingRepository();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.period.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updatePeriod() async {
    if (_nameController.text.trim().isEmpty) return;

    await _repo.updatePeriod(
      widget.period.copyWith(
        name: _nameController.text.trim(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
    widget.onPeriodUpdated();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Grading Period'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Period Name *'),
        autofocus: true,
        onSubmitted: (_) => _updatePeriod(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _updatePeriod, child: const Text('Save')),
      ],
    );
  }
}
