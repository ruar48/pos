class CatalogSyncWatchResult {
  const CatalogSyncWatchResult({
    required this.changed,
    required this.stockRevision,
    required this.settingsRevision,
    required this.stockChanged,
    required this.settingsChanged,
  });

  final bool changed;
  final String stockRevision;
  final String settingsRevision;
  final bool stockChanged;
  final bool settingsChanged;

  factory CatalogSyncWatchResult.fromJson(Map<String, dynamic> json) {
    return CatalogSyncWatchResult(
      changed: json['changed'] == true,
      stockRevision: (json['stock_revision'] ?? '0').toString(),
      settingsRevision: (json['settings_revision'] ?? '0').toString(),
      stockChanged: json['stock_changed'] == true,
      settingsChanged: json['settings_changed'] == true,
    );
  }
}
