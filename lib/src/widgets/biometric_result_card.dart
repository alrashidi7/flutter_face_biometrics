import 'package:flutter/material.dart';

/// Result card for biometric verification – success or mismatch.
///
/// Use [bottomWidget] to embed any widget (e.g. a face comparison) below
/// the action button, still inside the card's styled container.
class BiometricResultCard extends StatelessWidget {
  const BiometricResultCard({
    super.key,
    required this.success,
    this.message,
    this.detail,
    this.onAction,
    this.actionLabel,
    this.bottomWidget,
  });

  final bool success;
  final String? message;
  final String? detail;
  final VoidCallback? onAction;
  final String? actionLabel;

  /// Optional widget rendered below the action button inside the card.
  final Widget? bottomWidget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = success
        ? cs.primary.withValues(alpha: 0.08)
        : cs.error.withValues(alpha: 0.08);
    final iconColor = success ? cs.primary : cs.error;
    final title =
        message ?? (success ? 'Verification successful' : 'Verification failed');
    final icon = success ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (success ? cs.primary : cs.error).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 12),
            Text(
              detail!,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
          if (bottomWidget != null) ...[
            const SizedBox(height: 20),
            Divider(
              color: (success ? cs.primary : cs.error).withValues(alpha: 0.2),
              thickness: 1,
            ),
            const SizedBox(height: 16),
            bottomWidget!,
          ],
        ],
      ),
    );
  }
}
