import 'dart:io';
import 'package:flutter/material.dart';

import '../ui/plugin_colors.dart';

/// Shows both captured images (front + side) for the user to confirm or retake.
class CaptureReviewPage extends StatelessWidget {
  final String frontImagePath;
  final String sideImagePath;

  const CaptureReviewPage({
    super.key,
    required this.frontImagePath,
    required this.sideImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PluginColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                children: [
                  const Text(
                    'PHOTOS CAPTURED',
                    style: TextStyle(
                      color: PluginColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Review your photos below.\nMake sure your full body is visible.',
                    style: TextStyle(
                      color: PluginColors.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // ── Image Cards ─────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _ImageCard(
                        label: 'FRONT',
                        imagePath: frontImagePath,
                        accentColor: PluginColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImageCard(
                        label: 'SIDE',
                        imagePath: sideImagePath,
                        accentColor: const Color(0xFF44AAFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Action Buttons ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  // Retake button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('RETAKE'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PluginColors.textSecondary,
                        side: const BorderSide(color: PluginColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Confirm button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'CONFIRM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PluginColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String label;
  final String imagePath;
  final Color accentColor;

  const _ImageCard({
    required this.label,
    required this.imagePath,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Label
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(color: accentColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
        ),
        // Image
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
      ],
    );
  }
}
