import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';

class AttendanceSelfieResult {
  const AttendanceSelfieResult({
    required this.base64,
    required this.mime,
    required this.bytes,
  });

  final String base64;
  final String mime;
  final Uint8List bytes;
}

/// Capture a front-camera selfie for attendance (no face recognition).
Future<AttendanceSelfieResult?> showAttendanceSelfieSheet(
  BuildContext context, {
  required String staffName,
  required String actionLabel,
}) {
  return showDialog<AttendanceSelfieResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _AttendanceSelfieDialog(
      staffName: staffName,
      actionLabel: actionLabel,
    ),
  );
}

class _AttendanceSelfieDialog extends StatefulWidget {
  const _AttendanceSelfieDialog({
    required this.staffName,
    required this.actionLabel,
  });

  final String staffName;
  final String actionLabel;

  @override
  State<_AttendanceSelfieDialog> createState() =>
      _AttendanceSelfieDialogState();
}

class _AttendanceSelfieDialogState extends State<_AttendanceSelfieDialog> {
  final _picker = ImagePicker();
  Uint8List? _preview;
  String _mime = 'image/jpeg';
  bool _busy = false;
  String? _error;

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final path = picked.path.toLowerCase();
      final mime = path.endsWith('.png')
          ? 'image/png'
          : path.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      if (!mounted) return;
      setState(() {
        _preview = bytes;
        _mime = mime;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Could not open camera. Check camera permission and try again.';
      });
    }
  }

  void _confirm() {
    final bytes = _preview;
    if (bytes == null) return;
    Navigator.of(context).pop(
      AttendanceSelfieResult(
        base64: base64Encode(bytes),
        mime: _mime,
        bytes: bytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.actionLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.staffName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Take a selfie to record this punch. No face recognition.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.softSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _preview != null
                          ? Image.memory(_preview!, fit: BoxFit.cover)
                          : const Center(
                              child: Icon(
                                Icons.photo_camera_front_outlined,
                                size: 48,
                                color: AppColors.muted,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _preview == null
                                  ? Icons.camera_alt_outlined
                                  : Icons.refresh,
                            ),
                      label: Text(_preview == null ? 'Take photo' : 'Retake'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _preview == null || _busy ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Use photo'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
