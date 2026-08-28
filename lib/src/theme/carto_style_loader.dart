import 'dart:convert';

import 'package:flutter/material.dart' show Brightness;
import 'package:http/http.dart' as http;

import 'carto_basemap_config.dart';

class CartoStyleLoadException implements Exception {
  final String message;

  const CartoStyleLoadException(this.message);

  @override
  String toString() => 'CartoStyleLoadException: $message';
}

class CartoStyleLoader {
  CartoStyleLoader({required http.Client client}) : _client = client;

  final http.Client _client;
  final Map<String, Future<String>> _cache = {};

  Future<String> load(
    Brightness brightness,
    GoodBasemapConfig config, {
    String? languageCode,
    String? waterColor,
  }) {
    final apiKey = config.validatedApiKey();
    final styleUrl =
        brightness == Brightness.dark
            ? config.darkStyleUrl
            : config.lightStyleUrl;
    final cacheKey = <String>[
      brightness.name,
      styleUrl,
      cartoApiKeyFingerprint(apiKey),
      languageCode ?? '',
      waterColor ?? '',
    ].join('|');
    return _cache.putIfAbsent(
      cacheKey,
      () => _loadAndRewrite(styleUrl, apiKey, languageCode, waterColor),
    );
  }

  Future<String> _loadAndRewrite(
    String styleUrl,
    String apiKey,
    String? languageCode,
    String? waterColor,
  ) async {
    final style = await _fetchJson(Uri.parse(styleUrl), apiKey);
    final sources = style['sources'];
    if (sources is Map) {
      for (final sourceValue in sources.values) {
        if (sourceValue is! Map) continue;
        final source = sourceValue.cast<String, dynamic>();
        final tileJsonUrl = source['url'];
        if (tileJsonUrl is String) {
          final uri = Uri.tryParse(tileJsonUrl);
          if (uri != null && isCartoUri(uri)) {
            final tileJson = await _fetchJson(uri, apiKey);
            final tiles = tileJson['tiles'];
            if (tiles is! List || tiles.any((value) => value is! String)) {
              throw const CartoStyleLoadException(
                'CARTO tile metadata is missing tiles',
              );
            }
            source.remove('url');
            source['tiles'] = [
              for (final value in tiles.cast<String>())
                _rewriteUrl(value, apiKey),
            ];
            for (final key in const [
              'attribution',
              'minzoom',
              'maxzoom',
              'bounds',
              'scheme',
            ]) {
              if (tileJson.containsKey(key)) source[key] = tileJson[key];
            }
          }
        }

        final existingTiles = source['tiles'];
        if (existingTiles is List) {
          source['tiles'] = [
            for (final value in existingTiles)
              if (value is String) _rewriteUrl(value, apiKey) else value,
          ];
        }
      }
    }

    for (final key in const ['sprite', 'glyphs']) {
      final value = style[key];
      if (value is String) style[key] = _rewriteUrl(value, apiKey);
    }
    if (languageCode != null && languageCode.isNotEmpty) {
      _localizeLabels(style, languageCode);
    }
    if (waterColor != null && waterColor.isNotEmpty) {
      _setWaterColor(style, waterColor);
    }
    return jsonEncode(style);
  }

  void _setWaterColor(Map<String, dynamic> style, String waterColor) {
    final layers = style['layers'];
    if (layers is! List) return;

    for (final layerValue in layers) {
      if (layerValue is! Map || layerValue['id'] != 'water') continue;
      final paintValue = layerValue['paint'];
      if (paintValue is Map) paintValue['fill-color'] = waterColor;
    }
  }

  void _localizeLabels(Map<String, dynamic> style, String languageCode) {
    final layers = style['layers'];
    if (layers is! List) return;

    final localizedName = <dynamic>[
      'coalesce',
      <dynamic>['get', 'name:$languageCode'],
      if (languageCode == 'en') <dynamic>['get', 'name_en'],
      <dynamic>['get', 'name'],
      if (languageCode != 'en') <dynamic>['get', 'name_en'],
    ];

    for (final layerValue in layers) {
      if (layerValue is! Map || layerValue['type'] != 'symbol') continue;
      final layoutValue = layerValue['layout'];
      if (layoutValue is! Map) continue;
      final textField = layoutValue['text-field'];
      if (_usesNameField(textField)) {
        layoutValue['text-field'] = localizedName;
      }
    }
  }

  bool _usesNameField(dynamic value) {
    if (value is String) {
      return RegExp(r'\{name(?::[^}]+|_[^}]+)?\}').hasMatch(value);
    }
    if (value is List) return value.any(_usesNameField);
    if (value is Map) return value.values.any(_usesNameField);
    return false;
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri, String apiKey) async {
    try {
      final response = await _client.get(cartoUriWithApiKey(uri, apiKey));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CartoStyleLoadException('Unable to load basemap resource');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const CartoStyleLoadException('Invalid basemap JSON');
      }
      return decoded.cast<String, dynamic>();
    } on CartoStyleLoadException {
      rethrow;
    } catch (_) {
      throw const CartoStyleLoadException('Unable to load basemap resource');
    }
  }

  String _rewriteUrl(String value, String apiKey) {
    return cartoUrlWithApiKey(value, apiKey);
  }
}
