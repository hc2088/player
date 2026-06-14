import 'package:flutter/material.dart';

class PasswordInputDialog extends StatelessWidget {
  const PasswordInputDialog({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return PasswordInputDialogPanel(
      title: title,
      onCancel: () => Navigator.of(context).pop(),
      onSubmit: (password) => Navigator.of(context).pop(password),
    );
  }
}

class PasswordInputDialogPanel extends StatefulWidget {
  const PasswordInputDialogPanel({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onSubmit,
  });

  final String title;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmit;

  @override
  State<PasswordInputDialogPanel> createState() =>
      _PasswordInputDialogPanelState();
}

class _PasswordInputDialogPanelState extends State<PasswordInputDialogPanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(
          hintText: '请输入密码',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
