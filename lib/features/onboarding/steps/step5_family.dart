import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import '../screens/onboarding_screen.dart';

class Step5Family extends StatefulWidget {
  const Step5Family({super.key});

  @override
  State<Step5Family> createState() => _Step5FamilyState();
}

class SiblingInfo {
  String type;
  String education;
  String maritalStatus;
  SiblingInfo({this.type = 'Brother', this.education = '', this.maritalStatus = 'Unmarried'});
  Map<String, String> toJson() => {'type': type, 'education': education, 'marital_status': maritalStatus};
}

class _Step5FamilyState extends OnboardingStepState<Step5Family> {
  String? _familyType;
  String? _familyValue;
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final List<SiblingInfo> _siblings = [];

  final _familyTypes = {'Nuclear': 'nuclear', 'Joint': 'joint', 'Other': 'other'};
  final _familyValuesMap = {'Orthodox': 'middle', 'Traditional': 'middle', 'Moderate': 'upper_middle', 'Liberal': 'affluent'};
  final _maritalStatuses = ['Unmarried', 'Married', 'Divorced', 'Widowed'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final family = parent?.onboardingData?['family'];
      if (family != null && mounted) {
        setState(() {
          if (family['father_occupation'] != null) _fatherCtrl.text = family['father_occupation'];
          if (family['mother_occupation'] != null) _motherCtrl.text = family['mother_occupation'];
          
          if (family['family_type'] != null) {
            _familyType = _familyTypes.entries.cast<MapEntry<String, String>?>().firstWhere((e) => e?.value == family['family_type'], orElse: () => null)?.key;
          }
          
          if (family['family_class'] != null) {
            _familyValue = _familyValuesMap.entries.cast<MapEntry<String, String>?>().firstWhere((e) => e?.value == family['family_class'], orElse: () => null)?.key;
          }

          if (family['sibling_details'] != null && family['sibling_details'] is List) {
            _siblings.clear();
            for (var s in family['sibling_details']) {
              _siblings.add(SiblingInfo(
                type: s['type'] ?? 'Brother',
                education: s['education'] ?? '',
                maritalStatus: s['marital_status'] ?? 'Unmarried',
              ));
            }
          }
        });
      }
    });
  }

  @override
  Map<String, dynamic>? getStepData() {
    if (_familyType == null || _familyValue == null) {
      return null;
    }
    
    int brothers = _siblings.where((s) => s.type == 'Brother').length;
    int sisters = _siblings.where((s) => s.type == 'Sister').length;
    int marriedBrothers = _siblings.where((s) => s.type == 'Brother' && s.maritalStatus == 'Married').length;
    int marriedSisters = _siblings.where((s) => s.type == 'Sister' && s.maritalStatus == 'Married').length;

    return {
      'family_type': _familyTypes[_familyType],
      'family_class': _familyValuesMap[_familyValue],
      'father_occupation': _fatherCtrl.text.trim(),
      'mother_occupation': _motherCtrl.text.trim(),
      'brothers_count': brothers,
      'sisters_count': sisters,
      'married_brothers_count': marriedBrothers,
      'married_sisters_count': marriedSisters,
      'sibling_details': _siblings.map((s) => s.toJson()).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Family Type'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _familyTypes.keys
                .map((t) => _selectChip(
                    t, _familyType, (v) => setState(() => _familyType = v)))
                .toList(),
          ),
          const SizedBox(height: 24),

          _fieldLabel('Family Values'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _familyValuesMap.keys
                .map((v) => _selectChip(
                    v, _familyValue, (val) => setState(() => _familyValue = val)))
                .toList(),
          ),
          const SizedBox(height: 24),

          _fieldLabel("Father's Occupation"),
          _inputField(_fatherCtrl, 'e.g. Retired Govt Employee'),
          const SizedBox(height: 24),

          _fieldLabel("Mother's Occupation"),
          _inputField(_motherCtrl, 'e.g. Homemaker'),
          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _fieldLabel("Sibling Details"),
              TextButton.icon(
                onPressed: () => setState(() => _siblings.add(SiblingInfo())),
                icon: Icon(Icons.add_circle_outline, size: 20, color: AppColors.gold),
                label: Text('Add Sibling', style: TextStyle(color: AppColors.gold)),
              ),
            ],
          ),
          
          ..._siblings.asMap().entries.map((entry) {
            int idx = entry.key;
            SiblingInfo sib = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceHighest),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _selectChip('Brother', sib.type, (v) => setState(() => sib.type = v)),
                      const SizedBox(width: 8),
                      _selectChip('Sister', sib.type, (v) => setState(() => sib.type = v)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => setState(() => _siblings.removeAt(idx)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => sib.education = v,
                    style: AppTextStyles.labelMedium,
                    controller: TextEditingController(text: sib.education)..selection = TextSelection.collapsed(offset: sib.education.length),
                    decoration: const InputDecoration(
                      hintText: 'Education / Study',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('Marital Status'),
                  Wrap(
                    spacing: 8,
                    children: _maritalStatuses.map((s) => _smallChip(s, sib.maritalStatus, (v) => setState(() => sib.maritalStatus = v))).toList(),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _smallChip(String label, String? selected, ValueChanged<String> onTap) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? AppColors.goldSubtle : Colors.transparent,
          border: Border.all(color: isSelected ? AppColors.gold : AppColors.surfaceHighest),
        ),
        child: Text(label, style: AppTextStyles.labelSmall.copyWith(color: isSelected ? AppColors.gold : AppColors.textSecondary)),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label, style: AppTextStyles.labelMedium),
      );

  Widget _inputField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: AppTextStyles.labelLarge,
      decoration: InputDecoration(hintText: hint),
    );
  }

  Widget _selectChip(String label, String? selected, ValueChanged<String> onTap) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: isSelected ? AppColors.goldSubtle : AppColors.surfaceElevated,
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.surfaceHighest,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: AppTextStyles.labelMedium.copyWith(
                color: isSelected ? AppColors.gold : AppColors.textSecondary)),
      ),
    );
  }
}

