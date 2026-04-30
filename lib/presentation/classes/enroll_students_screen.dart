import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart'
    as xlsio
    hide Column, Row, Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/wave_header.dart';
import '../../core/services/route_observer.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../core/utils/platform_icons.dart';

class EnrollStudentsScreen extends StatefulWidget {
  final ClassModel classModel;

  const EnrollStudentsScreen({super.key, required this.classModel});

  @override
  State<EnrollStudentsScreen> createState() => _EnrollStudentsScreenState();
}

class _EnrollStudentsScreenState extends State<EnrollStudentsScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  final StudentRepository _repo = StudentRepository();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Student> _enrolled = [];
  List<Student> _available = [];
  String _searchQuery = '';
  bool _isLoading = true;
  late TabController _tabController;

  void _openAppSettings() async {
    await openAppSettings();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();

    // Auto-focus search bar after screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    print('[EnrollStudentsScreen] Returned to screen, refreshing...');
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final enrolled = await _repo.getStudentsByClass(widget.classModel.id!);
      final available = await _repo.getStudentsNotInClass(
        widget.classModel.id!,
      );
      print(
        '[EnrollStudentsScreen] enrolled=${enrolled.length} available=${available.length}',
      );
      if (mounted) {
        setState(() {
          _enrolled = enrolled;
          _available = available;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[EnrollStudentsScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enroll(Student student) async {
    await _repo.enrollStudentToClass(widget.classModel.id!, student.id!);
    print('[EnrollStudentsScreen] Enrolled student ${student.id}');

    // Clear search bar after enrolling
    _searchController.clear();
    setState(() => _searchQuery = '');

    await _load();
  }

  List<Student> _filterStudents(List<Student> students) {
    if (_searchQuery.isEmpty) return students;
    final query = _searchQuery.toLowerCase();
    return students.where((s) {
      return s.fullName.toLowerCase().contains(query) ||
          s.studentId.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _unenroll(Student student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Student'),
        content: Text('Remove ${student.fullName} from this class?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.unenrollStudentFromClass(widget.classModel.id!, student.id!);
    print('[EnrollStudentsScreen] Unenrolled student ${student.id}');
    await _load();
  }

  Future<void> _downloadTemplate() async {
    try {
      // Request storage permission based on platform and Android version
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+) use new media permissions
        // For older versions use storage permissions
        bool permissionGranted = false;

        // Try manageExternalStorage first (for full access)
        final manageStorageStatus = await Permission.manageExternalStorage
            .request();
        if (manageStorageStatus.isGranted) {
          permissionGranted = true;
        } else {
          // Fallback to storage permission for older Android versions
          final storageStatus = await Permission.storage.request();
          permissionGranted = storageStatus.isGranted;
        }

        if (!permissionGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Storage permission is required to download files. Please enable it in app settings.',
                ),
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: _openAppSettings,
                ),
              ),
            );
          }
          return;
        }
      } else if (Platform.isIOS) {
        // iOS permissions are handled by the system when accessing files
        // No explicit permission request needed for app documents directory
      }

      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      // Headers
      sheet.getRangeByName('A1').setText('ID Number');
      sheet.getRangeByName('B1').setText('Firstname');
      sheet.getRangeByName('C1').setText('Middle Name');
      sheet.getRangeByName('D1').setText('Lastname');
      // Style header row
      final headerStyle = workbook.styles.add('header');
      headerStyle.bold = true;
      headerStyle.backColor = '#4A90E2';
      headerStyle.fontColor = '#FFFFFF';
      sheet.getRangeByName('A1:D1').cellStyle = headerStyle;
      // Auto-fit columns
      sheet.autoFitColumn(1);
      sheet.autoFitColumn(2);
      sheet.autoFitColumn(3);
      sheet.autoFitColumn(4);

      // Save to Downloads directory
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        // Android 10+ uses different Downloads path
        downloadsDir = Directory('/storage/emulated/0/Download');
        // Fallback to external storage if primary doesn't exist
        if (!await downloadsDir.exists()) {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            downloadsDir = Directory('${externalDir.path}/Download');
          }
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        // Fallback to app documents directory
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      // Ensure directory exists
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
          print(
            '[EnrollStudentsScreen] Created Downloads directory: ${downloadsDir.path}',
          );
        } catch (e) {
          print(
            '[EnrollStudentsScreen] Failed to create Downloads directory: $e',
          );
          // Fallback to app documents directory
          downloadsDir = await getApplicationDocumentsDirectory();
          print(
            '[EnrollStudentsScreen] Using fallback directory: ${downloadsDir.path}',
          );
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'StudentImportTemplate_$timestamp.xlsx';
      final path = '${downloadsDir.path}/$fileName';
      final file = File(path);

      print('[EnrollStudentsScreen] Attempting to save template to: $path');
      print(
        '[EnrollStudentsScreen] Downloads directory exists: ${await downloadsDir.exists()}',
      );

      final bytes = workbook.saveAsStream();
      await file.writeAsBytes(bytes);
      workbook.dispose();

      // Verify file was created
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      print(
        '[EnrollStudentsScreen] Template download result: exists=$fileExists, size=$fileSize bytes',
      );
      print(
        '[EnrollStudentsScreen] Template downloaded to device storage: $path',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Template saved!'),
                const SizedBox(height: 4),
                Text(
                  'Location: Downloads/$fileName',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                Text(
                  'Path: $path',
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => Share.shareXFiles([
                XFile(path),
              ], text: 'Student Import Template'),
            ),
          ),
        );
      }
    } catch (e) {
      print('[EnrollStudentsScreen] Template download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating template: $e')),
        );
      }
    }
  }

  Future<void> _importFromExcel() async {
    try {
      print('[EnrollStudentsScreen] Starting file picker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result == null) {
        print('[EnrollStudentsScreen] No file selected');
        return;
      }

      final file = result.files.single;
      Uint8List bytes;
      String fileName;

      // Handle file reading based on platform
      if (file.bytes != null) {
        // Web or direct bytes available
        bytes = file.bytes!;
        fileName = file.name;
        print('[EnrollStudentsScreen] Using direct bytes from file picker');
      } else if (file.path != null) {
        // Android/iOS - need to read file from path
        final filePath = file.path!;
        final fileOnDisk = File(filePath);
        fileName = fileOnDisk.path.split('/').last;

        print('[EnrollStudentsScreen] Reading file from path: $filePath');

        if (!await fileOnDisk.exists()) {
          print(
            '[EnrollStudentsScreen] File does not exist at path: $filePath',
          );
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('File not found')));
          }
          return;
        }

        bytes = await fileOnDisk.readAsBytes();
        print(
          '[EnrollStudentsScreen] Successfully read ${bytes.length} bytes from file',
        );
      } else {
        print('[EnrollStudentsScreen] No bytes or path available for file');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to read file')));
        }
        return;
      }

      fileName = fileName.toLowerCase();
      print(
        '[EnrollStudentsScreen] File selected: $fileName, size: ${bytes.length} bytes',
      );

      if (fileName.endsWith('.csv')) {
        print('[EnrollStudentsScreen] Processing as CSV file');
        await _importFromCSV(bytes);
      } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
        print('[EnrollStudentsScreen] Processing as Excel file');
        await _importFromXLSX(bytes);
      } else {
        print('[EnrollStudentsScreen] Unsupported file format: $fileName');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unsupported file format. Please use CSV, XLSX, or XLS',
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('[EnrollStudentsScreen] Import error: $e');
      print('[EnrollStudentsScreen] Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _importFromXLSX(Uint8List bytes) async {
    try {
      print('[EnrollStudentsScreen] Starting XLSX parsing...');

      // Parse Excel file
      final excel = Excel.decodeBytes(bytes);
      print('[EnrollStudentsScreen] Excel parsed successfully');
      print('[EnrollStudentsScreen] Number of tables: ${excel.tables.length}');

      if (excel.tables.isEmpty) {
        print('[EnrollStudentsScreen] No sheets found in Excel file');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel file has no sheets')),
          );
        }
        return;
      }

      // Get first sheet
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      print('[EnrollStudentsScreen] Using sheet: $sheetName');
      print(
        '[EnrollStudentsScreen] Number of rows: ${sheet?.rows.length ?? 0}',
      );

      if (sheet == null || sheet.rows.isEmpty) {
        print('[EnrollStudentsScreen] Sheet is empty or null');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Excel sheet is empty')));
        }
        return;
      }

      // Validate headers (first row)
      final headerRow = sheet.rows[0];
      print('[EnrollStudentsScreen] Header row has ${headerRow.length} cells');

      final headers = headerRow.map((cell) {
        final value = cell?.value?.toString().toLowerCase().trim() ?? '';
        print('[EnrollStudentsScreen] Header cell: "$value"');
        return value;
      }).toList();

      final requiredHeaders = [
        'id number',
        'firstname',
        'middle name',
        'lastname',
      ];
      print('[EnrollStudentsScreen] Required headers: $requiredHeaders');
      print('[EnrollStudentsScreen] Found headers: $headers');

      for (final required in requiredHeaders) {
        if (!headers.contains(required)) {
          print('[EnrollStudentsScreen] Missing required header: $required');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Missing required header: $required')),
            );
          }
          return;
        }
      }

      print('[EnrollStudentsScreen] All required headers found');

      // Get header indices
      final idIndex = headers.indexOf('id number');
      final firstNameIndex = headers.indexOf('firstname');
      final middleNameIndex = headers.indexOf('middle name');
      final lastNameIndex = headers.indexOf('lastname');

      print(
        '[EnrollStudentsScreen] Header indices - ID: $idIndex, First: $firstNameIndex, Middle: $middleNameIndex, Last: $lastNameIndex',
      );

      int importedCount = 0;
      int enrolledCount = 0;
      int skippedCount = 0;
      List<String> skippedStudents = [];

      // Process each row (skip header row)
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        print(
          '[EnrollStudentsScreen] Processing row ${i + 1} with ${row.length} cells',
        );

        // Skip empty rows
        if (row.isEmpty ||
            row.every(
              (cell) => cell?.value?.toString().trim().isEmpty ?? true,
            )) {
          print('[EnrollStudentsScreen] Row ${i + 1} is empty, skipping');
          continue;
        }

        // Extract student data
        final studentId = row.length > idIndex
            ? (row[idIndex]?.value?.toString().trim() ?? '')
            : '';
        final firstName = row.length > firstNameIndex
            ? (row[firstNameIndex]?.value?.toString().trim() ?? '')
            : '';
        final middleName = row.length > middleNameIndex
            ? (row[middleNameIndex]?.value?.toString().trim() ?? '')
            : '';
        final lastName = row.length > lastNameIndex
            ? (row[lastNameIndex]?.value?.toString().trim() ?? '')
            : '';

        print(
          '[EnrollStudentsScreen] Row data - ID: "$studentId", First: "$firstName", Middle: "$middleName", Last: "$lastName"',
        );

        // Validate required fields
        if (studentId.isEmpty || firstName.isEmpty || lastName.isEmpty) {
          print('[EnrollStudentsScreen] Row ${i + 1}: Missing required fields');
          skippedCount++;
          skippedStudents.add('Row ${i + 1}: Missing required fields');
          continue;
        }

        // Check for duplicate ID
        final isDuplicate = await _repo.isStudentIdDuplicate(studentId);
        if (isDuplicate) {
          print('[EnrollStudentsScreen] Row ${i + 1}: Duplicate ID $studentId');
          skippedCount++;
          skippedStudents.add('Row ${i + 1}: Duplicate ID $studentId');
          continue;
        }

        // Check for duplicate name (case-insensitive)
        final existingStudents = await _repo.getAllStudents();
        final nameExists = existingStudents.any(
          (s) =>
              s.firstName.toLowerCase() == firstName.toLowerCase() &&
              s.lastName.toLowerCase() == lastName.toLowerCase() &&
              (s.middleName?.toLowerCase() ?? '') ==
                  (middleName.isEmpty ? '' : middleName.toLowerCase()),
        );

        if (nameExists) {
          print(
            '[EnrollStudentsScreen] Row ${i + 1}: Duplicate name $firstName $middleName $lastName',
          );
          skippedCount++;
          skippedStudents.add(
            'Row ${i + 1}: Duplicate name $firstName $middleName $lastName',
          );
          continue;
        }

        // Create and insert student
        final now = DateTime.now().toIso8601String();
        final student = Student(
          studentId: studentId,
          firstName: firstName,
          lastName: lastName,
          middleName: middleName.isEmpty ? null : middleName,
          createdAt: now,
          updatedAt: now,
        );

        final studentIdDb = await _repo.insertStudent(student);
        importedCount++;

        // Automatically enroll to current class
        await _repo.enrollStudentToClass(widget.classModel.id!, studentIdDb);
        enrolledCount++;

        print(
          '[EnrollStudentsScreen] Row ${i + 1}: Imported and enrolled student: $firstName $lastName ($studentId)',
        );
      }

      print(
        '[EnrollStudentsScreen] Processing complete - Imported: $importedCount, Enrolled: $enrolledCount, Skipped: $skippedCount',
      );

      // Refresh the student list
      await _load();

      // Show results
      if (mounted) {
        String message =
            'Import completed: $importedCount students imported, $enrolledCount enrolled';
        if (skippedCount > 0) {
          message += ', $skippedCount skipped';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            action: skippedCount > 0
                ? SnackBarAction(
                    label: 'Details',
                    onPressed: () => _showImportDetails(skippedStudents),
                  )
                : null,
          ),
        );
      }

      print(
        '[EnrollStudentsScreen] XLSX import completed: $importedCount imported, $enrolledCount enrolled, $skippedCount skipped',
      );
    } catch (e) {
      print('[EnrollStudentsScreen] XLSX import error: $e');
      print('[EnrollStudentsScreen] XLSX stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('XLSX import failed: $e')));
      }
    }
  }

  Future<void> _importFromCSV(Uint8List bytes) async {
    try {
      // Parse CSV content manually
      final content = utf8.decode(bytes);
      final lines = content.split('\n');
      final List<List<dynamic>> rows = [];

      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          // Simple CSV parsing - split by comma and handle quotes
          final List<String> cells = [];
          String currentCell = '';
          bool inQuotes = false;

          for (int i = 0; i < line.length; i++) {
            final char = line[i];
            if (char == '"') {
              inQuotes = !inQuotes;
            } else if (char == ',' && !inQuotes) {
              cells.add(currentCell.trim());
              currentCell = '';
            } else {
              currentCell += char;
            }
          }
          cells.add(currentCell.trim()); // Add last cell
          rows.add(cells);
        }
      }

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('CSV file is empty')));
        }
        return;
      }

      // Validate headers
      final headers = rows[0]
          .map((h) => h.toString().toLowerCase().trim())
          .toList();
      final requiredHeaders = [
        'id number',
        'firstname',
        'middle name',
        'lastname',
      ];

      for (final required in requiredHeaders) {
        if (!headers.contains(required)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Missing required header: $required')),
            );
          }
          return;
        }
      }

      // Get header indices
      final idIndex = headers.indexOf('id number');
      final firstNameIndex = headers.indexOf('firstname');
      final middleNameIndex = headers.indexOf('middle name');
      final lastNameIndex = headers.indexOf('lastname');

      int importedCount = 0;
      int enrolledCount = 0;
      int skippedCount = 0;
      List<String> skippedStudents = [];

      // Process each row (skip header row)
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        // Skip empty rows
        if (row.isEmpty ||
            row.every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }

        // Extract student data
        final studentId = row[idIndex].toString().trim();
        final firstName = row[firstNameIndex].toString().trim();
        final middleName = row[middleNameIndex].toString().trim();
        final lastName = row[lastNameIndex].toString().trim();

        // Validate required fields
        if (studentId.isEmpty || firstName.isEmpty || lastName.isEmpty) {
          skippedCount++;
          skippedStudents.add('Row $i: Missing required fields');
          continue;
        }

        // Check for duplicate ID
        final isDuplicate = await _repo.isStudentIdDuplicate(studentId);
        if (isDuplicate) {
          skippedCount++;
          skippedStudents.add('Row $i: Duplicate ID $studentId');
          continue;
        }

        // Check for duplicate name (case-insensitive)
        final existingStudents = await _repo.getAllStudents();
        final nameExists = existingStudents.any(
          (s) =>
              s.firstName.toLowerCase() == firstName.toLowerCase() &&
              s.lastName.toLowerCase() == lastName.toLowerCase() &&
              (s.middleName?.toLowerCase() ?? '') ==
                  (middleName.isEmpty ? '' : middleName.toLowerCase()),
        );

        if (nameExists) {
          skippedCount++;
          skippedStudents.add(
            'Row $i: Duplicate name $firstName $middleName $lastName',
          );
          continue;
        }

        // Create and insert student
        final now = DateTime.now().toIso8601String();
        final student = Student(
          studentId: studentId,
          firstName: firstName,
          lastName: lastName,
          middleName: middleName.isEmpty ? null : middleName,
          createdAt: now,
          updatedAt: now,
        );

        final studentIdDb = await _repo.insertStudent(student);
        importedCount++;

        // Automatically enroll to current class
        await _repo.enrollStudentToClass(widget.classModel.id!, studentIdDb);
        enrolledCount++;

        print(
          '[EnrollStudentsScreen] Imported and enrolled student: $firstName $lastName ($studentId)',
        );
      }

      // Refresh the student list
      await _load();

      // Show results
      if (mounted) {
        String message =
            'Import completed: $importedCount students imported, $enrolledCount enrolled';
        if (skippedCount > 0) {
          message += ', $skippedCount skipped';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            action: skippedCount > 0
                ? SnackBarAction(
                    label: 'Details',
                    onPressed: () => _showImportDetails(skippedStudents),
                  )
                : null,
          ),
        );
      }

      print(
        '[EnrollStudentsScreen] CSV import completed: $importedCount imported, $enrolledCount enrolled, $skippedCount skipped',
      );
    } catch (e) {
      print('[EnrollStudentsScreen] CSV import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV import failed: $e')));
      }
    }
  }

  void _showImportDetails(List<String> skippedStudents) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Details'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: skippedStudents.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                skippedStudents[index],
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
            title: 'Enroll Students',
            subtitle: widget.classModel.displayName,
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: [
              IconButton(
                tooltip: 'Download Template',
                icon: Icon(PlatformIcons.download, color: Colors.white),
                onPressed: _downloadTemplate,
              ),
              IconButton(
                tooltip: 'Import Excel',
                icon: Icon(PlatformIcons.uploadFile, color: Colors.white),
                onPressed: _importFromExcel,
              ),
            ],
            chips: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(color: Colors.white, width: 3),
                    insets: EdgeInsets.symmetric(horizontal: 24),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Enrolled (${_enrolled.length})'),
                    Tab(text: 'Available (${_available.length})'),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by name or ID...',
                            hintStyle: const TextStyle(
                              color: AppTheme.textLight,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              PlatformIcons.search,
                              color: gradientColors[0],
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      PlatformIcons.clear,
                                      color: gradientColors[0],
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: gradientColors[0].withValues(alpha: 0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: gradientColors[0].withValues(alpha: 0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: gradientColors[0],
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _StudentTab(
                              students: _filterStudents(_enrolled),
                              actionIcon: PlatformIcons.removeCircleOutline,
                              actionColor: AppTheme.danger,
                              emptyText: _searchQuery.isEmpty
                                  ? 'No students enrolled'
                                  : 'No students found',
                              onAction: _unenroll,
                              gradientColors: gradientColors,
                            ),
                            _StudentTab(
                              students: _filterStudents(_available),
                              actionIcon: PlatformIcons.addCircleOutline,
                              actionColor: AppTheme.success,
                              emptyText: _searchQuery.isEmpty
                                  ? 'All students are enrolled'
                                  : 'No students found',
                              onAction: _enroll,
                              gradientColors: gradientColors,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudentTab extends StatelessWidget {
  final List<Student> students;
  final IconData actionIcon;
  final Color actionColor;
  final String emptyText;
  final void Function(Student) onAction;
  final List<Color> gradientColors;

  const _StudentTab({
    required this.students,
    required this.actionIcon,
    required this.actionColor,
    required this.emptyText,
    required this.onAction,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PlatformIcons.people,
              size: 56,
              color: AppTheme.textLight.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              emptyText,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = students[i];
        final initials = '${s.firstName[0]}${s.lastName[0]}'.toUpperCase();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'ID: ${s.studentId}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onAction(s),
                icon: Icon(actionIcon, color: actionColor),
              ),
            ],
          ),
        );
      },
    );
  }
}
