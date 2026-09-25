import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api.dart';
import '../../state/session.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';

/// Email, then the six-digit code we send there. No passwords.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  var _codeSent = false;
  var _busy = false;
  String? _error;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _emailOk => _emailPattern.hasMatch(_email.text.trim());
  bool get _codeOk => RegExp(r'^\d{6}$').hasMatch(_code.text.trim());

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    await ref.read(sessionProvider.notifier).requestCode(_email.text);
    if (!mounted) return;
    setState(() {
      _codeSent = true;
      _code.clear();
    });
    _codeFocus.requestFocus();
  });

  Future<void> _signIn() => _run(
    () => ref.read(sessionProvider.notifier).signIn(_email.text, _code.text),
  );

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    const LogoMark(),
                    const SizedBox(width: 10),
                    Text('Jobwalk', style: text.titleLarge),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  _codeSent ? 'Check your email' : 'Sign in to Jobwalk',
                  style: text.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _codeSent
                      ? 'We sent a six-digit code to ${_email.text.trim()}. '
                            'It works for 10 minutes.'
                      : 'Your quotes follow you to any phone, and your crew '
                            "can quote under your name. We'll email you a "
                            'code; there is no password.',
                  style: text.bodyLarge?.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: 28),
                if (!_codeSent) ...[
                  // Separate keys: the code field must be a new field, not
                  // the email field reconfigured while focused.
                  TextField(
                    key: const ValueKey('email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(labelText: 'Email'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _emailOk && !_busy ? _sendCode() : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _emailOk && !_busy ? _sendCode : null,
                    child: Text(_busy ? 'Sending…' : 'Email me a code'),
                  ),
                ] else ...[
                  TextField(
                    key: const ValueKey('code'),
                    controller: _code,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: text.headlineSmall?.copyWith(letterSpacing: 6),
                    decoration: const InputDecoration(labelText: 'Code'),
                    onChanged: (_) {
                      setState(() {});
                      if (_codeOk && !_busy) _signIn();
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _codeOk && !_busy ? _signIn : null,
                    child: Text(_busy ? 'Signing in…' : 'Sign in'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _sendCode,
                        child: const Text('Send a new code'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _codeSent = false;
                                _error = null;
                              }),
                        child: const Text('Use a different email'),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: c.danger.fg),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
