import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
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
import '../../core/services/auth_service.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_repository.dart';
import 'student_form_screen.dart';
import 'student_profile_screen.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final StudentRepository _repo = StudentRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  List<Student> _students = [];
  List<Student> _filtered = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  void _openAppSettings() async {
    await openAppSettings();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = kIsWeb
          ? await _loadWebStudents()
          : await _repo.getAllStudents();
      print('[StudentListScreen] Loaded ${list.length} students');
      if (mounted) {
        setState(() {
          _students = list;
          _filtered = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[StudentListScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Student>> _loadWebStudents() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      print('[StudentListScreen] Web student load skipped: no Firebase user');
      return <Student>[];
    }

    final studentsSnap = await _firestore
        .collection('users/${firebaseUser.uid}/students')
        .get();

    final now = DateTime.now().toIso8601String();
    final list =
        studentsSnap.docs
            .map((doc) => doc.data())
            .where((data) {
              final deleted = data['deleted'];
              if (deleted is bool) return !deleted;
              if (deleted is int) return deleted != 1;
              if (deleted is String) {
                final normalized = deleted.toLowerCase();
                return normalized != '1' && normalized != 'true';
              }
              return true;
            })
            .map(
              (data) => Student(
                id: data['id'] is int ? data['id'] as int : null,
                studentId: data['student_id']?.toString() ?? '',
                firstName: data['first_name']?.toString() ?? '',
                lastName: data['last_name']?.toString() ?? '',
                middleName: data['middle_name']?.toString(),
                email: data['email']?.toString(),
                phone: data['phone']?.toString(),
                gender: data['gender']?.toString(),
                birthDate: data['birth_date']?.toString(),
                address: data['address']?.toString(),
                photoPath: data['photo_path']?.toString(),
                createdAt: data['created_at']?.toString() ?? now,
                updatedAt: data['updated_at']?.toString() ?? now,
              ),
            )
            .where(
              (student) =>
                  student.studentId.trim().isNotEmpty &&
                  student.firstName.trim().isNotEmpty &&
                  student.lastName.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final lastNameCompare = a.lastName.toLowerCase().compareTo(
              b.lastName.toLowerCase(),
            );
            if (lastNameCompare != 0) return lastNameCompare;
            return a.firstName.toLowerCase().compareTo(
              b.firstName.toLowerCase(),
            );
          });

    print(
      '[StudentListScreen] Web students loaded uid=${firebaseUser.uid} count=${list.length}',
    );
    return list;
  }

  void _search(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _students;
      } else {
        _filtered = _students.where((s) {
          final q = query.toLowerCase();
          return s.fullName.toLowerCase().contains(q) ||
              s.studentId.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _addStudent() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const StudentFormScreen()),
    );
    if (result == true) _load();
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
            '[StudentListScreen] Created Downloads directory: ${downloadsDir.path}',
          );
        } catch (e) {
          print('[StudentListScreen] Failed to create Downloads directory: $e');
          // Fallback to app documents directory
          downloadsDir = await getApplicationDocumentsDirectory();
          print(
            '[StudentListScreen] Using fallback directory: ${downloadsDir.path}',
          );
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'StudentImportTemplate_$timestamp.xlsx';
      final path = '${downloadsDir.path}/$fileName';
      final file = File(path);

      print('[StudentListScreen] Attempting to save template to: $path');
      print(
        '[StudentListScreen] Downloads directory exists: ${await downloadsDir.exists()}',
      );
      print(
        '[StudentListScreen] Directory permissions: ${await downloadsDir.list().isEmpty ? 'empty' : 'has files'}',
      );

      final bytes = workbook.saveAsStream();
      await file.writeAsBytes(bytes);
      workbook.dispose();

      // Verify file was created
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      print(
        '[StudentListScreen] Template download result: exists=$fileExists, size=$fileSize bytes',
      );
      print('[StudentListScreen] Template downloaded to device storage: $path');

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
      print('[StudentListScreen] Template download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating template: $e')),
        );
      }
    }
  }

  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );
      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;
      final bytes = file.bytes!;
      final fileName = file.name.toLowerCase();

      if (fileName.endsWith('.csv')) {
        await _importFromCSV(bytes);
      } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
        await _importFromXLSX(bytes);
      }
    } catch (e) {
      print('[StudentListScreen] Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _importFromXLSX(Uint8List bytes) async {
    try {
      // Parse Excel file
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel file has no sheets')),
          );
        }
        return;
      }

      // Get first sheet
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Excel sheet is empty')));
        }
        return;
      }

      // Validate headers (first row)
      final headerRow = sheet.rows[0];
      final headers = headerRow
          .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
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

      final studentRepo = StudentRepository();
      int importedCount = 0;
      int skippedCount = 0;
      List<String> skippedStudents = [];

      // Process each row (skip header row)
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];

        // Skip empty rows
        if (row.isEmpty ||
            row.every(
              (cell) => cell?.value?.toString().trim().isEmpty ?? true,
            )) {
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

        // Validate required fields
        if (studentId.isEmpty || firstName.isEmpty || lastName.isEmpty) {
          skippedCount++;
          skippedStudents.add('Row ${i + 1}: Missing required fields');
          continue;
        }

        // Check for duplicate ID
        final isDuplicate = await studentRepo.isStudentIdDuplicate(studentId);
        if (isDuplicate) {
          skippedCount++;
          skippedStudents.add('Row ${i + 1}: Duplicate ID $studentId');
          continue;
        }

        // Check for duplicate name (case-insensitive)
        final existingStudents = await studentRepo.getAllStudents();
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

        await studentRepo.insertStudent(student);
        importedCount++;

        print(
          '[StudentListScreen] Imported student: $firstName $lastName ($studentId)',
        );
      }

      // Refresh the student list
      await _load();

      // Show results
      if (mounted) {
        String message = 'Import completed: $importedCount students imported';
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
        '[StudentListScreen] XLSX import completed: $importedCount imported, $skippedCount skipped',
      );
    } catch (e) {
      print('[StudentListScreen] XLSX import error: $e');
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

      final studentRepo = StudentRepository();
      int importedCount = 0;
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
        final isDuplicate = await studentRepo.isStudentIdDuplicate(studentId);
        if (isDuplicate) {
          skippedCount++;
          skippedStudents.add('Row $i: Duplicate ID $studentId');
          continue;
        }

        // Check for duplicate name (case-insensitive)
        final existingStudents = await studentRepo.getAllStudents();
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

        await studentRepo.insertStudent(student);
        importedCount++;

        print(
          '[StudentListScreen] Imported student: $firstName $lastName ($studentId)',
        );
      }

      // Refresh the student list
      await _load();

      // Show results
      if (mounted) {
        String message = 'Import completed: $importedCount students imported';
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
        '[StudentListScreen] Import completed: $importedCount imported, $skippedCount skipped',
      );
    } catch (e) {
      print('[StudentListScreen] CSV import error: $e');
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

  Future<void> _openProfile(Student student) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StudentProfileScreen(student: student)),
    );
    if (result == true) _load();
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
            title: 'Students',
            subtitle: '${_students.length} total students',
            gradientColors: gradientColors,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(PlatformIcons.refresh, color: Colors.white),
                onPressed: _load,
              ),
              IconButton(
                tooltip: 'Logout',
                icon: Icon(PlatformIcons.logout, color: Colors.white),
                onPressed: () => AuthService.signOutAndGoToLogin(context),
              ),
            ],
            chips: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(PlatformIcons.search, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _search,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search students...',
                          hintStyle: TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Scrollable Student List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PlatformIcons.people,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No students yet'
                              : 'No students found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      itemCount: _filtered.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: () {
                          final w = MediaQuery.of(context).size.width;
                          // Responsive columns: Minimum 3 cards per row
                          if (w >= 1200) return 6; // Large desktop
                          if (w >= 1000) return 5; // Tablet/Large tablet
                          if (w >= 800) return 4; // Small tablet
                          if (w >= 600) return 3; // Large mobile
                          return 3; // Small mobile - minimum 3 cards
                        }(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.92,
                      ),
                      itemBuilder: (context, i) => _StudentCard(
                        student: _filtered[i],
                        onTap: () => _openProfile(_filtered[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_students_add',
        onPressed: _addStudent,
        backgroundColor: themeProvider.primaryColor,
        child: Icon(PlatformIcons.personAdd, color: Colors.white),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback onTap;

  const _StudentCard({required this.student, required this.onTap});

  ImageProvider? _photoProvider() {
    final data = student.photoPath;
    if (data == null || data.isEmpty) return null;
    try {
      final bytes = base64Decode(data);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (e) {
      print('[StudentListScreen] Invalid student photo, ignoring: $e');
      return null;
    }
  }

  Color _getRandomColor() {
    // Generate consistent color based on student ID hash
    final hash = student.studentId.hashCode;
    final colors = [
      const Color(0xFF4A90E2), // Blue
      const Color(0xFF50C878), // Green
      const Color(0xFFFF6B6B), // Red
      const Color(0xFF9B59B6), // Purple
      const Color(0xFFF39C12), // Orange
      const Color(0xFF1ABC9C), // Teal
      const Color(0xFFE74C3C), // Coral
      const Color(0xFF3498DB), // Sky Blue
      const Color(0xFF2ECC71), // Emerald
      const Color(0xFFE67E22), // Carrot
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final initials = '${student.firstName[0]}${student.lastName[0]}'
        .toUpperCase();
    final gradientColors = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).getGradientColors();
    final photo = _photoProvider();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8ECF4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const baseHeight = 120.0;
              final scale = (constraints.maxHeight / baseHeight)
                  .clamp(0.75, 1.0)
                  .toDouble();

              final avatarSize = (48.0 * scale).clamp(36.0, 48.0);
              final nameFontSize = (12.0 * scale).clamp(10.0, 12.0);
              final idFontSize = (11.0 * scale).clamp(9.5, 11.0);
              final initialsFontSize = (15.0 * scale).clamp(12.0, 15.0);
              final gapLarge = (8.0 * scale).clamp(4.0, 8.0);
              final gapSmall = (4.0 * scale).clamp(2.0, 4.0);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: photo == null ? _getRandomColor() : null,
                      gradient: photo == null
                          ? null
                          : LinearGradient(
                              colors: gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      image: photo != null
                          ? DecorationImage(image: photo, fit: BoxFit.cover)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: photo == null
                        ? Text(
                            initials,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: initialsFontSize,
                            ),
                          )
                        : null,
                  ),
                  SizedBox(height: gapLarge),
                  Text(
                    student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: nameFontSize,
                      color: const Color(0xFF1A2340),
                    ),
                  ),
                  SizedBox(height: gapSmall),
                  Text(
                    student.studentId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: idFontSize,
                      color: const Color(0xFF6B7A99),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
