import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../core/theme.dart';
import '../../../main.dart';
import '../../widgets/common.dart';

/// Choix du serveur : mode démo ou serveur GodaFret (adresse IP du réseau local
/// ou nom de domaine). Les URL Keycloak / Fineract sont déduites et modifiables.
Future<void> showServerSheet(BuildContext context, AppConfig current) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ServerSheet(current: current),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.current});
  final AppConfig current;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late bool _demo = widget.current.isDemo;
  final _host = TextEditingController();
  late final _fineract = TextEditingController(text: widget.current.fineractUrl);
  late final _keycloak = TextEditingController(text: widget.current.keycloakUrl);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AppRoot.of(context).settings.host().then((h) {
      if (h != null && mounted) _host.text = h;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _fineract.dispose();
    _keycloak.dispose();
    super.dispose();
  }

  void _onHost(String value) {
    if (value.trim().isEmpty) return;
    final urls = AppConfig.urlsForHost(value);
    _fineract.text = urls.fineract;
    _keycloak.text = urls.keycloak;
  }

  Future<void> _save() async {
    if (!_demo && (_fineract.text.trim().isEmpty || _keycloak.text.trim().isEmpty)) {
      showSnack(context, "Saisissez l'adresse du serveur.", error: true);
      return;
    }
    setState(() => _saving = true);
    final root = AppRoot.of(context);
    await root.settings.save(
      mode: _demo ? AuthMode.demo : AuthMode.keycloak,
      host: _host.text.trim(),
      fineractUrl: _demo ? null : _fineract.text.trim(),
      keycloakUrl: _demo ? null : _keycloak.text.trim(),
    );
    if (mounted) Navigator.pop(context);
    await root.restart();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  IconBadge(Icons.dns_rounded, color: AppColors.indigo),
                  SizedBox(width: 12),
                  Text('Serveur', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Démo'), icon: Icon(Icons.science_outlined)),
                  ButtonSegment(value: false, label: Text('Mon serveur'), icon: Icon(Icons.dns_outlined)),
                ],
                selected: {_demo},
                onSelectionChanged: (s) => setState(() => _demo = s.first),
              ),
              const SizedBox(height: 16),
              if (_demo)
                const InfoBanner('Données fictives sur le téléphone. Code OTP : 123456.')
              else ...[
                TextField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: _onHost,
                  decoration: const InputDecoration(
                    labelText: 'Adresse du serveur',
                    hintText: '192.168.1.50',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Avancé', style: TextStyle(fontWeight: FontWeight.w600)),
                  children: [
                    TextField(
                      controller: _keycloak,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'URL Keycloak'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fineract,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'URL API Fineract'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                const InfoBanner(
                  'Changer de serveur efface la session et le code PIN enregistrés sur ce téléphone.',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.amber,
                ),
              ],
              const SizedBox(height: 18),
              PrimaryButton(label: 'Enregistrer', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
