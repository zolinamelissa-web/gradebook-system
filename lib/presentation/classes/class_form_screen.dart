import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/subject_model.dart';
import '../../data/repositories/subject_repository.dart';

class ClassFormScreen extends StatefulWidget {
  final ClassModel? classModel;

  const ClassFormScreen({super.key, this.classModel});

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final SubjectRepository _repo = SubjectRepository();

  final _sectionController = TextEditingController();
  final _schoolYearController = TextEditingController();
  final _semesterController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _roomController = TextEditingController();

  List<Subject> _subjects = [];
  Subject? _selectedSubject;
  bool _isSaving = false;
  bool get _isEditing => widget.classModel != null;

  @override
  void initState() {
    super.initState();
    final c = widget.classModel;
    _sectionController.text = c?.section ?? '';
    _schoolYearController.text = c?.schoolYear ?? '';
    _semesterController.text = c?.semester ?? '';
    _scheduleController.text = c?.schedule ?? '';
    _roomController.text = c?.room ?? '';
    _loadSubjects(c?.subjectId);
  }

  @override
  void dispose() {
    _sectionController.dispose();
    _schoolYearController.dispose();
    _semesterController.dispose();
    _scheduleController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects(int? selectedId) async {
    final list = await _repo.getAllSubjects();
    print('[ClassFormScreen] Loaded ${list.length} subjects');
    if (mounted) {
      setState(() {
        _subjects = list;
        if (selectedId != null) {
          _selectedSubject = list.where((s) => s.id == selectedId).firstOrNull;
        }
      });
    }
  }

  Future<void> _addSubject() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _AddSubjectDialog(onSubjectAdded: (id) => _loadSubjects(id)),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create a subject'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      if (_isEditing) {
        final updated = widget.classModel!.copyWith(
          subjectId: _selectedSubject!.id,
          section: _sectionController.text.trim(),
          schoolYear: _schoolYearController.text.trim(),
          semester: _semesterController.text.trim().isEmpty
              ? null
              : _semesterController.text.trim(),
          schedule: _scheduleController.text.trim().isEmpty
              ? null
              : _scheduleController.text.trim(),
          room: _roomController.text.trim().isEmpty
              ? null
              : _roomController.text.trim(),
          updatedAt: now,
        );
        await _repo.updateClass(updated);
        print('[ClassFormScreen] Updated class id=${updated.id}');
      } else {
        final cls = ClassModel(
          subjectId: _selectedSubject!.id!,
          section: _sectionController.text.trim(),
          schoolYear: _schoolYearController.text.trim(),
          semester: _semesterController.text.trim().isEmpty
              ? null
              : _semesterController.text.trim(),
          schedule: _scheduleController.text.trim().isEmpty
              ? null
              : _scheduleController.text.trim(),
          room: _roomController.text.trim().isEmpty
              ? null
              : _roomController.text.trim(),
          createdAt: now,
          updatedAt: now,
        );
        final id = await _repo.insertClass(cls);
        print('[ClassFormScreen] Inserted class id=$id');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('[ClassFormScreen] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            title: widget.classModel == null ? 'Add Class' : 'Edit Class',
            subtitle: 'Class Information',
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [
                  _card(
                    title: 'Subject',
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 360;
                          final dropdown = DropdownButtonFormField<Subject>(
                            initialValue: _selectedSubject,
                            hint: const Text('Select subject'),
                            isExpanded: true,
                            icon: Icon(PlatformIcons.dropdown),
                            decoration: InputDecoration(
                              prefixIcon: Icon(PlatformIcons.book),
                            ),
                            items: _subjects
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        '${s.code} - ${s.name}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) => _subjects
                                .map(
                                  (s) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${s.code} - ${s.name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedSubject = v),
                            validator: (_) =>
                                _selectedSubject == null ? 'Required' : null,
                          );

                          final addButton = IconButton.filled(
                            onPressed: _addSubject,
                            icon: Icon(PlatformIcons.add),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                            ),
                            tooltip: 'Add Subject',
                          );

                          if (isCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                dropdown,
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: addButton,
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: dropdown),
                              const SizedBox(width: 8),
                              addButton,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _card(
                    title: 'Class Information',
                    children: [
                      _label('Section *'),
                      TextFormField(
                        controller: _sectionController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Section A, BSIT-1A',
                          prefixIcon: Icon(PlatformIcons.group),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _label('School Year *'),
                      TextFormField(
                        controller: _schoolYearController,
                        decoration: InputDecoration(
                          hintText: 'e.g. 2024-2025',
                          prefixIcon: Icon(PlatformIcons.calendarToday),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _label('Semester'),
                      TextFormField(
                        controller: _semesterController,
                        decoration: InputDecoration(
                          hintText: 'e.g. 1st Semester',
                          prefixIcon: Icon(PlatformIcons.event),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label('Schedule'),
                      TextFormField(
                        controller: _scheduleController,
                        decoration: InputDecoration(
                          hintText: 'e.g. MWF 7:00-8:00 AM',
                          prefixIcon: Icon(PlatformIcons.schedule),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label('Room'),
                      TextFormField(
                        controller: _roomController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Room 201',
                          prefixIcon: Icon(PlatformIcons.room),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.classModel == null
                                ? 'Add Class'
                                : 'Save Changes',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    ),
  );
}

// Custom dialog widget that properly manages TextEditingController lifecycle
class _AddSubjectDialog extends StatefulWidget {
  final Function(int?) onSubjectAdded;

  const _AddSubjectDialog({required this.onSubjectAdded});

  @override
  State<_AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<_AddSubjectDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  final SubjectRepository _repo = SubjectRepository();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _addSubject() async {
    if (_nameController.text.trim().isEmpty ||
        _codeController.text.trim().isEmpty) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final subject = Subject(
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final id = await _repo.insertSubject(subject);
    widget.onSubjectAdded(id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Subject'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(labelText: 'Subject Code *'),
            onSubmitted: (_) => _addSubject(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Subject Name *'),
            onSubmitted: (_) => _addSubject(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _addSubject, child: const Text('Add')),
      ],
    );
  }
}
