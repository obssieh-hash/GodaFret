import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';

/// Carte de mise en avant (fond bleu nuit, texte blanc). Plate, sans ombre.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.gradient = AppColors.primaryGradient,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.onTap,
  });

  final Widget child;
  final Gradient gradient;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(radius)),
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Carte grise claire, sans ombre.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Pastille ronde monochrome (fond gris, icône encre).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 42, this.filled = false});

  final IconData icon;

  /// Conservé pour compatibilité ; seules les icônes sémantiques le colorent.
  final Color? color;
  final double size;

  /// Pastille noire, icône blanche (actions principales).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = color == AppColors.green || color == AppColors.red || color == AppColors.amber || color == AppColors.gold;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? scheme.onSurface : (semantic ? color!.withValues(alpha: 0.12) : scheme.surfaceContainerHighest),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size * 0.48,
        color: filled ? scheme.surface : (semantic ? color : scheme.onSurface),
      ),
    );
  }
}

/// Montant qui peut être masqué.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency = 'DJF',
    this.style,
    this.hidden = false,
    this.signed = false,
    this.colored = false,
  });

  final double amount;
  final String currency;
  final TextStyle? style;
  final bool hidden;
  final bool signed;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    // Style Revolut : seuls les crédits sont en vert ; un débit n'a pas de signe « + ».
    final positive = amount >= 0;
    final color = colored && positive ? AppColors.green : style?.color;
    final text = hidden
        ? '•••••'
        : (signed && positive ? '+${Fmt.money(amount, currency: currency)}' : Fmt.money(amount, currency: currency));
    return Text(
      text,
      style: (style ?? const TextStyle()).copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// Avatar à initiales, couleur stable déduite du nom.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44, this.icon});

  final String name;
  final double size;
  final IconData? icon;

  static const _palette = [
    Color(0xFFE8ECF5),
    Color(0xFFFFF1CC),
    Color(0xFFE3F4EC),
    Color(0xFFF7E6E6),
    Color(0xFFEDE7F6),
    Color(0xFFE6F1F8),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF24262C) : _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final fg = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: icon != null
          ? Icon(icon, size: size * 0.46, color: fg)
          : Text(
              Fmt.initials(name),
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: size * 0.36),
            ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w500))),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.icon = Icons.info_outline_rounded, this.color});

  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }
}

/// Bouton principal : pilule noire.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.onDark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// Sur fond sombre : pilule blanche.
  final bool onDark;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: onDark
            ? FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.ink,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                disabledForegroundColor: Colors.white38,
              )
            : null,
        onPressed: loading ? null : onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  ],
                ),
        ),
      );
}

/// Ligne « libellé — valeur » pour les récapitulatifs.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: valueColor),
              ),
            ),
          ],
        ),
      );
}

/// Champ de saisie d'un montant, en grand (utilisé pour les prêts).
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.currency = 'DJF', this.validator, this.autofocus = false});

  final TextEditingController controller;
  final String currency;
  final String? Function(String?)? validator;
  final bool autofocus;

  /// Texte à pré-remplir pour un montant (sans décimales pour le franc Djibouti).
  static String text(double value, String currency) =>
      Fmt.decimals(currency) == 0 ? '${value.ceil()}' : value.toStringAsFixed(2).replaceAll('.', ',');

  static double? parse(String? text) =>
      double.tryParse((text ?? '').replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final noDecimals = Fmt.decimals(currency) == 0;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: !noDecimals),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1),
      decoration: InputDecoration(
        hintText: noDecimals ? '0' : '0,00',
        suffixText: Fmt.symbol(currency),
        suffixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      ),
      validator: validator ??
          (v) {
            final a = parse(v);
            if (a == null || a <= 0) return 'Saisissez un montant valide';
            return null;
          },
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.red : null,
    ));
}
