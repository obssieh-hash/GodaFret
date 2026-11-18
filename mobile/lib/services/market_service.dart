import 'dart:math';

import 'package:dio/dio.dart';

import '../models/market.dart';

/// Taux fixe du franc Djibouti (arrimé au dollar US depuis 1949).
const double djfPerUsd = 177.721;

/// Description d'un actif suivi et valeurs de repli quand le réseau est indisponible.
class _Spec {
  const _Spec(this.id, this.symbol, this.name, this.kind, this.base, this.vol, {this.cap});
  final String id;
  final String symbol;
  final String name;
  final AssetKind kind;
  final double base;

  /// Volatilité journalière typique (écart type, en fraction).
  final double vol;
  final double? cap;
}

const _crypto = [
  _Spec('bitcoin', 'BTC', 'Bitcoin', AssetKind.crypto, 96500, 0.028, cap: 1.9e12),
  _Spec('ethereum', 'ETH', 'Ethereum', AssetKind.crypto, 3450, 0.035, cap: 4.1e11),
  _Spec('tether', 'USDT', 'Tether', AssetKind.crypto, 1.0, 0.0004, cap: 1.4e11),
  _Spec('binancecoin', 'BNB', 'BNB', AssetKind.crypto, 655, 0.03, cap: 9.5e10),
  _Spec('solana', 'SOL', 'Solana', AssetKind.crypto, 188, 0.045, cap: 9.0e10),
  _Spec('ripple', 'XRP', 'XRP', AssetKind.crypto, 2.35, 0.05, cap: 1.3e11),
  _Spec('cardano', 'ADA', 'Cardano', AssetKind.crypto, 0.92, 0.05, cap: 3.2e10),
  _Spec('dogecoin', 'DOGE', 'Dogecoin', AssetKind.crypto, 0.36, 0.06, cap: 5.3e10),
];

const _bourse = [
  _Spec('AAPL', 'AAPL', 'Apple', AssetKind.stock, 242, 0.015),
  _Spec('MSFT', 'MSFT', 'Microsoft', AssetKind.stock, 438, 0.014),
  _Spec('NVDA', 'NVDA', 'Nvidia', AssetKind.stock, 152, 0.03),
  _Spec('AMZN', 'AMZN', 'Amazon', AssetKind.stock, 224, 0.018),
  _Spec('GOOGL', 'GOOGL', 'Alphabet', AssetKind.stock, 192, 0.017),
  _Spec('TSLA', 'TSLA', 'Tesla', AssetKind.stock, 335, 0.035),
  _Spec('META', 'META', 'Meta', AssetKind.stock, 610, 0.02),
  _Spec('^GSPC', 'S&P 500', 'S&P 500', AssetKind.marketIndex, 6050, 0.008),
  _Spec('^IXIC', 'NASDAQ', 'Nasdaq Composite', AssetKind.marketIndex, 19800, 0.011),
  _Spec('^FCHI', 'CAC 40', 'CAC 40 (Paris)', AssetKind.marketIndex, 7450, 0.009),
  _Spec('GC=F', 'OR', 'Or (once)', AssetKind.commodity, 2720, 0.009),
  _Spec('BZ=F', 'BRENT', 'Pétrole Brent (baril)', AssetKind.commodity, 74, 0.017),
];

/// Résultat d'un chargement : les actifs et l'origine des données.
class MarketSnapshot {
  const MarketSnapshot({required this.assets, required this.liveCrypto, required this.liveBourse, required this.at});
  final List<MarketAsset> assets;
  final bool liveCrypto;
  final bool liveBourse;
  final DateTime at;

  bool get fullyLive => liveCrypto && liveBourse;
  bool get anyLive => liveCrypto || liveBourse;
}

/// Cours des cryptomonnaies (CoinGecko) et de la bourse (Yahoo Finance),
/// en lecture seule et sans clé d'API. Sans réseau, des valeurs indicatives
/// sont générées pour que l'écran reste utilisable (et clairement signalées).
class MarketService {
  MarketService({Dio? dio, this.live = true})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;

  /// `false` : jamais d'appel réseau (tests, mode hors ligne).
  final bool live;

  static const _coingecko = 'https://api.coingecko.com/api/v3';
  static const _yahoo = 'https://query1.finance.yahoo.com/v8/finance/chart';

  Future<MarketSnapshot> load() async {
    final results = await Future.wait([_loadCrypto(), _loadBourse()]);
    final crypto = results[0];
    final bourse = results[1];
    return MarketSnapshot(
      assets: [...crypto.$1, ...bourse.$1],
      liveCrypto: crypto.$2,
      liveBourse: bourse.$2,
      at: DateTime.now(),
    );
  }

  Future<(List<MarketAsset>, bool)> _loadCrypto() async {
    if (live) {
      try {
        final res = await _dio.get<List<dynamic>>('$_coingecko/coins/markets', queryParameters: {
          'vs_currency': 'usd',
          'ids': _crypto.map((s) => s.id).join(','),
          'sparkline': 'true',
          'price_change_percentage': '24h',
        });
        final byId = {for (final m in res.data!.cast<Map<String, dynamic>>()) m['id'] as String: m};
        final assets = <MarketAsset>[];
        for (final s in _crypto) {
          final m = byId[s.id];
          if (m == null) continue;
          final spark = ((m['sparkline_in_7d'] as Map?)?['price'] as List?)?.whereType<num>().map((v) => v.toDouble()).toList() ?? [];
          assets.add(MarketAsset(
            id: s.id,
            symbol: (m['symbol'] as String? ?? s.symbol).toUpperCase(),
            name: m['name'] as String? ?? s.name,
            kind: AssetKind.crypto,
            price: (m['current_price'] as num).toDouble(),
            changePct: (m['price_change_percentage_24h'] as num?)?.toDouble() ?? 0,
            // Les dernières 24 h du graphique 7 jours (points horaires).
            sparkline: spark.length > 24 ? spark.sublist(spark.length - 24) : spark,
            high24h: (m['high_24h'] as num?)?.toDouble(),
            low24h: (m['low_24h'] as num?)?.toDouble(),
            marketCap: (m['market_cap'] as num?)?.toDouble(),
            volume: (m['total_volume'] as num?)?.toDouble(),
            logoUrl: m['image'] as String?,
          ));
        }
        if (assets.isNotEmpty) return (assets, true);
      } catch (_) {
        // Repli hors ligne ci-dessous.
      }
    }
    return (_crypto.map(_offline).toList(), false);
  }

  Future<(List<MarketAsset>, bool)> _loadBourse() async {
    if (live) {
      try {
        final assets = await Future.wait(_bourse.map(_yahooQuote));
        return (assets, true);
      } catch (_) {
        // Repli hors ligne ci-dessous.
      }
    }
    return (_bourse.map(_offline).toList(), false);
  }

  Future<MarketAsset> _yahooQuote(_Spec s) async {
    final chart = await _yahooChart(s.id, range: '1d', interval: '5m');
    final meta = chart.meta;
    final price = (meta['regularMarketPrice'] as num).toDouble();
    final prev = (meta['chartPreviousClose'] as num? ?? meta['previousClose'] as num?)?.toDouble();
    return MarketAsset(
      id: s.id,
      symbol: s.symbol,
      name: s.name,
      kind: s.kind,
      price: price,
      changePct: prev == null || prev == 0 ? 0 : (price - prev) / prev * 100,
      sparkline: chart.points.map((p) => p.price).toList(),
      high24h: (meta['regularMarketDayHigh'] as num?)?.toDouble(),
      low24h: (meta['regularMarketDayLow'] as num?)?.toDouble(),
      volume: (meta['regularMarketVolume'] as num?)?.toDouble(),
      exchange: meta['fullExchangeName'] as String? ?? meta['exchangeName'] as String?,
    );
  }

  Future<({Map<String, dynamic> meta, List<PricePoint> points})> _yahooChart(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_yahoo/${Uri.encodeComponent(symbol)}',
      queryParameters: {'range': range, 'interval': interval},
    );
    final result = ((res.data!['chart'] as Map)['result'] as List).first as Map<String, dynamic>;
    final times = (result['timestamp'] as List?)?.cast<num>() ?? const [];
    final quote = (((result['indicators'] as Map)['quote'] as List).first as Map)['close'] as List? ?? const [];
    final points = <PricePoint>[
      for (var i = 0; i < times.length && i < quote.length; i++)
        if (quote[i] is num)
          PricePoint(DateTime.fromMillisecondsSinceEpoch(times[i].toInt() * 1000), (quote[i] as num).toDouble()),
    ];
    return (meta: (result['meta'] as Map).cast<String, dynamic>(), points: points);
  }

  /// Historique d'un actif sur une période (graphique de la fiche détaillée).
  Future<List<PricePoint>> history(MarketAsset asset, ChartRange range, {bool liveData = true}) async {
    if (live && liveData) {
      try {
        if (asset.kind == AssetKind.crypto) {
          final days = range.span.inDays;
          final res = await _dio.get<Map<String, dynamic>>(
            '$_coingecko/coins/${asset.id}/market_chart',
            queryParameters: {'vs_currency': 'usd', 'days': '$days'},
          );
          final prices = (res.data!['prices'] as List).cast<List>();
          final points = [
            for (final p in prices) PricePoint(DateTime.fromMillisecondsSinceEpoch((p[0] as num).toInt()), (p[1] as num).toDouble()),
          ];
          if (points.length > 1) return points;
        } else {
          final (r, i) = switch (range) {
            ChartRange.day => ('1d', '5m'),
            ChartRange.week => ('5d', '30m'),
            ChartRange.month => ('1mo', '1d'),
            ChartRange.year => ('1y', '1d'),
          };
          final chart = await _yahooChart(asset.id, range: r, interval: i);
          if (chart.points.length > 1) return chart.points;
        }
      } catch (_) {
        // Repli hors ligne ci-dessous.
      }
    }
    return _walk(asset, range);
  }

  // --- Données indicatives hors ligne ------------------------------------------

  MarketAsset _offline(_Spec s) {
    final now = DateTime.now();
    final rnd = Random(s.symbol.hashCode ^ (now.year * 1000 + now.month * 40 + now.day));
    final change = (rnd.nextDouble() * 2 - 1) * s.vol * 100;
    final price = s.base * (1 + change / 100);
    final asset = MarketAsset(
      id: s.id,
      symbol: s.symbol,
      name: s.name,
      kind: s.kind,
      price: price,
      changePct: change,
      marketCap: s.cap,
    );
    final spark = _walk(asset, ChartRange.day, points: 24).map((p) => p.price).toList();
    final hi = spark.reduce(max);
    final lo = spark.reduce(min);
    return MarketAsset(
      id: s.id,
      symbol: s.symbol,
      name: s.name,
      kind: s.kind,
      price: price,
      changePct: change,
      sparkline: spark,
      high24h: hi,
      low24h: lo,
      marketCap: s.cap,
    );
  }

  /// Marche aléatoire déterministe qui part du cours d'ouverture implicite
  /// et se termine exactement sur le cours actuel.
  List<PricePoint> _walk(MarketAsset asset, ChartRange range, {int points = 60}) {
    final spec = [..._crypto, ..._bourse].where((s) => s.id == asset.id).firstOrNull;
    final vol = spec?.vol ?? 0.02;
    final days = range.span.inHours / 24;
    final rnd = Random(asset.id.hashCode ^ range.index * 7919);
    final start = asset.price / (1 + asset.changePct / 100 * (range == ChartRange.day ? 1 : days.clamp(1, 6)));
    // Écart type total sur la période, plafonné pour rester vraisemblable.
    final step = min(vol * sqrt(days), 0.6) / sqrt(points.toDouble());
    final raw = <double>[start];
    for (var i = 1; i < points; i++) {
      raw.add(raw.last * exp((rnd.nextDouble() * 2 - 1) * step * 1.7));
    }
    // Recale (en proportion) pour finir exactement sur le prix actuel.
    final ratio = asset.price / raw.last;
    final now = DateTime.now();
    return [
      for (var i = 0; i < points; i++)
        PricePoint(
          now.subtract(range.span * ((points - 1 - i) / (points - 1))),
          i == points - 1 ? asset.price : raw[i] * pow(ratio, i / (points - 1)),
        ),
    ];
  }
}
