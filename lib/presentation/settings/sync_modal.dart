import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/sync_service.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/utils/platform_icons.dart';
import 'table_selection_dialog.dart';

class SyncModal extends StatefulWidget {
  final int? classId;
  final String? syncDirection; // 'upload', 'download', or null for both
  final List<String>? selectedTables; // Pre-selected tables to sync

  const SyncModal({
    super.key,
    this.classId,
    this.syncDirection,
    this.selectedTables,
  });

  @override
  State<SyncModal> createState() => _SyncModalState();
}

class _SyncModalState extends State<SyncModal>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _status = 'Initializing sync...';
  SyncResult? _result;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();

    // Set initial status based on sync direction
    if (widget.syncDirection == 'upload') {
      _status = 'Uploading to cloud...';
    } else if (widget.syncDirection == 'download') {
      _status = 'Downloading from cloud...';
    } else {
      _status = 'Initializing sync...';
    }

    _startSync();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    try {
      final result = widget.classId == null
          ? await SyncService.syncAll(
              direction: widget.syncDirection,
              selectedTables: widget.selectedTables,
              onStatusUpdate: (status) {
                if (mounted) {
                  setState(() {
                    _status = status;
                  });
                }
                print('[SyncModal] Status update: $status');
              },
            )
          : await SyncService.syncClass(widget.classId!);

      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
          if (result.success) {
            if (widget.syncDirection == 'upload') {
              _status = 'Upload completed successfully!';
            } else if (widget.syncDirection == 'download') {
              _status = 'Download completed successfully!';
            } else {
              _status = 'Sync completed successfully!';
            }
          } else {
            final error = result.error ?? '';
            if (error.contains('No internet connection')) {
              _status = 'No internet connection. Sync cancelled.';
            } else {
              if (widget.syncDirection == 'upload') {
                _status = 'Upload failed';
              } else if (widget.syncDirection == 'download') {
                _status = 'Download failed';
              } else {
                _status = 'Sync failed';
              }
            }
          }
        });
      }
      print('[SyncModal] Sync result: ${result.summary()}');
      if (result.error != null && result.error!.isNotEmpty) {
        print('[SyncModal] Sync returned error: ${result.error}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = SyncResult()..error = e.toString();
          _isLoading = false;
          _status = 'Sync failed';
        });
      }
      print('[SyncModal] Sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final gradientColors = themeProvider.getGradientColors();

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon/Animation
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: _isLoading
                      ? LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : _result?.success == true
                      ? const LinearGradient(
                          colors: [AppTheme.success, Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [AppTheme.danger, Color(0xFFEF4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  shape: BoxShape.circle,
                ),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        _result?.success == true
                            ? PlatformIcons.checkCircle
                            : PlatformIcons.error,
                        color: Colors.white,
                        size: 48,
                      ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                _isLoading
                    ? 'Syncing...'
                    : _result?.success == true
                    ? 'Success!'
                    : 'Error',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Status message
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),

              // Result details (if completed)
              if (!_isLoading && _result != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _result!.success
                      ? Column(
                          children: [
                            if (widget.syncDirection != 'download')
                              _StatRow(
                                icon: PlatformIcons.cloudUpload,
                                label: 'Uploaded',
                                value: '${_result!.uploaded}',
                                color: const Color(0xFF0891B2),
                              ),
                            if (widget.syncDirection != null &&
                                widget.syncDirection != 'download' &&
                                widget.syncDirection != 'upload')
                              const SizedBox(height: 8),
                            if (widget.syncDirection != 'upload')
                              _StatRow(
                                icon: PlatformIcons.cloudDownload,
                                label: 'Downloaded',
                                value: '${_result!.downloaded}',
                                color: const Color(0xFF8B5CF6),
                              ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(
                              PlatformIcons.warning,
                              color: AppTheme.danger,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _result!.error ?? 'Unknown error',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],

              // Action button
              if (!_isLoading) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_result?.success == true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _result?.success == true
                          ? AppTheme.success
                          : AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _result?.success == true ? 'Done' : 'Close',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
