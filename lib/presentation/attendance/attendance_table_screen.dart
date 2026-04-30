import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../home/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class AttendanceTableScreen extends StatefulWidget {
  final ClassModel classModel;
  final int periodId;
  final String periodName;

  const AttendanceTableScreen({
    super.key,
    required this.classModel,
    required this.periodId,
    required this.periodName,
  });

  @override
  State<AttendanceTableScreen> createState() => _AttendanceTableScreenState();
}

class _AttendanceTableScreenState extends State<AttendanceTableScreen>
    with SingleTickerProviderStateMixin {
  final AttendanceRepository _attRepo = AttendanceRepository();
  final StudentRepository _studentRepo = StudentRepository();

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

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List<Student> _students = const [];
  List<String> _dates = const [];
  Map<int, Map<String, String>> _statusByStudentAndDate = const {};

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  String _formatYmd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _safeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]+'), '').trim();
    return cleaned.isEmpty ? 'export' : cleaned.replaceAll(' ', '_');
  }

  // ── Stats helpers ───────────────────────────────────────────────────────────

  Map<String, int> get _overallStats {
    int present = 0, absent = 0, late = 0;
    for (final perDate in _statusByStudentAndDate.values) {
      for (final s in perDate.values) {
        final st = s.trim().toLowerCase();
        if (st == 'present') present++;
        if (st == 'absent') absent++;
        if (st == 'late') late++;
      }
    }
    return {'present': present, 'absent': absent, 'late': late};
  }

  // ── Export helpers (unchanged logic) ────────────────────────────────────────

  Future<Map<String, String>> _loadHeaderDetails() async {
    final db = DatabaseHelper.instance;
    final teacherName = (await db.getSetting('teacher_name') ?? '').trim();
    final schoolName = (await db.getSetting('school_name') ?? '').trim();
    return {
      'teacher_name': teacherName,
      'school_name': schoolName,
      'subject_name': widget.classModel.subject?.name ?? '',
      'subject_code': widget.classModel.subject?.code ?? '',
      'section': widget.classModel.section,
      'school_year': widget.classModel.schoolYear,
      'schedule': widget.classModel.schedule ?? '',
      'room': widget.classModel.room ?? '',
    };
  }

  ({List<String> headers, List<List<String>> rows}) _buildExportTable() {
    final headers = <String>[
      'Student Name',
      ..._dates.map((d) => DateFormat('MMM d').format(DateTime.parse(d))),
    ];
    final rows = <List<String>>[];
    for (final s in _students) {
      final perDate =
          _statusByStudentAndDate[s.id!] ?? const <String, String>{};
      final row = <String>[s.fullName];
      for (final d in _dates) {
        final status = (perDate[d] ?? '').trim().toLowerCase();
        row.add(status.isEmpty ? '' : _statusLabel(status));
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
    final colCount = headers.length;
    final nameTarget = colCount > 20 ? 160.0 : 200.0;
    final nameWidth = nameTarget.clamp(120.0, contentWidth * 0.35);
    final remaining = (contentWidth - nameWidth).clamp(0.0, contentWidth);
    final otherCount = (colCount - 1).clamp(1, 9999);
    final minOther = colCount > 35 ? 18.0 : (colCount > 25 ? 22.0 : 28.0);
    final otherWidth = (remaining / otherCount).clamp(minOther, 40.0);
    final fittedNameWidth = (contentWidth - (otherWidth * otherCount)).clamp(
      120.0,
      nameWidth,
    );

    for (var i = 0; i < colCount; i++) {
      grid.columns[i].width = i == 0 ? fittedNameWidth : otherWidth;
    }
    final headerRow = grid.headers.add(1)[0];
    for (var i = 0; i < headers.length; i++) {
      headerRow.cells[i].value = headers[i];
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
    final padding = colCount > 30
        ? PdfPaddings(left: 2, right: 2, top: 2, bottom: 2)
        : PdfPaddings(left: 4, right: 4, top: 3, bottom: 3);
    grid.style = PdfGridStyle(cellPadding: padding, font: bodyFont);
    grid.applyBuiltInStyle(PdfGridBuiltInStyle.gridTable4);
    return grid;
  }

  Future<void> _exportPdf() async {
    if (_isLoading || _students.isEmpty || _dates.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);
      final export = _buildExportTable();
      final colCount = export.headers.length;
      final bodyFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        colCount > 35 ? 6 : (colCount > 25 ? 7 : 8),
      );
      final doc = PdfDocument();
      doc.pageSettings.size = const Size(612, 936);
      doc.pageSettings.orientation = PdfPageOrientation.landscape;
      final page = doc.pages.add();
      final g = page.graphics;
      final size = page.getClientSize();
      const margin = 24.0;
      final contentW = size.width - (margin * 2);
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
      double y = margin;
      g.drawString(
        'ATTENDANCE REPORT',
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
      const blockPadding = 12.0;
      const lineH = 14.0;
      final blockPairs = <({String k, String v})>[
        (k: 'Teacher', v: header['teacher_name'] ?? ''),
        (
          k: 'Subject',
          v: '${(header['subject_code'] ?? '').trim()} ${(header['subject_name'] ?? '').trim()}'
              .trim(),
        ),
        (k: 'Section', v: header['section'] ?? ''),
        (k: 'School Year', v: header['school_year'] ?? ''),
        (k: 'Period', v: widget.periodName),
        (k: 'Month', v: monthLabel),
        (k: 'Date Generated', v: dateLabel),
      ].where((p) => p.v.trim().isNotEmpty).toList();
      final blockTop = y + 8;
      final blockH =
          (blockPairs.isEmpty ? 0 : (blockPairs.length * lineH)) +
          (blockPadding * 2);
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
        bodyFont,
        contentW,
      );
      grid.draw(
        page: page,
        bounds: Rect.fromLTWH(margin, y, contentW, 0),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      final bytes = doc.saveSync();
      doc.dispose();
      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/attendance_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Attendance Report ($monthLabel)');
    } catch (e) {
      if (mounted) {
        _showErrorSnack('Failed to export PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_isLoading || _students.isEmpty || _dates.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final header = await _loadHeaderDetails();
      final now = DateTime.now();
      final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
      final dateLabel = DateFormat('MMMM d, yyyy').format(now);
      final export = _buildExportTable();
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Attendance';
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
      titleRange.setText('ATTENDANCE REPORT');
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
      writePair('Section', header['section'] ?? '');
      writePair('School Year', header['school_year'] ?? '');
      writePair('Period', widget.periodName);
      writePair('Month', monthLabel);
      writePair('Date Generated', dateLabel);
      row++;
      final tableStartRow = row;
      for (var c = 0; c < export.headers.length; c++) {
        final cell = sheet.getRangeByIndex(row, 1 + c);
        cell.setText(export.headers[c].replaceAll('\n', ' '));
        cell.cellStyle = tableHeaderStyle;
      }
      sheet.getRangeByIndex(row, 1).rowHeight = 20;
      row++;
      for (final rData in export.rows) {
        for (var c = 0; c < export.headers.length; c++) {
          final value = c < rData.length ? rData[c] : '';
          final cell = sheet.getRangeByIndex(row, 1 + c);
          cell.setText(value);
          cell.cellStyle = c == 0 ? nameCellStyle : cellStyle;
        }
        row++;
      }
      final tableEndRow = row - 1;
      final tableEndCol = export.headers.length;
      final tableRange = sheet.getRangeByIndex(
        tableStartRow,
        1,
        tableEndRow,
        tableEndCol,
      );
      tableRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      tableRange.cellStyle.borders.all.color = '#D0D6E5';
      for (var r = tableStartRow + 1; r <= tableEndRow; r++) {
        if ((r - tableStartRow).isOdd) {
          sheet.getRangeByIndex(r, 1, r, tableEndCol).cellStyle.backColor =
              '#FAFAFA';
        }
      }
      sheet.setColumnWidthInPixels(1, 220);
      for (var c = 2; c <= tableEndCol; c++) {
        sheet.setColumnWidthInPixels(c, 42);
      }
      final bytes = workbook.saveAsStream();
      workbook.dispose();
      final dir = await getTemporaryDirectory();
      final base = _safeFileName(widget.classModel.displayName);
      final file = File(
        '${dir.path}/attendance_${base}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Attendance Report ($monthLabel)');
    } catch (e) {
      if (mounted) _showErrorSnack('Failed to export Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFFF5C72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  ({String startDate, String endDate}) _monthRange(DateTime anyDayInMonth) {
    final start = DateTime(anyDayInMonth.year, anyDayInMonth.month, 1);
    final end = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1, 0);
    return (startDate: _formatYmd(start), endDate: _formatYmd(end));
  }

  Future<DateTime?> _pickMonthSheet(DateTime initialMonth) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F6FB),
      builder: (ctx) {
        DateTime displayMonth = DateTime(
          initialMonth.year,
          initialMonth.month,
          1,
        );

        return StatefulBuilder(
          builder: (context, setModalState) {
            final themeProvider = Provider.of<ThemeProvider>(context);
            final monthLabel = DateFormat(
              'MMMM yyyy',
              'en',
            ).format(displayMonth);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF1A237E,
                            ).withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final prev = DateTime(
                                displayMonth.year,
                                displayMonth.month - 1,
                                1,
                              );
                              setModalState(() => displayMonth = prev);
                            },
                            icon: const Icon(CupertinoIcons.chevron_left),
                            tooltip: 'Previous month',
                          ),
                          Expanded(
                            child: Text(
                              monthLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final next = DateTime(
                                displayMonth.year,
                                displayMonth.month + 1,
                                1,
                              );
                              if (next.isAfter(DateTime.now())) return;
                              setModalState(() => displayMonth = next);
                            },
                            icon: const Icon(CupertinoIcons.chevron_right),
                            tooltip: 'Next month',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            DateTime(displayMonth.year, displayMonth.month, 1),
                          );
                        },
                        icon: const Icon(CupertinoIcons.check_mark),
                        label: const Text('Select'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeProvider.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fadeCtrl.reset();
    final range = _monthRange(_selectedMonth);
    try {
      final students = await _studentRepo.getStudentsByClass(
        widget.classModel.id!,
      );
      final rows = await _attRepo.getAttendanceByDateRange(
        classId: widget.classModel.id!,
        periodId: widget.periodId,
        startDate: range.startDate,
        endDate: range.endDate,
      );
      final datesSet = <String>{};
      final statusMap = <int, Map<String, String>>{};
      for (final r in rows) {
        datesSet.add(r.date);
        statusMap.putIfAbsent(r.studentId, () => <String, String>{})[r.date] =
            r.status;
      }
      final dates = datesSet.toList()..sort();
      if (!mounted) return;
      setState(() {
        _students = students;
        _dates = dates;
        _statusByStudentAndDate = statusMap;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    }
  }

  Future<void> _pickMonth() async {
    final picked = await _pickMonthSheet(_selectedMonth);
    if (picked == null || !mounted) return;
    setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    await _load();
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

  String _statusLabel(String s) {
    if (s == 'present') return 'P';
    if (s == 'absent') return 'A';
    if (s == 'late') return 'L';
    return s.isEmpty ? '' : s.substring(0, 1).toUpperCase();
  }

  Color _statusColor(String s) {
    if (s == 'present') return const Color(0xFF00C897);
    if (s == 'absent') return const Color(0xFFFF5C72);
    if (s == 'late') return const Color(0xFFFFB74D);
    return const Color(0xFF9AA3B0);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    final monthLabel = DateFormat('MMMM yyyy', 'en').format(_selectedMonth);
    final subjectCode = (widget.classModel.subject?.code ?? '').trim();
    final subjectTitle = subjectCode.isNotEmpty
        ? subjectCode
        : (widget.classModel.subject?.name ?? widget.classModel.displayName);
    final stats = _overallStats;
    final present = stats['present'] ?? 0;
    final absent = stats['absent'] ?? 0;
    final late = stats['late'] ?? 0;
    final total = present + absent + late;
    final rate = total == 0 ? 0.0 : present / total;
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          WaveHeader(
            title: 'Report',
            subtitle: '$subjectTitle • ${widget.periodName}',
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: _isLoading || _isExporting ? null : _showExportSheet,
                icon: Icon(
                  _isExporting
                      ? PlatformIcons.watchLater
                      : PlatformIcons.iosShare,
                  color: Colors.white,
                ),
                tooltip: 'Export',
              ),
              TextButton.icon(
                onPressed: _pickMonth,
                icon: Icon(PlatformIcons.calendarMonth),
                label: Text(monthLabel),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
            chips: [
              WaveHeaderChip(
                icon: PlatformIcons.eventNote,
                label: 'Month',
                value: monthLabel,
              ),
              WaveHeaderChip(
                icon: PlatformIcons.people,
                label: 'Students',
                value: '${_students.length}',
              ),
              if (!_isLoading && total > 0) ...[
                WaveHeaderChip(
                  icon: PlatformIcons.checkCircleOutline,
                  label: 'Present',
                  value: '$present',
                ),
                WaveHeaderChip(
                  icon: PlatformIcons.cancel,
                  label: 'Absent',
                  value: '$absent',
                  isWarning: absent > 0,
                ),
                WaveHeaderChip(
                  icon: PlatformIcons.watchLater,
                  label: 'Late',
                  value: '$late',
                  isWarning: late > 0,
                ),
                WaveHeaderChip(
                  icon: PlatformIcons.timeline,
                  label: 'Rate',
                  value: '${(rate * 100).toStringAsFixed(0)}%',
                ),
              ],
            ],
          ),

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const _TableShimmer()
                : _error != null
                ? _ErrorState(error: _error.toString())
                : _students.isEmpty
                ? _EmptyState(
                    icon: PlatformIcons.groupOff,
                    message: 'No students enrolled in this class.',
                  )
                : _dates.isEmpty
                ? _EmptyState(
                    icon: PlatformIcons.eventBusy,
                    message: 'No attendance records for this month.',
                  )
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 20 : 12,
                        12,
                        isTablet ? 20 : 12,
                        20,
                      ),
                      child: _buildTable(),
                    ),
                  ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.07),
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
            // Legend strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFF),
                border: Border(bottom: BorderSide(color: Color(0xFFEEF1F6))),
              ),
              child: Row(
                children: [
                  Text(
                    '${_students.length} Students · ${_dates.length} Days',
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _LegendChip(label: 'P', color: const Color(0xFF00C897)),
                  const SizedBox(width: 6),
                  _LegendChip(label: 'A', color: const Color(0xFFFF5C72)),
                  const SizedBox(width: 6),
                  _LegendChip(label: 'L', color: const Color(0xFFFFB74D)),
                ],
              ),
            ),

            // Scrollable table
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 200 + _dates.length * 46.0,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF0F4FF),
                      ),
                      headingRowHeight: 42,
                      horizontalMargin: 14,
                      columnSpacing: 10,
                      dataRowMinHeight: 46,
                      dataRowMaxHeight: 46,
                      dividerThickness: 0.8,
                      columns: [
                        DataColumn(
                          label: Row(
                            children: [
                              Icon(
                                PlatformIcons.person,
                                size: 14,
                                color: Color(0xFF5B8AF5),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Student',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._dates.map((d) {
                          final dt = DateTime.parse(d);
                          final dayNum = DateFormat('d').format(dt);
                          final dayName = DateFormat(
                            'EEE',
                          ).format(dt).substring(0, 1);
                          return DataColumn(
                            label: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayName,
                                  style: const TextStyle(
                                    color: Color(0xFF9AA3B0),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  dayNum,
                                  style: const TextStyle(
                                    color: Color(0xFF1A237E),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      rows: List.generate(_students.length, (idx) {
                        final s = _students[idx];
                        final map =
                            _statusByStudentAndDate[s.id!] ??
                            const <String, String>{};
                        return DataRow(
                          color: WidgetStateProperty.resolveWith(
                            (states) => idx.isOdd
                                ? const Color(0xFFFAFBFF)
                                : Colors.white,
                          ),
                          cells: [
                            DataCell(
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF5B8AF5,
                                      ).withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        s.fullName.isNotEmpty
                                            ? s.fullName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Color(0xFF5B8AF5),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 148,
                                    child: Text(
                                      s.fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A237E),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ..._dates.map((d) {
                              final status = (map[d] ?? '')
                                  .trim()
                                  .toLowerCase();
                              if (status.isEmpty) {
                                return const DataCell(
                                  Center(
                                    child: Text(
                                      '—',
                                      style: TextStyle(
                                        color: Color(0xFFDDE2EE),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final color = _statusColor(status);
                              return DataCell(
                                Center(
                                  child: Container(
                                    width: 28,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: color.withValues(alpha: 0.30),
                                      ),
                                    ),
                                    child: Text(
                                      _statusLabel(status),
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Legend chip
// ─────────────────────────────────────────────────────────────────────────────

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Export Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ExportSheet extends StatelessWidget {
  final VoidCallback onPdf;
  final VoidCallback onExcel;

  const _ExportSheet({required this.onPdf, required this.onExcel});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  color: const Color(0xFF5B8AF5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  PlatformIcons.iosShare,
                  color: Color(0xFF5B8AF5),
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
                      color: Color(0xFF1A237E),
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
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFEEF1F6)),
          const SizedBox(height: 14),

          // PDF option
          _ExportOption(
            icon: PlatformIcons.pictureAsPdf,
            color: const Color(0xFFFF5C72),
            title: 'Export as PDF',
            subtitle: 'Printable attendance report',
            onTap: onPdf,
          ),
          const SizedBox(height: 10),

          // Excel option
          _ExportOption(
            icon: PlatformIcons.gridOn,
            color: const Color(0xFF00C897),
            title: 'Export as Excel',
            subtitle: 'Spreadsheet with full data',
            onTap: onExcel,
          ),
        ],
      ),
    );
  }
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
//  Loading shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _TableShimmer extends StatefulWidget {
  const _TableShimmer();

  @override
  State<_TableShimmer> createState() => _TableShimmerState();
}

class _TableShimmerState extends State<_TableShimmer>
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
    builder: (_, __) {
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
              (i) => Container(
                height: 46,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Error / Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD6DA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5C72).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF0),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                PlatformIcons.errorOutline,
                color: Color(0xFFFF5C72),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Failed to load attendance',
                    style: TextStyle(
                      color: Color(0xFF2E3A5C),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFF9AA3B0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
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
          child: Icon(icon, color: const Color(0xFF5B8AF5), size: 32),
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
