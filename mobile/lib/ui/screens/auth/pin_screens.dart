import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../services/pin_service.dart';
import '../../../state/session_controller.dart';
import '../../widgets/pin_pad.dart';
import 'auth_scaffold.dart';

/// Création (ou modification) du code PIN : saisie puis confirmation.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.changing = false});

  /// `true` depuis le profil (« Modifier mon code »).
  final bool changing;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  bool _error = false;
  String? _message;
  bool _bio = true;

  void _digit(String d) {
    if (_pin.length >= PinService.pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
      _message = null;
    });
    if (_pin.length < PinService.pinLength) return;

    if (!_confirming) {
      final problem = PinService.validateNewPin(_pin);
      if (problem != null) {
        setState(() {
          _error = true;
          _message = problem;
          _pin = '';
        });
        return;
      }
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _error = true;
        _message = 'Les codes ne correspondent pas. Recommencez.';
        _pin = '';
        _first = '';
        _confirming = false;
      });
      return;
    }
    _save();
  }

  Future<void> _save() async {
    final session = context.read<SessionController>();
    if (widget.changing) {
      await session.changePin(_pin);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code PIN modifié')));
      }
    } else {
      await session.createPin(_pin, enableBiometrics: _bio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return AuthScaffold(
      onBack: widget.changing ? () => Navigator.pop(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(),
            const BrandLogo(size: 56),
            const SizedBox(height: 22),
            Text(
              _confirming ? 'Confirmez votre code' : (widget.changing ? 'Nouveau code PIN' : 'Créez votre code PIN'),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _message ?? 'Ce code à 6 chiffres protège l\'accès à l\'application et valide vos opérations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _error ? const Color(0xFFFF8FA3) : Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 30),
            PinDots(length: PinService.pinLength, filled: _pin.length, error: _error, color: Colors.white),
            const Spacer(),
            if (!widget.changing && session.biometricsAvailable)
              SwitchListTile(
                value: _bio,
                onChanged: (v) => setState(() => _bio = v),
                activeThumbColor: AppColors.teal,
                title: const Text('Activer Face ID / empreinte', style: TextStyle(color: Colors.white)),
                secondary: const Icon(Icons.fingerprint_rounded, color: Colors.white70),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: PinPad(
                foreground: Colors.white,
                onDigit: _digit,
                onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Écran de verrouillage : déverrouillage par PIN ou biométrie.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _pin = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<SessionController>();
      if (session.biometricsEnabled) session.unlockWithBiometrics();
    });
  }

  Future<void> _digit(String d) async {
    final session = context.read<SessionController>();
    if (session.busy || _pin.length >= PinService.pinLength) return;
    setState(() => _pin += d);
    if (_pin.length == PinService.pinLength) {
      await session.unlockWithPin(_pin);
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final name = session.lastUsername;
    return AuthScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(),
            const BrandLogo(size: 56),
            const SizedBox(height: 22),
            Text(
              name == null ? 'Bon retour' : 'Bon retour, $name',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              session.error ?? 'Saisissez votre code PIN',
              textAlign: TextAlign.center,
              style: TextStyle(color: session.error != null ? const Color(0xFFFF8FA3) : Colors.white60),
            ),
            const SizedBox(height: 30),
            session.busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : PinDots(
                    length: PinService.pinLength,
                    filled: _pin.length,
                    error: session.error != null && _pin.isEmpty,
                    color: Colors.white,
                  ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: PinPad(
                foreground: Colors.white,
                onDigit: _digit,
                onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
                onBiometrics: session.biometricsEnabled ? session.unlockWithBiometrics : null,
              ),
            ),
            TextButton(
              onPressed: session.logout,
              child: const Text('Code oublié ? Se reconnecter', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
