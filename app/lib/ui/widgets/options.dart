import 'package:flutter/material.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../theme/colors.dart';

/// A tappable answer row with a radio- or checkbox-style indicator.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.multi = false,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool multi;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.brandSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? c.brand : c.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _Indicator(selected: selected, multi: multi),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.selected, required this.multi});

  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? c.brand : Colors.transparent,
        shape: multi ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: multi ? BorderRadius.circular(6) : null,
        border: Border.all(color: selected ? c.brand : c.inkFaint, width: 2),
      ),
      child: selected
          ? Icon(
              multi ? Icons.check : Icons.circle,
              size: multi ? 16 : 8,
              color: Colors.white,
            )
          : null,
    );
  }
}

/// The options of an intake question, with swatches for skin tone.
class QuestionOptions extends StatelessWidget {
  const QuestionOptions({
    super.key,
    required this.question,
    required this.answers,
    required this.onToggle,
  });

  final IntakeQuestion question;
  final IntakeAnswers answers;
  final void Function(String optionId) onToggle;

  @override
  Widget build(BuildContext context) {
    final selected = answers[question.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        for (final o in question.options)
          OptionTile(
            label: o.label,
            selected: selected.contains(o.id),
            multi: question.kind == QuestionKind.multi,
            onTap: () => onToggle(o.id),
            leading: question.id == Q.skinTone
                ? Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: skinToneSwatches[o.id],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}
