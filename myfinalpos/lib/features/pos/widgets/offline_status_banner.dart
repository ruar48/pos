import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class OfflineStatusBanner extends StatelessWidget {
  const OfflineStatusBanner({
    super.key,
    required this.pendingSyncCount,
    this.catalogSavedAt,
  });

  final int pendingSyncCount;
  final DateTime? catalogSavedAt;

  String get _catalogAgeLabel {
    final savedAt = catalogSavedAt;
    if (savedAt == null) return 'Using last saved product list.';
    final diff = DateTime.now().difference(savedAt);
    if (diff.inMinutes < 2) return 'Using product list saved just now.';
    if (diff.inHours < 1) {
      return 'Using product list saved ${diff.inMinutes} min ago.';
    }
    if (diff.inHours < 24) {
      return 'Using product list saved ${diff.inHours} hr ago.';
    }
    return 'Using product list saved on ${savedAt.month}/${savedAt.day}.';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.orange,
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Offline mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sales stay on this tablet until internet returns. '
                      'Other registers, inventory, and reports will not update yet. '
                      '$_catalogAgeLabel',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (pendingSyncCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$pendingSyncCount sale${pendingSyncCount == 1 ? '' : 's'} waiting to sync.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
