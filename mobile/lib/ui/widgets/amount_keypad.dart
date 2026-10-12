import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pavé numérique de saisie d'un montant (sans clavier système).
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, required this.onDelete, this.extraKey = '000'});

  final ValueChanged<String> onKey;
  final VoidCallback onDelete;

  /// Touche en bas à gauche : « 000 » pour le franc Djibouti, « , » sinon.
  final String extraKey;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    Widget key(String label, VoidCallback onTap, {Widget? child, String? semantics}) => Expanded(
          child: Semantics(
            button: true,
            label: semantics ?? label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: SizedBox(
                height: 58,
                child: Center(
                  child: child ?? Text(label, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: fg)),
                ),
              ),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) key(d, () => onKey(d))]),
        Row(
          children: [
            key(extraKey, () => onKey(extraKey)),
            key('0', () => onKey('0')),
            key('', onDelete, child: Icon(Icons.backspace_outlined, color: fg), semantics: 'Effacer'),
          ],
        ),
      ],
    );
  }
}
