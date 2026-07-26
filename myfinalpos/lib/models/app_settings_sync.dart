import 'app_settings.dart';

class AppSettingsSyncResult {
  const AppSettingsSyncResult({
    required this.revision,
    required this.unchanged,
    this.settings,
  });

  final String revision;
  final bool unchanged;
  final AppSettingsModel? settings;

  factory AppSettingsSyncResult.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];

    return AppSettingsSyncResult(
      revision: json['revision']?.toString() ?? '0',
      unchanged: json['unchanged'] == true,
      settings: rawSettings is Map<String, dynamic>
          ? AppSettingsModel.fromJson(rawSettings)
          : null,
    );
  }
}
