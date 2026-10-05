/// The canonical stock model/info observation. Empty strings represent an
/// unconfigured model or an automatic provider; they are not guessed routes.
class ConfiguredModel {
  const ConfiguredModel({required this.provider, required this.model});

  final String provider;
  final String model;

  static ConfiguredModel fromInfo(Map<String, dynamic> response) {
    final provider = response['provider'];
    final model = response['model'];
    if (provider is! String || model is! String) {
      throw const FormatException('Invalid stock model observation');
    }
    return ConfiguredModel(provider: provider, model: model);
  }

  bool get hasModel => model.isNotEmpty;
  ModelChoice? get choice => provider.isEmpty || !hasModel
      ? null
      : ModelChoice(provider: provider, model: model);
}

/// A model and its actual provider route. Display text never becomes identity.
class ModelChoice {
  final String provider;
  final String model;
  final String? providerLabel;
  final String? displayName;
  final String? detail;

  const ModelChoice({
    required this.provider,
    required this.model,
    this.providerLabel,
    this.displayName,
    this.detail,
  });

  String get routeLabel => providerLabel?.trim().isNotEmpty == true
      ? providerLabel!.trim()
      : provider;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : model;

  /// Stock model-options rows use slug/name and a list of string model IDs.
  static List<ModelChoice> fromOptions(Map<String, dynamic> response) {
    final providers = response['providers'];
    if (providers is! List) {
      throw const FormatException('Expected a list of provider records');
    }
    final choices = <ModelChoice>[];
    for (final row in providers) {
      if (row is! Map ||
          row['slug'] is! String ||
          (row['slug'] as String).trim().isEmpty ||
          row['name'] is! String ||
          row['models'] is! List) {
        throw const FormatException('Expected a model-options provider record');
      }
      final slug = (row['slug'] as String).trim();
      final label = (row['name'] as String).trim();
      for (final value in row['models'] as List) {
        if (value is! String || value.trim().isEmpty) {
          throw const FormatException('Expected a nonempty string model ID');
        }
        choices.add(
          ModelChoice(
            provider: slug,
            model: value.trim(),
            providerLabel: label.isEmpty ? null : label,
          ),
        );
      }
    }
    return choices;
  }
}

enum ModelSpecialChoice { automatic, profileDefault }

/// A typed selection. Inherited choices cannot be mistaken for a model route.
class ModelSelection {
  final ModelChoice? choice;
  final ModelSpecialChoice? special;

  const ModelSelection.model(ModelChoice this.choice) : special = null;
  const ModelSelection.special(ModelSpecialChoice this.special) : choice = null;

  @override
  bool operator ==(Object other) =>
      other is ModelSelection &&
      special == other.special &&
      choice?.provider == other.choice?.provider &&
      choice?.model == other.choice?.model;

  @override
  int get hashCode => Object.hash(special, choice?.provider, choice?.model);
}
