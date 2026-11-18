import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../models/market.dart';
import '../../../services/market_service.dart';
import '../../../state/market_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/market_widgets.dart';

/// Fiche d'un actif : cours, graphique interactif, statistiques.
class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});
  final String assetId;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  ChartRange _range = ChartRange.day;
  List<PricePoint>? _points;
  PricePoint? _scrub;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final m = context.read<MarketController>();
    final asset = m.byId(widget.assetId);
    if (asset == null) return;
    setState(() => _loading = true);
    final points = await m.history(asset, _range);
    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MarketController>();
    final asset = m.byId(widget.assetId);
    final scheme = Theme.of(context).colorScheme;
    if (asset == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Actif introuvable')));
    }
    final djf = m.inDjf;
    final watched = m.watchlist.contains(asset.id);
    final points = _points;
    final first = points != null && points.length > 1 ? points.first.price : null;
    final shownPrice = _scrub?.price ?? asset.price;
    final pct = _range == ChartRange.day && _scrub == null
        ? asset.changePct
        : (first == null || first == 0 ? asset.changePct : (shownPrice - first) / first * 100);
    final diff = first == null ? null : shownPrice - first;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: watched ? 'Retirer de ma liste' : 'Ajouter à ma liste',
            onPressed: () {
              m.toggleWatch(asset.id);
              showSnack(context, watched ? 'Retiré de votre liste' : 'Ajouté à votre liste');
            },
            icon: Icon(watched ? Icons.star_rounded : Icons.star_border_rounded, color: watched ? AppColors.gold : null),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              AssetLogo(asset, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(
                      [asset.symbol, asset.kind.label, if (asset.exchange != null) asset.exchange!].join(' · '),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              assetPrice(asset, shownPrice, djf: djf),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ChangePill(pct),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _scrub != null
                      ? DateFormat(_range == ChartRange.day || _range == ChartRange.week ? 'EEE d MMM, HH:mm' : 'd MMM yyyy', 'fr_FR').format(_scrub!.time)
                      : [
                          if (diff != null && asset.kind != AssetKind.marketIndex) '${diff < 0 ? '−' : '+'}${assetPrice(asset, diff.abs(), djf: djf)}',
                          switch (_range) {
                            ChartRange.day => "aujourd'hui",
                            ChartRange.week => 'sur 7 jours',
                            ChartRange.month => 'sur 1 mois',
                            ChartRange.year => 'sur 1 an',
                          },
                        ].join(' '),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: points == null
                ? const Center(child: CircularProgressIndicator())
                : AnimatedOpacity(
                    opacity: _loading ? 0.4 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: PriceChart(points: points, onScrub: (p) => setState(() => _scrub = p)),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final r in ChartRange.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: _range == r,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _range = r);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionHeader('Statistiques'),
          SurfaceCard(
            child: Column(
              children: [
                if (asset.high24h != null) KeyValueRow('Plus haut (jour)', assetPrice(asset, asset.high24h!, djf: djf)),
                if (asset.low24h != null) KeyValueRow('Plus bas (jour)', assetPrice(asset, asset.low24h!, djf: djf)),
                if (asset.marketCap != null) KeyValueRow('Capitalisation', _compact(asset.marketCap!, djf)),
                if (asset.volume != null)
                  KeyValueRow(
                    'Volume',
                    asset.kind == AssetKind.crypto ? _compact(asset.volume!, djf) : NumberFormat.compact(locale: 'fr_FR').format(asset.volume),
                  ),
                if (asset.kind != AssetKind.marketIndex)
                  KeyValueRow(
                    djf ? 'En dollars' : 'En francs Djibouti',
                    assetPrice(asset, asset.price, djf: !djf),
                  ),
                KeyValueRow('Source', m.isLive(asset) ? (asset.kind == AssetKind.crypto ? 'CoinGecko' : 'Yahoo Finance') : 'Indicatif (hors ligne)'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          InfoBanner(
            asset.kind == AssetKind.crypto
                ? "Les crypto-actifs sont très volatils et ne sont pas garantis. Golden Bridge Bank n'en achète ni n'en vend : "
                    'ces cours sont donnés à titre d’information.'
                : "Golden Bridge Bank ne fournit pas de service d'investissement : ces cours, parfois différés, sont donnés à titre d’information.",
            icon: Icons.info_outline_rounded,
          ),
          if (asset.kind != AssetKind.marketIndex) ...[
            const SizedBox(height: 10),
            Text(
              '1 \$ = ${NumberFormat.decimalPatternDigits(locale: 'fr_FR', decimalDigits: 3).format(djfPerUsd)} Fdj (parité fixe)',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Montant abrégé en milliards (Md) ou millions (M), à la française.
  String _compact(double usd, bool djf) {
    final v = djf ? usd * djfPerUsd : usd;
    final (div, unit) = v >= 1e9 ? (1e9, 'Md') : (v >= 1e6 ? (1e6, 'M') : (1.0, ''));
    final n = NumberFormat.decimalPatternDigits(locale: 'fr_FR', decimalDigits: v / div >= 100 ? 0 : 1)
        .format(v / div)
        .replaceAll('\u202f', '\u00a0');
    return '$n\u00a0${unit.isEmpty ? '' : '$unit\u00a0'}${djf ? 'Fdj' : '\$'}';
  }
}
