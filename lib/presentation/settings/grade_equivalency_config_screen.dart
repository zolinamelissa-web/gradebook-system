import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/auto_sync_service.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/grade_equivalency.dart';

class GradeEquivalencyConfigScreen extends StatefulWidget {
  const GradeEquivalencyConfigScreen({super.key});

  @override
  State<GradeEquivalencyConfigScreen> createState() =>
      _GradeEquivalencyConfigScreenState();
}

class _GradeEquivalencyConfigScreenState
    extends State<GradeEquivalencyConfigScreen> {
  GradeEquivalencyTable _table = const GradeEquivalencyTable(equivalencies: []);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final json = await DatabaseHelper.instance.getSetting(
      'grade_equivalency_table',
    );
    GradeEquivalencyTable table = const GradeEquivalencyTable(
      equivalencies: [],
    );

    if (json != null && json.isNotEmpty) {
      try {
        table = GradeEquivalencyTable.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
      } catch (e) {
        print('[GradeEquivalencyConfig] Error parsing table: $e');
      }
    }

    if (mounted) {
      setState(() {
        _table = table;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    await DatabaseHelper.instance.setSetting(
      'grade_equivalency_table',
      jsonEncode(_table.toJson()),
    );
    print(
      '[GradeEquivalencyConfig] Saved ${_table.equivalencies.length} equivalencies',
    );

    // Auto-sync settings to cloud
    AutoSyncService.syncSettings().catchError((e) {
      print('[GradeEquivalencyConfig] Auto-sync failed: $e');
    });
  }

  Future<void> _loadPreset(GradeEquivalencyTable preset) async {
    setState(() {
      _table = preset;
    });
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preset loaded successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _addEquivalency() async {
    final result = await _showEquivalencyDialog();
    if (result != null) {
      setState(() {
        _table = _table.copyWith(
          equivalencies: [..._table.equivalencies, result],
        );
      });
      await _save();
    }
  }

  Future<void> _editEquivalency(int index) async {
    final result = await _showEquivalencyDialog(
      existing: _table.equivalencies[index],
    );
    if (result != null) {
      final updated = List<GradeEquivalency>.from(_table.equivalencies);
      updated[index] = result;
      setState(() {
        _table = _table.copyWith(equivalencies: updated);
      });
      await _save();
    }
  }

  Future<void> _deleteEquivalency(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Equivalency'),
        content: const Text(
          'Are you sure you want to delete this equivalency?',
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

    if (confirm == true) {
      final updated = List<GradeEquivalency>.from(_table.equivalencies);
      updated.removeAt(index);
      setState(() {
        _table = _table.copyWith(equivalencies: updated);
      });
      await _save();
    }
  }

  Future<GradeEquivalency?> _showEquivalencyDialog({
    GradeEquivalency? existing,
  }) async {
    final minCtrl = TextEditingController(
      text: existing?.minPercentage.toStringAsFixed(0) ?? '',
    );
    final maxCtrl = TextEditingController(
      text: existing?.maxPercentage.toStringAsFixed(0) ?? '',
    );
    final gradeCtrl = TextEditingController(
      text: existing?.numericalGrade.toStringAsFixed(2) ?? '',
    );
    final descCtrl = TextEditingController(text: existing?.descriptor ?? '');
    final formKey = GlobalKey<FormState>();

    minCtrl.selection = TextSelection.collapsed(offset: minCtrl.text.length);
    maxCtrl.selection = TextSelection.collapsed(offset: maxCtrl.text.length);
    gradeCtrl.selection = TextSelection.collapsed(
      offset: gradeCtrl.text.length,
    );
    descCtrl.selection = TextSelection.collapsed(offset: descCtrl.text.length);

    final result = await showDialog<GradeEquivalency?>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(existing == null ? 'Add Equivalency' : 'Edit Equivalency'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Min %',
                          hintText: '75',
                          suffixIcon: minCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: Icon(PlatformIcons.close),
                                  onPressed: () {
                                    minCtrl.clear();
                                  },
                                ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final d = double.tryParse(v.trim());
                          if (d == null || d < 0 || d > 100) {
                            return '0-100';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Max %',
                          hintText: '76',
                          suffixIcon: maxCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: Icon(PlatformIcons.close),
                                  onPressed: () {
                                    maxCtrl.clear();
                                  },
                                ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final d = double.tryParse(v.trim());
                          if (d == null || d < 0 || d > 100) {
                            return '0-100';
                          }
                          final min = double.tryParse(minCtrl.text.trim());
                          if (min != null && d < min) {
                            return 'Max ≥ Min';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: gradeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numerical Grade',
                    hintText: '3.0',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final d = double.tryParse(v.trim());
                    if (d == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descriptor (optional)',
                    hintText: 'Passing, Good, etc.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final equiv = GradeEquivalency(
                  minPercentage: double.parse(minCtrl.text.trim()),
                  maxPercentage: double.parse(maxCtrl.text.trim()),
                  numericalGrade: double.parse(gradeCtrl.text.trim()),
                  descriptor: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                );
                Navigator.pop(context, equiv);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    Future.delayed(const Duration(milliseconds: 350), () {
      minCtrl.dispose();
      maxCtrl.dispose();
      gradeCtrl.dispose();
      descCtrl.dispose();
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Fixed Header with Wave
                WaveHeader(
                  title: 'Grade Equivalency Table',
                  subtitle:
                      'Configure grade conversion from percentage to numerical scale',
                  gradientColors: gradientColors,
                  leading: IconButton(
                    tooltip: 'Back',
                    icon: Icon(PlatformIcons.back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    PopupMenuButton<GradeEquivalencyTable>(
                      icon: Icon(PlatformIcons.moreVert, color: Colors.white),
                      tooltip: 'Load Preset',
                      onSelected: _loadPreset,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: GradeEquivalencyTable.depedTo1to5,
                          child: Text('DepEd to 1.0-5.0 Scale'),
                        ),
                        const PopupMenuItem(
                          value: GradeEquivalencyTable.depedTo4point0,
                          child: Text('DepEd to 4.0 Scale'),
                        ),
                      ],
                    ),
                  ],
                  chips: [
                    WaveHeaderChip(
                      icon: PlatformIcons.tableChart,
                      label: 'Equivalencies',
                      value: _table.equivalencies.length.toString(),
                    ),
                  ],
                ),
                // Scrollable Grade Equivalency Content
                Expanded(
                  child: _table.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PlatformIcons.tableChart,
                                size: 64,
                                color: Colors.grey.shade300,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No equivalencies configured',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to add or load a preset',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: themeProvider.secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 80),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            children: List.generate(
                              _table.equivalencies.length,
                              (index) => Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.divider),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: themeProvider.primaryColor
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _table.equivalencies[index].numericalGrade
                                          .toStringAsFixed(2),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: themeProvider.primaryColor,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '${_table.equivalencies[index].minPercentage.toStringAsFixed(0)}-${_table.equivalencies[index].maxPercentage.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle:
                                      _table.equivalencies[index].descriptor !=
                                          null
                                      ? Text(
                                          _table
                                              .equivalencies[index]
                                              .descriptor!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          PlatformIcons.edit,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _editEquivalency(index),
                                        color: themeProvider.primaryColor,
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          PlatformIcons.delete,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _deleteEquivalency(index),
                                        color: AppTheme.danger,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEquivalency,
        backgroundColor: themeProvider.primaryColor,
        child: Icon(PlatformIcons.add, color: Colors.white),
      ),
    );
  }
}
