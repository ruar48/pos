import 'package:flutter/widgets.dart';

import 'face_scanner_engine_stub.dart'
    if (dart.library.html) 'face_scanner_engine_web.dart'
    if (dart.library.io) 'face_scanner_engine_io.dart';

typedef ScannerMessageHandler = void Function(Map<String, dynamic> payload);

/// Platform camera + face scanner host (WebView on mobile, iframe on web).
abstract class FaceScannerEngine {
  Future<String?> start(ScannerMessageHandler onMessage);

  Future<void> syncLayout(double width, double height, bool landscape);

  Future<void> capture();

  Future<void> openCamera();

  Widget preview();

  void dispose();
}

FaceScannerEngine createFaceScannerEngine() => createFaceScannerEngineImpl();
