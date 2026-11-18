import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/market.dart';

/// Cours formaté d'un actif selon la devise choisie.
String assetPrice(MarketAsset a, double value, {required bool djf}) =>
    Fmt.price(value, djf: djf, points: a.kind == AssetKind.marketIndex);

/// Pastille ronde : logo du fournisseur (crypto) ou monogramme coloré.
class AssetLogo extends StatelessWidget {
  const AssetLogo(this.asset, {super.key, this.size = 40});
  final MarketAsset asset;
  final double size;

  static const _colors = <String, Color>{
    'BTC': Color(0xFFF7931A),
    'ETH': Color(0xFF627EEA),
    'USDT': Color(0xFF26A17B),
    'BNB': Color(0xFFF0B90B),
    'SOL': Color(0xFF9945FF),
    'XRP': Color(0xFF23292F),
    'ADA': Color(0xFF0033AD),
    'DOGE': Color(0xFFC2A633),
    'AAPL': Color(0xFF111111),
    'MSFT': Color(0xFF00A4EF),
    'NVDA': Color(0xFF76B900),
    'AMZN': Color(0xFFFF9900),
    'GOOGL': Color(0xFF4285F4),
    'TSLA': Color(0xFFE31937),
    'META': Color(0xFF0866FF),
    'OR': Color(0xFFD4A017),
    'BRENT': Color(0xFF3B3B3B),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[asset.symbol] ?? AppColors.navyLight;
    final label = asset.kind == AssetKind.marketIndex
        ? asset.symbol.replaceAll(RegExp(r'[^A-Z0-9]'), '').substring(0, 2)
        : asset.symbol.substring(0, 1);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: asset.kind == AssetKind.commodity
          ? Icon(asset.symbol == 'OR' ? Icons.diamond_rounded : Icons.oil_barrel_rounded, color: Colors.white, size: size * 0.5)
          : Text(
              label,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * (label.length > 1 ? 0.34 : 0.44)),
            ),
    );
    final url = asset.logoUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
      ),
    );
  }
}

/// Variation colorée : « ▲ 2,35 % ».
class ChangePill extends StatelessWidget {
  const ChangePill(this.pct, {super.key, this.filled = true, this.fontSize = 12.5});
  final double pct;
  final bool filled;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final color = up ? AppColors.green : AppColors.red;
    final text = Text(
      '${up ? '▲' : '▼'} ${Fmt.percent(pct).substring(1)}',
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: fontSize, fontFeatures: const [FontFeature.tabularFigures()]),
    );
    if (!filled) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: text,
    );
  }
}

/// Mini-graphique de tendance.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.color, this.width = 64, this.height = 28, this.fill = true});
  final List<double> values;
  final Color? color;
  final double width;
  final double height;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (values.length < 2 || values.last >= values.first ? AppColors.green : AppColors.red);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: values.length < 2 ? null : CustomPaint(painter: _LinePainter(values, c, fill: fill, stroke: 1.6)),
      ),
    );
  }
}

/// Graphique de cours interactif : glisser le doigt pour lire un point.
class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.points, required this.onScrub, this.height = 220});
  final List<PricePoint> points;
  final ValueChanged<PricePoint?> onScrub;
  final double height;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _index;

  void _update(Offset local, double width) {
    final n = widget.points.length;
    if (n < 2) return;
    final i = ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _index) {
      HapticFeedback.selectionClick();
      setState(() => _index = i);
      widget.onScrub(widget.points[i]);
    }
  }

  void _end() {
    setState(() => _index = null);
    widget.onScrub(null);
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.points.map((p) => p.price).toList();
    final up = values.length < 2 || values.last >= values.first;
    final color = up ? AppColors.green : AppColors.red;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _update(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _update(d.localPosition, box.maxWidth),
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        onLongPressStart: (d) => _update(d.localPosition, box.maxWidth),
        onLongPressMoveUpdate: (d) => _update(d.localPosition, box.maxWidth),
        onLongPressEnd: (_) => _end(),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: values.length < 2
              ? null
              : CustomPaint(
                  painter: _LinePainter(
                    values,
                    color,
                    fill: true,
                    stroke: 2.2,
                    baseline: Theme.of(context).colorScheme.outlineVariant,
                    cursor: _index,
                    cursorColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color, {required this.fill, required this.stroke, this.baseline, this.cursor, this.cursorColor});
  final List<double> values;
  final Color color;
  final bool fill;
  final double stroke;
  final Color? baseline;
  final int? cursor;
  final Color? cursorColor;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    final pad = stroke + 2;
    double x(int i) => i / (values.length - 1) * size.width;
    double y(double v) => pad + (1 - (v - lo) / (hi - lo)) * (size.height - pad * 2);

    if (baseline != null) {
      final dash = Paint()
        ..color = baseline!
        ..strokeWidth = 1;
      final by = y(values.first);
      for (double dx = 0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, by), Offset(math.min(dx + 4, size.width), by), dash);
      }
    }

    final path = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      // Courbe lissée entre deux points.
      final px = x(i - 1), py = y(values[i - 1]);
      final cx = x(i), cy = y(values[i]);
      final mx = (px + cx) / 2;
      path.cubicTo(mx, py, mx, cy, cx, cy);
    }

    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final i = cursor;
    if (i != null) {
      final cx = x(i), cy = y(values[i]);
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), Paint()
        ..color = (cursorColor ?? color).withValues(alpha: 0.35)
        ..strokeWidth = 1);
      canvas.drawCircle(Offset(cx, cy), 6, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color || old.cursor != cursor || old.baseline != baseline;
}
