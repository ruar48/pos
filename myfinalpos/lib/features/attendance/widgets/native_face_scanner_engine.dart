import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'face_scanner_engine.dart';
import 'attendance_scanner_oval_overlay.dart';

/// Native camera preview + hidden WebView for face-api model inference only.
/// Avoids Chromium WebView getUserMedia, which fails on many Android emulators.
class NativeFaceScannerEngine with WidgetsBindingObserver implements FaceScannerEngine {
  WebViewController? _web;
  CameraController? _camera;
  ScannerMessageHandler? _onMessage;
  Timer? _reopenTimer;
  var _modelsReady = false;
  var _cameraReady = false;
  var _scanning = false;
  var _openingCamera = false;
  var _wasCameraActive = false;
  final _previewHostKey = GlobalKey<_NativeScannerPreviewHostState>();

  @override
  Future<String?> start(ScannerMessageHandler onMessage) async {
    _onMessage = onMessage;
    WidgetsBinding.instance.addObserver(this);

    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      return 'Camera permission is required. Allow camera in system settings, then restart the app.';
    }

    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF111827))
      ..addJavaScriptChannel(
        'FaceCapture',
        onMessageReceived: _onScannerMessage,
      );

    web.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          await web.runJavaScript(
            'window.setNativeCameraMode && window.setNativeCameraMode(true);',
          );
        },
      ),
    );

    await web.loadFlutterAsset('assets/face_recognition/scanner.html');
    _web = web;
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _releaseCamera();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _scheduleCameraReopen();
    }
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    if (logicalSize.width >= 1 && logicalSize.height >= 1) {
      return;
    }
    if (_wasCameraActive && _camera != null) {
      _releaseCamera();
      _scheduleCameraReopen();
    }
  }

  void _scheduleCameraReopen() {
    if (!_wasCameraActive || !_modelsReady) return;
    _reopenTimer?.cancel();
    _reopenTimer = Timer(const Duration(milliseconds: 300), () {
      if (_wasCameraActive && _modelsReady && !_openingCamera && _camera == null) {
        _cameraReady = false;
        openCamera();
      }
    });
  }

  void _releaseCamera() {
    _reopenTimer?.cancel();
    final camera = _camera;
    _camera = null;
    _cameraReady = false;
    _previewHostKey.currentState?.detachController();
    if (camera != null) {
      unawaited(camera.dispose());
    }
  }

  void _onScannerMessage(JavaScriptMessage message) {
    try {
      final payload = jsonDecode(message.message) as Map<String, dynamic>;
      final type = payload['type']?.toString() ?? '';

      if (type == 'models_ready') {
        _modelsReady = true;
      }
      if (type == 'descriptor' || type == 'error') {
        _scanning = false;
      }
      if (type == 'ready' && _cameraReady) {
        return;
      }
      _onMessage?.call(payload);
    } catch (error) {
      _onMessage?.call({
        'type': 'error',
        'message': error.toString(),
      });
    }
  }

  @override
  Future<void> syncLayout(double width, double height, bool landscape) async {
    // Layout is handled by Flutter CameraPreview; models run in a 1×1 offscreen WebView.
  }

  @override
  Future<void> openCamera() async {
    if (_openingCamera || (_cameraReady && _camera != null)) return;
    if (!_modelsReady) {
      _onMessage?.call({
        'type': 'status',
        'message': 'Loading face models…',
      });
      return;
    }

    _openingCamera = true;
    _onMessage?.call({'type': 'status', 'message': 'Opening camera…'});
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(
          'No camera found. On the emulator: Extended controls → Camera → Front → Webcam0, then cold boot.',
        );
      }

      var front = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          front = camera;
          break;
        }
      }

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.landscapeLeft);
      } catch (_) {
        // Some devices do not support capture orientation lock.
      }

      _camera = controller;
      _cameraReady = true;
      _wasCameraActive = true;
      _previewHostKey.currentState?.attachController(controller);
      _onMessage?.call({'type': 'camera'});
      _onMessage?.call({'type': 'ready'});
    } catch (error) {
      _releaseCamera();
      _onMessage?.call({
        'type': 'error',
        'message': error is StateError
            ? error.message
            : 'Camera unavailable: $error',
      });
    } finally {
      _openingCamera = false;
    }
  }

  @override
  Future<void> capture() async {
    if (_scanning) {
      return;
    }

    final camera = _camera;
    final web = _web;
    if (camera == null || !camera.value.isInitialized) {
      _onMessage?.call({
        'type': 'error',
        'message': _openingCamera
            ? 'Camera is still opening…'
            : 'Camera not ready. Wait a moment and try again.',
      });
      return;
    }
    if (web == null || !_modelsReady) {
      _onMessage?.call({
        'type': 'error',
        'message': 'Face models still loading…',
      });
      return;
    }

    _scanning = true;
    _onMessage?.call({'type': 'scanning'});

    try {
      final file = await camera.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final escaped = jsonEncode(dataUrl);
      await web.runJavaScript(
        'window.detectFromBase64Json && window.detectFromBase64Json($escaped);',
      );
    } catch (error) {
      _scanning = false;
      _onMessage?.call({
        'type': 'error',
        'message': error.toString(),
      });
    }
  }

  @override
  Widget preview() {
    final web = _web;

    return Stack(
      fit: StackFit.expand,
      children: [
        _NativeScannerPreviewHost(
          key: _previewHostKey,
          initialController: _camera,
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: AttendanceScannerOvalOverlay(),
          ),
        ),
        if (web != null)
          Offstage(
            child: SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: web),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reopenTimer?.cancel();
    _wasCameraActive = false;
    _releaseCamera();
    _web = null;
    _onMessage = null;
  }
}

class _NativeScannerPreviewHost extends StatefulWidget {
  const _NativeScannerPreviewHost({
    super.key,
    required this.initialController,
  });

  final CameraController? initialController;

  @override
  State<_NativeScannerPreviewHost> createState() => _NativeScannerPreviewHostState();
}

class _NativeScannerPreviewHostState extends State<_NativeScannerPreviewHost> {
  CameraController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.initialController;
    _controller?.addListener(_onCameraChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onCameraChanged);
    super.dispose();
  }

  void attachController(CameraController controller) {
    _controller?.removeListener(_onCameraChanged);
    _controller = controller;
    _controller?.addListener(_onCameraChanged);
    if (mounted) setState(() {});
  }

  void detachController() {
    _controller?.removeListener(_onCameraChanged);
    _controller = null;
    if (mounted) setState(() {});
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF111827));
    }
    return _NativeCameraPreview(controller: controller);
  }
}

class _NativeCameraPreview extends StatelessWidget {
  const _NativeCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const ColoredBox(color: Color(0xFF111827));
    }

    // CameraPreview already respects sensor orientation on Android.
    // Only mirror the front camera so the live view matches a natural selfie.
    Widget preview = CameraPreview(controller);
    if (controller.description.lensDirection == CameraLensDirection.front) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
        child: preview,
      );
    }

    final orientation = controller.value.deviceOrientation;
    var width = previewSize.width;
    var height = previewSize.height;
    if (orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight) {
      if (height > width) {
        final swap = width;
        width = height;
        height = swap;
      }
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: width,
          height: height,
          child: preview,
        ),
      ),
    );
  }
}
