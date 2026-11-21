import 'package:flutter/material.dart';
import '../../../core/l10n/app_language.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../bloc/discover_filters.dart';

/// Full-featured discover filter bottom sheet.
/// Mirrors the onboarding preferences step (age, height, denomination,
/// profession, salary) and adds location + caste for session overrides.
/// The Apply button is always pinned at the bottom — it never scrolls away.
class DiscoverFilterSheet extends StatefulWidget {
  final DiscoverFilters currentFilters;

  const DiscoverFilterSheet({super.key, required this.currentFilters});

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  late RangeValues _ageRange;
  late RangeValues _heightRange;
  late RangeValues _salaryRange;
  late String _denomination;
  late bool _denomFlexible;
  late bool _locationFlexible;
  late bool _casteFlexible;
  late String _professionPref;
  late TextEditingController _locationCtrl;
  late Set<String> _intents;
  late bool _baptisedOnly;
  late bool _servesInChurch;

  static const _intentOptions = {
    'ready_now': 'Ready now',
    'within_6_months': 'Within 6 months',
    'within_1_year': 'Within 1 year',
    'within_2_years': 'Within 2 years',
  };

  static const _denomOptions = [
    'Any',
    'CSI',
    'Catholic',
    'Pentecostal',
    'Protestant',
    'Born Again',
    'Orthodox',
    'Other',
  ];

  static const _professionOptions = {
    'Any': 'any',
    'Private': 'pvt',
    'Government': 'govt',
    'Other': 'other',
  };

  @override
  void initState() {
    super.initState();
    final f = widget.currentFilters;
    _ageRange = RangeValues(f.ageMin.toDouble(), f.ageMax.toDouble());
    _heightRange = RangeValues(f.heightMin.toDouble(), f.heightMax.toDouble());
    _salaryRange = RangeValues(f.salaryMin.toDouble(), f.salaryMax.toDouble());
    _denomination = f.denomination;
    _denomFlexible = f.denominationFlexible;
    _locationFlexible = f.locationFlexible;
    _casteFlexible = f.casteFlexible;
    _professionPref = _professionOptions.keys.firstWhere(
      (k) => _professionOptions[k] == f.professionPreference,
      orElse: () => 'Any',
    );
    _locationCtrl = TextEditingController(text: f.location ?? '');
    _intents = {...f.marriageIntents};
    _baptisedOnly = f.baptisedOnly;
    _servesInChurch = f.servesInChurch;
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  void _applyFilters() {
    Navigator.of(context).pop(
      DiscoverFilters(
        ageMin: _ageRange.start.round(),
        ageMax: _ageRange.end.round(),
        heightMin: _heightRange.start.round(),
        heightMax: _heightRange.end.round(),
        denomination: _denomination,
        denominationFlexible: _denomFlexible || _denomination == 'Any',
        location: _locationFlexible
            ? null
            : (_locationCtrl.text.trim().isEmpty
                  ? null
                  : _locationCtrl.text.trim()),
        locationFlexible: _locationFlexible,
        casteFlexible: _casteFlexible,
        professionPreference: _professionOptions[_professionPref] ?? 'any',
        salaryMin: _salaryRange.start.round(),
        salaryMax: _salaryRange.end.round(),
        marriageIntents: _intentOptions.keys.where(_intents.contains).toList(),
        baptisedOnly: _baptisedOnly,
        servesInChurch: _servesInChurch,
      ),
    );
  }

  void _resetFilters() => Navigator.of(context).pop(DiscoverFilters.defaults());

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── handle ──────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── header with reset ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  tr('Filter profiles'),
                  style: AppTextStyles.headlineMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _resetFilters,
                  child: Text(
                    tr('Reset All'),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.surfaceHighest, height: 1),
          // ── scrollable fields ────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAgeSection(),
                  _divider(),
                  _buildHeightSection(),
                  _divider(),
                  _buildDenominationSection(),
                  _divider(),
                  _buildFaithSection(),
                  _divider(),
                  _buildProfessionSection(),
                  _divider(),
                  _buildSalarySection(),
                  _divider(),
                  _buildLocationSection(),
                  _divider(),
                  _buildCasteSection(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // ── pinned apply button ──────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              border: Border(top: BorderSide(color: AppColors.surfaceHighest)),
            ),
            child: ElevatedButton(
              onPressed: _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.textOnGold,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                tr('Apply Filters'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.15, duration: 280.ms, curve: Curves.easeOut);
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Divider(color: AppColors.surfaceHighest, height: 1),
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      tr(text),
      style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
    ),
  );

  SliderThemeData get _sliderTheme => SliderTheme.of(context).copyWith(
    activeTrackColor: AppColors.gold,
    inactiveTrackColor: AppColors.surfaceHighest,
    thumbColor: AppColors.gold,
    overlayColor: AppColors.goldSubtle,
    rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
  );

  // ── Age ────────────────────────────────────────────────────────
  Widget _buildAgeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(tr('Age Range')),
            Text(
              tr('{a} – {b} yrs', {
                'a': _ageRange.start.round(),
                'b': _ageRange.end.round(),
              }),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gold),
            ),
          ],
        ),
        SliderTheme(
          data: _sliderTheme,
          child: RangeSlider(
            values: _ageRange,
            min: 18,
            max: 60,
            divisions: 42,
            onChanged: (v) => setState(() => _ageRange = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr('18 yrs'), style: AppTextStyles.bodySmall),
            Text(tr('60 yrs'), style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  // ── Height ─────────────────────────────────────────────────────
  Widget _buildHeightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(tr('Height Range')),
            Text(
              tr('{a} – {b} cm', {
                'a': _heightRange.start.round(),
                'b': _heightRange.end.round(),
              }),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gold),
            ),
          ],
        ),
        SliderTheme(
          data: _sliderTheme,
          child: RangeSlider(
            values: _heightRange,
            min: 140,
            max: 220,
            divisions: 80,
            onChanged: (v) => setState(() => _heightRange = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr('140 cm'), style: AppTextStyles.bodySmall),
            Text(tr('220 cm'), style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  // ── Denomination ────────────────────────────────────────────────
  Widget _buildDenominationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(tr('Preferred Denomination')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _denomOptions.map((d) {
            final selected = _denomination == d;
            return GestureDetector(
              onTap: () => setState(() {
                _denomination = d;
                _denomFlexible = d == 'Any';
              }),
              child: AnimatedContainer(
                duration: 180.ms,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.goldSubtle
                      : AppColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.surfaceHighest,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  tr(d),
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.gold : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Faith: marriage timeline, baptised, serving ────────────────
  Widget _buildFaithSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(tr('Planning to marry')),
        Text(
          _intents.isEmpty
              ? tr('Any timeline')
              : tr('Only the timelines you choose'),
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _intentOptions.entries.map((e) {
            final selected = _intents.contains(e.key);
            return GestureDetector(
              onTap: () => setState(
                () => selected ? _intents.remove(e.key) : _intents.add(e.key),
              ),
              child: AnimatedContainer(
                duration: 180.ms,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.goldSubtle
                      : AppColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.surfaceHighest,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  tr(e.value),
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.gold : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _faithSwitch(
          tr('Baptised only'),
          tr('Show only members who are baptised'),
          _baptisedOnly,
          (v) => setState(() => _baptisedOnly = v),
        ),
        const SizedBox(height: 8),
        _faithSwitch(
          tr('Serves in church'),
          tr('Choir, worship, Sunday school, youth and other ministries'),
          _servesInChurch,
          (v) => setState(() => _servesInChurch = v),
        ),
      ],
    );
  }

  Widget _faithSwitch(
    String title,
    String hint,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelLarge),
              Text(
                hint,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.gold,
        ),
      ],
    );
  }

  // ── Profession ──────────────────────────────────────────────────
  Widget _buildProfessionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(tr('Profession Preference')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _professionOptions.keys.map((p) {
            final selected = _professionPref == p;
            return GestureDetector(
              onTap: () => setState(() => _professionPref = p),
              child: AnimatedContainer(
                duration: 180.ms,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.goldSubtle
                      : AppColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.surfaceHighest,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  p,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.gold : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Salary ──────────────────────────────────────────────────────
  Widget _buildSalarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(tr('Annual Salary')),
            Text(
              '${_salaryRange.start.round()}L – ${_salaryRange.end.round()}L+',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gold),
            ),
          ],
        ),
        SliderTheme(
          data: _sliderTheme,
          child: RangeSlider(
            values: _salaryRange,
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (v) => setState(() => _salaryRange = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('₹0', style: AppTextStyles.bodySmall),
            Text('₹100L+', style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  // ── Location ────────────────────────────────────────────────────
  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(tr('City / Location')),
            _flexibleToggle(
              label: tr('Anywhere'),
              value: _locationFlexible,
              onChanged: (v) => setState(() => _locationFlexible = v),
            ),
          ],
        ),
        if (!_locationFlexible)
          TextField(
            controller: _locationCtrl,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: tr('e.g. Hyderabad, Vijayawada'),
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
              filled: true,
              fillColor: AppColors.surfaceHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(
                Icons.location_on_outlined,
                color: AppColors.gold,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
      ],
    );
  }

  // ── Caste ───────────────────────────────────────────────────────
  Widget _buildCasteSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(tr('Caste Preference')),
            Text(
              _casteFlexible
                  ? tr('Open to all castes')
                  : tr('Match my saved preference'),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        _flexibleToggle(
          label: tr('Flexible'),
          value: _casteFlexible,
          onChanged: (v) => setState(() => _casteFlexible = v),
        ),
      ],
    );
  }

  Widget _flexibleToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(label),
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.gold,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}
