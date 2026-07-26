import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'face_scanner_engine.dart';
import 'attendance_scanner_oval_overlay.dart';

FaceScannerEngine createFaceScannerEngineImpl() => _WebFaceScannerEngine();

class _WebFaceScannerEngine implements FaceScannerEngine {
  static int _nextViewId = 0;

  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _subscription;
  ScannerMessageHandler? _onMessage;
  late final String _viewType;
  var _registered = false;
  var _frameReady = false;

  @override
  Future<String?> start(ScannerMessageHandler onMessage) async {
    _onMessage = onMessage;
    _viewType = 'greentok-face-scanner-${_nextViewId++}';

    _subscription = html.window.onMessage.listen(_handleMessage);
    _registerViewFactory();
    return null;
  }

  void _registerViewFactory() {
    if (_registered) return;
    _registered = true;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final root = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..style.position = 'relative'
        ..style.pointerEvents = 'none';

      final iframe = html.IFrameElement()
        ..src = _scannerAssetUrl()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0';
      iframe.setAttribute('allow', 'camera; microphone');

      root.append(iframe);
      _iframe = iframe;
      return root;
    });
  }

  String _scannerAssetUrl() {
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}$path''assets/assets/face_recognition/scanner.html';
  }

  void _handleMessage(html.MessageEvent event) {
    final raw = event.data;
    Map<String, dynamic>? payload;

    if (raw is String) {
      try {
        payload = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
    } else if (raw is Map) {
      payload = Map<String, dynamic>.from(raw);
    } else {
      return;
    }

    if (payload['source'] != 'greentok-face-scanner') return;
    final type = payload['type']?.toString() ?? '';
    if (type == 'ready' || type == 'camera') {
      _frameReady = true;
    }
    if (type == 'models_ready') {
      _frameReady = false;
    }
    _onMessage?.call(payload);
  }

  void _postToFrame(Map<String, dynamic> message) {
    _iframe?.contentWindow?.postMessage(
      {
        'source': 'greentok-face-host',
        ...message,
      },
      '*',
    );
  }

  @override
  Future<void> syncLayout(double width, double height, bool landscape) async {
    _postToFrame({
      'type': 'setScannerLayout',
      'width': width.round(),
      'height': height.round(),
      'landscape': landscape,
    });
  }

  @override
  Future<void> capture() async {
    if (_iframe == null) {
      _onMessage?.call({
        'type': 'error',
        'message': 'Scanner still loading…',
      });
      return;
    }
    if (!_frameReady) {
      _onMessage?.call({
        'type': 'error',
        'message': 'Camera not ready yet. Wait for Ready, then scan.',
      });
      return;
    }
    _postToFrame({'type': 'startFaceCapture'});
  }

  @override
  Future<void> openCamera() async {
    _postToFrame({'type': 'startCamera'});
  }

  @override
  Widget preview() {
    if (!_registered) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        const Positioned.fill(
          child: IgnorePointer(
            child: AttendanceScannerOvalOverlay(),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _iframe = null;
    _onMessage = null;
  }
}
