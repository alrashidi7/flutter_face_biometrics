import 'package:flutter/material.dart';

/// Explains what biometric enrollment and verification do.
class BiometricInfoSection extends StatelessWidget {
  const BiometricInfoSection({
    super.key,
    this.title = 'How we secure you',
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: compact ? 20 : 24,
              color: cs.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Item(
          icon: Icons.visibility_rounded,
          title: 'Liveness check',
          description: 'Blink to capture – reduces photo spoofing.',
          compact: compact,
        ),
        _Item(
          icon: Icons.face_rounded,
          title: 'Face embedding',
          description: 'FaceNet converts your face into a unique 128D vector.',
          compact: compact,
        ),
        _Item(
          icon: Icons.fingerprint_rounded,
          title: 'Device signature',
          description: 'Hardware-backed key binds your face to this device.',
          compact: compact,
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.description,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 36 : 40,
            height: compact ? 36 : 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: compact ? 18 : 20, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
