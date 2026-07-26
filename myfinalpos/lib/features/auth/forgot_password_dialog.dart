import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/top_toast.dart';
import '../../services/pos_api.dart';
import 'auth_form_styles.dart';

Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String? initialEmail,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ForgotPasswordDialog(initialEmail: initialEmail),
  );
}

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final emailController = TextEditingController();
  final api = PosApi();
  bool sending = false;
  String? successMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail?.trim().isNotEmpty == true) {
      emailController.text = widget.initialEmail!.trim();
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      showTopWarning(context, 'Enter your username or email.');
      return;
    }

    setState(() {
      sending = true;
      successMessage = null;
    });

    try {
      final message = await api.requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() {
        sending = false;
        successMessage = message;
      });
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthDialogShell(
      title: 'Forgot Password',
      subtitle: 'We will email you a secure link to reset your password',
      icon: Icons.mail_lock_outlined,
      onClose: sending ? null : () => Navigator.pop(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (successMessage != null) ...[
            AuthInfoBanner(
              message: successMessage!,
              icon: Icons.mark_email_read_outlined,
            ),
            const SizedBox(height: 16),
          ] else ...[
            const AuthInfoBanner(
              message:
                  'Use the email on your staff account. The reset link opens in a browser.',
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: emailController,
            enabled: !sending && successMessage == null,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendResetLink(),
            decoration: authFieldDecoration(
              label: 'Username or email',
              icon: Icons.alternate_email_outlined,
              hintText: 'you@store.com',
            ),
          ),
        ],
      ),
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(successMessage != null ? 'Close' : 'Cancel'),
            ),
          ),
          if (successMessage == null) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: sending ? null : _sendResetLink,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  sending ? 'Sending...' : 'Send reset link',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
