import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/utils/icon_fix.dart';
import '../../core/widgets/wave_header.dart';
import '../../core/services/lesson_ai_service.dart';
import '../../data/models/lesson_model.dart';
import '../../data/repositories/lesson_repository.dart';

class LessonFormScreen extends StatefulWidget {
  final int classId;
  final Lesson? lesson;

  const LessonFormScreen({super.key, required this.classId, this.lesson});

  @override
  State<LessonFormScreen> createState() => _LessonFormScreenState();
}

class _LessonFormScreenState extends State<LessonFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = LessonRepository();

  late final TextEditingController _weekController;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _objectivesController;
  late final TextEditingController _referencesController;

  String? _pdfPath;
  String? _pdfFileName;
  bool _isSaving = false;
  bool _isProcessingPDF = false;
  bool get _isEditing => widget.lesson != null;

  late quill.QuillController _quillController;

  @override
  void initState() {
    super.initState();
    final l = widget.lesson;
    // If editing, use existing week number; if adding new, default to 1
    final initialWeek = l?.weekNumber ?? 1;
    _weekController = TextEditingController(text: initialWeek.toString());
    _titleController = TextEditingController(text: l?.title ?? '');
    _contentController = TextEditingController(text: l?.content ?? '');
    _objectivesController = TextEditingController(text: l?.objectives ?? '');
    _referencesController = TextEditingController(text: l?.references ?? '');
    // Initialize Quill document from stored JSON delta or plain text
    if (l?.content != null && l!.content!.isNotEmpty) {
      try {
        final data = jsonDecode(l.content!) as List<dynamic>;
        final doc = quill.Document.fromJson(data);
        _quillController = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {
        _quillController = quill.QuillController(
          document: quill.Document()..insert(0, l.content!),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } else {
      _quillController = quill.QuillController.basic();
    }

    _pdfPath = l?.pdfPath;
    if (_pdfPath != null) {
      _pdfFileName = _pdfPath!.split('/').last;
    }
  }

  @override
  void dispose() {
    _weekController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _objectivesController.dispose();
    _referencesController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<void> _pickPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        _showError('Could not access file path');
        return;
      }

      setState(() {
        _pdfPath = file.path;
        _pdfFileName = file.name;
      });

      print('[LessonFormScreen] PDF selected: $_pdfFileName');

      // Ask if user wants to process with AI
      if (mounted) {
        final process = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(PlatformIcons.autoAwesome, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text('AI Processing'),
              ],
            ),
            content: const Text(
              'Would you like to extract text from this PDF and generate lesson content with AI?',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Process with AI'),
              ),
            ],
          ),
        );

        if (process == true) {
          await _processWithAI();
        }
      }
    } catch (e) {
      print('[LessonFormScreen] Error picking PDF: $e');
      _showError('Error selecting PDF: $e');
    }
  }

  Future<void> _processWithAI() async {
    if (_pdfPath == null) return;

    setState(() => _isProcessingPDF = true);

    try {
      print('[LessonFormScreen] Processing PDF with AI...');

      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('AI is analyzing your file...'),
                    SizedBox(height: 8),
                    Text(
                      'This may take a moment',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Extract text from PDF
      final extractedText = await LessonAIService.extractTextFromLessonFile(
        _pdfPath!,
      );

      // Generate content with AI
      final result = await LessonAIService.generateLessonContent(
        pdfText: extractedText,
        lessonTitle: _titleController.text.isEmpty
            ? 'Lesson'
            : _titleController.text,
        weekNumber: int.tryParse(_weekController.text) ?? 1,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        setState(() {
          _contentController.text = result.content;
          _objectivesController.text = result.objectives;
          _referencesController.text = result.references;

          // Replace Quill document with AI-generated plain text
          _quillController = quill.QuillController(
            document: quill.Document()..insert(0, result.content),
            selection: const TextSelection.collapsed(offset: 0),
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI processing completed successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      print('[LessonFormScreen] Error processing PDF: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showError('Error processing PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessingPDF = false);
    }
  }

  Future<void> _save() async {
    print('[LessonFormScreen] _save() called');
    if (!_formKey.currentState!.validate()) {
      print('[LessonFormScreen] Form validation failed');
      return;
    }

    print('[LessonFormScreen] Form validation passed, starting save...');
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now().toIso8601String();
      final weekNumber = int.parse(_weekController.text);
      print(
        '[LessonFormScreen] Week number: $weekNumber, Title: ${_titleController.text}',
      );

      // Serialize Quill document to JSON for storage
      final deltaJson = _quillController.document.toDelta().toJson();
      final contentJson = jsonEncode(deltaJson);

      if (_isEditing) {
        final updated = widget.lesson!.copyWith(
          weekNumber: weekNumber,
          title: _titleController.text.trim(),
          pdfPath: _pdfPath,
          content: contentJson,
          objectives: _objectivesController.text.trim(),
          references: _referencesController.text.trim(),
          updatedAt: now,
        );
        await _repo.updateLesson(updated);
        print('[LessonFormScreen] Updated lesson id=${updated.id}');
      } else {
        final lesson = Lesson(
          classId: widget.classId,
          weekNumber: weekNumber,
          title: _titleController.text.trim(),
          pdfPath: _pdfPath,
          content: contentJson,
          objectives: _objectivesController.text.trim(),
          references: _referencesController.text.trim(),
          createdAt: now,
          updatedAt: now,
        );
        final id = await _repo.insertLesson(lesson);
        print('[LessonFormScreen] Inserted lesson id=$id');
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('[LessonFormScreen] Error saving: $e');
      _showError('Error saving lesson: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
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
            title: _isEditing ? 'Edit Lesson' : 'Add Lesson',
            subtitle: 'Weekly Class Lesson',
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
                  _buildCard(
                    title: 'Basic Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _weekController,
                              decoration: InputDecoration(
                                labelText: 'Week Number *',
                                hintText: 'e.g. 1 (Week 1)',
                                prefixIcon: Icon(PlatformIcons.calendarToday),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                if (int.tryParse(v) == null) {
                                  return 'Must be a number';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Lesson Title *',
                          prefixIcon: Icon(PlatformIcons.title),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCard(
                    title: 'Lesson File Upload',
                    children: [
                      if (_pdfFileName != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                PlatformIcons.description,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _pdfFileName!,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: _isProcessingPDF
                                    ? null
                                    : () => setState(() {
                                        _pdfPath = null;
                                        _pdfFileName = null;
                                      }),
                                icon: Icon(PlatformIcons.close, size: 20),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessingPDF ? null : _pickPDF,
                          icon: Icon(PlatformIcons.uploadFile),
                          label: Text(
                            _pdfFileName == null
                                ? 'Upload PDF or Word (.docx)'
                                : 'Change File',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCard(
                    title: 'Lesson Content',
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE0E4EE)),
                          color: Colors.white,
                        ),
                        child: IconTheme(
                          data: Theme.of(context).iconTheme,
                          child: Column(
                            children: [
                              IconFix.fixIcon(
                                quill.QuillSimpleToolbar(
                                  controller: _quillController,
                                  config: const quill.QuillSimpleToolbarConfig(
                                    multiRowsDisplay: false,
                                    showCodeBlock: false,
                                    showQuote: false,
                                    showInlineCode: false,
                                    showRedo: false,
                                    showUndo: false,
                                    showFontFamily: false,
                                    showFontSize: false,
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              SizedBox(
                                height: 220,
                                child: quill.QuillEditor.basic(
                                  controller: _quillController,
                                  config: const quill.QuillEditorConfig(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCard(
                    title: 'Learning Objectives (ABCD Format)',
                    children: [
                      TextFormField(
                        controller: _objectivesController,
                        decoration: const InputDecoration(
                          labelText: 'Objectives',
                          hintText:
                              'AI will generate ABCD objectives or enter manually',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        minLines: 4,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCard(
                    title: 'References',
                    children: [
                      TextFormField(
                        controller: _referencesController,
                        decoration: const InputDecoration(
                          labelText: 'References',
                          hintText:
                              'AI will extract references or enter manually',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 6,
                        minLines: 3,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving ? null : _save,
        backgroundColor: themeProvider.primaryColor,
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(PlatformIcons.save, color: Colors.white),
      ),
    );
  }

  Widget _buildCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF4)),
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
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
