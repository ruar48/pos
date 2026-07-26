import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/face_scanner_engine.dart';

class FaceScanResult {
  const FaceScanResult(this.descriptor);

  final List<double> descriptor;
}

/// Full-screen landscape face scanner for tablet POS (native camera + web iframe).
Future<FaceScanResult?> showFaceScanSheet(BuildContext context) {
  return Navigator.of(context).push<FaceScanResult>(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const _FaceScanPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FaceScanPage extends StatefulWidget {
  const _FaceScanPage();

  @override
  State<_FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<_FaceScanPage> {
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _bootstrap();
  }

  @override
  void dispose() {
    _engine?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
            _status = 'Center your face in the oval';
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
        Navigator.of(context).pop(FaceScanResult(descriptor));
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
    if (!_ready || _scanning || !_started || _engine == null) return;
    await _engine!.capture();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 10, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final next = Size(constraints.maxWidth, constraints.maxHeight);
                      if (_viewSize != next && next.width > 0 && next.height > 0) {
                        _viewSize = next;
                        if (kIsWeb) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _syncLayout());
                        }
                      }
                      return _started && _engine != null
                          ? Stack(
                          fit: StackFit.expand,
                          children: [
                            _engine!.preview(),
                            if (_modelsReady && !_cameraOn && !_ready)
                              ColoredBox(
                                color: AppColors.softSurface,
                                child: Center(
                                  child: _error != null
                                      ? Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text(
                                            _error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: AppColors.muted),
                                          ),
                                        )
                                      : const CircularProgressIndicator(
                                          color: AppColors.green,
                                        ),
                                ),
                              ),
                            if (_error != null && _cameraOn)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Center(
                          child: _error != null
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.muted, height: 1.4),
                                  ),
                                )
                              : const CircularProgressIndicator(color: AppColors.green),
                        );
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Register face',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Scan the staff member’s face to enroll',
                                style: TextStyle(color: AppColors.muted, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 15),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _ready && !_scanning ? _capture : null,
                      icon: _scanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.face_retouching_natural_outlined),
                      label: Text(_scanning ? 'Scanning…' : 'Scan face'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
