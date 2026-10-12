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
        icon: const Icon(Icons.settings_rounded, color: Colors.white70),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 84)),
                  const SizedBox(height: 28),
                  const Center(child: BrandWordmark(onDark: true, size: 26)),
                  const SizedBox(height: 10),
                  const Text(
                    'Envoyez, payez, recevez. Simplement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 14.5),
                  ),
                  const SizedBox(height: 14),
                  Center(child: _ModeChip(config)),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _user,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                    decoration: darkField('Numéro de téléphone', Icons.phone_iphone_rounded).copyWith(
                      prefixText: '${Brand.phonePrefix}  ',
                      prefixStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                      hintText: '77 00 00 00',
                      hintStyle: const TextStyle(color: Colors.white30),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Saisissez votre numéro de téléphone' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pass,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white),
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: darkField(
                      'Mot de passe',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                    validator: (v) => (v ?? '').isEmpty ? 'Saisissez votre mot de passe' : null,
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(session.error!),
                  ],
                  const SizedBox(height: 26),
                  PrimaryButton(
                    label: 'Se connecter',
                    icon: Icons.arrow_forward_rounded,
                    loading: session.busy,
                    onDark: true,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 26),
                  const _SecurityNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip(this.config);
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(config.keycloakUrl)?.host ?? '';
    final (label, icon, color) = switch (config.authMode) {
      AuthMode.demo => ('Mode démo · OTP 123456', Icons.science_outlined, AppColors.amber),
      AuthMode.keycloak => ('Serveur $host · MFA', Icons.verified_user_outlined, AppColors.teal),
      AuthMode.fineract => ('Fineract · 2FA', Icons.shield_outlined, AppColors.sky),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
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
  Widget build(BuildContext context) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Golden Bridge Bank · connexion sécurisée',
              style: TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ),
        ],
      );
}
