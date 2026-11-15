import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/size_recommendation.dart';
import '../models/virtual_try_on.dart';
import '../services/fashn_ai_service.dart';
import 'plugin_colors.dart';

/// Virtual Try-On screen powered by Fashn AI `tryon-max` model.
class VirtualTryOnPage extends StatefulWidget {
  /// Path to the user's front-facing captured photo.
  final String frontImagePath;

  /// Confirmed size recommendation result from the previous step.
  final SizeRecommendationResult? recommendation;

  /// Optional custom API key. Defaults to provided Fashn AI key.
  final String? apiKey;

  /// Optional injected service for testing.
  final FashnAiService? fashnService;

  /// Optional pre-selected garment image path (useful for testing or direct picking).
  final String? initialGarmentPath;
  final TryOnCategory? initialCategory;

  const VirtualTryOnPage({
    super.key,
    required this.frontImagePath,
    this.recommendation,
    this.apiKey,
    this.fashnService,
    this.initialGarmentPath,
    this.initialCategory,
  });

  @override
  State<VirtualTryOnPage> createState() => _VirtualTryOnPageState();
}

class _VirtualTryOnPageState extends State<VirtualTryOnPage> {
  static const Color _accent = PluginColors.accent;
  static const Color _danger = Color(0xFFDC2626);

  late final FashnAiService _service;
  late TryOnCategory _selectedCategory;

  String? _selectedGarmentPath;

  TryOnSessionStatus _sessionStatus = TryOnSessionStatus.idle;
  String _statusMessage = '';
  String? _errorMessage;

  VirtualTryOnResult? _tryOnResult;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    final providedKey = widget.apiKey?.trim() ?? '';
    _service = widget.fashnService ??
        FashnAiService(
          apiKey: providedKey.isNotEmpty
              ? providedKey
              : FashnAiService.defaultApiKey,
        );
    _selectedGarmentPath = widget.initialGarmentPath;

    // Initial category inferred from explicit param or the garment analyzed on the size page
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    } else if (widget.recommendation != null) {
      _selectedCategory = switch (widget.recommendation!.garment) {
        GarmentType.tShirt => TryOnCategory.tops,
        GarmentType.shorts || GarmentType.pants => TryOnCategory.bottoms,
        GarmentType.dress => TryOnCategory.onePieces,
      };
    } else {
      _selectedCategory = TryOnCategory.tops;
    }
  }

  Future<void> _pickGarmentImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (picked != null) {
        setState(() {
          _selectedGarmentPath = picked.path;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not load image: $e');
    }
  }

  Future<void> _startTryOn() async {
    if (_selectedGarmentPath == null) {
      setState(() => _errorMessage = 'Please select or upload a garment image first.');
      return;
    }

    if (widget.fashnService == null && _service.apiKey.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'Fashn AI API key is not configured. Pass fashnApiKey to '
            'startCapture(...) or run with --dart-define=FASHN_API_KEY=your_key.';
      });
      return;
    }

    setState(() {
      _sessionStatus = TryOnSessionStatus.encoding;
      _statusMessage = 'Connecting to Fashn AI tryon-max...';
      _errorMessage = null;
    });

    try {
      final result = await _service.runTryOn(
        modelImagePath: widget.frontImagePath,
        garmentImagePath: _selectedGarmentPath!,
        category: _selectedCategory,
        resolution: '1k',
        generationMode: 'balanced',
        onStatusUpdate: (status, message) {
          if (mounted) {
            setState(() {
              _sessionStatus = status;
              _statusMessage = message;
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _tryOnResult = result;
        _sessionStatus = TryOnSessionStatus.completed;
      });
    } on FashnAiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionStatus = TryOnSessionStatus.failed;
        _errorMessage = (e.details != null && e.details!.isNotEmpty)
            ? '${e.message}: ${e.details}'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionStatus = TryOnSessionStatus.failed;
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PluginColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    key: const Key('tryon_back_button'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: PluginColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(_tryOnResult),
                  ),
                  const Text(
                    'VIRTUAL TRY-ON',
                    style: TextStyle(
                      color: PluginColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                  IconButton(
                    key: const Key('tryon_skip_button'),
                    icon: const Icon(Icons.close_rounded,
                        color: PluginColors.textSecondary, size: 24),
                    onPressed: () => Navigator.of(context).pop(_tryOnResult),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_tryOnResult != null)
                      _buildResultView()
                    else ...[
                      _buildCategorySelector(),
                      const SizedBox(height: 18),
                      _buildSideBySidePreview(),
                      const SizedBox(height: 18),
                      _buildGarmentUploadOptions(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorBanner(_errorMessage!),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // ── Bottom Action Button ─────────────────────────────────────────
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GARMENT CATEGORY',
          style: TextStyle(
            color: PluginColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: TryOnCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            return Expanded(
              child: GestureDetector(
                key: Key('tryon_cat_${cat.apiValue}'),
                onTap: _sessionStatus.isProcessing
                    ? null
                    : () => setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: EdgeInsets.only(
                      right: cat == TryOnCategory.values.last ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accent.withValues(alpha: 0.10)
                        : PluginColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? _accent
                          : PluginColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cat.apiValue.toUpperCase(),
                      style: TextStyle(
                        color: isSelected
                            ? _accent
                            : PluginColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSideBySidePreview() {
    return Row(
      children: [
        // Left: User Front Photo
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR PHOTO',
                style: TextStyle(
                  color: PluginColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: PluginColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(widget.frontImagePath),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => const ColoredBox(
                      color: PluginColors.surface,
                      child: Icon(Icons.broken_image,
                          color: PluginColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Right: Selected Garment
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GARMENT TO FIT',
                style: TextStyle(
                  color: PluginColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              GesturementPreviewBox(
                imagePath: _selectedGarmentPath,
                onTap: () => _pickGarmentImage(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGarmentUploadOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'GARMENT IMAGE',
              style: TextStyle(
                color: PluginColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            ElevatedButton.icon(
              key: const Key('tryon_upload_gallery_btn'),
              onPressed: () => _pickGarmentImage(ImageSource.gallery),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent.withValues(alpha: 0.15),
                foregroundColor: _accent,
                elevation: 0,
                side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultView() {
    final result = _tryOnResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode toggle: Try-On vs Original
        Center(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: PluginColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: PluginColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTogglePill(
                  label: 'Virtual Try-On',
                  icon: Icons.auto_awesome_rounded,
                  isSelected: !_showOriginal,
                  onTap: () => setState(() => _showOriginal = false),
                ),
                const SizedBox(width: 4),
                _buildTogglePill(
                  label: 'Original Photo',
                  icon: Icons.person_rounded,
                  isSelected: _showOriginal,
                  onTap: () => setState(() => _showOriginal = true),
                ),
              ],
            ),
          ),
        ),

        // Photo Box
        Container(
          height: 380,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _showOriginal
                ? Image.file(
                    File(widget.frontImagePath),
                    fit: BoxFit.contain,
                  )
                : (result.localTryOnImagePath != null
                    ? Image.file(
                        File(result.localTryOnImagePath!),
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        result.tryOnImageUrl,
                        fit: BoxFit.contain,
                      )),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _tryOnResult = null;
                _sessionStatus = TryOnSessionStatus.idle;
              });
            },
            icon: const Icon(Icons.refresh_rounded,
                size: 16, color: PluginColors.textSecondary),
            label: const Text(
              'Try on another garment',
              style: TextStyle(color: PluginColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTogglePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : PluginColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : PluginColors.textSecondary,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _danger, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: _sessionStatus.isProcessing
          ? Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: PluginColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: PluginColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          : _tryOnResult != null
              ? SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    key: const Key('tryon_finish_button'),
                    onPressed: () => Navigator.of(context).pop(_tryOnResult),
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: const Text(
                      'ACCEPT & FINISH',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    key: const Key('tryon_submit_button'),
                    onPressed: _startTryOn,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: const Text(
                      'START VIRTUAL TRY-ON',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
    );
  }
}

/// Helper widget to preview or upload a garment image.
class GesturementPreviewBox extends StatelessWidget {
  final String? imagePath;
  final VoidCallback onTap;

  const GesturementPreviewBox({
    super.key,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final isUrl = hasImage &&
        (imagePath!.startsWith('http://') || imagePath!.startsWith('https://'));

    return GestureDetector(
      key: const Key('tryon_garment_preview_box'),
      onTap: onTap,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: PluginColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage
                ? PluginColors.accent.withValues(alpha: 0.4)
                : PluginColors.border,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                (isUrl
                    ? Image.network(imagePath!, fit: BoxFit.cover)
                    : Image.file(File(imagePath!), fit: BoxFit.cover))
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 38,
                      color: PluginColors.textSecondary,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap to upload\na garment',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: PluginColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              if (hasImage)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 11, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Change',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
