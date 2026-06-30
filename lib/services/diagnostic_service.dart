import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/verification_output.dart';

/// MVP-ONLY: calls the Agent Engine directly from the device using a
/// short-lived OAuth access token. This token expires (~1hr) and is
/// visible to anyone who inspects the app — fine for local testing,
/// NOT safe for a real release. Replace with a backend proxy before
/// shipping to real users.
class DiagnosticService {
  static const String _accessToken =
      'ya29.a0AT3oNZ8-mc8acGa9nCfxkDns5y-W9p5VEKD5Wz_1G_nrUuOD-wYfd8pio_n60siCSHBRmpF6benMJa6HHP-hJljC2m2MzAQqO3KWR_GVeexGKdSdZ7CdUT7QW2ESFOgmebf8SQ_W-mc9S51fF8XLhxJapSw-uo3cpFpiEEfTkcqs35_-1vhroq1RcXdRQlQUsS42dD-TZIVFQAaCgYKAbESARISFQHGX2MiMsYPWMsAm27OfqBbY-0rdw0213';

  static const String _baseUrl =
      'https://us-central1-aiplatform.googleapis.com/v1/projects/'
      'project-f890bbaf-d48c-4bd8-bb9/locations/us-central1/'
      'reasoningEngines/383033017477627904';

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json; charset=utf-8',
      };

  /// Reuses the same user id UserService already generated on first launch.
  static Future<String> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('registered_user_id') ?? 'mvp_anonymous_user';
  }

  /// Creates a new ADK session for this user. Call once per report flow.
  static Future<String> createSession() async {
    final userId = await _getUserId();
    final response = await http
        .post(
          Uri.parse('$_baseUrl:query'),
          headers: _headers,
          body: jsonEncode({
            'class_method': 'async_create_session',
            'input': {'user_id': userId},
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw DiagnosticServiceException(
        'Failed to create session (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    // ADK returns the session object directly in the output payload.
    final sessionId = decoded is Map
        ? (decoded['output']?['id'] ?? decoded['id'])
        : null;
    if (sessionId == null) {
      throw DiagnosticServiceException(
        'Session created but no id found in response: ${response.body}',
      );
    }
    return sessionId.toString();
  }

  /// Sends images + description + coordinates to the agent via streamQuery,
  /// waits for the full stream, and returns the parsed final result.
  static Future<VerificationOutput> analyzeIssue({
    required List<File> images,
    required String description,
    required double latitude,
    required double longitude,
    String? sessionId,
  }) async {
    final userId = await _getUserId();
    final resolvedSessionId = sessionId ?? await createSession();

    final imageParts = <Map<String, dynamic>>[];
    for (final file in images) {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final mimeType = (ext == 'jpg' || ext == 'jpeg')
          ? 'image/jpeg'
          : 'image/$ext';
      imageParts.add({
        'inline_data': {
          'mime_type': mimeType,
          'data': base64Encode(bytes),
        },
      });
    }

    final textPart = {
      'text': 'Issue description: $description\n'
          'Location: latitude=$latitude, longitude=$longitude',
    };

    final message = {
      'role': 'user',
      'parts': [textPart, ...imageParts],
    };

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl:streamQuery?alt=sse'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'class_method': 'stream_query',
      'input': {
        'message': message,
        'user_id': userId,
        'session_id': resolvedSessionId,
      },
    });

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: 120));

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw DiagnosticServiceException(
        'Server returned ${streamedResponse.statusCode}: $body',
      );
    }

    final fullBody = await streamedResponse.stream.bytesToString();

    // Response is newline-delimited JSON events (optionally "data: "-prefixed
    // SSE lines). Walk every event, and keep the LAST text part seen — that's
    // the agent's final structured JSON output after any tool calls.
    String? lastText;
    for (final rawLine in const LineSplitter().convert(fullBody)) {
      final line = rawLine.startsWith('data: ')
          ? rawLine.substring(6).trim()
          : rawLine.trim();
      if (line.isEmpty) continue;

      Map<String, dynamic>? event;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) event = decoded;
      } catch (_) {
        continue; // not a JSON line, skip
      }
      if (event == null) continue;

      final parts = event['content']?['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is Map && part['text'] is String) {
            lastText = part['text'] as String;
          }
        }
      }
    }

    if (lastText == null) {
      throw DiagnosticServiceException(
        'No text result found in agent response.\nRaw body: $fullBody',
      );
    }

    final Map<String, dynamic> resultJson;
    try {
      resultJson = jsonDecode(lastText) as Map<String, dynamic>;
    } catch (e) {
      throw DiagnosticServiceException(
        'Could not parse agent output as JSON: $lastText',
      );
    }

    return VerificationOutput.fromJson(resultJson);
  }
}

class DiagnosticServiceException implements Exception {
  final String message;
  DiagnosticServiceException(this.message);

  @override
  String toString() => message;
}
