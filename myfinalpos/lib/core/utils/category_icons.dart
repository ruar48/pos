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
  // Café, bakery & dessert categories.
  CategoryIconOption(key: 'coffee', label: 'Coffee', icon: Icons.local_cafe),
  CategoryIconOption(
    key: 'espresso',
    label: 'Espresso Bar',
    icon: Icons.coffee_maker,
  ),
  CategoryIconOption(
    key: 'tea',
    label: 'Tea',
    icon: Icons.emoji_food_beverage,
  ),
  CategoryIconOption(
    key: 'cold_drinks',
    label: 'Cold Drinks',
    icon: Icons.local_drink,
  ),
  CategoryIconOption(key: 'smoothie', label: 'Smoothies', icon: Icons.blender),
  CategoryIconOption(
    key: 'pastry',
    label: 'Pastries',
    icon: Icons.bakery_dining,
  ),
  CategoryIconOption(
    key: 'bread',
    label: 'Bread',
    icon: Icons.breakfast_dining,
  ),
  CategoryIconOption(key: 'cake', label: 'Cakes', icon: Icons.cake),
  CategoryIconOption(key: 'cookie', label: 'Cookies', icon: Icons.cookie),
  CategoryIconOption(key: 'dessert', label: 'Desserts', icon: Icons.icecream),
  CategoryIconOption(
    key: 'sandwich',
    label: 'Sandwiches',
    icon: Icons.lunch_dining,
  ),
  CategoryIconOption(
    key: 'brunch',
    label: 'Brunch',
    icon: Icons.brunch_dining,
  ),
  CategoryIconOption(
    key: 'merch',
    label: 'Merch & Beans',
    icon: Icons.storefront_outlined,
  ),

  // Existing agricultural categories — kept so saved icon keys still resolve.
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

  // Café, bakery & dessert names first — this is a coffee shop catalog.
  if (normalized.contains('espresso') ||
      normalized.contains('barista') ||
      normalized.contains('brew')) {
    return 'espresso';
  }
  if (normalized.contains('coffee') ||
      normalized.contains('latte') ||
      normalized.contains('mocha') ||
      normalized.contains('cappuccino') ||
      normalized.contains('americano')) {
    return 'coffee';
  }
  if (normalized.contains('tea') || normalized.contains('matcha')) {
    return 'tea';
  }
  if (normalized.contains('smoothie') ||
      normalized.contains('shake') ||
      normalized.contains('frappe')) {
    return 'smoothie';
  }
  if (normalized.contains('cold') ||
      normalized.contains('iced') ||
      normalized.contains('juice') ||
      normalized.contains('soda') ||
      normalized.contains('milk') ||
      normalized.contains('beverage') ||
      normalized.contains('drink')) {
    return 'cold_drinks';
  }
  if (normalized.contains('cake') ||
      normalized.contains('slice') ||
      normalized.contains('cheesecake')) {
    return 'cake';
  }
  if (normalized.contains('cookie') || normalized.contains('biscuit')) {
    return 'cookie';
  }
  if (normalized.contains('pastr') ||
      normalized.contains('croissant') ||
      normalized.contains('danish') ||
      normalized.contains('donut') ||
      normalized.contains('doughnut') ||
      normalized.contains('muffin') ||
      normalized.contains('pie') ||
      normalized.contains('tart')) {
    return 'pastry';
  }
  if (normalized.contains('bread') ||
      normalized.contains('loaf') ||
      normalized.contains('bun') ||
      normalized.contains('bake')) {
    return 'bread';
  }
  if (normalized.contains('dessert') ||
      normalized.contains('ice cream') ||
      normalized.contains('gelato') ||
      normalized.contains('sweet')) {
    return 'dessert';
  }
  if (normalized.contains('sandwich') ||
      normalized.contains('panini') ||
      normalized.contains('bagel') ||
      normalized.contains('toast')) {
    return 'sandwich';
  }
  if (normalized.contains('brunch') ||
      normalized.contains('breakfast') ||
      normalized.contains('meal')) {
    return 'brunch';
  }
  if (normalized.contains('merch') ||
      normalized.contains('bean') ||
      normalized.contains('mug') ||
      normalized.contains('tumbler')) {
    return 'merch';
  }

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
