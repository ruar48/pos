import 'dart:convert';

import 'dart:io' show Platform;



import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:webview_flutter/webview_flutter.dart';

import 'package:webview_flutter_android/webview_flutter_android.dart';



import 'face_scanner_engine.dart';



/// WebView camera host (desktop / fallback). Mobile uses [NativeFaceScannerEngine].

class WebViewFaceScannerEngine implements FaceScannerEngine {

  WebViewController? _controller;

  ScannerMessageHandler? _onMessage;



  @override

  Future<String?> start(ScannerMessageHandler onMessage) async {

    _onMessage = onMessage;



    final camera = await Permission.camera.request();

    if (!camera.isGranted) {

      return 'Camera permission is required. Allow camera in system settings, then restart the app.';

    }



    final controller = WebViewController()

      ..setJavaScriptMode(JavaScriptMode.unrestricted)

      ..setBackgroundColor(const Color(0xFF111827))

      ..addJavaScriptChannel(

        'FaceCapture',

        onMessageReceived: _onScannerMessage,

      )

      ..setOnConsoleMessage((message) {

        debugPrint('Face scanner: ${message.message}');

      })

      ..setNavigationDelegate(

        NavigationDelegate(

          onPageFinished: (_) {},

        ),

      );



    if (controller.platform is AndroidWebViewController) {

      final android = controller.platform as AndroidWebViewController;

      android.setMediaPlaybackRequiresUserGesture(false);

      await android.setOnPlatformPermissionRequest((request) async {

        await request.grant();

      });

    }



    await controller.loadFlutterAsset('assets/face_recognition/scanner.html');

    _controller = controller;

    return null;

  }



  void _onScannerMessage(JavaScriptMessage message) {

    try {

      final payload = jsonDecode(message.message) as Map<String, dynamic>;

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

    if (_controller == null) return;

    final hostLandscape = !kIsWeb && Platform.isAndroid ? true : landscape;

    await _controller!.runJavaScript(

      'window.setScannerLayout && window.setScannerLayout(${width.round()}, ${height.round()}, ${hostLandscape ? 'true' : 'false'}, -90);',

    );

  }



  @override

  Future<void> capture() async {

    if (_controller == null) return;

    await _controller!.runJavaScript('window.startFaceCapture && window.startFaceCapture();');

  }



  @override

  Future<void> openCamera() async {

    if (_controller == null) return;

    await _controller!.runJavaScript('window.startCamera && window.startCamera();');

  }



  @override

  Widget preview() {

    final controller = _controller;

    if (controller == null) {

      return const SizedBox.shrink();

    }



    if (controller.platform is AndroidWebViewController) {

      return WebViewWidget.fromPlatformCreationParams(

        params: AndroidWebViewWidgetCreationParams(

          controller: controller.platform as AndroidWebViewController,

          displayWithHybridComposition: true,

        ),

      );

    }

    return WebViewWidget(controller: controller);

  }



  @override

  void dispose() {

    _controller = null;

    _onMessage = null;

  }

}


