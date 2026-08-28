/// Configuration for CARTO-backed vector and raster basemaps.
class GoodBasemapConfig {
  final String lightStyleUrl;
  final String darkStyleUrl;
  final String? cartoApiKey;
  final bool requireApiKey;

  const GoodBasemapConfig({
    this.lightStyleUrl =
        'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
    this.darkStyleUrl =
        'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
    this.cartoApiKey,
    this.requireApiKey = false,
  });

  String validatedApiKey() {
    final value = cartoApiKey?.trim() ?? '';
    if (requireApiKey && value.isEmpty) {
      throw const GoodBasemapConfigurationException(
        'CARTO API key is required',
      );
    }
    return value;
  }
}

class GoodBasemapConfigurationException implements Exception {
  final String message;

  const GoodBasemapConfigurationException(this.message);

  @override
  String toString() => 'GoodBasemapConfigurationException: $message';
}

bool isCartoUri(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'cartocdn.com' ||
      host.endsWith('.cartocdn.com') ||
      host == 'carto.com' ||
      host.endsWith('.carto.com');
}

Uri cartoUriWithApiKey(Uri uri, String apiKey) {
  if (apiKey.isEmpty || !isCartoUri(uri)) return uri;
  return uri.replace(
    queryParameters: <String, String>{...uri.queryParameters, 'key': apiKey},
  );
}

String cartoUrlWithApiKey(String value, String apiKey) {
  final placeholders = <String, String>{};
  var index = 0;
  for (final match in RegExp(r'\{[^}]+\}').allMatches(value)) {
    placeholders.putIfAbsent(
      match.group(0)!,
      () => '__GOODMAP_TEMPLATE_${index++}__',
    );
  }
  var protected = value;
  for (final entry in placeholders.entries) {
    protected = protected.replaceAll(entry.key, entry.value);
  }
  final uri = Uri.tryParse(protected);
  if (uri == null) return value;
  var rewritten = cartoUriWithApiKey(uri, apiKey).toString();
  for (final entry in placeholders.entries) {
    rewritten = rewritten.replaceAll(entry.value, entry.key);
  }
  return rewritten;
}

String cartoApiKeyFingerprint(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
