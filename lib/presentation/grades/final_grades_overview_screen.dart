import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grading_category_model.dart';
import '../../data/models/grading_period_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/grading_system_config.dart';
import '../../data/models/grade_equivalency.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/grading_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../home/home_screen.dart';

class FinalGradesOverviewScreen extends StatefulWidget {
  final ClassModel classModel;

  const FinalGradesOverviewScreen({super.key, required this.classModel});

  @override
  State<FinalGradesOverviewScreen> createState() =>
      _FinalGradesOverviewScreenState();
}

class _FinalGradesOverviewScreenState extends State<FinalGradesOverviewScreen> {
  final StudentRepository _studentRepo = StudentRepository();
  final GradingRepository _gradingRepo = GradingRepository();

  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  bool _isLoading = true;
  bool _isExporting = false;
  Object? _error;

  List<Student> _students = const [];
  List<GradingPeriod> _periods = const [];

  /// Map: periodId -> categories in that period.
  Map<int, List<GradingCategory>> _categoriesByPeriod = const {};

  /// Map: studentId -> (periodId -> finalGrade)
  Map<int, Map<int, double>> _periodGradeByStudent = const {};

  /// Map: studentId -> (periodId -> (categoryId -> (score, max)))
  Map<int, Map<int, Map<int, ({double score, double max})>>>
  _categoryTotalsByStudent = const {};

  GradingSystemConfig _gradingSystem = GradingSystemConfig.percentage100;
  GradeEquivalencyTable _eqTable = const GradeEquivalencyTable(
    equivalencies: [],
  );

  bool get _isCollege =>
      _gradingSystem.type == GradingSystemType.college1to5 ||
      _gradingSystem.type == GradingSystemType.college4point0;

  String _safeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]+'), '').trim();
    return cleaned.isEmpty ? 'export' : cleaned.replaceAll(' ', '_');
  }

  Future<Map<String, String>> _loadHeaderDetails() async {
    final db = DatabaseHelper.instance;
    final teacherName = (await db.getSetting('teacher_name') ?? '').trim();
    final schoolName = (await db.getSetting('school_name') ?? '').trim();

    final subjectName = widget.classModel.subject?.name ?? '';
    final subjectCode = widget.classModel.subject?.code ?? '';
    final subjectDesc = widget.classModel.subject?.description ?? '';
    final section = widget.classModel.section;
    final schoolYear = widget.classModel.schoolYear;
    final schedule = widget.classModel.schedule ?? '';
    final room = widget.classModel.room ?? '';

    return {
      'teacher_name': teacherName,
      'school_name': schoolName,
      'subject_name': subjectName,
      'subject_code': subjectCode,
      'subject_description': subjectDesc,
      'section': section,
      'school_year': schoolYear,
      'schedule': schedule,
      'room': room,
    };
  }

  String _fmt(double v) => '${v.toStringAsFixed(2)}%';

  String _fmtScoreMax(({double score, double max})? v) {
    if (v == null) return '-';
    return '${v.score.toStringAsFixed(0)}/${v.max.toStringAsFixed(0)}';
  }

  ({List<String> headers, List<List<String>> rows}) _buildExportTable() {
    final headers = <String>['Student Name'];

    for (final p in _periods) {
      final pid = p.id;
      final categories = pid == null
          ? const <GradingCategory>[]
          : (_categoriesByPeriod[pid] ?? const <GradingCategory>[]);
      for (final c in categories) {
        headers.add('${c.name}\n(score/max)');
      }
      headers.add('${p.name}\nGrade');
    }

    headers.add('SUM');
    headers.add('FINAL');
    if (_isCollege) {
      headers.add('Equivalent');
      headers.add('Remarks');
    }

    final rows = <List<String>>[];
    for (final s in _students) {
      if (s.id == null) continue;
      final studentId = s.id!;

      final grades = _periodGradeByStudent[studentId] ?? const <int, double>{};
      final catTotalsByPeriod = _categoryTotalsByStudent[studentId] ?? const {};

      final row = <String>[s.fullName];
      for (final p in _periods) {
        final pid = p.id;
        final categories = pid == null
            ? const <GradingCategory>[]
            : (_categoriesByPeriod[pid] ?? const <GradingCategory>[]);
        final totals = pid == null
            ? const <int, ({double score, double max})>{}
            : (catTotalsByPeriod[pid] ??
                  const <int, ({double score, double max})>{});

        for (final c in categories) {
          row.add(c.id == null ? '-' : _fmtScoreMax(totals[c.id!]));
        }
        row.add(pid == null ? '-' : _fmt(grades[pid] ?? 0));
      }

      final sum = _periods.fold<double>(
        0.0,
        (acc, p) => acc + (p.id == null ? 0 : (grades[p.id!] ?? 0)),
      );
      final finalAvg = _periods.isEmpty ? 0.0 : (sum / _periods.length);
      row.add(_fmt(sum));
      row.add(_fmt(finalAvg));

      if (_isCollege) {
        final eq = _eqTable.convertPercentageToNumerical(finalAvg);
        row.add(eq == null ? '-' : eq.toStringAsFixed(2));
        row.add(_eqTable.getDescriptor(finalAvg) ?? '-');
      }

      rows.add(row);
    }

    return (headers: headers, rows: rows);
  }

  PdfGrid _buildPdfGrid(
    List<String> headers,
    List<List<String>> rows,
    PdfFont bodyFont,
    double contentWidth,
  ) {
    final grid = PdfGrid();
    grid.columns.add(count: headers.length);

    // Responsive column widths to avoid cutting in PDF.
    // Keep Student Name wider, distribute the remaining width across the rest.
    final colCount = headers.length;
    final minOther = colCount > 18 ? 34.0 : (colCount > 14 ? 42.0 : 52.0);
    final nameTarget = colCount > 18 ? 150.0 : 180.0;
    final nameWidth = nameTarget.clamp(120.0, contentWidth * 0.35);
    final remaining = (contentWidth - nameWidth).clamp(0.0, contentWidth);
    final otherCount = (colCount - 1).clamp(1, 9999);
    final otherWidth = (remaining / otherCount).clamp(minOther, 90.0);
    final fittedNameWidth = (contentWidth - (otherWidth * otherCount)).clamp(
      120.0,
      nameWidth,
    );

    for (var i = 0; i < colCount; i++) {
      grid.columns[i].width = i == 0 ? fittedNameWidth : otherWidth;
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
        9,
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

    final padding = colCount > 18
        ? PdfPaddings(left: 2, right: 2, top: 2, bottom: 2)
        : (colCount > 14
              ? PdfPaddings(left: 3, right: 3, top: 3, bottom: 3)
              : PdfPaddings(left: 5, right: 5, top: 4, bottom: 4));

    grid.style = PdfGridStyle(cellPadding: padding, font: bodyFont);
    grid.applyBuiltInStyle(PdfGridBuiltInStyle.gridTable4);
    return grid;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final classId = widget.classModel.id;
      if (classId == null) {
        throw Exception('Class id is null');
      }

      final db = DatabaseHelper.instance;
      final gradingSystemJson = await db.getSetting('grading_system');
      GradingSystemConfig gradingSystem = GradingSystemConfig.percentage100;
      if (gradingSystemJson != null && gradingSystemJson.isNotEmpty) {
        try {
          gradingSystem = GradingSystemConfig.fromJson(
            jsonDecode(gradingSystemJson) as Map<String, dynamic>,
          );
        } catch (e) {
          print('[FinalGradesOverviewScreen] Error parsing grading system: $e');
        }
      }

      final eqJson = await db.getSetting('grade_equivalency_table');
      GradeEquivalencyTable eqTable = const GradeEquivalencyTable(
        equivalencies: [],
      );
      if (eqJson != null && eqJson.isNotEmpty) {
        try {
          eqTable = GradeEquivalencyTable.fromJson(
            jsonDecode(eqJson) as Map<String, dynamic>,
          );
        } catch (e) {
          print(
            '[FinalGradesOverviewScreen] Error parsing equivalency table: $e',
          );
        }
      }

      if (eqTable.isNotEmpty) {
        final filtered = eqTable.equivalencies
            .where((e) => e.minPercentage != 0 || e.maxPercentage != 0)
            .toList();
        if (filtered.length != eqTable.equivalencies.length) {
          print(
            '[FinalGradesOverviewScreen] Filtered invalid equivalency rows: before=${eqTable.equivalencies.length} after=${filtered.length}',
          );
        }
        eqTable = eqTable.copyWith(equivalencies: filtered);
      }

      if (eqTable.isEmpty) {
        if (gradingSystem.type == GradingSystemType.college4point0) {
          eqTable = GradeEquivalencyTable.depedTo4point0;
          print(
            '[FinalGradesOverviewScreen] Using default equivalency preset: depedTo4point0',
          );
        } else if (gradingSystem.type == GradingSystemType.college1to5) {
          eqTable = GradeEquivalencyTable.depedTo1to5;
          print(
            '[FinalGradesOverviewScreen] Using default equivalency preset: depedTo1to5',
          );
        }
      }

      final students = await _studentRepo.getStudentsByClass(classId);
      final periods = await _gradingRepo.getPeriodsByClass(classId);

      final categoriesByPeriod = <int, List<GradingCategory>>{};
      for (final p in periods) {
        if (p.id == null) continue;
        categoriesByPeriod[p.id!] = await _gradingRepo.getCategoriesByPeriod(
          p.id!,
        );
      }

      final gradeMap = <int, Map<int, double>>{};
      final categoryTotalsMap =
          <int, Map<int, Map<int, ({double score, double max})>>>{};

      for (final s in students) {
        if (s.id == null) continue;
        final perStudent = <int, double>{};
        final perStudentCats = <int, Map<int, ({double score, double max})>>{};
        for (final p in periods) {
          if (p.id == null) continue;
          final effectiveGrades = await _gradingRepo
              .getEffectiveGradesByStudent(
                studentId: s.id!,
                classId: classId,
                periodId: p.id!,
              );

          final catTotals = <int, ({double score, double max})>{};
          for (final g in effectiveGrades) {
            catTotals[g.categoryId] = (score: g.score, max: g.maxScore);
          }
          perStudentCats[p.id!] = catTotals;

          final pg = await _gradingRepo.computeStudentPeriodGrade(
            studentId: s.id!,
            classId: classId,
            periodId: p.id!,
          );
          perStudent[p.id!] = pg;
        }
        gradeMap[s.id!] = perStudent;
        categoryTotalsMap[s.id!] = perStudentCats;

        final sum = periods.fold<double>(
          0.0,
          (acc, p) => acc + (p.id == null ? 0 : (perStudent[p.id!] ?? 0)),
        );
        final finalAvg = periods.isEmpty ? 0.0 : (sum / periods.length);

        if (gradingSystem.type == GradingSystemType.college1to5 ||
            gradingSystem.type == GradingSystemType.college4point0) {
          final eq = eqTable.convertPercentageToNumerical(finalAvg);
          final desc = eqTable.getDescriptor(finalAvg);
          print(
            '[FinalGradesOverviewScreen] Equivalent studentId=${s.id} percent=${finalAvg.toStringAsFixed(2)} eq=${eq?.toStringAsFixed(2) ?? '-'} desc=${desc ?? '-'}',
          );
        }

        print(
          '[FinalGradesOverviewScreen] studentId=${s.id} name=${s.fullName} sum=${sum.toStringAsFixed(2)} periods=${periods.length} final=${finalAvg.toStringAsFixed(2)}',
        );
      }

      print(
        '[FinalGradesOverviewScreen] Loaded classId=$classId students=${students.length} periods=${periods.length}',
      );

      if (!mounted) return;
      setState(() {
        _students = students;
        _periods = periods;
        _categoriesByPeriod = categoriesByPeriod;
        _periodGradeByStudent = gradeMap;
        _categoryTotalsByStudent = categoryTotalsMap;
        _gradingSystem = gradingSystem;
        _eqTable = eqTable;
        _isLoading = false;
      });
    } catch (e) {
      print('[FinalGradesOverviewScreen] Load error: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_isLoading || _students.isEmpty || _periods.isEmpty) return;
    setState(() => _isExporting = true);

    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);

      final export = _buildExportTable();

      final doc = PdfDocument();
      // Long paper 8.5" x 13" (in points, 72pt per inch): 612 x 936.
      // Set size first, then landscape for a wide table.
      doc.pageSettings.size = const Size(612, 936);
      doc.pageSettings.orientation = PdfPageOrientation.landscape;
      final page = doc.pages.add();
      final g = page.graphics;
      final size = page.getClientSize();
      final w = size.width;

      const margin = 24.0;
      final contentW = w - (margin * 2);

      final titleFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        16,
        style: PdfFontStyle.bold,
      );
      final labelFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        10,
        style: PdfFontStyle.bold,
      );
      final valueFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final colCount = export.headers.length;
      final smallFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        colCount > 18 ? 7 : (colCount > 14 ? 8 : 9),
      );

      double y = margin;
      g.drawString(
        'FINAL GRADES OVERVIEW',
        titleFont,
        bounds: Rect.fromLTWH(margin, y, contentW, 24),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      y += 26;

      if ((header['school_name'] ?? '').trim().isNotEmpty) {
        g.drawString(
          header['school_name']!,
          PdfStandardFont(
            PdfFontFamily.helvetica,
            12,
            style: PdfFontStyle.bold,
          ),
          bounds: Rect.fromLTWH(margin, y, contentW, 18),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        y += 18;
      }

      final blockTop = y + 8;
      final blockPadding = 12.0;
      final lineH = 14.0;
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

      final blockH =
          (blockPairs.isEmpty ? 0 : (blockPairs.length * lineH)) +
          (blockPadding * 2);
      if (blockH > 0) {
        final rect = Rect.fromLTWH(margin, blockTop, contentW, blockH);
        g.drawRectangle(
          pen: PdfPens.lightGray,
          brush: PdfSolidBrush(PdfColor(250, 250, 250)),
          bounds: rect,
        );

        double yy = blockTop + blockPadding;
        for (final p in blockPairs) {
          g.drawString(
            '${p.k}: ',
            labelFont,
            bounds: Rect.fromLTWH(margin + 10, yy, 110, lineH),
          );
          g.drawString(
            p.v,
            valueFont,
            bounds: Rect.fromLTWH(margin + 120, yy, contentW - 130, lineH),
          );
          yy += lineH;
        }

        y = blockTop + blockH + 14;
      } else {
        y += 14;
      }

      final grid = _buildPdfGrid(
        export.headers,
        export.rows,
        smallFont,
        contentW,
      );
      final layoutResult = grid.draw(
        page: page,
        bounds: Rect.fromLTWH(margin, y, contentW, 0),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );

      // Signature placeholders
      final teacherName = (header['teacher_name'] ?? '').trim();
      final signFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final signLabelFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        10,
        style: PdfFontStyle.bold,
      );
      const signLineH = 14.0;

      PdfPage signPage = layoutResult?.page ?? page;
      final signSize = signPage.getClientSize();
      final signW = signSize.width;
      final signContentW = signW - (margin * 2);
      double signY = (layoutResult?.bounds.bottom ?? (y + 200)) + 26;

      // One-row (3 columns) signature layout
      const labelH = 16.0;
      const labelGap = 18.0;
      const roleGap = 6.0;
      final neededH = labelH + labelGap + signLineH + roleGap + signLineH + 12;
      if (signY + neededH > (signSize.height - margin)) {
        signPage = doc.pages.add();
        signY = margin;
      }

      const colGap = 18.0;
      final colW = (signContentW - (colGap * 2)) / 3;
      final x1 = margin;
      final x2 = margin + colW + colGap;
      final x3 = margin + (colW * 2) + (colGap * 2);

      void drawSigColumn({
        required double x,
        required String label,
        required String name,
        required String role,
      }) {
        signPage.graphics.drawString(
          label,
          signLabelFont,
          bounds: Rect.fromLTWH(x, signY, colW, labelH),
        );

        final lineY = signY + labelGap;
        signPage.graphics.drawLine(
          PdfPens.black,
          Offset(x, lineY + 2),
          Offset(x + colW, lineY + 2),
        );
        signPage.graphics.drawString(
          name.isEmpty ? ' ' : name,
          signFont,
          bounds: Rect.fromLTWH(x, lineY - 12, colW, 14),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        signPage.graphics.drawString(
          role,
          signFont,
          bounds: Rect.fromLTWH(x, lineY + 6, colW, 14),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
      }

      drawSigColumn(
        x: x1,
        label: 'Prepared by:',
        name: teacherName,
        role: 'Instructor',
      );
      drawSigColumn(
        x: x2,
        label: 'Reviewed by:',
        name: '',
        role: 'Program Coordinator',
      );
      drawSigColumn(
        x: x3,
        label: 'Approved by:',
        name: '',
        role: 'College Dean',
      );

      final bytes = doc.saveSync();
      doc.dispose();

      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/final_grades_overview_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      print('[FinalGradesOverviewScreen] Export PDF saved: ${file.path}');

      final RenderBox? box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Final Grades Overview',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      print('[FinalGradesOverviewScreen] Export PDF error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_isLoading || _students.isEmpty || _periods.isEmpty) return;
    setState(() => _isExporting = true);

    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);

      final export = _buildExportTable();

      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Final Grades';
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

      final tableHeaderStyle = workbook.styles.add('tableHeaderStyle');
      tableHeaderStyle.bold = true;
      tableHeaderStyle.fontSize = 10;
      tableHeaderStyle.backColor = '#EBEEF5';
      tableHeaderStyle.hAlign = xlsio.HAlignType.center;
      tableHeaderStyle.vAlign = xlsio.VAlignType.center;

      final cellStyle = workbook.styles.add('cellStyle');
      cellStyle.fontSize = 10;
      cellStyle.hAlign = xlsio.HAlignType.center;
      cellStyle.vAlign = xlsio.VAlignType.center;

      final nameCellStyle = workbook.styles.add('nameCellStyle');
      nameCellStyle.fontSize = 10;
      nameCellStyle.hAlign = xlsio.HAlignType.left;
      nameCellStyle.vAlign = xlsio.VAlignType.center;

      final lastCol = export.headers.length;
      final titleRange = sheet.getRangeByIndex(1, 1, 1, lastCol);
      titleRange.merge();
      titleRange.setText('FINAL GRADES OVERVIEW');
      titleRange.cellStyle = titleStyle;
      sheet.getRangeByIndex(1, 1).rowHeight = 26;

      int row = 3;
      void writePair(String label, String value) {
        if (value.trim().isEmpty) return;
        sheet.getRangeByIndex(row, 1).setText(label);
        sheet.getRangeByIndex(row, 1).cellStyle = labelStyle;
        final r = sheet.getRangeByIndex(row, 2, row, lastCol);
        r.merge();
        r.setText(value);
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
      final tableStartCol = 1;
      for (var c = 0; c < export.headers.length; c++) {
        final cell = sheet.getRangeByIndex(row, tableStartCol + c);
        cell.setText(export.headers[c].replaceAll('\n', ' '));
        cell.cellStyle = tableHeaderStyle;
      }
      sheet.getRangeByIndex(row, 1).rowHeight = 20;
      row++;

      for (final rData in export.rows) {
        for (var c = 0; c < export.headers.length; c++) {
          final value = c < rData.length ? rData[c] : '';
          final cell = sheet.getRangeByIndex(row, tableStartCol + c);
          cell.setText(value);
          cell.cellStyle = c == 0 ? nameCellStyle : cellStyle;
        }
        row++;
      }

      final tableEndRow = row - 1;
      final tableEndCol = export.headers.length;
      final tableRange = sheet.getRangeByIndex(
        tableStartRow,
        tableStartCol,
        tableEndRow,
        tableEndCol,
      );
      tableRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      tableRange.cellStyle.borders.all.color = '#D0D6E5';

      for (var r = tableStartRow + 1; r <= tableEndRow; r++) {
        if ((r - tableStartRow).isOdd) {
          final rr = sheet.getRangeByIndex(r, 1, r, tableEndCol);
          rr.cellStyle.backColor = '#FAFAFA';
        }
      }

      // Column widths
      sheet.setColumnWidthInPixels(1, 220);
      for (var c = 2; c <= tableEndCol; c++) {
        sheet.setColumnWidthInPixels(c, 95);
      }

      // Signature placeholders (below table)
      row += 2;
      final teacherName = (header['teacher_name'] ?? '').trim();

      final signLabelStyle = workbook.styles.add('signLabelStyle');
      signLabelStyle.bold = true;
      signLabelStyle.fontSize = 10;

      final signRoleStyle = workbook.styles.add('signRoleStyle');
      signRoleStyle.fontSize = 10;
      signRoleStyle.hAlign = xlsio.HAlignType.center;

      final signNameStyle = workbook.styles.add('signNameStyle');
      signNameStyle.fontSize = 10;
      signNameStyle.hAlign = xlsio.HAlignType.center;
      signNameStyle.borders.bottom.lineStyle = xlsio.LineStyle.thin;

      // One-row (3 columns) signature layout
      final totalCols = lastCol;
      final colW = (totalCols / 3).floor();
      final w1 = colW < 4 ? 4 : colW;
      final start1 = 1;
      final start2 = (start1 + w1).clamp(1, totalCols);
      final start3 = (start2 + w1).clamp(1, totalCols);
      final end1 = (start2 - 1).clamp(start1, totalCols);
      final end2 = (start3 - 1).clamp(start2, totalCols);
      final end3 = totalCols;

      void writeSigRow({
        required int startCol,
        required int endCol,
        required String label,
        required String name,
        required String role,
      }) {
        sheet.getRangeByIndex(row, startCol).setText(label);
        sheet.getRangeByIndex(row, startCol).cellStyle = signLabelStyle;

        final nameRange = sheet.getRangeByIndex(
          row + 2,
          startCol,
          row + 2,
          endCol,
        );
        nameRange.merge();
        nameRange.setText(name);
        nameRange.cellStyle = signNameStyle;

        final roleRange = sheet.getRangeByIndex(
          row + 3,
          startCol,
          row + 3,
          endCol,
        );
        roleRange.merge();
        roleRange.setText(role);
        roleRange.cellStyle = signRoleStyle;
      }

      writeSigRow(
        startCol: start1,
        endCol: end1,
        label: 'Prepared by:',
        name: teacherName,
        role: 'Instructor',
      );
      writeSigRow(
        startCol: start2,
        endCol: end2,
        label: 'Reviewed by:',
        name: ' ',
        role: 'Program Coordinator',
      );
      writeSigRow(
        startCol: start3,
        endCol: end3,
        label: 'Approved by:',
        name: ' ',
        role: 'College Dean',
      );

      row += 6;

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/final_grades_overview_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      print('[FinalGradesOverviewScreen] Export Excel saved: ${file.path}');

      final RenderBox? box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Final Grades Overview',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      print('[FinalGradesOverviewScreen] Export Excel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    final subjectTitle = (widget.classModel.subject?.code.isNotEmpty ?? false)
        ? widget.classModel.subject!.code
        : (widget.classModel.subject?.name ?? widget.classModel.displayName);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          // Fixed Header with Wave
          WaveHeader(
            title: 'Final Grades Overview',
            subtitle: subjectTitle,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _isLoading || _isExporting ? null : _exportPdf,
                icon: Icon(PlatformIcons.pictureAsPdf, color: Colors.white),
                tooltip: 'Export PDF',
              ),
              IconButton(
                onPressed: _isLoading || _isExporting ? null : _exportExcel,
                icon: Icon(PlatformIcons.gridOn, color: Colors.white),
                tooltip: 'Export Excel',
              ),
              IconButton(
                onPressed: _load,
                icon: Icon(PlatformIcons.refresh, color: Colors.white),
                tooltip: 'Refresh',
              ),
            ],
            chips: [
              WaveHeaderChip(
                icon: PlatformIcons.people,
                label: 'Students',
                value: '${_students.length}',
              ),
              WaveHeaderChip(
                icon: PlatformIcons.eventNote,
                label: 'Periods',
                value: '${_periods.length}',
                isWarning: _periods.isEmpty,
              ),
            ],
          ),
          // Scrollable Final Grades Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Failed to load grades: $_error',
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  )
                : _students.isEmpty
                ? const Center(
                    child: Text(
                      'No students enrolled.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : _periods.isEmpty
                ? const Center(
                    child: Text(
                      'No grading periods configured.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : _buildTable(),
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

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow(),
                  const Divider(height: 1, thickness: 2),
                  ..._students.map(_buildStudentRow),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.1),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell(
              width: 220,
              text: 'Student Name',
              isHeader: true,
              align: TextAlign.left,
            ),
            ..._periods.expand((p) {
              final pid = p.id;
              final categories = pid == null
                  ? const <GradingCategory>[]
                  : (_categoriesByPeriod[pid] ?? const <GradingCategory>[]);
              return [
                ...categories.map(
                  (c) => _cell(
                    width: 120,
                    text: '${c.name}\n(score/max)',
                    isHeader: true,
                  ),
                ),
                _cell(width: 110, text: '${p.name}\nGrade', isHeader: true),
              ];
            }),
            _cell(width: 110, text: 'SUM', isHeader: true),
            _cell(width: 120, text: 'FINAL', isHeader: true),
            if (_isCollege)
              _cell(width: 110, text: 'Equivalent', isHeader: true),
            if (_isCollege) _cell(width: 140, text: 'Remarks', isHeader: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentRow(Student student) {
    final studentId = student.id;
    final grades = studentId == null
        ? const <int, double>{}
        : (_periodGradeByStudent[studentId] ?? const <int, double>{});
    final catTotalsByPeriod = studentId == null
        ? const <int, Map<int, ({double score, double max})>>{}
        : (_categoryTotalsByStudent[studentId] ??
              const <int, Map<int, ({double score, double max})>>{});

    final sum = _periods.fold<double>(
      0.0,
      (acc, p) => acc + (p.id == null ? 0 : (grades[p.id!] ?? 0)),
    );
    final finalAvg = _periods.isEmpty ? 0.0 : (sum / _periods.length);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell(width: 220, text: student.fullName, align: TextAlign.left),
            ..._periods.expand((p) {
              final pid = p.id;
              final categories = pid == null
                  ? const <GradingCategory>[]
                  : (_categoriesByPeriod[pid] ?? const <GradingCategory>[]);
              final totals = pid == null
                  ? const <int, ({double score, double max})>{}
                  : (catTotalsByPeriod[pid] ??
                        const <int, ({double score, double max})>{});

              return [
                ...categories.map(
                  (c) => _cell(
                    width: 120,
                    text: c.id == null ? '-' : _fmtScoreMax(totals[c.id!]),
                  ),
                ),
                _cell(
                  width: 110,
                  text: pid == null ? '-' : _fmt(grades[pid] ?? 0),
                ),
              ];
            }),
            _cell(width: 110, text: _fmt(sum)),
            _cell(width: 120, text: _fmt(finalAvg), highlight: true),
            if (_isCollege)
              _cell(
                width: 110,
                text:
                    (_eqTable.convertPercentageToNumerical(
                      finalAvg,
                    ))?.toStringAsFixed(2) ??
                    '-',
              ),
            if (_isCollege)
              _cell(
                width: 140,
                text: _eqTable.getDescriptor(finalAvg) ?? '-',
                align: TextAlign.left,
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell({
    required double width,
    required String text,
    TextAlign align = TextAlign.center,
    bool isHeader = false,
    bool highlight = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.success.withValues(alpha: 0.08) : null,
        border: const Border(right: BorderSide(color: AppTheme.divider)),
      ),
      child: Text(
        text,
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.w800 : FontWeight.w600,
          fontSize: 12,
          color: isHeader ? AppTheme.textPrimary : AppTheme.textSecondary,
        ),
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
