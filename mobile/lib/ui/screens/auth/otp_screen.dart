import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/session_controller.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

/// Étape MFA : saisie du code à 6 chiffres.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _length = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _cooldown = 30;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.length != _length) return;
    final session = context.read<SessionController>();
    await session.verifyOtp(_controller.text);
    if (mounted && session.error != null) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return AuthScaffold(
      onBack: session.cancelOtp,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    AuthTitle(
                      'Vérification en 2 étapes',
                      subtitle: session.otpHint ?? 'Saisissez le code à 6 chiffres.',
                    ),
                    const SizedBox(height: 32),
                    _OtpBoxes(controller: _controller, focus: _focus, length: _length, onCompleted: _submit),
                    if (session.error != null) ...[const SizedBox(height: 18), ErrorBanner(session.error!)],
                    if (session.info != null) ...[const SizedBox(height: 18), InfoBanner(session.info!)],
                    if (session.auth.canResendOtp) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _cooldown > 0 || session.busy
                              ? null
                              : () {
                                  session.resendOtp();
                                  _startCooldown();
                                },
                          child: Text(_cooldown > 0 ? 'Renvoyer le code dans $_cooldown s' : 'Renvoyer le code'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => PrimaryButton(
                label: 'Valider',
                loading: session.busy,
                onPressed: value.text.length == _length ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six cases de saisie reposant sur un champ texte invisible.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.controller, required this.focus, required this.length, required this.onCompleted});

  final TextEditingController controller;
  final FocusNode focus;
  final int length;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: focus.requestFocus,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0,
            // Le champ reste accessible aux lecteurs d'écran.
            alwaysIncludeSemantics: true,
            child: TextField(
              controller: controller,
              focusNode: focus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: length,
              decoration: const InputDecoration(labelText: 'Code de vérification', counterText: ''),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == length) onCompleted();
              },
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([controller, focus]),
            builder: (context, _) {
              final text = controller.text;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(length, (i) {
                  final active = focus.hasFocus && i == text.length.clamp(0, length - 1);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}
