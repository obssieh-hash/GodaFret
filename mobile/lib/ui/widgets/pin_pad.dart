import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pastilles indiquant le nombre de chiffres saisis, avec secousse en cas d'erreur.
class PinDots extends StatefulWidget {
  const PinDots({super.key, required this.length, required this.filled, this.error = false, this.color});

  final int length;
  final int filled;
  final bool error;
  final Color? color;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant PinDots old) {
    super.didUpdateWidget(old);
    if (widget.error && !old.error) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : 12 * (1 - t) * (((t * 8).floor().isEven) ? 1 : -1);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.length, (i) {
          final on = i < widget.filled;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: on ? 18 : 16,
            height: on ? 18 : 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.error ? Colors.redAccent : (on ? color : Colors.transparent),
              border: Border.all(color: widget.error ? Colors.redAccent : color.withValues(alpha: 0.55), width: 2),
            ),
          );
        }),
      ),
    );
  }
}

/// Clavier numérique pour le code PIN.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.onBiometrics,
    this.foreground,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometrics;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Theme.of(context).colorScheme.onSurface;
    Widget key(Widget child, VoidCallback? onTap, {String? semantics}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AspectRatio(
              aspectRatio: 1.45,
              child: Semantics(
                button: true,
                label: semantics,
                excludeSemantics: true,
                onTap: onTap,
                child: Material(
                  color: onTap == null ? Colors.transparent : fg.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: onTap == null
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            onTap();
                          },
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        );

    Widget digit(String d) => key(
          Text(d, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: fg)),
          () => onDigit(d),
          semantics: d,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: row.map(digit).toList()),
        Row(
          children: [
            key(
              Icon(Icons.fingerprint_rounded, size: 32, color: onBiometrics == null ? Colors.transparent : fg),
              onBiometrics,
              semantics: 'Biométrie',
            ),
            digit('0'),
            key(Icon(Icons.backspace_outlined, color: fg), onDelete, semantics: 'Effacer'),
          ],
        ),
      ],
    );
  }
}
