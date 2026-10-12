import 'package:intl/intl.dart';

/// Formats français : montants, dates, dates Fineract.
class Fmt {
  static String money(num value, {String currency = 'DJF', bool signed = false}) {
    final f = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: _symbol(currency),
      decimalDigits: decimals(currency),
    );
    // L'espace fine insécable (U+202F) n'existe pas dans Poppins : espace insécable classique.
    final text = f.format(value.abs()).replaceAll('\u202f', '\u00a0');
    if (signed) return '${value < 0 ? '−' : '+'} $text';
    return value < 0 ? '−$text' : text;
  }

  static String compact(num value, {String currency = 'DJF'}) {
    final f = NumberFormat.compactCurrency(locale: 'fr_FR', symbol: _symbol(currency));
    return f.format(value).replaceAll('\u202f', '\u00a0');
  }

  /// Nombre de décimales d'une devise (le franc Djibouti n'en a pas).
  static int decimals(String code) => switch (code) {
        'DJF' || 'XOF' || 'XAF' || 'JPY' => 0,
        _ => 2,
      };

  static String symbol(String code) => _symbol(code);

  static String _symbol(String code) => switch (code) {
        'DJF' => 'Fdj',
        'EUR' => '€',
        'USD' => r'$',
        'XOF' || 'XAF' => 'FCFA',
        'MAD' => 'DH',
        'GBP' => '£',
        _ => code,
      };

  static String date(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy', 'fr_FR').format(d);
  static String shortDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM', 'fr_FR').format(d);
  static String dayHeader(DateTime d) {
    final today = DateTime.now();
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    return DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  }

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return date(d);
  }

  /// Format de date envoyé à Fineract (avec `dateFormat: yyyy-MM-dd`).
  static String api(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Fineract renvoie les dates sous forme `[2026, 10, 5]` ou `"2026-10-05"`.
  static DateTime? parseFineract(dynamic raw) {
    if (raw == null) return null;
    if (raw is List && raw.length >= 3) {
      return DateTime(raw[0] as int, raw[1] as int, raw[2] as int);
    }
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  /// « 77101010 » → « 77 10 10 10 ».
  static String phone(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    final local = digits.startsWith('+253') ? digits.substring(4) : digits;
    if (local.length != 8) return raw;
    return '${local.substring(0, 2)} ${local.substring(2, 4)} ${local.substring(4, 6)} ${local.substring(6)}';
  }

  static String maskAccount(String accountNo) {
    if (accountNo.length <= 4) return accountNo;
    return '•••• ${accountNo.substring(accountNo.length - 4)}';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

double toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
