import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';

/// 💳 Demande de prêt avec simulation de l'échéancier (Fineract
/// `POST /loans?command=calculateLoanSchedule`, puis `POST /loans`).
class LoanRequestScreen extends StatefulWidget {
  const LoanRequestScreen({super.key});

  @override
  State<LoanRequestScreen> createState() => _LoanRequestScreenState();
}

class _LoanRequestScreenState extends State<LoanRequestScreen> {
  late final Future<List<LoanProduct>> _products = context.read<BankController>().repo.loanProducts();
  final _purpose = TextEditingController();
  LoanProduct? _product;
  double _amount = 0;
  int _months = 12;
  LoanSimulation? _simulation;
  bool _simulating = false;
  bool _sending = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _purpose.dispose();
    super.dispose();
  }

  double get _min => _product?.minPrincipal ?? 100;
  double get _max => _product?.maxPrincipal ?? 50000;
  int get _minMonths => _product?.minRepayments ?? 1;
  int get _maxMonths => _product?.maxRepayments ?? 120;

  void _select(LoanProduct p) {
    setState(() {
      _product = p;
      _amount = (p.defaultPrincipal ?? (_min + _max) / 2).clamp(_min, _max).toDouble();
      _months = (p.defaultRepayments ?? 12).clamp(_minMonths, _maxMonths);
    });
    _simulate();
  }

  void _simulate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final p = _product;
      if (p == null) return;
      setState(() {
        _simulating = true;
        _error = null;
      });
      try {
        final s = await context.read<BankController>().repo.simulateLoan(p, _amount, _months);
        if (mounted) setState(() => _simulation = s);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      } finally {
        if (mounted) setState(() => _simulating = false);
      }
    });
  }

  Future<void> _submit() async {
    final p = _product;
    if (p == null) return;
    final ok = await confirmWithPin(
      context,
      title: 'Envoyer la demande',
      summary: '${p.name} · ${Fmt.money(_amount, currency: p.currency)} sur $_months mois',
    );
    if (!ok || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<BankController>().perform(
            (repo) => repo.applyForLoan(p, _amount, _months, purpose: _purpose.text.trim()),
          );
      if (!mounted) return;
      await SuccessScreen.show(
        context,
        title: 'Demande envoyée',
        message: 'Votre conseiller étudie votre dossier. Vous serez notifié de la décision.',
        details: [
          ('Produit', p.name),
          ('Montant', Fmt.money(_amount, currency: p.currency)),
          ('Durée', '$_months échéances'),
          if (_simulation != null) ('Mensualité estimée', Fmt.money(_simulation!.monthly, currency: p.currency)),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demande de prêt')),
      body: FutureBuilder<List<LoanProduct>>(
        future: _products,
        builder: (context, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(20), child: ErrorBanner('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final products = snap.data!;
          if (products.isEmpty) {
            return const EmptyState(icon: Icons.inventory_2_outlined, title: 'Aucun produit de prêt disponible');
          }
          final p = _product;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              const SectionHeader('1. Choisissez un produit'),
              for (final prod in products) ...[
                _ProductTile(product: prod, selected: prod.id == p?.id, onTap: () => _select(prod)),
                const SizedBox(height: 10),
              ],
              if (p != null) ...[
                const SizedBox(height: 10),
                const SectionHeader('2. Montant et durée'),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SliderLabel('Montant', Fmt.money(_amount, currency: p.currency)),
                      Slider(
                        value: _amount,
                        min: _min,
                        max: _max,
                        divisions: ((_max - _min) / 100).round().clamp(1, 1000),
                        onChanged: (v) => setState(() => _amount = (v / 100).round() * 100.0),
                        onChangeEnd: (_) => _simulate(),
                      ),
                      _Bounds(Fmt.money(_min, currency: p.currency), Fmt.money(_max, currency: p.currency)),
                      const SizedBox(height: 16),
                      _SliderLabel('Durée', '$_months échéances'),
                      Slider(
                        value: _months.toDouble(),
                        min: _minMonths.toDouble(),
                        max: _maxMonths.toDouble(),
                        divisions: (_maxMonths - _minMonths).clamp(1, 1000),
                        onChanged: (v) => setState(() => _months = v.round()),
                        onChangeEnd: (_) => _simulate(),
                      ),
                      _Bounds('$_minMonths', '$_maxMonths'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SimulationCard(simulation: _simulation, loading: _simulating, currency: p.currency, principal: _amount),
                const SizedBox(height: 18),
                TextField(
                  controller: _purpose,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Objet du prêt (facultatif)',
                    prefixIcon: Icon(Icons.lightbulb_outline_rounded),
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(_error!)],
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Envoyer ma demande',
                  icon: Icons.send_rounded,
                  loading: _sending,
                  onPressed: _simulating ? null : _submit,
                ),
                const SizedBox(height: 12),
                const InfoBanner(
                  'Simulation indicative. Votre demande sera étudiée par un conseiller avant approbation et décaissement.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.selected, required this.onTap});
  final LoanProduct product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final range = product.minPrincipal != null && product.maxPrincipal != null
        ? '${Fmt.compact(product.minPrincipal!, currency: product.currency)} – ${Fmt.compact(product.maxPrincipal!, currency: product.currency)}'
        : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 1.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const IconBadge(Icons.request_quote_rounded, color: AppColors.sky, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    if (product.description != null && product.description!.isNotEmpty)
                      Text(product.description!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (range != null) Text(range, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        if (product.interestRate != null)
                          Text('${product.interestRate!.toStringAsFixed(2).replaceAll('.', ',')} %/période',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.teal)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? scheme.primary : scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderLabel extends StatelessWidget {
  const _SliderLabel(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      );
}

class _Bounds extends StatelessWidget {
  const _Bounds(this.min, this.max);
  final String min;
  final String max;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [Text(min, style: style), const Spacer(), Text(max, style: style)]),
    );
  }
}

class _SimulationCard extends StatelessWidget {
  const _SimulationCard({required this.simulation, required this.loading, required this.currency, required this.principal});
  final LoanSimulation? simulation;
  final bool loading;
  final String currency;
  final double principal;

  @override
  Widget build(BuildContext context) {
    final s = simulation;
    return GradientCard(
      gradient: AppColors.tealGradient,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: loading ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mensualité estimée', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              s == null ? '—' : Fmt.money(s.monthly, currency: currency),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _White('Coût des intérêts', s == null ? '—' : Fmt.money(s.totalInterest, currency: currency))),
                Expanded(child: _White('Total à rembourser', s == null ? '—' : Fmt.money(s.totalRepayment, currency: currency))),
              ],
            ),
            if (s != null && s.installments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Première échéance le ${Fmt.date(s.installments.first.dueDate)}, dernière le ${Fmt.date(s.installments.last.dueDate)}.',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _White extends StatelessWidget {
  const _White(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
        ],
      );
}
