/// Données de marché (consultation uniquement) : cryptomonnaies et bourse.
library;

enum AssetKind { crypto, stock, marketIndex, commodity }

extension AssetKindLabel on AssetKind {
  String get label => switch (this) {
        AssetKind.crypto => 'Crypto',
        AssetKind.stock => 'Action',
        AssetKind.marketIndex => 'Indice',
        AssetKind.commodity => 'Matière première',
      };

  bool get isBourse => this != AssetKind.crypto;
}

/// Un actif suivi. Les prix sont en dollars US (devise de cotation).
class MarketAsset {
  const MarketAsset({
    required this.id,
    required this.symbol,
    required this.name,
    required this.kind,
    required this.price,
    required this.changePct,
    this.sparkline = const [],
    this.high24h,
    this.low24h,
    this.marketCap,
    this.volume,
    this.logoUrl,
    this.exchange,
  });

  /// Identifiant chez le fournisseur : id CoinGecko (« bitcoin ») ou symbole Yahoo (« AAPL »).
  final String id;
  final String symbol;
  final String name;
  final AssetKind kind;
  final double price;

  /// Variation sur 24 h (crypto) ou depuis la clôture précédente (bourse), en %.
  final double changePct;
  final List<double> sparkline;
  final double? high24h;
  final double? low24h;
  final double? marketCap;
  final double? volume;
  final String? logoUrl;
  final String? exchange;

  bool get up => changePct >= 0;
}

/// Période d'un graphique de cours.
enum ChartRange { day, week, month, year }

extension ChartRangeLabel on ChartRange {
  String get label => switch (this) {
        ChartRange.day => '1J',
        ChartRange.week => '1S',
        ChartRange.month => '1M',
        ChartRange.year => '1A',
      };

  Duration get span => switch (this) {
        ChartRange.day => const Duration(days: 1),
        ChartRange.week => const Duration(days: 7),
        ChartRange.month => const Duration(days: 30),
        ChartRange.year => const Duration(days: 365),
      };
}

class PricePoint {
  const PricePoint(this.time, this.price);
  final DateTime time;
  final double price;
}
