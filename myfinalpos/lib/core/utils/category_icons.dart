import 'package:flutter/material.dart';

class CategoryIconOption {
  const CategoryIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

const List<CategoryIconOption> categoryIconOptions = [
  CategoryIconOption(key: 'eco', label: 'Seeds', icon: Icons.eco),
  CategoryIconOption(key: 'grass', label: 'Crops', icon: Icons.grass),
  CategoryIconOption(
    key: 'compost',
    label: 'Fertilizer',
    icon: Icons.compost,
  ),
  CategoryIconOption(
    key: 'shield',
    label: 'Protection',
    icon: Icons.shield_outlined,
  ),
  CategoryIconOption(
    key: 'pest_control',
    label: 'Pesticide',
    icon: Icons.pest_control,
  ),
  CategoryIconOption(key: 'pets', label: 'Animal Feed', icon: Icons.pets),
  CategoryIconOption(
    key: 'build',
    label: 'Tools',
    icon: Icons.build_outlined,
  ),
  CategoryIconOption(
    key: 'agriculture',
    label: 'Farm',
    icon: Icons.agriculture,
  ),
  CategoryIconOption(
    key: 'water_drop',
    label: 'Irrigation',
    icon: Icons.water_drop,
  ),
  CategoryIconOption(
    key: 'local_florist',
    label: 'Plants',
    icon: Icons.local_florist,
  ),
  CategoryIconOption(
    key: 'inventory_2',
    label: 'Supplies',
    icon: Icons.inventory_2_outlined,
  ),
  CategoryIconOption(
    key: 'medical_services',
    label: 'Veterinary',
    icon: Icons.medical_services_outlined,
  ),
  CategoryIconOption(key: 'grain', label: 'Grain', icon: Icons.grain),
  CategoryIconOption(
    key: 'park',
    label: 'Organic',
    icon: Icons.park_outlined,
  ),
  CategoryIconOption(
    key: 'category',
    label: 'General',
    icon: Icons.category_outlined,
  ),
];

String suggestCategoryIconKey(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return 'category';

  if (normalized.contains('seedling') ||
      normalized.contains('nursery') ||
      normalized.contains('plant')) {
    return 'local_florist';
  }
  if (normalized.contains('seed')) return 'eco';
  if (normalized.contains('fertil') || normalized.contains('compost')) {
    return 'compost';
  }
  if (normalized.contains('pestic') ||
      normalized.contains('herb') ||
      normalized.contains('fungic') ||
      normalized.contains('insect')) {
    return 'shield';
  }
  if (normalized.contains('feed') ||
      normalized.contains('animal') ||
      normalized.contains('livestock') ||
      normalized.contains('poultry') ||
      normalized.contains('broiler') ||
      normalized.contains('layer')) {
    return 'pets';
  }
  if (normalized.contains('tool') ||
      normalized.contains('equipment') ||
      normalized.contains('machinery') ||
      normalized.contains('tractor')) {
    return 'build';
  }
  if (normalized.contains('irrig') ||
      normalized.contains('water') ||
      normalized.contains('drip') ||
      normalized.contains('sprinkler')) {
    return 'water_drop';
  }
  if (normalized.contains('harvest') ||
      normalized.contains('crate') ||
      normalized.contains('sack') ||
      normalized.contains('supply') ||
      normalized.contains('supplies')) {
    return 'inventory_2';
  }
  if (normalized.contains('vet') || normalized.contains('medic')) {
    return 'medical_services';
  }
  if (normalized.contains('grain') ||
      normalized.contains('rice') ||
      normalized.contains('corn')) {
    return 'grain';
  }
  if (normalized.contains('organic')) return 'park';

  return 'category';
}

CategoryIconOption categoryIconOptionForKey(String key) {
  for (final option in categoryIconOptions) {
    if (option.key == key) return option;
  }
  return categoryIconOptions.last;
}

IconData resolveCategoryIcon({
  String? iconKey,
  String? categoryName,
}) {
  final resolvedKey = iconKey != null && iconKey.trim().isNotEmpty
      ? iconKey.trim()
      : suggestCategoryIconKey(categoryName ?? '');

  return categoryIconOptionForKey(resolvedKey).icon;
}

String categoryIconLabel({
  String? iconKey,
  String? categoryName,
}) {
  final resolvedKey = iconKey != null && iconKey.trim().isNotEmpty
      ? iconKey.trim()
      : suggestCategoryIconKey(categoryName ?? '');

  return categoryIconOptionForKey(resolvedKey).label;
}

IconData categoryIcon(String category) =>
    resolveCategoryIcon(categoryName: category);
