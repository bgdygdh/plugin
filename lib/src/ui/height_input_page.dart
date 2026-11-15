import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/size_recommendation.dart';
import '../services/scale_calculator.dart';
import 'plugin_colors.dart';

enum _HeightUnit { cm, ftIn }

/// Full-screen page that asks for the user's real height and gender.
///
/// Pops with a [UserBioProfile] containing height and gender, or `null` if the user
/// backs out. The height is the "ruler" that converts photo pixels to cm.
class HeightInputPage extends StatefulWidget {
  /// Height pre-filled in the input, in centimetres.
  final double initialHeightCm;

  /// Gender pre-selected in the input.
  final Gender initialGender;

  const HeightInputPage({
    super.key,
    this.initialHeightCm = 170,
    this.initialGender = Gender.male,
  });

  @override
  State<HeightInputPage> createState() => _HeightInputPageState();
}

class _HeightInputPageState extends State<HeightInputPage> {
  static const Color _accent = PluginColors.accent;
  static const double _cmPerInch = 2.54;

  late Gender _gender;
  _HeightUnit _unit = _HeightUnit.cm;
  late final TextEditingController _cmController;
  late final TextEditingController _feetController;
  late final TextEditingController _inchesController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gender = widget.initialGender;
    _cmController = TextEditingController();
    _feetController = TextEditingController();
    _inchesController = TextEditingController();
    _fillFields(widget.initialHeightCm);
  }

  @override
  void dispose() {
    _cmController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    super.dispose();
  }

  // ── Conversion helpers ─────────────────────────────────────────────────────

  /// Writes [cm] into all three input fields (cm and ft/in).
  void _fillFields(double cm) {
    _cmController.text = cm == cm.roundToDouble()
        ? cm.toStringAsFixed(0)
        : cm.toStringAsFixed(1);

    final totalInches = (cm / _cmPerInch).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches - feet * 12;
    _feetController.text = feet.toString();
    _inchesController.text = inches.toString();
  }

  double? _parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  /// The currently entered height in cm, or null if the input is unusable.
  double? _currentHeightCm() {
    if (_unit == _HeightUnit.cm) {
      return _parse(_cmController.text);
    }
    final feet = _parse(_feetController.text);
    final inches = _parse(_inchesController.text) ?? 0;
    if (feet == null) return null;
    return (feet * 12 + inches) * _cmPerInch;
  }

  void _switchUnit(_HeightUnit unit) {
    if (unit == _unit) return;
    // Carry the current value over to the other unit when it is valid.
    final current = _currentHeightCm();
    if (current != null && current > 0) {
      _fillFields(current);
    }
    setState(() {
      _unit = unit;
      _error = null;
    });
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final cm = _currentHeightCm();
    if (cm == null) {
      setState(() => _error = 'Please enter your height.');
      return;
    }
    if (cm < ScaleCalculator.minUserHeightCm ||
        cm > ScaleCalculator.maxUserHeightCm) {
      setState(() => _error =
          'Height must be between 100 cm and 250 cm (3 ft 3 in – 8 ft 2 in).');
      return;
    }
    Navigator.of(context).pop(
      UserBioProfile(
        heightCm: double.parse(cm.toStringAsFixed(1)),
        gender: _gender,
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PluginColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('height_close_button'),
                  icon: const Icon(Icons.close,
                      color: PluginColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildBadge(),
                    const SizedBox(height: 14),
                    const Text(
                      'Your Profile\n& Height',
                      style: TextStyle(
                        color: PluginColors.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select your gender for accurate size chart matching, '
                      'and enter your real height to calibrate photo measurements.',
                      style: TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildGenderSelector(),
                    const SizedBox(height: 28),
                    _buildUnitToggle(),
                    const SizedBox(height: 20),
                    _unit == _HeightUnit.cm
                        ? _buildCmField()
                        : _buildFeetInchesFields(),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const Key('height_error_text'),
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildTipCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  key: const Key('height_continue_button'),
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'CONTINUE TO CAMERA',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'STEP 1 · PROFILE SETUP',
        style: TextStyle(
          color: _accent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR GENDER',
          style: TextStyle(
            color: PluginColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildGenderCard(
              gender: Gender.male,
              label: 'Male',
              icon: Icons.male_rounded,
              key: const Key('gender_select_male'),
            ),
            const SizedBox(width: 12),
            _buildGenderCard(
              gender: Gender.female,
              label: 'Female',
              icon: Icons.female_rounded,
              key: const Key('gender_select_female'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderCard({
    required Gender gender,
    required String label,
    required IconData icon,
    required Key key,
  }) {
    final selected = _gender == gender;
    return Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _gender = gender),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? _accent.withValues(alpha: 0.10)
                : PluginColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _accent : PluginColors.border,
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? _accent : PluginColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? PluginColors.textPrimary
                      : PluginColors.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: _accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitToggle() {
    Widget segment(String label, _HeightUnit unit, Key key) {
      final selected = _unit == unit;
      return Expanded(
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => _switchUnit(unit),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _accent.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _accent : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _accent : PluginColors.textSecondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PluginColors.border),
      ),
      child: Row(
        children: [
          segment('CM', _HeightUnit.cm, const Key('unit_cm')),
          segment('FT · IN', _HeightUnit.ftIn, const Key('unit_ftin')),
        ],
      ),
    );
  }

  Widget _buildCmField() {
    return _HeightField(
      fieldKey: const Key('height_cm_field'),
      controller: _cmController,
      suffix: 'cm',
      allowDecimal: true,
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _buildFeetInchesFields() {
    return Row(
      children: [
        Expanded(
          child: _HeightField(
            fieldKey: const Key('height_ft_field'),
            controller: _feetController,
            suffix: 'ft',
            allowDecimal: false,
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _HeightField(
            fieldKey: const Key('height_in_field'),
            controller: _inchesController,
            suffix: 'in',
            allowDecimal: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        ),
      ],
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PluginColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tip: use your barefoot height. In the photos, stand barefoot '
              'or in socks, tie back voluminous hair and avoid hats — they '
              'add centimetres that are not part of your height.',
              style: TextStyle(
                color: PluginColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeightField extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final String suffix;
  final bool allowDecimal;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _HeightField({
    required this.fieldKey,
    required this.controller,
    required this.suffix,
    required this.allowDecimal,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(allowDecimal ? r'[0-9.,]' : r'[0-9]'),
        ),
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: PluginColors.textPrimary,
        fontSize: 44,
        fontWeight: FontWeight.bold,
      ),
      cursorColor: PluginColors.accent,
      decoration: InputDecoration(
        suffixText: suffix,
        suffixStyle: const TextStyle(
          color: PluginColors.textSecondary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: PluginColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PluginColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PluginColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
