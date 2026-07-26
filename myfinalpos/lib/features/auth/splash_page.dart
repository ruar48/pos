import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/brand.dart';
import '../../core/theme/app_colors.dart';
import '../../services/offline/offline_catalog_store.dart';
import '../../services/offline/pos_connectivity.dart';
import '../pos/pages/pos_home_page.dart';
import 'login.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), _routeNext);
  }

  Future<void> _routeNext() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(LoginPage.rememberKey) ?? true;
    final savedUser =
        remember ? await OfflineSessionStore.loadUser() : null;

    if (!mounted) return;

    if (savedUser != null) {
      unawaited(PosConnectivity.instance.refresh(force: true));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PosHomePage(currentUser: savedUser),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGreen,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            AppBrand.splashWelcome,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.darkGreen,
              height: 1.25,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
