import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/grading_category_model.dart';
import '../../data/models/grading_assessment_model.dart';
import '../../data/models/assessment_score_model.dart';
import '../../data/models/grade_model.dart';
import '../../data/models/grading_system_config.dart';
import '../../data/models/grade_equivalency.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/database/database_helper.dart';
import '../home/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: detect exam categories by name
// ─────────────────────────────────────────────────────────────────────────────

bool _isExamCategory(GradingCategory c) {
  final n = c.name.trim().toLowerCase();
  return n == 'examination' ||
      n == 'exam' ||
      n.startsWith('exam') ||
      n.contains('examination');
}

// ─────────────────────────────────────────────────────────────────────────────
//  Color palette (shared with app design system)
// ─────────────────────────────────────────────────────────────────────────────

const _kHeaderBg = Color(0xFF1A237E);
const _kAccentBlue = Color(0xFF5B8AF5);
const _kAccentGreen = Color(0xFF00C897);
const _kAccentRed = Color(0xFFFF5C72);
const _kRowAlt = Color(0xFFF8FAFF);
const _kDivider = Color(0xFFEEF1F6);
const _kHeaderRow = Color(0xFFF0F4FF);
const _kExamBg = Color(0xFFFFF8F0); // warm tint for exam columns
const _kExamAccent = Color(0xFFFF8A65); // orange accent for exam category

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class StudentRecordsScreen extends StatefulWidget {
  final ClassModel classModel;

  const StudentRecordsScreen({super.key, required this.classModel});

  @override
  State<StudentRecordsScreen> createState() => _StudentRecordsScreenState();
}

class _StudentRecordsScreenState extends State<StudentRecordsScreen>
    with SingleTickerProviderStateMixin {
  final _gradingRepo = GradingRepository();
  final _studentRepo = StudentRepository();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  bool _isLoading = true;
  bool _isExporting = false;

  List<GradingCategory> _categories = [];
  List<Student> _students = [];
  Map<int, List<GradingAssessment>> _assessmentsByCategory = {};
  Map<String, AssessmentScore> _scores = {};
  Map<int, double> _finalGrades = {};
  Map<int, double?> _finalEquivalentGrades = {};
  Map<int, String?> _finalRemarks = {};
  GradingSystemConfig _gradingSystem = GradingSystemConfig.percentage100;

  int? _draggedCategoryIndex;
  bool _isDragging = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Partition helpers ──────────────────────────────────────────────────────

  /// Non-exam categories (rendered first)
  List<GradingCategory> get _regularCategories =>
      _categories.where((c) => !_isExamCategory(c)).toList();

  /// Exam categories (rendered just before Period Grade)
  List<GradingCategory> get _examCategories =>
      _categories.where(_isExamCategory).toList();

  bool get _isCollege =>
      _gradingSystem.type == GradingSystemType.college1to5 ||
      _gradingSystem.type == GradingSystemType.college4point0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Export helpers (logic unchanged) ───────────────────────────────────────

  String _safeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]+'), '').trim();
    return cleaned.isEmpty ? 'export' : cleaned.replaceAll(' ', '_');
  }

  PdfGrid _buildPdfGrid(
    List<String> headers,
    List<List<String>> rows,
    PdfFont bodyFont,
  ) {
    final grid = PdfGrid();
    grid.columns.add(count: headers.length);

    // Calculate dynamic column widths for 8x13 inch landscape paper
    // 13 inches = 936 points total width
    final totalColumns = headers.length;
    final nameColumnWidth = 200.0; // Fixed width for student name column
    final remainingWidth =
        936.0 - nameColumnWidth; // 13x8 landscape width minus name column
    final otherColumnWidth =
        remainingWidth / (totalColumns - 1); // Distribute remaining width

    for (var i = 0; i < headers.length; i++) {
      grid.columns[i].width = i == 0 ? nameColumnWidth : otherColumnWidth;
    }

    final headerRow = grid.headers.add(1)[0];
    for (var i = 0; i < headers.length; i++) {
      headerRow.cells[i].value = headers[i].replaceAll('\n', ' ');
      headerRow.cells[i].stringFormat = PdfStringFormat(
        alignment: i == 0 ? PdfTextAlignment.left : PdfTextAlignment.center,
        lineAlignment: PdfVerticalAlignment.middle,
      );
    }
    headerRow.style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(235, 238, 245)),
      textBrush: PdfBrushes.black,
      font: PdfStandardFont(
        PdfFontFamily.helvetica,
        8,
        style: PdfFontStyle.bold,
      ),
    );
    for (var r = 0; r < rows.length; r++) {
      final dataRow = grid.rows.add();
      final row = rows[r];
      for (var i = 0; i < headers.length; i++) {
        dataRow.cells[i].value = i < row.length ? row[i] : '';
        dataRow.cells[i].stringFormat = PdfStringFormat(
          alignment: i == 0 ? PdfTextAlignment.left : PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        );
      }
      if (r.isOdd) {
        dataRow.style = PdfGridRowStyle(
          backgroundBrush: PdfSolidBrush(PdfColor(250, 250, 250)),
          textBrush: PdfBrushes.black,
          font: bodyFont,
        );
      }
    }
    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 4, right: 4, top: 3, bottom: 3),
      font: bodyFont,
    );
    grid.applyBuiltInStyle(PdfGridBuiltInStyle.gridTable4);
    return grid;
  }

  Future<Map<String, String>> _loadHeaderDetails() async {
    final db = DatabaseHelper.instance;
    final teacherName = (await db.getSetting('teacher_name') ?? '').trim();
    final schoolName = (await db.getSetting('school_name') ?? '').trim();
    return {
      'teacher_name': teacherName,
      'school_name': schoolName,
      'subject_name': widget.classModel.subject?.name ?? '',
      'subject_code': widget.classModel.subject?.code ?? '',
      'subject_description': widget.classModel.subject?.description ?? '',
      'section': widget.classModel.section,
      'school_year': widget.classModel.schoolYear,
      'schedule': widget.classModel.schedule ?? '',
      'room': widget.classModel.room ?? '',
    };
  }

  /// Build export table with exam columns placed just before Period Grade.
  ({List<String> headers, List<List<String>> rows, bool isCollege})
  _buildExportTable() {
    final regular = _regularCategories;
    final exams = _examCategories;

    final headers = <String>['Student Name'];

    // Regular categories first - only show Total and Weighted columns
    for (final cat in regular) {
      final assessments = _assessmentsByCategory[cat.id!] ?? [];
      if (assessments.isNotEmpty) {
        headers.add('${cat.name} Total');
        headers.add('${cat.name} Weighted');
      }
    }

    // Exam categories second (just before Period Grade) - only show Total and Weighted columns
    for (final cat in exams) {
      final assessments = _assessmentsByCategory[cat.id!] ?? [];
      if (assessments.isNotEmpty) {
        headers.add('${cat.name} Total');
        headers.add('${cat.name} Weighted');
      }
    }

    headers.add('Period Grade');
    headers.add(_isCollege ? 'Final Grade (Eq.)' : 'Final Grade');
    if (_isCollege) headers.add('Remarks');

    final rows = <List<String>>[];
    for (final s in _students) {
      final row = <String>[s.fullName];

      void appendCategoryColumns(GradingCategory cat) {
        final assessments = _assessmentsByCategory[cat.id!] ?? [];
        if (assessments.isNotEmpty) {
          double total = 0, maxTotal = 0;
          for (final a in assessments) {
            final v = _scores['${a.id}_${s.id!}']?.score;
            if (v != null) total += v;
            maxTotal += a.maxScore;
          }

          // Add Category Total
          final pct = maxTotal > 0
              ? '${((total / maxTotal) * 100).toStringAsFixed(1)}%'
              : '-';
          row.add(pct);

          // Add Category Weighted
          final weighted = maxTotal > 0
              ? ((total / maxTotal) * 100 * (cat.weight / 100)).toStringAsFixed(
                  1,
                )
              : '-';
          row.add(weighted);
        }
      }

      for (final cat in regular) {
        appendCategoryColumns(cat);
      }
      for (final cat in exams) {
        appendCategoryColumns(cat);
      }

      row.add(_computePeriodGrade(s.id!).toStringAsFixed(2));

      if (_isCollege) {
        row.add((_finalEquivalentGrades[s.id!])?.toStringAsFixed(2) ?? '-');
        row.add(_finalRemarks[s.id!] ?? '-');
      } else {
        row.add((_finalGrades[s.id!])?.toStringAsFixed(2) ?? '0.00');
      }

      rows.add(row);
    }

    return (headers: headers, rows: rows, isCollege: _isCollege);
  }

  Future<void> _exportPdf() async {
    if (_isLoading || _students.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);
      const margin = 20.0;
      final smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8);
      final doc = PdfDocument();

      // Create custom 8x13 inch landscape page
      // 8 inches = 576 points, 13 inches = 936 points
      // Landscape: width = 936, height = 576
      final page = doc.pages.add();
      final g = page.graphics;
      final w = page.getClientSize().width;
      final contentW = w - (margin * 2);
      final h = page.getClientSize().height;

      double y = margin;
      g.drawString(
        'STUDENT RECORDS',
        PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold),
        bounds: Rect.fromLTWH(margin, y, contentW, 30),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      y += 35;
      if ((header['school_name'] ?? '').trim().isNotEmpty) {
        g.drawString(
          header['school_name']!,
          PdfStandardFont(
            PdfFontFamily.helvetica,
            14,
            style: PdfFontStyle.bold,
          ),
          bounds: Rect.fromLTWH(margin, y, contentW, 22),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        y += 22;
      }
      final labelFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        9,
        style: PdfFontStyle.bold,
      );
      final valueFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
      const blockPadding = 10.0, lineH = 12.0;
      final blockPairs = <({String k, String v})>[
        (k: 'Teacher', v: header['teacher_name'] ?? ''),
        (
          k: 'Subject',
          v: '${(header['subject_code'] ?? '').trim()} ${(header['subject_name'] ?? '').trim()}'
              .trim(),
        ),
        (k: 'Description', v: header['subject_description'] ?? ''),
        (k: 'Section', v: header['section'] ?? ''),
        (k: 'School Year', v: header['school_year'] ?? ''),
        (k: 'Schedule', v: header['schedule'] ?? ''),
        (k: 'Room', v: header['room'] ?? ''),
        (k: 'Date Generated', v: dateLabel),
      ].where((p) => p.v.trim().isNotEmpty).toList();
      final blockTop = y + 8;
      final blockH =
          (blockPairs.isEmpty ? 0.0 : blockPairs.length * lineH) +
          blockPadding * 2;
      if (blockH > 0) {
        g.drawRectangle(
          pen: PdfPens.lightGray,
          brush: PdfSolidBrush(PdfColor(250, 250, 250)),
          bounds: Rect.fromLTWH(margin, blockTop, contentW, blockH),
        );
        double yy = blockTop + blockPadding;
        for (final p in blockPairs) {
          g.drawString(
            '${p.k}: ',
            labelFont,
            bounds: Rect.fromLTWH(margin + 10, yy, 100, lineH),
          );
          g.drawString(
            p.v,
            valueFont,
            bounds: Rect.fromLTWH(margin + 110, yy, contentW - 120, lineH),
          );
          yy += lineH;
        }
        y = blockTop + blockH + 12;
      }

      // Calculate remaining space for table
      final remainingHeight = h - y - margin;

      final export = _buildExportTable();
      final grid = _buildPdfGrid(export.headers, export.rows, smallFont);
      grid.draw(
        page: page,
        bounds: Rect.fromLTWH(margin, y, contentW, remainingHeight),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      final bytes = doc.saveSync();
      doc.dispose();
      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/student_records_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Student Records Report');
    } catch (e) {
      _snack('Export PDF failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_isLoading || _students.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);
      final export = _buildExportTable();
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Student Records';
      sheet.showGridlines = false;
      final titleStyle = workbook.styles.add('titleStyle');
      titleStyle.bold = true;
      titleStyle.fontSize = 18;
      titleStyle.hAlign = xlsio.HAlignType.center;
      final labelStyle = workbook.styles.add('labelStyle');
      labelStyle.bold = true;
      labelStyle.fontSize = 10;
      labelStyle.hAlign = xlsio.HAlignType.left;
      final valueStyle = workbook.styles.add('valueStyle');
      valueStyle.fontSize = 10;
      valueStyle.hAlign = xlsio.HAlignType.left;
      final thStyle = workbook.styles.add('thStyle');
      thStyle.bold = true;
      thStyle.fontSize = 10;
      thStyle.backColor = '#EBEEF5';
      thStyle.hAlign = xlsio.HAlignType.center;
      thStyle.vAlign = xlsio.VAlignType.center;
      final cellStyle = workbook.styles.add('cellStyle');
      cellStyle.fontSize = 10;
      cellStyle.hAlign = xlsio.HAlignType.center;
      cellStyle.vAlign = xlsio.VAlignType.center;
      final nameStyle = workbook.styles.add('nameStyle');
      nameStyle.fontSize = 10;
      nameStyle.hAlign = xlsio.HAlignType.left;
      nameStyle.vAlign = xlsio.VAlignType.center;
      final lastCol = export.headers.length;
      final titleRange = sheet.getRangeByIndex(1, 1, 1, lastCol);
      titleRange.merge();
      titleRange.setText('STUDENT RECORDS');
      titleRange.cellStyle = titleStyle;
      sheet.getRangeByIndex(1, 1).rowHeight = 26;
      int row = 3;
      void writePair(String lbl, String val) {
        if (val.trim().isEmpty) return;
        sheet.getRangeByIndex(row, 1).setText(lbl);
        sheet.getRangeByIndex(row, 1).cellStyle = labelStyle;
        final r = sheet.getRangeByIndex(row, 2, row, lastCol);
        r.merge();
        r.setText(val);
        r.cellStyle = valueStyle;
        row++;
      }

      writePair('School', header['school_name'] ?? '');
      writePair('Teacher', header['teacher_name'] ?? '');
      writePair(
        'Subject',
        '${(header['subject_code'] ?? '').trim()} ${(header['subject_name'] ?? '').trim()}'
            .trim(),
      );
      writePair('Description', header['subject_description'] ?? '');
      writePair('Section', header['section'] ?? '');
      writePair('School Year', header['school_year'] ?? '');
      writePair('Schedule', header['schedule'] ?? '');
      writePair('Room', header['room'] ?? '');
      writePair('Date Generated', dateLabel);
      row++;
      final tableStartRow = row;
      for (var c = 0; c < export.headers.length; c++) {
        final cell = sheet.getRangeByIndex(row, 1 + c);
        cell.setText(export.headers[c].replaceAll('\n', ' '));
        cell.cellStyle = thStyle;
      }
      sheet.getRangeByIndex(row, 1).rowHeight = 20;
      row++;
      for (final rData in export.rows) {
        for (var c = 0; c < export.headers.length; c++) {
          final cell = sheet.getRangeByIndex(row, 1 + c);
          cell.setText(c < rData.length ? rData[c] : '');
          cell.cellStyle = c == 0 ? nameStyle : cellStyle;
        }
        row++;
      }
      final tableEndRow = row - 1;
      final tableRange = sheet.getRangeByIndex(
        tableStartRow,
        1,
        tableEndRow,
        export.headers.length,
      );
      tableRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      tableRange.cellStyle.borders.all.color = '#D0D6E5';
      for (var r = tableStartRow + 1; r <= tableEndRow; r++) {
        if ((r - tableStartRow).isOdd) {
          sheet
                  .getRangeByIndex(r, 1, r, export.headers.length)
                  .cellStyle
                  .backColor =
              '#FAFAFA';
        }
      }
      sheet.setColumnWidthInPixels(1, 220);
      for (var c = 2; c <= export.headers.length; c++) {
        sheet.setColumnWidthInPixels(c, 90);
      }
      final bytes = workbook.saveAsStream();
      workbook.dispose();
      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/student_records_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Student Records Report');
    } catch (e) {
      _snack('Export Excel failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _kAccentRed : _kHeaderBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Load data ──────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    _fadeCtrl.reset();
    try {
      final db = DatabaseHelper.instance;
      final gsJson = await db.getSetting('grading_system');
      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      if (gsJson != null && gsJson.isNotEmpty) {
        try {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gsJson) as Map<String, dynamic>,
          );
        } catch (e) {
          print('[StudentRecordsScreen] Error parsing grading system: $e');
        }
      }
      final eqJsonRaw = await db.getSetting('grade_equivalency_table');
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      if (eqJsonRaw != null && eqJsonRaw.isNotEmpty) {
        try {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJsonRaw) as Map<String, dynamic>,
          );
        } catch (e) {
          print('[StudentRecordsScreen] Error parsing equivalency table: $e');
        }
      }
      if (eqTable.isNotEmpty) {
        final filtered = eqTable.equivalencies
            .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
            .toList();
        eqTable = eqTable.copyWith(equivalencies: filtered);
      }
      if (eqTable.isEmpty) {
        if (gradingSystem.type == GradingSystemType.college4point0) {
          eqTable = GradeEquivalencyTable.depedTo4point0;
        } else if (gradingSystem.type == GradingSystemType.college1to5) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
        }
      }
      final periods = await _gradingRepo.getPeriodsByClass(
        widget.classModel.id!,
      );
      final activePeriod = periods.firstWhere(
        (p) => p.isActive,
        orElse: () => periods.isNotEmpty
            ? periods.first
            : GradingPeriod(
                classId: widget.classModel.id!,
                name: 'No Period',
                orderNum: 0,
                isActive: false,
                isLocked: false,
                createdAt: DateTime.now().toIso8601String(),
                updatedAt: DateTime.now().toIso8601String(),
              ),
      );
      final students = await _studentRepo.getStudentsByClass(
        widget.classModel.id!,
      );
      students.sort((a, b) => a.fullName.compareTo(b.fullName));

      List<GradingCategory> categories = [];
      Map<int, List<GradingAssessment>> assessmentsByCategory = {};
      Map<String, AssessmentScore> scores = {};
      Map<int, double> finalGrades = {};
      Map<int, double?> finalEqGrades = {};
      Map<int, String?> finalRemarks = {};

      for (final student in students) {
        final fg = await _gradingRepo.computeCumulativeGrade(
          studentId: student.id!,
          classId: widget.classModel.id!,
        );
        finalGrades[student.id!] = fg;
        final isC =
            gradingSystem.type == GradingSystemType.college1to5 ||
            gradingSystem.type == GradingSystemType.college4point0;
        if (isC) {
          finalEqGrades[student.id!] = eqTable.convertPercentageToNumerical(fg);
          finalRemarks[student.id!] = eqTable.getDescriptor(fg);
        }
      }

      if (activePeriod.id != null) {
        categories = await _gradingRepo.getCategoriesByPeriod(activePeriod.id!);
        categories.sort((a, b) => a.name.compareTo(b.name));
        for (final category in categories) {
          final assessments = await _gradingRepo.getAssessments(
            classId: widget.classModel.id!,
            periodId: activePeriod.id!,
            categoryId: category.id!,
          );
          assessments.sort((a, b) => a.orderNum.compareTo(b.orderNum));
          assessmentsByCategory[category.id!] = assessments;
          for (final assessment in assessments) {
            final ss = await _gradingRepo.getScoresByAssessment(assessment.id!);
            for (final score in ss) {
              scores['${assessment.id}_${score.studentId}'] = score;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _students = students;
          _assessmentsByCategory = assessmentsByCategory;
          _scores = scores;
          _finalGrades = finalGrades;
          _finalEquivalentGrades = finalEqGrades;
          _finalRemarks = finalRemarks;
          _gradingSystem = gradingSystem;
          _isLoading = false;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      print('[StudentRecordsScreen] Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Grade helpers ──────────────────────────────────────────────────────────

  /// Returns the weighted-average contribution of a single category for a student.
  /// Formula: (sum of scores / sum of max scores) * 100 * (category.weight / 100)
  double _computeCategoryWeightedGrade(int studentId, GradingCategory cat) {
    final assessments = _assessmentsByCategory[cat.id!] ?? [];
    if (assessments.isEmpty) return 0;
    double total = 0, maxTotal = 0;
    for (final a in assessments) {
      total += _scores['${a.id}_$studentId']?.score ?? 0;
      maxTotal += a.maxScore;
    }
    return maxTotal > 0 ? (total / maxTotal) * 100 * (cat.weight / 100) : 0;
  }

  /// Period Grade Formula (Teacher):
  ///   100 - ((5/8) * (100 - SUM(U, X)))
  ///
  /// Where (Excel mapping):
  ///   U = SUM of all category weighted contributions aside from Exam
  ///   X = AVERAGE of Exam category weighted contributions
  ///
  /// Behavior:
  /// - If U or X is missing/blank -> return 0
  /// - Round to 0 decimals
  /// - Minimum grade 70
  /// - Clamp 0..100
  double _computePeriodGrade(int studentId) {
    final double uNonExam = _regularCategories.fold(0.0, (sum, cat) {
      return sum + _computeCategoryWeightedGrade(studentId, cat);
    });

    final examWeightedList = _examCategories
        .map((cat) => _computeCategoryWeightedGrade(studentId, cat))
        .where((v) => v > 0)
        .toList();
    final double xExamAvg = examWeightedList.isEmpty
        ? 0.0
        : (examWeightedList.reduce((a, b) => a + b) / examWeightedList.length);

    if (uNonExam <= 0 || xExamAvg <= 0) {
      print(
        '[StudentRecords] Period grade: missing U/X (U=$uNonExam, X=$xExamAvg) for studentId=$studentId',
      );
      return 0.0;
    }

    final double sumUx = uNonExam + xExamAvg;
    final double raw = 100 - ((5 / 8) * (100 - sumUx));
    final double rounded = raw.roundToDouble();
    final double minApplied = rounded > 70 ? rounded : 70.0;
    final double clamped = minApplied.clamp(0.0, 100.0).toDouble();

    print(
      '[StudentRecords] Period grade formula studentId=$studentId U=$uNonExam X=$xExamAvg SUM=$sumUx raw=$raw rounded=$rounded final=$clamped',
    );

    return clamped;
  }

  bool _isFailedGrade(Student student) {
    final finalPct = _finalGrades[student.id!];
    if (finalPct == null) return false;
    final passing = _gradingSystem.passingScore;
    final failed = finalPct < passing;
    print(
      '[StudentRecords] Failed check studentId=${student.id} final=$finalPct passing=$passing -> $failed',
    );
    return failed;
  }

  // ── Drag helpers ───────────────────────────────────────────────────────────

  void _onCategoryDragStart(int index) => setState(() {
    _draggedCategoryIndex = index;
    _isDragging = true;
  });

  void _onCategoryDragEnd() => setState(() {
    _draggedCategoryIndex = null;
    _isDragging = false;
  });

  void _onCategoryDragAccept(int targetIndex) {
    if (_draggedCategoryIndex != null && _draggedCategoryIndex != targetIndex) {
      setState(() {
        final dragged = _categories[_draggedCategoryIndex!];
        _categories.removeAt(_draggedCategoryIndex!);
        _categories.insert(targetIndex, dragged);
      });
    }
    _onCategoryDragEnd();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          WaveHeader(
            title: 'Student Records',
            subtitle: widget.classModel.displayName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _isExporting ? () {} : _showExportSheet,
                icon: _isExporting
                    ? Icon(PlatformIcons.watchLater, color: Colors.white)
                    : Icon(PlatformIcons.iosShare, color: Colors.white),
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? _RecordsShimmer()
                : _students.isEmpty
                ? _EmptyState(
                    icon: PlatformIcons.groupOff,
                    message: 'No students enrolled.',
                  )
                : _categories.isEmpty
                ? _EmptyState(
                    icon: PlatformIcons.category,
                    message:
                        'No grade categories configured.\nSet up categories in Grading Periods.',
                  )
                : FadeTransition(opacity: _fadeAnim, child: _buildTableView()),
          ),
        ],
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

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportSheet(
        onPdf: () {
          Navigator.pop(context);
          _exportPdf();
        },
        onExcel: () {
          Navigator.pop(context);
          _exportExcel();
        },
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  TABLE VIEW
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildTableView() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _kHeaderBg.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTableHeader(),
                  Container(height: 2, color: _kDivider),
                  ..._students.asMap().entries.map(
                    (e) => _buildStudentRow(e.value, e.key),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── TABLE HEADER ────────────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    final regular = _regularCategories;
    final exams = _examCategories;

    return Container(
      color: _kHeaderRow,
      child: IntrinsicHeight(
        child: Row(
          children: [
            // ── Student Name ────────────────────────────────────────────────
            _HeaderCell(
              width: 200,
              child: Row(
                children: [
                  Icon(PlatformIcons.person, size: 13, color: _kAccentBlue),
                  SizedBox(width: 6),
                  Text(
                    'Student Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: _kHeaderBg,
                    ),
                  ),
                ],
              ),
            ),

            // ── Regular categories ──────────────────────────────────────────
            ..._buildCategoryHeaderCells(regular, isExam: false),

            // ── Exam categories (just before Period Grade) ──────────────────
            if (exams.isNotEmpty) ...[
              _buildExamSeparator(),
              ..._buildCategoryHeaderCells(exams, isExam: true),
            ],

            // ── Period Grade ────────────────────────────────────────────────
            _HeaderCell(
              width: 100,
              bg: _kAccentBlue.withValues(alpha: 0.10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PlatformIcons.calculate, size: 13, color: _kAccentBlue),
                  SizedBox(height: 3),
                  Text(
                    'Period\nGrade',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: _kAccentBlue,
                    ),
                  ),
                ],
              ),
            ),

            // ── Final Grade ─────────────────────────────────────────────────
            _HeaderCell(
              width: 120,
              bg: _kAccentGreen.withValues(alpha: 0.10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PlatformIcons.workspacePremium,
                    size: 13,
                    color: _kAccentGreen,
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Grade',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: _kAccentGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isCollege ? '(Equiv.)' : '(All Periods)',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _kAccentGreen.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),

            // ── Remarks (college only) ──────────────────────────────────────
            if (_isCollege)
              _HeaderCell(
                width: 160,
                child: const Text(
                  'Remarks',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: _kAccentGreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Thin vertical separator before exam columns
  Widget _buildExamSeparator() => Container(
    width: 3,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_kExamAccent.withValues(alpha: 0.7), _kExamAccent],
      ),
    ),
  );

  /// Build header cells for a list of categories.
  /// [isExam] controls the visual accent (orange tint vs blue tint).
  List<Widget> _buildCategoryHeaderCells(
    List<GradingCategory> cats, {
    required bool isExam,
  }) {
    final cells = <Widget>[];
    for (var ci = 0; ci < cats.length; ci++) {
      final category = cats[ci];
      final assessments = _assessmentsByCategory[category.id!] ?? [];
      final isDragged =
          _isDragging && _draggedCategoryIndex == _categories.indexOf(category);
      final accent = isExam ? _kExamAccent : _kAccentBlue;

      if (assessments.isNotEmpty) {
        // Category Total column (drag-drop enabled)
        cells.add(
          LongPressDraggable<int>(
            data: _categories.indexOf(category),
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: 110,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PlatformIcons.dragHandle,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Container(
              width: 100,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            onDragStarted: () =>
                _onCategoryDragStart(_categories.indexOf(category)),
            onDragEnd: (_) => _onCategoryDragEnd(),
            child: DragTarget<int>(
              builder: (context, candidates, _) => _HeaderCell(
                width: 100,
                bg: isExam
                    ? _kExamBg
                    : (candidates.isNotEmpty
                          ? _kAccentGreen.withValues(alpha: 0.08)
                          : null),
                dragged: isDragged,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PlatformIcons.dragHandle,
                          size: 11,
                          color: accent.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isExam
                          ? '${category.name}\nTotal'
                          : '${category.name}\nTotal',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: isExam ? _kExamAccent : _kAccentBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${category.weight.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9AA3B0),
                      ),
                    ),
                  ],
                ),
              ),
              onAcceptWithDetails: (details) =>
                  _onCategoryDragAccept(_categories.indexOf(category)),
            ),
          ),
        );

        // Category Weighted column
        cells.add(
          DragTarget<int>(
            builder: (context, candidates, _) => _HeaderCell(
              width: 100,
              bg: isExam
                  ? _kExamBg.withValues(alpha: 0.8)
                  : _kAccentGreen.withValues(alpha: 0.07),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${category.name}\nContrib.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: _kAccentGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.weight.toStringAsFixed(0)}% wt',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9AA3B0),
                    ),
                  ),
                ],
              ),
            ),
            onAcceptWithDetails: (details) =>
                _onCategoryDragAccept(_categories.indexOf(category)),
          ),
        );
      }
    }
    return cells;
  }

  // ── STUDENT ROW ─────────────────────────────────────────────────────────────

  Widget _buildStudentRow(Student student, int rowIndex) {
    final regular = _regularCategories;
    final exams = _examCategories;
    final failed = _isFailedGrade(student);
    final isAlt = rowIndex.isOdd;

    return Container(
      decoration: BoxDecoration(
        color: isAlt ? _kRowAlt : Colors.white,
        border: const Border(bottom: BorderSide(color: _kDivider)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // ── Name ────────────────────────────────────────────────────────
            _DataCell(
              width: 200,
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _kAccentBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        student.fullName.isNotEmpty
                            ? student.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: _kAccentBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      student.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _kHeaderBg,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Regular category data ────────────────────────────────────────
            ..._buildCategoryDataCells(student, regular, isExam: false),

            // ── Exam separator + exam data ───────────────────────────────────
            if (exams.isNotEmpty) ...[
              Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _kExamAccent.withValues(alpha: 0.4),
                      _kExamAccent.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
              ..._buildCategoryDataCells(student, exams, isExam: true),
            ],

            // ── Period Grade ────────────────────────────────────────────────
            _DataCell(
              width: 100,
              bg: _kAccentBlue.withValues(alpha: 0.07),
              child: Text(
                _computePeriodGrade(student.id!).toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _kAccentBlue,
                ),
              ),
            ),

            // ── Final Grade ─────────────────────────────────────────────────
            _DataCell(
              width: 120,
              bg: failed
                  ? _kAccentRed.withValues(alpha: 0.10)
                  : _kAccentGreen.withValues(alpha: 0.10),
              child: Text(
                _isCollege
                    ? (_finalEquivalentGrades[student.id!]?.toStringAsFixed(
                            2,
                          ) ??
                          '-')
                    : (_finalGrades[student.id!]?.toStringAsFixed(2) ?? '0.00'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: failed ? _kAccentRed : _kAccentGreen,
                ),
              ),
            ),

            // ── Remarks ─────────────────────────────────────────────────────
            if (_isCollege)
              _DataCell(
                width: 160,
                child: Text(
                  _finalRemarks[student.id!] ?? '-',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFF2E3A5C),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the score + total + weighted data cells for a list of categories.
  List<Widget> _buildCategoryDataCells(
    Student student,
    List<GradingCategory> cats, {
    required bool isExam,
  }) {
    final cells = <Widget>[];
    for (final category in cats) {
      final assessments = _assessmentsByCategory[category.id!] ?? [];
      double catTotal = 0, catMax = 0;

      if (assessments.isNotEmpty) {
        // Calculate totals without showing individual scores
        for (final assessment in assessments) {
          final score = _scores['${assessment.id}_${student.id!}'];
          final v = score?.score ?? 0;
          catTotal += v;
          catMax += assessment.maxScore;
        }

        // Category Total
        cells.add(
          _DataCell(
            width: 100,
            bg: isExam ? _kExamBg : const Color(0xFFF8FAFF),
            rightBorderWidth: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  catMax > 0
                      ? '${((catTotal / catMax) * 100).toStringAsFixed(1)}%'
                      : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: isExam ? _kExamAccent : _kAccentBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${catTotal.toStringAsFixed(1)}/${catMax.toStringAsFixed(0)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                    color: Color(0xFF9AA3B0),
                  ),
                ),
              ],
            ),
          ),
        );

        // Category Weighted
        final weighted = _computeCategoryWeightedGrade(student.id!, category);
        cells.add(
          _DataCell(
            width: 100,
            bg: isExam
                ? _kExamBg.withValues(alpha: 0.7)
                : const Color(0xFFF0FFF8),
            rightBorderWidth: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weighted > 0 ? weighted.toStringAsFixed(1) : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: isExam ? _kExamAccent : _kAccentGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${category.weight.toStringAsFixed(0)}% wt',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                    color: Color(0xFF9AA3B0),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return cells;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable cell widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  final double width;
  final Widget child;
  final Color? bg;
  final bool dragged;

  const _HeaderCell({
    required this.width,
    required this.child,
    this.bg,
    this.dragged = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: dragged
          ? _kAccentBlue.withValues(alpha: 0.12)
          : (bg ?? _kHeaderRow),
      border: Border(right: const BorderSide(color: _kDivider, width: 1)),
    ),
    child: child,
  );
}

class _DataCell extends StatelessWidget {
  final double width;
  final Widget child;
  final Color? bg;
  final double rightBorderWidth;

  const _DataCell({
    required this.width,
    required this.child,
    this.bg,
    this.rightBorderWidth = 1,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: bg,
      border: Border(
        right: BorderSide(color: _kDivider, width: rightBorderWidth),
      ),
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Export Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ExportSheet extends StatelessWidget {
  final VoidCallback onPdf;
  final VoidCallback onExcel;
  const _ExportSheet({required this.onPdf, required this.onExcel});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.of(context).padding.bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF1F6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kAccentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                PlatformIcons.iosShare,
                color: _kAccentBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export Report',
                  style: TextStyle(
                    color: _kHeaderBg,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Choose export format',
                  style: TextStyle(
                    color: Color(0xFF9AA3B0),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: const Color(0xFFEEF1F6)),
        const SizedBox(height: 14),
        _ExportOption(
          icon: PlatformIcons.pictureAsPdf,
          color: _kAccentRed,
          title: 'Export as PDF',
          subtitle: 'Printable student records',
          onTap: onPdf,
        ),
        const SizedBox(height: 10),
        _ExportOption(
          icon: PlatformIcons.gridOn,
          color: _kAccentGreen,
          title: 'Export as Excel',
          subtitle: 'Spreadsheet with full data',
          onTap: onExcel,
        ),
      ],
    ),
  );
}

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ExportOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF9AA3B0),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(PlatformIcons.chevronRight, color: color, size: 14),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shimmer / Empty
// ─────────────────────────────────────────────────────────────────────────────

class _RecordsShimmer extends StatefulWidget {
  const _RecordsShimmer();

  @override
  State<_RecordsShimmer> createState() => _RecordsShimmerState();
}

class _RecordsShimmerState extends State<_RecordsShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, _) {
      final opacity = 0.5 + 0.5 * math.sin(_anim.value * math.pi);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: List.generate(
              8,
              (_) => Container(
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF).withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Color(0xFFEEF3FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _kAccentBlue, size: 32),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9AA3B0),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
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
