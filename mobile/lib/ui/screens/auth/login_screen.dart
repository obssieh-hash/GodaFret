import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../core/theme.dart';
import '../../../state/session_controller.dart';
import '../../widgets/common.dart';
import '../../../core/brand.dart';
import '../../widgets/brand.dart';
import 'auth_scaffold.dart';
import 'server_sheet.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _user = TextEditingController(text: context.read<SessionController>().lastUsername ?? '');
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    context.read<SessionController>().login(_user.text.replaceAll(' ', ''), _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final config = session.config;
    return AuthScaffold(
      trailing: IconButton(
        tooltip: 'Serveur',
        onPressed: () => showServerSheet(context, config),
        icon: const Icon(Icons.tune_rounded),
      ),
      child: Form(
        key: _form,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const BrandWordmark(size: 20),
                      const SizedBox(height: 36),
                      const AuthTitle(
                        'Bon retour',
                        subtitle: 'Envoyez, payez, recevez. Simplement.',
                      ),
                      const SizedBox(height: 12),
                      _ModeChip(config),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _user,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          labelText: 'Numéro de téléphone',
                          hintText: '77 00 00 00',
                          prefixIcon: const _CountryPrefix(),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Saisissez votre numéro de téléphone' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pass,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Afficher' : 'Masquer',
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (v) => (v ?? '').isEmpty ? 'Saisissez votre mot de passe' : null,
                      ),
                      if (session.error != null) ...[
                        const SizedBox(height: 16),
                        ErrorBanner(session.error!),
                      ],
                    ],
                  ),
                ),
              ),
              const _SecurityNote(),
              const SizedBox(height: 12),
              PrimaryButton(label: 'Se connecter', loading: session.busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🇩🇯', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(Brand.phonePrefix, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Container(width: 1, height: 22, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ),
      );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip(this.config);
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(config.keycloakUrl)?.host ?? '';
    final label = switch (config.authMode) {
      AuthMode.demo => 'Mode démo · OTP 123456',
      AuthMode.keycloak => 'Serveur $host · MFA',
      AuthMode.fineract => 'Fineract · 2FA',
    };
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.isDemo ? AppColors.amber : AppColors.green,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text('Golden Bridge Bank · connexion chiffrée', style: TextStyle(color: muted, fontSize: 12.5)),
        ),
      ],
    );
  }
}
