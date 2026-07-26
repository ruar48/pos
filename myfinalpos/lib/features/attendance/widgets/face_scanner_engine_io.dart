import 'dart:io' show Platform;

import 'face_scanner_engine.dart';
import 'native_face_scanner_engine.dart';
import 'webview_face_scanner_engine.dart';

FaceScannerEngine createFaceScannerEngineImpl() {
  if (Platform.isAndroid || Platform.isIOS) {
    return NativeFaceScannerEngine();
  }
  return WebViewFaceScannerEngine();
}
