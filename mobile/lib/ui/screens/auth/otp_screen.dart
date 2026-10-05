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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_moon_outlined, color: Colors.white, size: 40),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Vérification en 2 étapes',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  session.otpHint ?? 'Saisissez le code à 6 chiffres.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
                const SizedBox(height: 32),
                _OtpBoxes(
                  controller: _controller,
                  focus: _focus,
                  length: _length,
                  onCompleted: _submit,
                ),
                if (session.error != null) ...[const SizedBox(height: 18), ErrorBanner(session.error!)],
                if (session.info != null) ...[const SizedBox(height: 18), InfoBanner(session.info!)],
                const SizedBox(height: 28),
                ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, value, _) => PrimaryButton(
                    label: 'Valider',
                    loading: session.busy,
                    onDark: true,
                    onPressed: value.text.length == _length ? _submit : null,
                  ),
                ),
                if (session.auth.canResendOtp) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _cooldown > 0 || session.busy
                        ? null
                        : () {
                            session.resendOtp();
                            _startCooldown();
                          },
                    child: Text(
                      _cooldown > 0 ? 'Renvoyer le code dans $_cooldown s' : 'Renvoyer le code',
                      style: TextStyle(color: _cooldown > 0 ? Colors.white38 : Colors.white),
                    ),
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
                      color: Colors.white.withValues(alpha: i < text.length ? 0.14 : 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: active ? const Color(0xFF8B85FF) : Colors.white.withValues(alpha: 0.1),
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
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
