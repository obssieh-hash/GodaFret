import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/pin_service.dart';
import '../../state/session_controller.dart';
import 'common.dart';
import 'pin_pad.dart';

/// Demande le code PIN pour valider une opération sensible
/// (retrait, transfert, remboursement). Retourne `true` si validé.
Future<bool> confirmWithPin(BuildContext context, {required String title, required String summary}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PinSheet(title: title, summary: summary),
  );
  return ok ?? false;
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title, required this.summary});
  final String title;
  final String summary;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  String _pin = '';
  bool _error = false;
  bool _checking = false;

  Future<void> _digit(String d) async {
    if (_checking || _pin.length >= PinService.pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == PinService.pinLength) {
      setState(() => _checking = true);
      final session = context.read<SessionController>();
      final ok = await session.checkPin(_pin);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else if (session.stage != SessionStage.unlocked) {
        Navigator.pop(context, false);
      } else {
        setState(() {
          _error = true;
          _pin = '';
          _checking = false;
        });
      }
    }
  }

  Future<void> _bio() async {
    final session = context.read<SessionController>();
    if (await session.pin.authenticateWithBiometrics() && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.lock_outline_rounded, size: 52),
            const SizedBox(height: 12),
            Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(widget.summary, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 22),
            PinDots(length: PinService.pinLength, filled: _pin.length, error: _error),
            SizedBox(
              height: 28,
              child: _error
                  ? const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Code incorrect', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                    )
                  : null,
            ),
            PinPad(
              onDigit: _digit,
              onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              onBiometrics: session.biometricsEnabled ? _bio : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Écran de confirmation d'une opération (reçu).
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key, required this.title, required this.message, this.amount, this.details = const []});

  final String title;
  final String message;
  final String? amount;
  final List<(String, String)> details;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? amount,
    List<(String, String)> details = const [],
  }) {
    return Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, a, _) => FadeTransition(
          opacity: a,
          child: SuccessScreen(title: title, message: message, amount: amount, details: details),
        ),
      ),
    );
  }

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 20),
              Text(widget.title, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              if (widget.amount != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.amount!,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2),
                ),
              ],
              const SizedBox(height: 6),
              Text(widget.message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              if (widget.details.isNotEmpty) ...[
                const SizedBox(height: 28),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [for (final (k, v) in widget.details) KeyValueRow(k, v)]),
                ),
              ],
              const Spacer(flex: 2),
              PrimaryButton(label: 'Terminé', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}
