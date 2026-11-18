import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../models/market.dart';
import '../../../state/market_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/market_widgets.dart';
import '../home/home_shell.dart';
import 'asset_detail_screen.dart';

/// 📈 Marchés : bourse et cryptomonnaies, en consultation.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  MarketFilter _filter = MarketFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MarketController>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MarketController>();
    final scheme = Theme.of(context).colorScheme;
    final list = m.filtered(_filter);
    final snap = m.snapshot;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: m.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Marchés', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  ),
                  _CurrencySwitch(djf: m.inDjf, onTap: m.toggleCurrency),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                snap == null
                    ? 'Chargement des cours…'
                    : snap.fullyLive
                    ? 'Cours en direct · mis à jour ${Fmt.relative(snap.at).toLowerCase()}'
                    : snap.anyLive
                    ? 'En direct en partie · certaines valeurs indicatives'
                    : 'Hors ligne · valeurs indicatives',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (m.error != null) ...[ErrorBanner(m.error!, onRetry: m.refresh), const SizedBox(height: 12)],
              if (snap == null && m.loading)
                const _Skeleton()
              else ...[
                if (m.movers.isNotEmpty) ...[
                  const SectionHeader('Plus fortes variations'),
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: m.movers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _MoverCard(asset: m.movers[i], djf: m.inDjf),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                _FilterTabs(value: _filter, onChanged: (f) => setState(() => _filter = f)),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.star_border_rounded,
                          title: 'Votre liste est vide',
                          message: "Ouvrez un actif et touchez l'étoile pour le suivre.",
                        )
                      : Column(
                          children: [for (final a in list) AssetTile(asset: a, djf: m.inDjf)],
                        ),
                ),
              ],
              const SizedBox(height: 18),
              const InfoBanner(
                "Consultation uniquement : Golden Bridge Bank n'achète ni ne vend d'actifs pour vous. "
                'Les cours, fournis par CoinGecko et Yahoo Finance, peuvent être différés. Les crypto-actifs sont très volatils.',
                icon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sélecteur pleine largeur : Tout, Ma liste, Crypto, Bourse.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.value, required this.onChanged});
  final MarketFilter value;
  final ValueChanged<MarketFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (f, label) in const [
            (MarketFilter.all, 'Tout'),
            (MarketFilter.watchlist, 'Ma liste'),
            (MarketFilter.crypto, 'Crypto'),
            (MarketFilter.bourse, 'Bourse'),
          ])
            Expanded(
              child: Semantics(
                button: true,
                selected: value == f,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == f ? scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: value == f
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: value == f ? FontWeight.w600 : FontWeight.w500,
                        color: value == f ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrencySwitch extends StatelessWidget {
  const _CurrencySwitch({required this.djf, required this.onTap});
  final bool djf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(String label, bool on) => AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: on ? scheme.onSurface : Colors.transparent, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: on ? scheme.surface : scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
    return Semantics(
      button: true,
      label: djf ? 'Afficher en dollars' : 'Afficher en francs Djibouti',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(22)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [seg(r'$', !djf), seg('Fdj', djf)]),
        ),
      ),
    );
  }
}

/// Ligne d'actif : logo, nom, tendance, cours et variation.
class AssetTile extends StatelessWidget {
  const AssetTile({super.key, required this.asset, required this.djf, this.dense = false});
  final MarketAsset asset;
  final bool djf;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '${asset.name}, ${assetPrice(asset, asset.price, djf: djf)}, ${Fmt.percent(asset.changePct)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => push(context, AssetDetailScreen(assetId: asset.id)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
          child: Row(
            children: [
              AssetLogo(asset, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      asset.kind == AssetKind.stock || asset.kind == AssetKind.crypto ? asset.symbol : asset.kind.label,
                      style: TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Sparkline(asset.sparkline, width: 56, height: 26),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 124),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        assetPrice(asset, asset.price, djf: djf),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                    const SizedBox(height: 3),
                    ChangePill(asset.changePct, filled: false, fontSize: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoverCard extends StatelessWidget {
  const _MoverCard({required this.asset, required this.djf});
  final MarketAsset asset;
  final bool djf;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        onTap: () => push(context, AssetDetailScreen(assetId: asset.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AssetLogo(asset, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    asset.symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Sparkline(asset.sparkline, width: 120, height: 30),
            const SizedBox(height: 8),
            ChangePill(asset.changePct),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainer;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
    );
    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar(110, 12), const SizedBox(height: 6), bar(50, 10)],
                  ),
                ),
                bar(80, 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// Carte « Marchés » de l'accueil : la liste suivie en un coup d'œil.
class MarketsPreviewCard extends StatelessWidget {
  const MarketsPreviewCard({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MarketController>();
    final items = m.filtered(MarketFilter.watchlist).take(3).toList();
    final shown = items.isEmpty ? m.assets.take(3).toList() : items;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.candlestick_chart_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Bourse et crypto', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                ),
                if (m.loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Chargement des cours…')),
            )
          else
            for (final a in shown) AssetTile(asset: a, djf: m.inDjf, dense: true),
          TextButton(onPressed: onSeeAll, child: const Text('Voir les marchés')),
        ],
      ),
    );
  }
}
