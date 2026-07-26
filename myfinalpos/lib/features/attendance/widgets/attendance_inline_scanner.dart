import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/attendance_board.dart';
import '../attendance_formatters.dart';
import '../../pos/widgets/app_shell_scaffold.dart';
import 'attendance_live_clock.dart';
import 'face_scanner_engine.dart';

typedef FaceDescriptorHandler = Future<void> Function(List<double> descriptor);

/// Always-on face scanner embedded on the attendance page (mirrors web terminal).
class AttendanceInlineScanner extends StatefulWidget {
  const AttendanceInlineScanner({
    super.key,
    required this.onDescriptor,
    this.busy = false,
    this.expand = false,
    this.schedule,
    this.clockEnabled = true,
  });

  final FaceDescriptorHandler onDescriptor;
  final bool busy;
  final bool expand;
  final AttendanceSchedule? schedule;
  final bool clockEnabled;

  @override
  State<AttendanceInlineScanner> createState() => _AttendanceInlineScannerState();
}

class _AttendanceInlineScannerState extends State<AttendanceInlineScanner> {
  FaceScannerEngine? _engine;
  var _started = false;
  var _ready = false;
  var _modelsReady = false;
  var _cameraOn = false;
  var _scanning = false;
  var _openingCamera = false;
  String? _error;
  String _status = 'Starting camera…';
  Size? _viewSize;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _engine?.dispose();
    final engine = createFaceScannerEngine();
    _engine = engine;

    final permissionError = await engine.start(_onScannerMessage);
    if (!mounted) return;

    if (permissionError != null) {
      setState(() {
        _started = false;
        _ready = false;
        _cameraOn = false;
        _error = permissionError;
        _status = 'Camera denied';
      });
      return;
    }

    setState(() {
      _started = true;
      _error = null;
      _status = 'Loading face models…';
    });
  }

  Future<void> _openCamera() async {
    if (_engine == null || !_modelsReady || _cameraOn || _openingCamera) return;
    setState(() {
      _openingCamera = true;
      _error = null;
      _status = 'Opening camera…';
    });
    await _engine!.openCamera();
    if (mounted) {
      setState(() => _openingCamera = false);
    }
  }

  void _reset() {
    setState(() {
      _scanning = false;
      _error = null;
      _status = _ready ? 'Face the camera inside the oval' : _status;
    });
  }

  Future<void> _syncLayout() async {
    if (!kIsWeb || !mounted || !_started || _engine == null) return;

    final size = _viewSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;

    await _engine!.syncLayout(
      size.width,
      size.height,
      size.width >= size.height,
    );
  }

  void _onScannerMessage(Map<String, dynamic> payload) {
    if (!mounted) return;

    final type = payload['type']?.toString() ?? '';

    switch (type) {
      case 'status':
        setState(() {
          _status = payload['message']?.toString() ?? _status;
        });
        break;
      case 'models_ready':
        setState(() {
          _modelsReady = true;
          _status = 'Opening camera…';
        });
        _openCamera();
        break;
      case 'camera':
      case 'ready':
        setState(() {
          _cameraOn = true;
          if (type == 'ready') {
            _ready = true;
            _status = 'Face the camera inside the oval';
          }
          _error = null;
        });
        break;
      case 'scanning':
        setState(() {
          _scanning = true;
          _status = 'Scanning…';
        });
        break;
      case 'descriptor':
        final raw = payload['data'];
        if (raw is! List) return;
        final descriptor = raw.map((v) => (v as num).toDouble()).toList();
        setState(() => _scanning = false);
        widget.onDescriptor(descriptor);
        break;
      case 'error':
        setState(() {
          _scanning = false;
          _error = payload['message']?.toString();
          _status = 'Try again';
        });
        break;
    }
  }

  Future<void> _capture() async {
    if (!widget.clockEnabled) {
      setState(() {
        _error = 'Switch to today’s date to clock staff in or out.';
        _status = 'Viewing past date';
      });
      return;
    }
    if (!_ready || _scanning || widget.busy || !_started || _engine == null) return;
    await _engine!.capture();
  }

  Widget _buildStatusBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _ready ? AppColors.lightGreen : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _ready ? AppColors.greenBorder : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _ready ? AppColors.green : AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildPreviewStack({bool rounded = true}) {
    final drawerOpen = AppShellScope.maybeOf(context)?.drawerOpen ?? false;
    final hideWebPreview = kIsWeb && drawerOpen;

    final preview = hideWebPreview
        ? const ColoredBox(color: Color(0xFF111827))
        : _engine!.preview();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (rounded)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: preview,
          )
        else
          preview,
        if (_modelsReady && !_cameraOn && !_ready)
          ColoredBox(
            color: AppColors.softSurface,
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextButton.icon(
                        onPressed: _openCamera,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(
                          _error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  : const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.green,
                      ),
                    ),
            ),
          ),
        if (_error != null && _cameraOn)
          Positioned(
            left: 10,
            right: 10,
            bottom: 56,
            child: Material(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewArea({required bool fill}) {
    if (!_started || _engine == null) {
      return Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              )
            : const CircularProgressIndicator(color: AppColors.green),
      );
    }

    if (fill) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final next = Size(constraints.maxWidth, constraints.maxHeight);
          if (_viewSize != next && next.width > 0 && next.height > 0) {
            _viewSize = next;
            if (kIsWeb) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _syncLayout());
            }
          }
          return _buildPreviewStack(rounded: false);
        },
      );
    }

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: _buildPreviewStack(),
    );
  }

  Widget _buildExpandLayout(String badgeLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _buildPreviewArea(fill: true)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Live scanner',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _buildStatusBadge(badgeLabel),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: PointerInterceptor(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ready ? const Color(0xFF86EFAC) : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _ready && !_scanning && !widget.busy ? _capture : null,
                    icon: _scanning || widget.busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.face_retouching_natural_outlined, size: 16),
                    label: Text(_scanning || widget.busy ? 'Scanning…' : 'Scan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                      tooltip: 'Reset',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgeLabel = _ready
        ? 'Ready'
        : _cameraOn
            ? 'Loading'
            : 'Starting';

    if (widget.expand) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildExpandLayout(badgeLabel),
      );
    }

    final header = <Widget>[
      AttendanceLiveClock(compact: false),
      Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live scanner',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ready to scan — face the camera and we clock you in or out automatically.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _buildStatusBadge(badgeLabel),
        ],
      ),
      if (!widget.clockEnabled) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: const Text(
            'Viewing a past date — scanner is live, but clock in/out only works for today.',
            style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
          ),
        ),
      ],
      if (widget.schedule != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.softSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            attendanceScheduleSummary(widget.schedule!),
            style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
          ),
        ),
      ],
      const SizedBox(height: 12),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...header,
            _buildPreviewArea(fill: false),
            const SizedBox(height: 10),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ready ? AppColors.green : AppColors.muted,
                fontSize: 12,
                fontWeight: _ready ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PointerInterceptor(
                    child: FilledButton.icon(
                      onPressed: _ready && !_scanning && !widget.busy ? _capture : null,
                      icon: _scanning || widget.busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.face_retouching_natural_outlined, size: 18),
                      label: Text(_scanning || widget.busy ? 'Scanning…' : 'Scan now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
