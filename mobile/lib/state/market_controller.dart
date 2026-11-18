import 'package:flutter/foundation.dart';

import '../models/market.dart';
import '../services/market_service.dart';
import '../services/secure_store.dart';

enum MarketFilter { all, watchlist, crypto, bourse }

/// État de l'onglet « Marchés » : cours, liste de favoris, devise d'affichage.
class MarketController extends ChangeNotifier {
  MarketController(this.service, {this.store});

  final MarketService service;
  final SecureStore? store;

  static const _watchKey = 'market_watchlist';
  static const _currencyKey = 'market_currency';
  static const defaultWatchlist = {'bitcoin', 'ethereum', 'AAPL', 'GC=F'};

  MarketSnapshot? snapshot;
  bool loading = false;
  String? error;
  Set<String> watchlist = {...defaultWatchlist};

  /// Affichage en francs Djibouti (sinon en dollars, devise de cotation).
  bool inDjf = false;
  bool _prefsLoaded = false;

  List<MarketAsset> get assets => snapshot?.assets ?? const [];

  List<MarketAsset> filtered(MarketFilter f) => switch (f) {
        MarketFilter.all => assets,
        MarketFilter.watchlist => assets.where((a) => watchlist.contains(a.id)).toList(),
        MarketFilter.crypto => assets.where((a) => a.kind == AssetKind.crypto).toList(),
        MarketFilter.bourse => assets.where((a) => a.kind.isBourse).toList(),
      };

  /// Plus fortes variations (hausse ou baisse), hors stablecoins.
  List<MarketAsset> get movers {
    final list = assets.where((a) => a.symbol != 'USDT').toList()
      ..sort((a, b) => b.changePct.abs().compareTo(a.changePct.abs()));
    return list.take(6).toList();
  }

  MarketAsset? byId(String id) => assets.where((a) => a.id == id).firstOrNull;

  bool get stale => snapshot == null || DateTime.now().difference(snapshot!.at) > const Duration(minutes: 1);

  Future<void> ensureLoaded() async {
    if (stale && !loading) await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!_prefsLoaded) await _loadPrefs();
      snapshot = await service.load();
    } catch (e) {
      error = 'Cours indisponibles pour le moment.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<List<PricePoint>> history(MarketAsset asset, ChartRange range) => service.history(
        asset,
        range,
        liveData: asset.kind == AssetKind.crypto ? snapshot?.liveCrypto ?? false : snapshot?.liveBourse ?? false,
      );

  bool isLive(MarketAsset a) =>
      a.kind == AssetKind.crypto ? snapshot?.liveCrypto ?? false : snapshot?.liveBourse ?? false;

  void toggleWatch(String id) {
    watchlist = {...watchlist};
    if (!watchlist.remove(id)) watchlist.add(id);
    notifyListeners();
    store?.write(_watchKey, watchlist.join(','));
  }

  void toggleCurrency() {
    inDjf = !inDjf;
    notifyListeners();
    store?.write(_currencyKey, inDjf ? 'DJF' : 'USD');
  }

  Future<void> _loadPrefs() async {
    _prefsLoaded = true;
    final store = this.store;
    if (store == null) return;
    try {
      final saved = await store.read(_watchKey);
      if (saved != null) watchlist = saved.split(',').where((s) => s.isNotEmpty).toSet();
      inDjf = await store.read(_currencyKey) == 'DJF';
    } catch (_) {
      // Préférences facultatives.
    }
  }
}
