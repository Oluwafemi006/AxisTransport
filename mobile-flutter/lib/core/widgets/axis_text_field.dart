import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Champ de saisie Axis Transport.
///
/// Présente le libellé au-dessus du champ (selon la maquette), supporte la variante
/// mot de passe avec bascule de visibilité et la variante téléphone avec indicatif
/// béninois « +229 » fixe.
class AxisTextField extends StatefulWidget {
  const AxisTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.isPassword = false,
    this.isPhone = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.readOnly = false,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool isPassword;
  final bool isPhone;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final bool readOnly;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;

  @override
  State<AxisTextField> createState() => _AxisTextFieldState();
}

class _AxisTextFieldState extends State<AxisTextField> {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _obscured = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    Widget? suffix;
    if (widget.isPassword) {
      final tooltip = _obscured ? 'Afficher le mot de passe' : 'Masquer le mot de passe';
      suffix = Semantics(
        button: true,
        label: tooltip,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(
            _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: axis.iconMuted,
            size: AxisSizes.icon,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      );
    } else if (widget.suffixIcon != null) {
      suffix = widget.suffixIcon;
    }

    Widget? prefix;
    if (widget.isPhone) {
      prefix = Padding(
        padding: const EdgeInsets.only(left: AxisSpacing.s14, right: AxisSpacing.s8),
        child: Text(
          '+229',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: axis.ink,
          ),
        ),
      );
    } else if (widget.prefixIcon != null) {
      prefix = widget.prefixIcon;
    }

    final effectiveKeyboard = widget.isPhone
        ? TextInputType.phone
        : (widget.keyboardType ?? (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: widget.enabled ? axis.ink : axis.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AxisSpacing.s6),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          obscureText: widget.isPassword ? _obscured : false,
          keyboardType: effectiveKeyboard,
          textInputAction: widget.textInputAction,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: widget.enabled ? axis.ink : axis.textMuted,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            helperText: widget.helperText,
            errorText: widget.errorText,
            prefixIcon: prefix,
            prefixIconConstraints: widget.isPhone
                ? const BoxConstraints(minWidth: 0, minHeight: 0)
                : null,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

