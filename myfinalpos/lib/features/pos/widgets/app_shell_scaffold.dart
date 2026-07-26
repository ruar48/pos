import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/theme/app_colors.dart';
import '../pages/pos_home_page.dart';
import 'app_drawer.dart';
import 'app_drawer_section.dart';

/// Exposes shell UI state to pages that host web platform views (camera iframe).
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.drawerOpen,
    required super.child,
  });

  final bool drawerOpen;

  static AppShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShellScope>();
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) {
    return drawerOpen != oldWidget.drawerOpen;
  }
}

class AppShellScaffold extends StatefulWidget {
  const AppShellScaffold({
    super.key,
    required this.pageState,
    required this.activeSection,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.scrollBody = false,
  });

  final PosHomePageState pageState;
  final AppDrawerSection activeSection;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final bool scrollBody;

  @override
  State<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends State<AppShellScaffold> {
  var _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    return AppShellScope(
      drawerOpen: _drawerOpen,
      child: Scaffold(
        backgroundColor: AppColors.page,
        onDrawerChanged: (opened) {
          if (_drawerOpen != opened) {
            setState(() => _drawerOpen = opened);
          }
        },
        drawer: PointerInterceptor(
          child: AppDrawer(
            pageState: widget.pageState,
            activeSection: widget.activeSection,
          ),
        ),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          shape: const Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
          automaticallyImplyLeading: false,
          leading: PointerInterceptor(
            child: Builder(
              builder: (scaffoldContext) => IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              ),
            ),
          ),
          title: widget.subtitle == null
              ? Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
          actions: widget.actions
              ?.map((action) => PointerInterceptor(child: action))
              .toList(),
        ),
        body: SafeArea(
          child: widget.scrollBody
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: widget.body,
                )
              : widget.body,
        ),
      ),
    );
  }
}
