import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

// ═══════════════════════════════════════════════════════════════
//  GeminiService — Gemini 2.0 Flash con Function Calling
//
//  Arquitectura:
//  1. System prompt con contenido del documento de contexto
//  2. Function Declarations: endpoints de FastAPI como "tools"
//  3. Gemini decide cuándo llamar al backend según la pregunta
//  4. El resultado de la tool se reinyecta como contexto
// ═══════════════════════════════════════════════════════════════

class GeminiService {
  // ── CONFIGURACIÓN ──────────────────────────────────────────
  // Obtén tu API key en: https://aistudio.google.com/app/apikey
  static const String _apiKey = 'AIzaSyCuOaLPOypJTSnyeWbeKNQb7GoeADdBqeQ';
  static const String _model  = 'gemini-flash-latest';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models'
      '/$_model:generateContent?key=$_apiKey';

  // ── DOCUMENT CONTEXT ───────────────────────────────────────
  // Aquí irá el contenido extraído del PDF de 36 páginas.
  // Reemplaza este placeholder cuando subas el documento.
  static const String _documentContext = '''
[CONTENIDO DEL DOCUMENTO TÉCNICO - PENDIENTE DE CARGA]

Una vez que subas el PDF, este string se reemplazará con el
contenido extraído del documento de 36 páginas que servirá
como base de conocimiento para GreenBot.
''';

  // ── SYSTEM PROMPT ──────────────────────────────────────────
  static String get _systemPrompt => '''
Eres GreenBot, asistente agrícola inteligente de la plataforma GreenCode.
Tu especialidad es el Valle de Atlixco, Puebla, México.

## TU ROL
- Ayudar a agricultores con decisiones sobre sus cultivos y parcelas
- Interpretar datos climáticos, de suelo y agronómicos en lenguaje claro
- Basar tus respuestas en datos reales del backend cuando sean relevantes
- Usar el documento técnico como base de conocimiento agrónomo

## DOCUMENTO DE REFERENCIA TÉCNICA
$_documentContext

## CÓMO USAR LAS HERRAMIENTAS
- Llama a `get_frost_check` cuando el usuario pregunte sobre heladas,
  temperatura mínima, riesgo de congelamiento o temperatura del suelo
- Llama a las herramientas SOLO cuando la pregunta del usuario lo requiera
- Combina los datos del backend con el conocimiento del documento
- Siempre explica los resultados en términos prácticos para el agricultor

## ESTILO DE RESPUESTA
- Responde en español, tono amigable y directo
- Máximo 3 párrafos por respuesta
- Si hay riesgo agrícola, indícalo claramente con ⚠️
- Si las condiciones son favorables, usa ✅
- Evita tecnicismos innecesarios
''';

  // ── FUNCTION DECLARATIONS (Tools para Gemini) ──────────────
  // Cada función mapea a un endpoint de tu FastAPI.
  // Agrega más funciones aquí cuando tengas nuevos endpoints.
  static const List<Map<String, dynamic>> _tools = [
    {
      'functionDeclarations': [
        {
          'name': 'get_frost_check',
          'description':
              'Obtiene datos de temperatura del aire y del suelo para una '
              'coordenada específica. Úsala cuando el usuario pregunte sobre '
              'heladas, temperatura mínima, riesgo de congelamiento, '
              'temperatura del suelo o condiciones climáticas actuales.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'lat': {
                'type': 'NUMBER',
                'description': 'Latitud de la parcela. Default: 19.0414 (Valle de Atlixco)',
              },
              'lon': {
                'type': 'NUMBER',
                'description': 'Longitud de la parcela. Default: -98.2063 (Valle de Atlixco)',
              },
            },
            'required': [],
          },
        },

        // ── TEMPLATE para agregar más endpoints ──────────────
        // Descomenta y adapta cuando tengas nuevos endpoints:
        //
        // {
        //   'name': 'get_soil_analysis',
        //   'description': 'Obtiene análisis de suelo: pH, humedad, nutrientes. '
        //       'Úsala cuando el usuario pregunte sobre calidad del suelo, '
        //       'fertilidad o condiciones para siembra.',
        //   'parameters': {
        //     'type': 'OBJECT',
        //     'properties': {
        //       'lat': {'type': 'NUMBER', 'description': 'Latitud'},
        //       'lon': {'type': 'NUMBER', 'description': 'Longitud'},
        //     },
        //     'required': [],
        //   },
        // },
        //
        // {
        //   'name': 'get_precipitation',
        //   'description': 'Obtiene datos de precipitación y humedad ambiental.',
        //   'parameters': {
        //     'type': 'OBJECT',
        //     'properties': {
        //       'lat': {'type': 'NUMBER', 'description': 'Latitud'},
        //       'lon': {'type': 'NUMBER', 'description': 'Longitud'},
        //     },
        //     'required': [],
        //   },
        // },
      ],
    },
  ];

  // ── EJECUTAR TOOL CALL ─────────────────────────────────────
  // Recibe el nombre de la función y sus args, llama al backend.
  static Future<String> _executeToolCall(
    String functionName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (functionName) {
        case 'get_frost_check':
          final lat = (args['lat'] as num?)?.toDouble() ?? 19.0414;
          final lon = (args['lon'] as num?)?.toDouble() ?? -98.2063;
          final result = await ApiService.getFrostCheck(lat: lat, lon: lon);
          return jsonEncode(result);

        // Agrega más cases aquí cuando tengas nuevos endpoints:
        // case 'get_soil_analysis':
        //   final result = await ApiService.getSoilAnalysis(...);
        //   return jsonEncode(result);

        default:
          return jsonEncode({'error': 'Función desconocida: $functionName'});
      }
    } catch (e) {
      return jsonEncode({'error': 'Error al llamar al backend: $e'});
    }
  }

  // ── SEND MESSAGE (entrada principal) ──────────────────────
  // Maneja el flujo completo con function calling de Gemini.
  static Future<String> sendMessage({
    required String userMessage,
    required List<Map<String, dynamic>> history,
  }) async {
    // Construye el historial de conversación para la API
    final contents = <Map<String, dynamic>>[];

    // Agrega historial previo (máx. 20 mensajes para no saturar)
    final recentHistory = history.length > 20
        ? history.sublist(history.length - 20)
        : history;

    for (final msg in recentHistory) {
      contents.add({
        'role': msg['role'],
        'parts': [{'text': msg['text']}],
      });
    }

    // Agrega el mensaje actual del usuario
    contents.add({
      'role': 'user',
      'parts': [{'text': userMessage}],
    });

    // ── Primera llamada a Gemini ───────────────────────────
    var response = await _callGemini(contents);
    var responseBody = jsonDecode(response.body);

    // ── Manejo de Function Calling ─────────────────────────
    // Si Gemini decide llamar a una tool, ejecutamos el backend
    // y reinyectamos el resultado para que genere la respuesta final
    int maxToolRounds = 3; // Evita loops infinitos
    while (_hasFunctionCall(responseBody) && maxToolRounds > 0) {
      maxToolRounds--;

      final candidate = responseBody['candidates'][0];
      final parts     = candidate['content']['parts'] as List;

      // Agrega la respuesta de Gemini (con tool call) al historial
      contents.add({
        'role': 'model',
        'parts': parts,
      });

      // Ejecuta cada tool call
      final toolResultParts = <Map<String, dynamic>>[];
      for (final part in parts) {
        if (part['functionCall'] != null) {
          final fc           = part['functionCall'];
          final functionName = fc['name'] as String;
          final args         = (fc['args'] as Map<String, dynamic>?) ?? {};

          final toolResult = await _executeToolCall(functionName, args);

          toolResultParts.add({
            'functionResponse': {
              'name': functionName,
              'response': {'content': toolResult},
            },
          });
        }
      }

      // Reinyecta los resultados del backend al contexto
      contents.add({
        'role': 'user',
        'parts': toolResultParts,
      });

      // Segunda llamada: Gemini genera la respuesta final con los datos
      response     = await _callGemini(contents);
      responseBody = jsonDecode(response.body);
    }

    // ── Extrae la respuesta final de texto ─────────────────
    return _extractText(responseBody);
  }

  // ── LLAMADA HTTP A GEMINI ──────────────────────────────────
  static Future<http.Response> _callGemini(
    List<Map<String, dynamic>> contents,
  ) async {
    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': _systemPrompt}],
      },
      'contents': contents,
      'tools': _tools,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
        'topP': 0.9,
      },
    });

    return http.post(
      Uri.parse(_baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 30));
  }

  // ── HELPERS ───────────────────────────────────────────────
  static bool _hasFunctionCall(Map<String, dynamic> responseBody) {
    try {
      final parts = responseBody['candidates'][0]['content']['parts'] as List;
      return parts.any((p) => p['functionCall'] != null);
    } catch (_) {
      return false;
    }
  }

  static String _extractText(Map<String, dynamic> responseBody) {
    try {
      final parts = responseBody['candidates'][0]['content']['parts'] as List;
      final textParts = parts
          .where((p) => p['text'] != null)
          .map((p) => p['text'] as String)
          .toList();
      return textParts.join('\n').trim();
    } catch (e) {
      // Manejo de errores de la API
      if (responseBody['error'] != null) {
        final err = responseBody['error'];
        return '⚠️ Error de GreenBot: ${err['message'] ?? 'Error desconocido'}';
      }
      return '⚠️ No pude procesar la respuesta. Intenta de nuevo.';
    }
  }
}