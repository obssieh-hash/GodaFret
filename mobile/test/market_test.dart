import 'package:flutter_test/flutter_test.dart';
import 'package:golden_bridge_pay/core/formatters.dart';
import 'package:golden_bridge_pay/models/market.dart';
import 'package:golden_bridge_pay/services/market_service.dart';
import 'package:golden_bridge_pay/state/market_controller.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('formats des cours : dollars, francs Djibouti, points, pourcentages', () {
    expect(Fmt.price(96500), '96 500,00 \$');
    expect(Fmt.price(0.3478), '0,3478 \$');
    expect(Fmt.price(100, djf: true), '17 772 Fdj');
    expect(Fmt.price(6050.5, points: true, djf: true), '6 050,50 pts');
    expect(Fmt.percent(2.345), '+2,35 %');
    expect(Fmt.percent(-0.8), '−0,80 %');
  });

  test('hors ligne : données indicatives cohérentes, graphiques terminés sur le cours', () async {
    final service = MarketService(live: false);
    final snap = await service.load();
    expect(snap.anyLive, isFalse);
    expect(snap.assets.where((a) => a.kind == AssetKind.crypto), hasLength(8));
    expect(snap.assets.where((a) => a.kind.isBourse), hasLength(12));
    for (final a in snap.assets) {
      expect(a.price, greaterThan(0), reason: a.name);
      expect(a.sparkline.length, greaterThan(10), reason: a.name);
      for (final r in ChartRange.values) {
        final h = await service.history(a, r);
        expect(h.last.price, closeTo(a.price, a.price * 1e-9), reason: '${a.name} ${r.label}');
        expect(h.every((p) => p.price > 0), isTrue, reason: '${a.name} ${r.label}');
      }
    }
  });

  test('liste suivie, filtres et devise', () async {
    final m = MarketController(MarketService(live: false));
    await m.refresh();
    expect(m.filtered(MarketFilter.watchlist).map((a) => a.id).toSet(), MarketController.defaultWatchlist);
    m.toggleWatch('solana');
    expect(m.filtered(MarketFilter.watchlist).any((a) => a.id == 'solana'), isTrue);
    m.toggleWatch('solana');
    expect(m.filtered(MarketFilter.watchlist).any((a) => a.id == 'solana'), isFalse);
    expect(m.filtered(MarketFilter.bourse).every((a) => a.kind != AssetKind.crypto), isTrue);
    expect(m.movers.any((a) => a.symbol == 'USDT'), isFalse);
    m.toggleCurrency();
    expect(m.inDjf, isTrue);
  });
}
