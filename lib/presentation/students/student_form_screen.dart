import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../home/home_screen.dart';

class StudentFormScreen extends StatefulWidget {
  final Student? student;

  const StudentFormScreen({super.key, this.student});

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final StudentRepository _repo = StudentRepository();
  final AuthRepository _authRepo = AuthRepository();
  final List<_NavItem> _navItems = [
    _NavItem(icon: PlatformIcons.dashboard, label: 'Dashboard'),
    _NavItem(icon: PlatformIcons.students, label: 'Students'),
    _NavItem(icon: PlatformIcons.classes, label: 'Classes'),
    _NavItem(icon: PlatformIcons.analytics, label: 'Analytics'),
    _NavItem(icon: PlatformIcons.settings, label: 'Settings'),
  ];

  late final TextEditingController _idController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  String? _selectedGender;
  bool _isSaving = false;
  bool get _isEditing => widget.student != null;
  String? _photoBase64;

  Timer? _idSearchDebounce;
  bool _isIdSearching = false;
  List<Map<String, dynamic>> _idSuggestions = [];

  ImageProvider? _photoImageProvider() {
    final data = _photoBase64;
    if (data == null || data.isEmpty) return null;
    try {
      final bytes = base64Decode(data);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (e) {
      print('[StudentFormScreen] Invalid photo data, ignoring: $e');
      return null;
    }
  }

  final List<String> _genders = ['Male', 'Female'];

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    _idController = TextEditingController(text: s?.studentId ?? '');
    _firstNameController = TextEditingController(text: s?.firstName ?? '');
    _lastNameController = TextEditingController(text: s?.lastName ?? '');
    _middleNameController = TextEditingController(text: s?.middleName ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    final gender = s?.gender;
    _selectedGender = gender != null && _genders.contains(gender)
        ? gender
        : null;
    _photoBase64 = s?.photoPath;

    _idController.addListener(_onStudentIdChanged);
  }

  @override
  void dispose() {
    _idSearchDebounce?.cancel();
    _idController.removeListener(_onStudentIdChanged);
    _idController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onStudentIdChanged() {
    if (_isEditing) return;
    final q = _idController.text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _idSuggestions = []);
      return;
    }

    _idSearchDebounce?.cancel();
    _idSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchStudentIdSuggestions(q);
    });
  }

  Future<void> _searchStudentIdSuggestions(String query) async {
    if (_isEditing) return;
    final q = query.trim();
    if (q.length < 2) {
      if (mounted) setState(() => _idSuggestions = []);
      return;
    }

    if (mounted) {
      setState(() {
        _isIdSearching = true;
      });
    }

    try {
      final user = await _authRepo.getActiveUser();
      if (user == null) {
        print('[StudentFormScreen] Student ID lookup skipped: no active user');
        if (mounted) setState(() => _idSuggestions = []);
        return;
      }

      final userId = user.uid;
      final col = FirebaseFirestore.instance.collection(
        'users/$userId/students',
      );
      final snap = await col
          .where('student_id', isGreaterThanOrEqualTo: q)
          .where('student_id', isLessThan: '$q\uf8ff')
          .limit(8)
          .get();

      final suggestions = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        suggestions.add({...d.data(), 'doc_id': d.id});
      }

      print(
        '[StudentFormScreen] Firebase suggestions query="$q" returned ${suggestions.length}',
      );

      if (!mounted) return;
      // If user already changed the input, ignore this result.
      if (_idController.text.trim() != q) return;

      setState(() {
        _idSuggestions = suggestions;
      });
    } catch (e) {
      print('[StudentFormScreen] Firebase lookup error for "$q": $e');
      if (!mounted) return;
      setState(() => _idSuggestions = []);
    } finally {
      if (mounted) setState(() => _isIdSearching = false);
    }
  }

  void _applySuggestion(Map<String, dynamic> s) {
    final sid = (s['student_id'] as String?) ?? '';
    print('[StudentFormScreen] Applying Firebase suggestion student_id=$sid');

    setState(() {
      _idController.text = sid;
      _firstNameController.text = (s['first_name'] as String?) ?? '';
      _lastNameController.text = (s['last_name'] as String?) ?? '';
      _middleNameController.text = (s['middle_name'] as String?) ?? '';
      _emailController.text = (s['email'] as String?) ?? '';
      _phoneController.text = (s['phone'] as String?) ?? '';
      _addressController.text = (s['address'] as String?) ?? '';
      final genderValue = (s['gender'] as String?)?.trim();
      _selectedGender =
          genderValue != null &&
              genderValue.isNotEmpty &&
              _genders.contains(genderValue)
          ? genderValue
          : null;
      final photo = (s['photo_path'] as String?) ?? '';
      _photoBase64 = photo.isEmpty ? null : photo;
      _idSuggestions = [];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student data loaded from Firebase'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final isDuplicate = await _repo.isStudentIdDuplicate(
        _idController.text.trim(),
        excludeId: widget.student?.id,
      );
      if (isDuplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Student ID already exists. Please use a unique ID.',
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }
      if (_isEditing) {
        final updated = widget.student!.copyWith(
          studentId: _idController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          middleName: _middleNameController.text.trim().isEmpty
              ? null
              : _middleNameController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          gender: _selectedGender,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          photoPath: _photoBase64,
          updatedAt: now,
        );
        final count = await _repo.updateStudent(updated);
        print(
          '[StudentFormScreen] Updated student id=${updated.id}: $count rows',
        );
      } else {
        final student = Student(
          studentId: _idController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          middleName: _middleNameController.text.trim().isEmpty
              ? null
              : _middleNameController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          gender: _selectedGender,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          photoPath: _photoBase64,
          createdAt: now,
          updatedAt: now,
        );
        final id = await _repo.insertStudent(student);
        print('[StudentFormScreen] Inserted student id=$id');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('[StudentFormScreen] Error: $e');
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Student'),
        content: Text(
          'Are you sure you want to delete ${widget.student!.fullName}? This action cannot be undone.',
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
    if (confirmed != true) return;
    try {
      await _repo.deleteStudent(widget.student!.id!);
      print('[StudentFormScreen] Deleted student id=${widget.student!.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('[StudentFormScreen] Delete error: $e');
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();

    // Let user choose between camera and gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PlatformIcons.camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: Icon(PlatformIcons.photoLibrary),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Convert image to Base64
      final bytes = await File(picked.path).readAsBytes();
      final base64String = base64Encode(bytes);

      setState(() {
        _photoBase64 = base64String;
      });

      print(
        '[StudentFormScreen] Selected photo from $source, encoded to Base64 (${base64String.length} chars)',
      );
    } catch (e) {
      print('[StudentFormScreen] Error picking photo: $e');
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
            title: widget.student == null ? 'Add Student' : 'Edit Student',
            subtitle: 'Student Information',
            gradientColors: gradientColors,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(PlatformIcons.back, color: Colors.white),
            ),
            actions: _isEditing
                ? [
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(PlatformIcons.delete, color: Colors.white70),
                    ),
                  ]
                : null,
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE8ECF4)),
                    ),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: themeProvider.primaryColor
                                .withValues(alpha: 0.1),
                            backgroundImage: _photoImageProvider(),
                            child: _photoImageProvider() == null
                                ? Icon(
                                    PlatformIcons.person,
                                    color: themeProvider.primaryColor,
                                    size: 30,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Student Photo (Optional)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Add a photo to make the student easier to recognize.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _pickPhoto,
                            icon: Icon(PlatformIcons.photoLibrary),
                            label: const Text('Choose'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Basic Information',
                    children: [
                      _FieldLabel('Student ID *'),
                      TextFormField(
                        controller: _idController,
                        decoration: InputDecoration(
                          hintText: 'e.g. 2024-0001',
                          prefixIcon: Icon(PlatformIcons.idNumber),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      if (!_isEditing &&
                          (_isIdSearching || _idSuggestions.isNotEmpty))
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: _isIdSearching
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              themeProvider.primaryColor,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Searching in Firebase...',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Suggestions from Firebase',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ..._idSuggestions.map((s) {
                                      final sid =
                                          (s['student_id'] as String?) ?? '';
                                      final fn =
                                          (s['first_name'] as String?) ?? '';
                                      final ln =
                                          (s['last_name'] as String?) ?? '';
                                      final name = ('$fn $ln').trim();
                                      return InkWell(
                                        onTap: () => _applySuggestion(s),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                PlatformIcons.cloudDownload,
                                                size: 18,
                                                color:
                                                    themeProvider.primaryColor,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      sid,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    if (name.isNotEmpty)
                                                      Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black54,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                PlatformIcons.forward,
                                                size: 14,
                                                color: Colors.black26,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                        ),
                      const SizedBox(height: 14),
                      _FieldLabel('First Name *'),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'First name',
                          prefixIcon: Icon(PlatformIcons.personOutline),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Last Name *'),
                      TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Last name',
                          prefixIcon: Icon(PlatformIcons.personOutline),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Middle Name'),
                      TextFormField(
                        controller: _middleNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Middle name (optional)',
                          prefixIcon: Icon(PlatformIcons.personOutline),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Gender'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedGender,
                        hint: const Text('Select gender'),
                        icon: Icon(PlatformIcons.dropdown),
                        decoration: InputDecoration(
                          prefixIcon: Icon(PlatformIcons.gender),
                        ),
                        items: _genders
                            .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Contact Information',
                    children: [
                      _FieldLabel('Email'),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'student@email.com',
                          prefixIcon: Icon(PlatformIcons.email),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Phone'),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '09XX-XXX-XXXX',
                          prefixIcon: Icon(PlatformIcons.phone),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Address'),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Home address',
                          prefixIcon: Icon(PlatformIcons.location),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isEditing ? 'Save Changes' : 'Add Student',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: 1,
        items: _navItems,
        onTap: (i) {
          if (i == 1) {
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

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}
