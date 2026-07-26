import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';
import '../../core/constants/brand.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/top_toast.dart';
import '../../core/widgets/brand_logo.dart';
import '../../models/app_user.dart';
import '../../services/offline/offline_catalog_store.dart';
import '../../services/offline/pos_connectivity.dart';
import 'forgot_password_dialog.dart';
import '../pos/pages/pos_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static const rememberKey = 'login_remember_username';
  static const savedUsernameKey = 'login_saved_username';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final _formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  bool loading = false;
  bool hidePassword = true;
  bool rememberMe = true;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
  }

  Future<void> _loadSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(LoginPage.savedUsernameKey) ?? '';
    final remember = prefs.getBool(LoginPage.rememberKey) ?? true;

    if (!mounted) return;
    setState(() {
      rememberMe = remember;
      if (remember && saved.isNotEmpty) {
        email.text = saved;
      } else if (kDebugMode && email.text.isEmpty) {
        email.text = 'admin@agriculture.local';
        password.text = 'password';
      }
    });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void _clearGeneralError() {
    if (_generalError != null) {
      setState(() => _generalError = null);
    }
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Username or email is required';
    return null;
  }

  String? _validatePassword(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Password is required';
    return null;
  }

  String _connectionErrorMessage(Object error) {
    if (kDebugMode) {
      debugPrint('Login error ($apiBaseUrl): $error');
    }
    if (error is TimeoutException) {
      return 'Server took too long to respond. Check your connection and try again.';
    }
    if (error is SocketException) {
      return 'Cannot reach the server ($apiBaseUrl). Check your network or API address.';
    }
    if (error is http.ClientException) {
      return 'Network error: ${error.message}. API: $apiBaseUrl';
    }
    if (error is HandshakeException || error is TlsException) {
      return 'Secure connection failed. Check the tablet date/time, Wi‑Fi, and try again.';
    }
    if (error is FormatException) {
      return 'Received an invalid response from the server. '
          'Make sure the app uses https://posmunoz.store and the API is online.';
    }
    if (error is TypeError) {
      return 'Received an unexpected login response from the server.';
    }
    if (kDebugMode) {
      return 'Login failed: $error';
    }
    return 'Something went wrong. Please try again.';
  }

  bool _isSuccessResponse(Map<String, dynamic> data) {
    final success = data['success'];
    return success == true || success == 1 || success == '1' || success == 'true';
  }

  AppUser? _userFromLoginResponse(Map<String, dynamic> data) {
    final rawUser = data['user'];
    if (rawUser is Map) {
      return AppUser.fromJson(Map<String, dynamic>.from(rawUser));
    }
    final nested = data['data'];
    if (nested is Map) {
      final nestedUser = nested['user'];
      if (nestedUser is Map) {
        return AppUser.fromJson(Map<String, dynamic>.from(nestedUser));
      }
    }
    return null;
  }

  String? _messageFromResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('<')) {
      return 'Server returned a web page instead of JSON. '
          'Check that the API URL uses HTTPS and the backend is deployed correctly.';
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return cleanApiErrorMessage(message.toString());
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _persistUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LoginPage.rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(LoginPage.savedUsernameKey, email.text.trim());
    } else {
      await prefs.remove(LoginPage.savedUsernameKey);
    }
  }

  Future<void> login() async {
    _clearGeneralError();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      if (email.text.trim().isEmpty) {
        emailFocus.requestFocus();
      } else {
        passwordFocus.requestFocus();
      }
      return;
    }

    setState(() => loading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/login.php'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.text.trim(),
              'password': password.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        setState(() {
          _generalError = _messageFromResponseBody(response.body) ??
              'Received an invalid response from the server.';
        });
        return;
      }

      if (response.statusCode == 200 && _isSuccessResponse(data)) {
        final user = _userFromLoginResponse(data);
        if (user == null) {
          setState(() {
            _generalError =
                'Login succeeded but the server response was missing user details.';
          });
          return;
        }

        await _persistUsername();
        if (rememberMe) {
          await OfflineSessionStore.saveUser(user);
        } else {
          await OfflineSessionStore.clearUser();
        }
        PosConnectivity.instance.noteApiReachable();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PosHomePage(currentUser: user),
          ),
        );
        return;
      }

      setState(() {
        _generalError = (data['message'] as String?)?.trim().isNotEmpty == true
            ? cleanApiErrorMessage(data['message'] as String)
            : response.statusCode == 401
                ? 'Invalid username or password.'
                : 'Login failed (HTTP ${response.statusCode}).';
      });
      passwordFocus.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _generalError = _connectionErrorMessage(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 900;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: isCompact
          ? _LoginMobileLayout(
              form: _LoginFormCard(
                formKey: _formKey,
                email: email,
                password: password,
                emailFocus: emailFocus,
                passwordFocus: passwordFocus,
                loading: loading,
                hidePassword: hidePassword,
                rememberMe: rememberMe,
                generalError: _generalError,
                onTogglePassword: () =>
                    setState(() => hidePassword = !hidePassword),
                onRememberChanged: (value) =>
                    setState(() => rememberMe = value),
                onClearError: _clearGeneralError,
                onLogin: login,
                validateEmail: _validateEmail,
                validatePassword: _validatePassword,
              ),
            )
          : Row(
              children: [
                const Expanded(flex: 11, child: _LoginBrandPanel()),
                Expanded(
                  flex: 9,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 40,
                      ),
                      child: _LoginFormCard(
                        formKey: _formKey,
                        email: email,
                        password: password,
                        emailFocus: emailFocus,
                        passwordFocus: passwordFocus,
                        loading: loading,
                        hidePassword: hidePassword,
                        rememberMe: rememberMe,
                        generalError: _generalError,
                        onTogglePassword: () =>
                            setState(() => hidePassword = !hidePassword),
                        onRememberChanged: (value) =>
                            setState(() => rememberMe = value),
                        onClearError: _clearGeneralError,
                        onLogin: login,
                        validateEmail: _validateEmail,
                        validatePassword: _validatePassword,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LoginBrandPanel extends StatelessWidget {
  const _LoginBrandPanel();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/greentok_login.png',
          height: height,
          fit: BoxFit.cover,
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.darkGreen.withValues(alpha: 0.72),
                AppColors.darkGreen.withValues(alpha: 0.35),
                AppColors.darkGreen.withValues(alpha: 0.82),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Text(
                  AppBrand.posSubtitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Smart POS.\nSmart Business.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Manage sales, inventory, and farm supply checkout from one tablet register.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _BrandFeatureChip(
                    icon: Icons.bolt_outlined,
                    label: 'Fast checkout',
                  ),
                  _BrandFeatureChip(
                    icon: Icons.shield_outlined,
                    label: 'Secure access',
                  ),
                  _BrandFeatureChip(
                    icon: Icons.insights_outlined,
                    label: 'Live reports',
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandFeatureChip extends StatelessWidget {
  const _BrandFeatureChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginMobileLayout extends StatelessWidget {
  const _LoginMobileLayout({required this.form});

  final Widget form;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/greentok_login.png',
                  fit: BoxFit.cover,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.darkGreen.withValues(alpha: 0.2),
                        AppColors.darkGreen.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Text(
                    'Smart POS. Smart Business.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: form,
          ),
        ],
      ),
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.formKey,
    required this.email,
    required this.password,
    required this.emailFocus,
    required this.passwordFocus,
    required this.loading,
    required this.hidePassword,
    required this.rememberMe,
    required this.generalError,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onClearError,
    required this.onLogin,
    required this.validateEmail,
    required this.validatePassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool loading;
  final bool hidePassword;
  final bool rememberMe;
  final String? generalError;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onClearError;
  final Future<void> Function() onLogin;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePassword;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: BrandLogo(
                    size: BrandLogoSize.lg,
                    subtitle: AppBrand.posSubtitle,
                    showLogo: false,
                    alignment: CrossAxisAlignment.center,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to your farm supply store register',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: email,
                  focusNode: emailFocus,
                  enabled: !loading,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  validator: validateEmail,
                  onChanged: (_) => onClearError(),
                  onFieldSubmitted: (_) => passwordFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    label: 'Username or email',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  focusNode: passwordFocus,
                  enabled: !loading,
                  obscureText: hidePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: validatePassword,
                  onChanged: (_) => onClearError(),
                  onFieldSubmitted: (_) => onLogin(),
                  decoration: _fieldDecoration(
                    label: 'Password',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      onPressed: loading ? null : onTogglePassword,
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _LoginOptionsRow(
                  rememberMe: rememberMe,
                  loading: loading,
                  onRememberChanged: onRememberChanged,
                  onForgotPassword: () => showForgotPasswordDialog(
                    context,
                    initialEmail: email.text.trim(),
                  ),
                ),
                if (generalError != null) ...[
                  const SizedBox(height: 12),
                  _LoginErrorBanner(
                    message: generalError!,
                    onDismiss: onClearError,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: loading ? null : onLogin,
                    icon: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded, size: 22),
                    label: Text(
                      loading ? 'Signing in...' : 'Sign in',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Server: $apiBaseUrl',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.green),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.softSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.green, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    );
  }
}

class _LoginOptionsRow extends StatelessWidget {
  const _LoginOptionsRow({
    required this.rememberMe,
    required this.loading,
    required this.onRememberChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final bool loading;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: loading ? null : () => onRememberChanged(!rememberMe),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: rememberMe,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        activeColor: AppColors.green,
                        side: const BorderSide(color: AppColors.border, width: 1.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        onChanged: loading
                            ? null
                            : (value) => onRememberChanged(value ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Remember me',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: loading ? null : onForgotPassword,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.green,
          ),
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.green,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
