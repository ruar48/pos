import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/pos_dashboard_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const PosDashboardApp());
  });
}
