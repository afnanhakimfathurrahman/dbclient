import 'dart:convert';

import 'package:db_client/ai/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A client whose server answers [response] and records the request.
(AiClient, List<http.Request>) clientFor(
  AiProviderPreset preset,
  Object response, {
  int status = 200,
  String apiKey = 'secret',
  String? baseUrl,
}) {
  final requests = <http.Request>[];
  final mock = MockClient((request) async {
    requests.add(request);
    return http.Response(jsonEncode(response), status);
  });
  final client = AiClient(
    AiEndpoint(
      preset: preset,
      baseUrl: baseUrl ?? '${preset.baseUrl}/',
      model: 'm1',
      apiKey: apiKey,
    ),
    httpClient: mock,
  );
  return (client, requests);
}

void main() {
  group('complete', () {
    test('OpenAI-compatible chat completions', () async {
      final (client, requests) = clientFor(AiProviderPreset.openRouter, {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'SELECT 1'},
          },
        ],
      });
      expect(await client.complete(system: 'sys', user: 'hi'), 'SELECT 1');
      final r = requests.single;
      expect(r.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(r.headers['authorization'], 'Bearer secret');
      final body = jsonDecode(r.body) as Map;
      expect(body['model'], 'm1');
      expect(body['messages'], [
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('sends no authorization without a key (local servers)', () async {
      final (client, requests) = clientFor(AiProviderPreset.ollama, {
        'choices': [
          {
            'message': {'content': 'x'},
          },
        ],
      }, apiKey: '');
      await client.complete(system: 's', user: 'u');
      expect(requests.single.headers.containsKey('authorization'), isFalse);
    });

    test('Anthropic messages', () async {
      final (client, requests) = clientFor(AiProviderPreset.anthropic, {
        'content': [
          {'type': 'text', 'text': 'SELECT '},
          {'type': 'text', 'text': '2'},
        ],
      });
      expect(await client.complete(system: 'sys', user: 'hi'), 'SELECT 2');
      final r = requests.single;
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(r.headers['x-api-key'], 'secret');
      expect(r.headers['anthropic-version'], isNotNull);
      final body = jsonDecode(r.body) as Map;
      expect(body['system'], 'sys');
      expect(body['max_tokens'], isPositive);
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('Gemini generateContent', () async {
      final (client, requests) = clientFor(AiProviderPreset.gemini, {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'SELECT 3'},
              ],
            },
          },
        ],
      });
      expect(await client.complete(system: 'sys', user: 'hi'), 'SELECT 3');
      final r = requests.single;
      expect(
        r.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/m1:generateContent',
      );
      expect(r.headers['x-goog-api-key'], 'secret');
      final body = jsonDecode(r.body) as Map;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'sys'},
        ],
      });
    });

    test('reports the provider error message', () async {
      final (client, _) = clientFor(AiProviderPreset.openAi, {
        'error': {'message': 'Incorrect API key provided'},
      }, status: 401);
      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            'Provider error 401: Incorrect API key provided',
          ),
        ),
      );
    });

    test('reports plain string errors (Ollama)', () async {
      final (client, _) = clientFor(AiProviderPreset.ollama, {
        'error': 'model "m1" not found',
      }, status: 404);
      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('model "m1" not found'),
          ),
        ),
      );
    });

    test('rejects an empty base URL', () async {
      final (client, requests) = clientFor(
        AiProviderPreset.custom,
        const {},
        baseUrl: '',
      );
      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(isA<AiException>()),
      );
      expect(requests, isEmpty);
    });
  });

  group('listModels', () {
    test('OpenAI-compatible', () async {
      final (client, requests) = clientFor(AiProviderPreset.openAi, {
        'data': [
          {'id': 'b'},
          {'id': 'a'},
        ],
      });
      expect(await client.listModels(), ['a', 'b']);
      expect(requests.single.url.path, '/v1/models');
    });

    test('Gemini keeps generateContent models without the prefix', () async {
      final (client, _) = clientFor(AiProviderPreset.gemini, {
        'models': [
          {
            'name': 'models/gemini-x',
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/embedding',
            'supportedGenerationMethods': ['embedContent'],
          },
        ],
      });
      expect(await client.listModels(), ['gemini-x']);
    });
  });
}
