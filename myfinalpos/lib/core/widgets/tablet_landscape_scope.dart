import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// POS tablets are landscape-only. When camera open makes Flutter report
/// portrait metrics, rotate the whole UI back to landscape layout.
class TabletLandscapeScope extends StatefulWidget {
  const TabletLandscapeScope({super.key, required this.child});

  final Widget child;

  @override
  State<TabletLandscapeScope> createState() => _TabletLandscapeScopeState();
}

class _TabletLandscapeScopeState extends State<TabletLandscapeScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockLandscape();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _lockLandscape();
    if (mounted) setState(() {});
  }

  Future<void> _lockLandscape() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;

    final mq = MediaQuery.of(context);
    if (mq.size.width >= mq.size.height) return widget.child;

    final landscapeW = mq.size.height;
    final landscapeH = mq.size.width;

    return RotatedBox(
      quarterTurns: 1,
      child: SizedBox(
        width: landscapeW,
        height: landscapeH,
        child: MediaQuery(
          data: mq.copyWith(size: Size(landscapeW, landscapeH)),
          child: widget.child,
        ),
      ),
    );
  }
}
