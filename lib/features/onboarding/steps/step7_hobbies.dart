import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

import '../screens/onboarding_screen.dart';

class Step7Hobbies extends StatefulWidget {
  const Step7Hobbies({super.key});

  @override
  State<Step7Hobbies> createState() => _Step7HobbiesState();
}

class _Step7HobbiesState extends OnboardingStepState<Step7Hobbies> with AutomaticKeepAliveClientMixin {
  final List<int> _selectedHobbyIds = [];
  List<Map<String, dynamic>> _hobbies = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchHobbies();
  }

  Future<void> _fetchHobbies() async {
    try {
      final response = await DioClient.instance.get(ApiEndpoints.onboardingHobbies);
      final data = response.data['data'] as List;
      
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final savedHobbies = parent?.onboardingData?['hobbies'] as List?;
      
      setState(() {
        _hobbies = data.map((h) => {'id': h['id'] as int, 'name': h['name'] as String}).toList();
        
        if (savedHobbies != null) {
          for (var sh in savedHobbies) {
            final int id = sh['id'];
            if (!_selectedHobbyIds.contains(id)) {
              _selectedHobbyIds.add(id);
            }
          }
        }
        
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Map<String, dynamic>? getStepData() {
    if (_selectedHobbyIds.isEmpty) {
      return null;
    }
    return {
      'hobby_ids': _selectedHobbyIds,
    };
  }

  void _toggleHobby(int id) {
    setState(() {
      if (_selectedHobbyIds.contains(id)) {
        _selectedHobbyIds.remove(id);
      } else {
        if (_selectedHobbyIds.length < 10) {
          _selectedHobbyIds.add(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can select up to 10 hobbies.')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    if (_hobbies.isEmpty) {
      return Center(
        child: Text('Unable to load hobbies. Please try again.', style: AppTextStyles.bodyMedium),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Selected: ', style: AppTextStyles.labelMedium),
              Text('${_selectedHobbyIds.length}/10',
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
            ],
          ),
          const SizedBox(height: 20),

          Text('Choose your hobbies', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hobbies
                .map((hobby) => _multiSelectChip(
                    hobby['name'] as String,
                    _selectedHobbyIds.contains(hobby['id']),
                    () => _toggleHobby(hobby['id'] as int)))
                .toList(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _multiSelectChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
