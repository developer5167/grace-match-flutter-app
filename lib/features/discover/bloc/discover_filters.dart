import 'package:equatable/equatable.dart';

/// Session-level discover feed filter overrides.
/// When all fields are at defaults the backend uses the user's saved preferences.
class DiscoverFilters extends Equatable {
  final int ageMin;
  final int ageMax;
  final int heightMin;
  final int heightMax;
  final String denomination; // single value; 'Any' = flexible
  final bool denominationFlexible;
  final String? location;
  final bool locationFlexible;
  final bool casteFlexible;
  final String professionPreference; // 'any' | 'pvt' | 'govt' | 'other'
  final int salaryMin; // in Lakhs
  final int salaryMax; // in Lakhs

  const DiscoverFilters({
    this.ageMin = 18,
    this.ageMax = 60,
    this.heightMin = 140,
    this.heightMax = 220,
    this.denomination = 'Any',
    this.denominationFlexible = true,
    this.location,
    this.locationFlexible = false,
    this.casteFlexible = false,
    this.professionPreference = 'any',
    this.salaryMin = 0,
    this.salaryMax = 100,
  });

  factory DiscoverFilters.defaults() => const DiscoverFilters();

  bool get isDefault =>
      ageMin == 18 &&
      ageMax == 60 &&
      heightMin == 140 &&
      heightMax == 220 &&
      (denomination == 'Any' || denominationFlexible) &&
      location == null &&
      !locationFlexible &&
      !casteFlexible &&
      professionPreference == 'any' &&
      salaryMin == 0 &&
      salaryMax == 100;

  /// Builds query-string params to pass to the discover feed endpoint.
  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (ageMin != 18) params['age_min'] = ageMin.toString();
    if (ageMax != 60) params['age_max'] = ageMax.toString();
    if (heightMin != 140) params['height_min'] = heightMin.toString();
    if (heightMax != 220) params['height_max'] = heightMax.toString();

    if (denomination != 'Any' && !denominationFlexible) {
      params['denominations'] = denomination.toLowerCase();
    } else {
      params['denomination_flexible'] = 'true';
    }

    if (locationFlexible) {
      params['location_flexible'] = 'true';
    } else if (location != null && location!.isNotEmpty) {
      params['location'] = location!;
    }

    if (casteFlexible) params['caste_flexible'] = 'true';
    if (professionPreference != 'any') {
      params['profession_preference'] = professionPreference;
    }
    if (salaryMin != 0) params['salary_min'] = salaryMin.toString();
    if (salaryMax != 100) params['salary_max'] = salaryMax.toString();

    return params;
  }

  @override
  List<Object?> get props => [
    ageMin,
    ageMax,
    heightMin,
    heightMax,
    denomination,
    denominationFlexible,
    location,
    locationFlexible,
    casteFlexible,
    professionPreference,
    salaryMin,
    salaryMax,
  ];
}
