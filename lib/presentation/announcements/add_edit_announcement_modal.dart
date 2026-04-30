import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/announcement_model.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../core/utils/platform_icons.dart';

class AddEditAnnouncementModal extends StatefulWidget {
  final int classId;
  final String className;
  final Announcement? announcement;

  const AddEditAnnouncementModal({
    super.key,
    required this.classId,
    required this.className,
    this.announcement,
  });

  @override
  State<AddEditAnnouncementModal> createState() =>
      _AddEditAnnouncementModalState();
}

class _AddEditAnnouncementModalState extends State<AddEditAnnouncementModal> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _hasInternetConnection = true;

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    if (widget.announcement != null) {
      _titleController.text = widget.announcement!.title;
      _contentController.text = widget.announcement!.content;
    }
  }

  Future<void> _checkInternetConnection() async {
    try {
      // Try to reach Firebase to check internet connection
      await FirebaseFirestore.instance.collection('test').limit(1).get();
      setState(() {
        _hasInternetConnection = true;
      });
    } catch (e) {
      setState(() {
        _hasInternetConnection = false;
      });
    }
  }

  Future<void> _saveAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasInternetConnection) {
      _showErrorDialog(
        'No Internet Connection',
        'Announcements require an internet connection to be saved to Firebase. Please check your connection and try again.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = await AuthRepository().getActiveUser();
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get class remote ID
      final classInfo = await SubjectRepository().getClassById(widget.classId);
      if (classInfo?.remoteId == null) {
        throw Exception('Class information not found');
      }

      if (widget.announcement == null) {
        // Create new announcement
        await AnnouncementRepository.instance.createAnnouncement(
          teacherId: currentUser.uid,
          classId: classInfo!.remoteId!,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
        );
      } else {
        // Update existing announcement
        await AnnouncementRepository.instance.updateAnnouncement(
          announcementId: widget.announcement!.remoteId!,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.announcement == null
                  ? 'Announcement created successfully'
                  : 'Announcement updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      print('[AddEditAnnouncementModal] Error saving announcement: $e');
      _showErrorDialog('Error', 'Failed to save announcement: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.announcement != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(PlatformIcons.close),
                ),
                Expanded(
                  child: Text(
                    isEditing ? 'Edit Announcement' : 'New Announcement',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48), // Balance the close button
              ],
            ),
          ),

          // Internet connection status
          if (!_hasInternetConnection)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.red[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No internet connection. Announcements require internet to sync with Firebase.',
                      style: TextStyle(color: Colors.red[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Class info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            PlatformIcons.classes,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.className,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title field
                    Text(
                      'Title',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        hintText: 'Enter announcement title',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        if (value.trim().length < 3) {
                          return 'Title must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Content field
                    Text(
                      'Content',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: 'Enter announcement content',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 8,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter announcement content';
                        }
                        if (value.trim().length < 10) {
                          return 'Content must be at least 10 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Character count
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_contentController.text.length} characters',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveAnnouncement,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEditing
                                    ? 'Update Announcement'
                                    : 'Create Announcement',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}
