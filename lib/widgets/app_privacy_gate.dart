import 'package:flutter/material.dart';

import '../services/local_media_service.dart';

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
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

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
    _passwordFocusNode.dispose();
    _passwordController.dispose();
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
    if (!_unlocked && !_enteringPassword && _passwordController.text.isEmpty) {
      return;
    }

    setState(() {
      _unlocked = false;
      _enteringPassword = false;
      _passwordController.clear();
    });
  }

  void _showPasswordInput() {
    if (_enteringPassword) return;

    setState(() {
      _enteringPassword = true;
      _passwordController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_enteringPassword) return;
      _passwordFocusNode.requestFocus();
    });
  }

  void _hidePasswordInput() {
    setState(() {
      _enteringPassword = false;
      _passwordController.clear();
    });
  }

  void _submitPassword() {
    final password = _passwordController.text;
    final isUnlocked = LocalMediaService.isUnlockPassword(password);

    setState(() {
      _unlocked = isUnlocked;
      _enteringPassword = false;
      _passwordController.clear();
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
          _HelloWorldLockPage(
            enteringPassword: _enteringPassword,
            passwordController: _passwordController,
            passwordFocusNode: _passwordFocusNode,
            onShowPasswordInput: _showPasswordInput,
            onCancel: _hidePasswordInput,
            onSubmit: _submitPassword,
          ),
      ],
    );
  }
}

class _HelloWorldLockPage extends StatelessWidget {
  const _HelloWorldLockPage({
    required this.enteringPassword,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.onShowPasswordInput,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool enteringPassword;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final VoidCallback onShowPasswordInput;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final inputWidth =
        (MediaQuery.of(context).size.width - 48).clamp(0, 360).toDouble();

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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: inputWidth,
                    ),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: '请输入密码',
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => onSubmit(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: onCancel,
                                  child: const Text('取消'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: onSubmit,
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
