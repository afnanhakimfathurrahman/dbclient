import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/secret_store.dart';
import '../state/providers.dart';
import 'ai_client.dart';

/// The chosen AI provider. Off (null) until the user sets it up, since
/// using it sends schema details to a third party.
class AiSettings {
  const AiSettings({
    required this.preset,
    required this.baseUrl,
    required this.model,
  });

  final AiProviderPreset preset;
  final String baseUrl;
  final String model;

  String get label => '${preset.label} · $model';
}

/// Settings in shared preferences, kept per provider so switching back
/// restores them; API keys in secure storage.
class AiSettingsNotifier extends Notifier<AiSettings?> {
  static const _presetKey = 'ai.preset';
  static String _baseUrlKey(AiProviderPreset p) => 'ai.${p.name}.baseUrl';
  static String _modelKey(AiProviderPreset p) => 'ai.${p.name}.model';

  final _secrets = SecretStore();

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AiSettings? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final preset = AiProviderPreset.values.asNameMap()[prefs.getString(
      _presetKey,
    )];
    return preset == null ? null : settingsFor(preset);
  }

  /// Saved (or default) settings for [preset].
  AiSettings settingsFor(AiProviderPreset preset) => AiSettings(
    preset: preset,
    baseUrl: _prefs.getString(_baseUrlKey(preset)) ?? preset.baseUrl,
    model: _prefs.getString(_modelKey(preset)) ?? preset.model,
  );

  Future<String> apiKey(AiProviderPreset preset) async =>
      await _secrets.readAiApiKey(preset.name) ?? '';

  Future<void> save(AiSettings settings, {required String apiKey}) async {
    final preset = settings.preset;
    await _prefs.setString(_baseUrlKey(preset), settings.baseUrl.trim());
    await _prefs.setString(_modelKey(preset), settings.model.trim());
    if (apiKey.trim().isEmpty) {
      await _secrets.deleteAiApiKey(preset.name);
    } else {
      await _secrets.writeAiApiKey(preset.name, apiKey.trim());
    }
    await _prefs.setString(_presetKey, preset.name);
    state = settingsFor(preset);
  }

  /// Turns the assistant off. Saved keys stay, to make turning it back on
  /// easy.
  Future<void> disable() async {
    await _prefs.remove(_presetKey);
    state = null;
  }

  /// A client for the active settings, or null when off.
  Future<AiClient?> client() async {
    final settings = state;
    if (settings == null) return null;
    return AiClient(
      AiEndpoint(
        preset: settings.preset,
        baseUrl: settings.baseUrl,
        model: settings.model,
        apiKey: await apiKey(settings.preset),
      ),
    );
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings?>(
  AiSettingsNotifier.new,
);
