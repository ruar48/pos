import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/top_toast.dart';
import '../pos/pages/pos_home_page.dart';
import 'auth_form_styles.dart';
import 'forgot_password_dialog.dart';

Future<void> showChangePasswordDialog(
  BuildContext context, {
  required PosHomePageState pageState,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ChangePasswordDialog(pageState: pageState),
  );
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool saving = false;
  bool hideCurrent = true;
  bool hideNew = true;
  bool hideConfirm = true;

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (currentPassword.isEmpty) {
      showTopWarning(context, 'Enter your current password.');
      return;
    }

    if (newPassword.length < 6) {
      showTopWarning(context, 'New password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      showTopWarning(context, 'New passwords do not match.');
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppTopSuccess('Password changed successfully');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  void _openForgotPassword() {
    final user = widget.pageState.widget.currentUser;
    final email = user.email.trim().isNotEmpty
        ? user.email
        : user.username;
    Navigator.of(context).pop();
    showForgotPasswordDialog(context, initialEmail: email);
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required VoidCallback onToggleVisibility,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextField(
      controller: controller,
      enabled: !saving,
      obscureText: hidden,
      textInputAction: textInputAction,
      decoration: authFieldDecoration(
        label: label,
        icon: Icons.lock_outline,
        suffixIcon: IconButton(
          onPressed: saving ? null : onToggleVisibility,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthDialogShell(
      title: 'Change Password',
      subtitle: 'Update your register login password',
      icon: Icons.lock_reset_rounded,
      onClose: saving ? null : () => Navigator.pop(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _passwordField(
            controller: currentPasswordController,
            label: 'Current password',
            hidden: hideCurrent,
            onToggleVisibility: () => setState(() => hideCurrent = !hideCurrent),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: saving ? null : _openForgotPassword,
              child: const Text(
                'Forgot current password?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _passwordField(
            controller: newPasswordController,
            label: 'New password',
            hidden: hideNew,
            onToggleVisibility: () => setState(() => hideNew = !hideNew),
          ),
          const SizedBox(height: 14),
          _passwordField(
            controller: confirmPasswordController,
            label: 'Confirm new password',
            hidden: hideConfirm,
            onToggleVisibility: () => setState(() => hideConfirm = !hideConfirm),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          const AuthInfoBanner(
            message: 'Use at least 6 characters. You will stay signed in after saving.',
          ),
        ],
      ),
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                saving ? 'Saving...' : 'Save password',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
