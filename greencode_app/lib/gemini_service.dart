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
  static const String _apiKey = 'AIzaSyCu3tcz1reSqJcqtfwGKjcLwmQIXSuc7mk';
  static const String _model  = 'gemini-flash-latest';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models'
      '/$_model:generateContent?key=$_apiKey';

  // ── DOCUMENT CONTEXT ───────────────────────────────────────
  // Aquí irá el contenido extraído del PDF de 36 páginas.
  // Reemplaza este placeholder cuando subas el documento.
  static const String _documentContext = '''
═══════════════════════════════════════════════════════
CORPUS DE DATOS GREENCODE
Resiliencia Agroclimática para Cultivos de Ciclo Corto en Puebla
═══════════════════════════════════════════════════════

RESUMEN EJECUTIVO
Los policultivos tipo milpa alcanzan RET 1.6-2.0 (60-100% más productivos que monocultivos).
Siniestralidad en Puebla: 47.7% sequía, 32.3% granizada, heladas tardías abril 2025 dañaron
1,180-1,700 ha en 32 municipios. El acolchado orgánico reduce 3.5-4.4°C la temperatura del
suelo y 67% la evaporación.

═══════════════════════════════════════════════════════
1. MARCO CONCEPTUAL
═══════════════════════════════════════════════════════
GreenCode NO predice el clima, sino diseña sistemas estructuralmente resistentes.
5 capas de resiliencia:
- Capa 1 (Suelo y agua): acolchado orgánico, terrazas, zanjas de infiltración, materia orgánica
- Capa 2 (Biodiversidad funcional): policultivos, milpa, MIAF, fijación biológica de N
- Capa 3 (Microclima): barreras vivas de maguey y nopal, cortinas rompevientos, frutales
- Capa 4 (Genética adaptada): variedades INIFAP y criollas con tolerancias documentadas
- Capa 5 (Saber temporal): calendario fenológico ligado a indicadores naturales validados

═══════════════════════════════════════════════════════
2. DATOS TÉCNICOS VALIDADOS
═══════════════════════════════════════════════════════

ACOLCHADO ORGÁNICO (rastrojo maíz, paja frijol, paja avena, bagazo maguey):
- Reducción temperatura superficial suelo (paja arroz): -3.5°C (albedo +46%) [Inzunza-Ibarra et al., 2017]
- Monocultivo vs. policultivo milpa (cobertura calabaza): suelo monocultivo +4.4°C más caliente
- Retención humedad policultivo MFC vs monocultivo: +45% (CVA 0.33 vs 0.27 m³/m³)
- Reducción evaporación con acolchado (humedad alta): -67% [Zribi, 2013]
- Reducción evaporación (humedad baja): -35%
- Almacenamiento adicional de agua: +38 a 71 mm [Zhang et al., 2016]
- Materia orgánica MIAF Plan Puebla (6 años, 0-30cm): 0.71% → 1.74% [Juárez-Ramón et al., 2008]

CARBONO ORGÁNICO POR SISTEMA (Castelán-Vega et al., BUAP-ICUAP, Calpan 2023):
- Bosque conservado: 300 Mg C/ha (6.0× vs monocultivo)
- Milpa tradicional: 150 Mg C/ha (3.0×)
- Metepantle (maguey + cultivos): 120 Mg C/ha (2.4×)
- Monocultivo de maíz: 50 Mg C/ha (referencia)

FIJACIÓN BIOLÓGICA DE NITRÓGENO (frijol Phaseolus vulgaris):
- Rango general FBN: 60-120 kg N/ha/ciclo
- Aporte en milpa mesoamericana: ~30-60 kg N/ha
- Proporción N derivado de atmósfera (variedades mejoradas): >50%
- Aumento rendimiento por inoculación nativa: hasta +89%
- Cultivar 'Rocha' Tehuacán: ETc total 217.94 mm, integral térmica 1,322 UC

RAZÓN EQUIVALENTE DE TIERRA (RET/LER) - DATOS CUANTITATIVOS:
- Maíz-Frijol (Piedras Blancas): RET 1.9
- Maíz-Frijol-Calabaza (Piedras Blancas): RET 1.6
- Frijol-Calabaza: RET 1.7
- Milpa clásica MFC (Gliessman): RET 1.73
- Maíz-Calabaza (Frailesca, Chiapas): RET 2.94
- MIAF completo (PV + relevo OI + frutales): RET 1.96 [Turrent, 2014]
- Asociaciones triples con frutales (Calpan y Chiautzingo, Puebla): RET >2.0

SISTEMA MIAF (Milpa Intercalada con Árboles Frutales):
- Erosión bajo manejo convencional: 199 t/ha/año
- Erosión bajo MIAF: 0.40 kg suelo/kg grano (88× menos)
- Reducción escurrimientos MIAF: hasta -46%
- Reducción erosión MIAF: hasta -80%
- Reducción fugas nutrientes vs convencional: N -73.4%, P -49.2%, K -49.3%, Ca -82.4%
- Zona protección eólica barrera viva: 10× la altura aguas abajo, 7× aguas arriba
- Cortina rompeviento completa: hasta 20× la altura aguas abajo
- Rentabilidad MIAF Calpan: maíz 7t/ha + frijol 484kg/ha + calabaza 403kg/ha = \$76,920 MXN/año; B/C = 4.27

BARRERAS VIVAS EN ALTIPLANO POBLANO (1,500-2,200 msnm):
- Maguey mezcalero (Agave salmiana): 1,600-1,800 msnm
- Nopal tunero (Opuntia ficus-indica): 1,500-1,700 msnm
- Tejocote (Crataegus mexicana): 4 variedades en Calpan
- Capulín (Prunus serotina): indicador fenológico y rompeviento
- Durazno criollo (Prunus persica): 2,000-2,200 msnm

═══════════════════════════════════════════════════════
3. PARÁMETROS FENOLÓGICOS POR CULTIVO
═══════════════════════════════════════════════════════

CALABACITA (Cucurbita pepo L.) - variedades Grey Zucchini, Adelita, criollas Calpan:
Fenología:
- Emergencia: 5-9 días
- Floración masculina: 35-39 días (~452 UC, Tbase 10°C)
- Primer corte (Adelita): 49 días (~632 UC)
- Ciclo total: 90-120 días
Umbrales térmicos:
- Mínima letal: <0°C (NO tolera heladas)
- Mínima germinación: 15°C
- Óptima germinación: 21-35°C
- Óptima crecimiento: 18-25°C
- Máxima tolerable: 35°C (>35°C reduce polinización)
- Tbase (cero vegetativo): 10°C
- Óptima suelo: 18-24°C
Requerimientos hídricos:
- Lámina rodado: 520 mm (5-6 riegos cada 12-16 días)
- Lámina goteo: 280 mm
- ETc plena fructificación: 4-6 mm/día
- Kc inicial/media/final: 0.50 / 0.95 / 0.75
- Etapas críticas: establecimiento, floración, llenado de fruto
Siembra: 25,000-28,000 pl/ha; profundidad 1.5-4 cm; surcos 80-100 cm
Puebla: 2° productor nacional (67,839 t, 14.1%); Atlixco líder (12,403 t)

CILANTRO (Coriandrum sativum L.) - variedades Pacífica, Caloro:
Fenología:
- Emergencia: 4-14 días (óptimo 5-8 d a 18-25°C)
- Cosecha follaje: 40-50 días (clima cálido), 60-70 días (Puebla/templado)
- Ciclo total follaje: 40-70 días
Umbrales térmicos:
- Mínima letal: resiste heladas ligeras (~-2°C breves); daño >2h a -4°C
- Mínima germinación: 5-10°C; óptima ≥15°C
- Óptima crecimiento: 18-22°C
- Máxima sin espigado prematuro: 24°C
- Máxima absoluta: 30°C
- Tbase estimada: 4-7°C (GDD específicos para Puebla NO localizados)
Requerimientos hídricos:
- Lámina ideal: 300-400 mm/ciclo
- En Los Reyes de Juárez: 6-11 riegos rodados/ciclo
- ETc: 2-4 mm/día; Kc: 0.7 / 1.05 / 0.95
- Etapa crítica: germinación-establecimiento (días 0-15)
Siembra: 15-25 kg/ha estándar; intensiva hasta 80-100 kg/ha; profundidad 0.6-2 cm
Puebla: 1° productor nacional (54,044 t, 45.9%); Los Reyes de Juárez 2,970 ha
⚠️ Alerta FDA 24-23: bloquea exportación abril-agosto; sequía 2024 redujo -50% producción

FRIJOL PRECOZ (Phaseolus vulgaris L.) - Negro Guanajuato, Primavera-28, Flor de Durazno:
Fenología:
- Emergencia (V1): 5-8 días
- Inicio floración (R6): 30 días (Negro Grijalva) – 53 días (Primavera-28)
- Madurez fisiológica: 70-110 días según variedad
- GDD ciclo completo: 900-1,350 °C·d (Tbase 8.3°C validada México)
Umbrales térmicos:
- Mínima letal: -1 a -2°C daño foliar
- Mínima germinación operativa: 15°C
- Óptima crecimiento: 18-24°C
- Máxima tolerable: 30°C (>35°C aborto floral)
- Tbase: 8.3°C (validado México)
Requerimientos hídricos:
- Lámina aspersión: 298-489 mm; temporal altiplano: 350-400 mm mínimo
- ETc media: 3.5-5.5 mm/día; Kc: 0.40 / 1.15 / 0.35
- Etapas críticas: floración R6 y llenado R7-R8 (déficit <60% ETc impacta rendimiento)
Siembra: 180,000-250,000 pl/ha temporal; profundidad 4-5 cm; surcos 70-80 cm
Variedades INIFAP para Puebla: Negro Guanajuato, Primavera-28, Junio León, Flor de Mayo
Eugenia, Mayomex, Flor de Durazno, Negro Altiplano, Negro Otomí, Negro 8025

RÁBANO (Raphanus sativus L.):
Fenología:
- Emergencia: 3-7 días
- Cosecha rabanito precoz: 20-35 días
- Ciclo total: 20-70 días
Umbrales térmicos:
- Mínima letal: -2°C; tolera fríos ligeros
- Óptima crecimiento: 18-22°C (rango operativo 6-30°C)
- Máxima tolerable: 30°C (raíces picantes y ahuecadas)
- Tbase estimada: ~4°C (GDD específicos NO localizados)
Requerimientos hídricos:
- Lámina: 60-120 mm/ciclo; ETc: 2-3 mm/día; Kc: 0.7 / 0.90 / 0.85
- Frecuencia riego: cada 2-3 días
- Etapa crítica: engrosamiento raíz (15-25 dds) — estrés produce raíces fibrosas y rajadas
Puebla: 1° productor nacional (23,319 t, 55.9%); 1,230 ha en 2024

═══════════════════════════════════════════════════════
4. REGIONES AGROECOLÓGICAS DE PUEBLA
═══════════════════════════════════════════════════════

VALLE DE PUEBLA (Angelópolis):
- Altitud: ~2,150 msnm; Clima: Cw templado subhúmedo
- T media: 16-17°C; Precipitación: 400-900 mm
- Suelos: Luvisol, Vertisol, Phaeozem; pH: 5.8-7.0
- Heladas: 20-60 días/año; Canícula: julio-agosto
- Cultivos clave: cilantro, rábano, calabacita, lechuga, alfalfa
- Riesgo principal: heladas tardías (abril), granizadas (mayo-sep), downbursts
- Presa Valsequillo (405 millones m³) provee al DR-030

CALPAN / FALDAS POPOCATÉPETL:
- Altitud: 2,200-3,200 msnm; Clima: C(w2) + Cb'(w2) semifrío
- T media: 13-14°C; Precipitación: 900-1,100 mm (la más alta)
- Suelos: Arenosol 86%, Andosol; pH: 5.5-6.5 ácido
- Heladas: 40-80 días/año; mínimas hasta -3°C; vientos catabáticos
- Cultivos clave: maíz criollo, calabacita criolla, frijol, frutales nogada
- Riesgo principal: heladas (feb 2026: 430 ha; abr 2025: 181 ha), ceniza volcánica
- Cuna del chile en nogada; 80.3% de la población en pobreza

TEHUACÁN / RESERVA BIOSFERA:
- Altitud: 1,200-2,800 msnm; Clima: semiárido BSohw
- T media: 17-18°C; Precipitación: 250-800 mm (la más baja)
- Suelos: Leptosol 46%, Regosol; pH: 7.0-8.5 alcalino
- Heladas: 5-20 días/año
- Cultivos clave: maíz, agave, pitaya, jitomate riego, amaranto
- Riesgo principal: sequía crónica, sobreexplotación acuífero
- Técnicas: apantles, jagüeyes, lama-bordo, agroforestería cactáceas
- Patrimonio Mundial UNESCO 2018

REGIÓN DE LAS CHOLULAS:
- Altitud: 2,000-2,180 msnm; Clima: C(w2) templado subhúmedo
- T media: 15.7-16.6°C; Precipitación: 800-1,000 mm
- Suelos: Phaeozem dominante; pH: 6.0-7.0
- Heladas: 20-40 días/año
- Cultivos clave: maíz, frijol, hortalizas, ornamentales
- Riesgo principal: urbanización (69.87% territorio ya urbano), heladas, granizadas

═══════════════════════════════════════════════════════
5. SINIESTRALIDAD AGRÍCOLA EN PUEBLA (2015-2026)
═══════════════════════════════════════════════════════

Distribución por causa (2023, 12,857 ha siniestradas):
- Sequía: 47.7% (6,127 ha)
- Granizada: 32.3% (4,159 ha)
- Vientos fuertes: 12.8% (1,640 ha)
- Heladas tardías abril 2025: 1,180-1,700 ha en 32 municipios ("peor en casi 2 décadas")
- Heladas febrero 2026: 430 ha en 5 municipios (Tlahuapan, Chiautzingo, Domingo Arenas,
  Huejotzingo, San Salvador El Verde)

Eventos memorables:
- 2011: 111,810 ha maíz temporal en 57 municipios
- 2021: sequía afectó 74.7% de municipios poblanos
- 2024: sequía+granizo redujo -50% producción cilantro; precio rollo \$130→\$450
- 2024 may: downburst ciudad Puebla, granizo 1m, vientos 80 km/h

VENTANAS DE MAYOR RIESGO:
- Mayo-julio: granizadas y downbursts
- Agosto-septiembre: canícula
- Diciembre-febrero: heladas invernales
- ABRIL: heladas tardías catastróficas (2025)

═══════════════════════════════════════════════════════
6. REGLAS DE RECOMENDACIÓN (DECÁLOGO GREENCODE)
═══════════════════════════════════════════════════════

1. CALABACITA + RIESGO HELADA (Valle de Puebla, Calpan, Cholulas, abril):
   → Acolchado orgánico 10cm rastrojo maíz (-3.5°C amortiguamiento)
   → Siembra escalonada DESPUÉS de floración del durazno (indicador fin heladas)

2. CILANTRO en Los Reyes de Juárez:
   → Variedades Pacífica o Caloro; 6-11 riegos/ciclo; lámina 300-400 mm
   → Alerta sequía extrema: activar acolchado + diversificación con rábano en camas alternas

3. FRIJOL PRECOZ en Valles Altos:
   → Priorizar Primavera-28 (102-105 d, temporal Valles Altos)
   → GDD 900-1,350 °C·d, Tbase 8.3°C; lámina mínima 350-400 mm

4. RÁBANO:
   → Ciclo 20-35 d reduce ventana de exposición a eventos
   → Etapa crítica: engrosamiento (15-25 dds) requiere humedad constante
   → Combinable con cilantro en sucesión

5. TEHUACÁN:
   → Contraindicar cultivos de alta demanda hídrica sin apantles/jagüeyes funcionales
   → Promover variedades criollas adaptadas y agroforestería con cactáceas

6. CALPAN:
   → Milpa serrana + calabaza criolla local + variedades INIFAP frijol + frutales criollos
   → Sistema MIAF (RET 1.96)

7. CHOLULAS:
   → Proteger calpulli y huertos familiares como reservorios fitogenéticos
   → Riesgo de sellado urbano

8. BARRERAS VIVAS en pendiente >10%:
   → Maguey-nopal; zona protección 10× altura aguas abajo
   → Reducción erosión hasta 80% bajo MIAF

9. ALERTAS HISTÓRICAS:
   → Activar alerta en: mayo-julio (granizadas), agosto-sep (canícula),
     diciembre-febrero (heladas), ABRIL (heladas tardías catastróficas)

10. CABAÑUELAS:
    → Valor cultural ÚNICAMENTE; NO ajustar recomendaciones técnicas
    → SÍ usar indicadores fenológicos validados: floración capulín, jacaranda,
      durazno y manzano para determinar fechas de siembra

═══════════════════════════════════════════════════════
7. BRECHAS DE CONOCIMIENTO (NO INVENTAR DATOS)
═══════════════════════════════════════════════════════
- GDD específicos para cilantro y rábano en Puebla: NO localizados
- LER cuantitativo para combinaciones cilantro-rábano: NO existe en literatura peer-review
- Variedades INIFAP para calabacita, cilantro y rábano en Puebla: NO publicadas
- Fijación de N específica por cultivar poblano: NO hay estudios isotópicos publicados
- Topónimo "Alto Balmún": NO verificable (usar "Cuenca del Alto Atoyac")
- Camellones/chinampas en Cholula: evidencia débil; NO documentados strictu sensu

═══════════════════════════════════════════════════════
8. INVESTIGADORES CLAVE
═══════════════════════════════════════════════════════
- Dra. Rosalía Castelán Vega (BUAP-ICUAP): carbono orgánico, degradación suelos, Calpan
- Dr. José Isabel Cortés Flores (COLPOS): co-creador MIAF, fruticultura en laderas
- Dr. Antonio Turrent Fernández (INIFAP-CEVAMEX): co-creador MIAF, milpa, soberanía alimentaria
- Dr. Miguel Ángel Damián Huato (BUAP-ICUAP): seguridad alimentaria, maíz pequeños productores
- Dra. Rocío Albino-Garduño (UIEM/COLPOS): LER/MIAF mexicano 2015-2024
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
        {
          'name': 'get_monthly_risk',
          'description':
              'Obtiene pronóstico climático mensual usando modelo SEAS5 para '
              'los próximos 1 a 6 meses. Úsala cuando el usuario pregunte sobre '
              'riesgo estacional, pronóstico a largo plazo, planificación de '
              'siembra por temporada, o tendencias climáticas futuras.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'lat': {
                'type': 'NUMBER',
                'description': 'Latitud de la parcela. Default: 19.0414',
              },
              'lon': {
                'type': 'NUMBER',
                'description': 'Longitud de la parcela. Default: -98.2063',
              },
              'months_ahead': {
                'type': 'INTEGER',
                'description': 'Cuántos meses hacia adelante pronosticar (1-6). Default: 3',
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

        case 'get_monthly_risk':
          final lat = (args['lat'] as num?)?.toDouble() ?? 19.0414;
          final lon = (args['lon'] as num?)?.toDouble() ?? -98.2063;
          final months = (args['months_ahead'] as num?)?.toInt() ?? 3;
          final result = await ApiService.getMonthlyRisk(lat: lat, lon: lon, monthsAhead: months);
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