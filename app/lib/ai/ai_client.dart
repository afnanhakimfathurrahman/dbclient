/// Chat-completion clients for the AI assistant.
///
/// Three wire protocols cover most providers: OpenAI's chat completions
/// (also served by OpenRouter, Groq, DeepSeek, Ollama, LM Studio, vLLM…),
/// Anthropic's Messages API and Google's Gemini API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum AiProtocol { openAi, anthropic, gemini }

/// Known providers with their defaults. Base URL and model stay editable,
/// so any OpenAI-compatible server works through [custom].
enum AiProviderPreset {
  openAi(
    'OpenAI',
    AiProtocol.openAi,
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4.1-mini',
  ),
  anthropic(
    'Anthropic',
    AiProtocol.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-sonnet-5-5',
  ),
  gemini(
    'Google Gemini',
    AiProtocol.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    model: 'gemini-2.5-flash',
  ),
  openRouter(
    'OpenRouter',
    AiProtocol.openAi,
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-4.1-mini',
  ),
  groq(
    'Groq',
    AiProtocol.openAi,
    baseUrl: 'https://api.groq.com/openai/v1',
    model: 'llama-3.3-70b-versatile',
  ),
  deepSeek(
    'DeepSeek',
    AiProtocol.openAi,
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  ),
  ollama(
    'Ollama (local)',
    AiProtocol.openAi,
    baseUrl: 'http://localhost:11434/v1',
    model: 'qwen2.5-coder',
    requiresApiKey: false,
  ),
  custom(
    'Custom (OpenAI-compatible)',
    AiProtocol.openAi,
    baseUrl: '',
    model: '',
    requiresApiKey: false,
  );

  const AiProviderPreset(
    this.label,
    this.protocol, {
    required this.baseUrl,
    required this.model,
    this.requiresApiKey = true,
  });

  final String label;
  final AiProtocol protocol;
  final String baseUrl;
  final String model;
  final bool requiresApiKey;
}

/// Where and how to reach a model. The API key comes from secure storage.
class AiEndpoint {
  const AiEndpoint({
    required this.preset,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
  });

  final AiProviderPreset preset;
  final String baseUrl;
  final String model;
  final String apiKey;

  AiProtocol get protocol => preset.protocol;
}

class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiClient {
  AiClient(this.endpoint, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final AiEndpoint endpoint;
  final http.Client _http;

  static const _timeout = Duration(seconds: 120);
  static const _maxTokens = 4096;

  void close() => _http.close();

  String get _base {
    final url = endpoint.baseUrl.trim();
    if (url.isEmpty) throw const AiException('Set a base URL for the provider.');
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get _model {
    final model = endpoint.model.trim();
    if (model.isEmpty) throw const AiException('Choose a model.');
    // Gemini lists models as "models/<id>".
    return model.startsWith('models/') ? model.substring(7) : model;
  }

  Uri _uri(String path) {
    final uri = Uri.tryParse('$_base/$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiException('Invalid provider URL: ${endpoint.baseUrl}');
    }
    return uri;
  }

  Map<String, String> get _headers {
    final key = endpoint.apiKey.trim();
    return {
      'content-type': 'application/json',
      ...switch (endpoint.protocol) {
        AiProtocol.openAi => {if (key.isNotEmpty) 'authorization': 'Bearer $key'},
        AiProtocol.anthropic => {
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
        },
        AiProtocol.gemini => {'x-goog-api-key': key},
      },
    };
  }

  /// Sends one system + user turn and returns the reply text.
  Future<String> complete({required String system, required String user}) async {
    final (Uri uri, Map<String, Object?> body) = switch (endpoint.protocol) {
      AiProtocol.openAi => (
        _uri('chat/completions'),
        {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        },
      ),
      AiProtocol.anthropic => (
        _uri('messages'),
        {
          'model': _model,
          'max_tokens': _maxTokens,
          'system': system,
          'messages': [
            {'role': 'user', 'content': user},
          ],
        },
      ),
      AiProtocol.gemini => (
        _uri('models/${Uri.encodeComponent(_model)}:generateContent'),
        {
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': user},
              ],
            },
          ],
        },
      ),
    };
    final json = await _send(
      () => _http.post(uri, headers: _headers, body: jsonEncode(body)),
    );
    final text = switch (endpoint.protocol) {
      AiProtocol.openAi => _openAiText(json),
      AiProtocol.anthropic => _joinText(json['content'], 'text'),
      AiProtocol.gemini => _geminiText(json),
    };
    if (text == null || text.trim().isEmpty) {
      throw const AiException('The model returned an empty reply.');
    }
    return text;
  }

  /// Model ids the provider offers, sorted.
  Future<List<String>> listModels() async {
    final json = await _send(
      () => _http.get(
        _uri(switch (endpoint.protocol) {
          // Both page their lists; ask for one big page.
          AiProtocol.anthropic => 'models?limit=1000',
          AiProtocol.gemini => 'models?pageSize=1000',
          AiProtocol.openAi => 'models',
        }),
        headers: _headers,
      ),
    );
    final ids = switch (endpoint.protocol) {
      AiProtocol.openAi || AiProtocol.anthropic => [
        for (final m in (json['data'] as List?) ?? const [])
          if (m is Map && m['id'] is String) m['id'] as String,
      ],
      AiProtocol.gemini => [
        for (final m in (json['models'] as List?) ?? const [])
          if (m is Map &&
              m['name'] is String &&
              ((m['supportedGenerationMethods'] as List?)?.contains(
                    'generateContent',
                  ) ??
                  true))
            (m['name'] as String).replaceFirst('models/', ''),
      ],
    };
    return ids..sort();
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const AiException('The provider did not answer in time.');
    } on http.ClientException catch (e) {
      throw AiException('Could not reach the provider: ${e.message}');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _errorMessage(json) ?? response.reasonPhrase ?? '';
      throw AiException(
        'Provider error ${response.statusCode}'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    if (json is! Map<String, Object?>) {
      throw const AiException('The provider sent an unexpected response.');
    }
    return json;
  }

  /// `{"error": {"message": …}}` (OpenAI, Anthropic, Gemini) or
  /// `{"error": "…"}` (Ollama and some proxies).
  static String? _errorMessage(Object? json) {
    if (json is! Map) return null;
    final error = json['error'];
    if (error is String) return error;
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    return json['message'] is String ? json['message'] as String : null;
  }

  static String? _openAiText(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map?)?['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String) return content;
    // Some servers send content parts.
    return _joinText(content, 'text');
  }

  static String? _geminiText(Map<String, Object?> json) {
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final reason = (json['promptFeedback'] as Map?)?['blockReason'];
      if (reason != null) throw AiException('The request was blocked: $reason');
      return null;
    }
    final content = (candidates.first as Map?)?['content'];
    return content is Map ? _joinText(content['parts'], 'text') : null;
  }

  /// Joins the [field] of each part in a list of content parts.
  static String? _joinText(Object? parts, String field) {
    if (parts is! List) return null;
    return [
      for (final p in parts)
        if (p is Map && p[field] is String) p[field] as String,
    ].join();
  }
}
