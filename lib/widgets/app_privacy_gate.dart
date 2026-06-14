import 'package:flutter/material.dart';

import '../services/local_media_service.dart';
import 'password_input_dialog.dart';

class AppPrivacyGate extends StatefulWidget {
  const AppPrivacyGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppPrivacyGate> createState() => _AppPrivacyGateState();
}

class _AppPrivacyGateState extends State<AppPrivacyGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _enteringPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _lock();
    }
  }

  void _lock() {
    if (!_unlocked && !_enteringPassword) {
      return;
    }

    setState(() {
      _unlocked = false;
      _enteringPassword = false;
    });
  }

  void _showPasswordInput() {
    if (_enteringPassword) return;

    setState(() {
      _enteringPassword = true;
    });
  }

  void _hidePasswordInput() {
    setState(() {
      _enteringPassword = false;
    });
  }

  void _submitPassword(String password) {
    final isUnlocked = LocalMediaService.isUnlockPassword(password);

    setState(() {
      _unlocked = isUnlocked;
      _enteringPassword = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !_unlocked,
          child: TickerMode(
            enabled: _unlocked,
            child: widget.child,
          ),
        ),
        if (!_unlocked)
          _PrivacyLockOverlay(
            enteringPassword: _enteringPassword,
            onShowPasswordInput: _showPasswordInput,
            onCancel: _hidePasswordInput,
            onSubmit: _submitPassword,
          ),
      ],
    );
  }
}

class _PrivacyLockOverlay extends StatelessWidget {
  const _PrivacyLockOverlay({
    required this.enteringPassword,
    required this.onShowPasswordInput,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool enteringPassword;
  final VoidCallback onShowPasswordInput;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: ValueKey(enteringPassword),
      initialEntries: [
        OverlayEntry(
          builder: (_) => _HelloWorldLockPage(
            enteringPassword: enteringPassword,
            onShowPasswordInput: onShowPasswordInput,
            onCancel: onCancel,
            onSubmit: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _HelloWorldLockPage extends StatelessWidget {
  const _HelloWorldLockPage({
    required this.enteringPassword,
    required this.onShowPasswordInput,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool enteringPassword;
  final VoidCallback onShowPasswordInput;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enteringPassword ? null : onShowPasswordInput,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(
                child: Text(
                  'helloworld',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (enteringPassword)
                Center(
                  child: PasswordInputDialogPanel(
                    title: '访问验证',
                    onCancel: onCancel,
                    onSubmit: onSubmit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
