import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../api_service.dart';
import '../gemini_service.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map_geojson/flutter_map_geojson.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  // ───── PALETA TLALI · VERDES NATURALES (basada en el logo) ─────
static const Color _kPrimary     = Color(0xFF1FA971); // emerald vibrante
static const Color _kPrimaryMid  = Color(0xFF118A5A); // verde medio profundo
static const Color _kPrimaryDark = Color(0xFF0A5C3D); // verde bosque profundo
static const Color _kPrimarySoft = Color(0xFFA8E6C3); // verde menta claro
static const Color _kAccent      = Color(0xFF4CD295); // acento brillante
static const Color _kPrimaryGhost= Color(0xFFE8F8EF); // tinte muy suave

// ── FONDOS Y SUPERFICIES
static const Color _kBg      = Color(0xFFF5FAF6); // fondo casi blanco con tinte verde
static const Color _kSurface = Color(0xFFFFFFFF);
static const Color _kSidebar = Color(0xFFE6F4EB); // sidebar verde suave
static const Color _kBorder  = Color(0xFFAFDCC0); // borde verde claro
static const Color _kDivider = Color(0xFFCFE7D7);

// ── LETRAS OSCURAS
static const Color _kInk     = Color(0xFF0A2E1F); // texto principal verde casi negro
static const Color _kInkMid  = Color(0xFF1A4D33); // texto medio
static const Color _kInkSoft = Color(0xFF4A7A5E); // texto suave

// ───── COLORES POR CAPA (alto contraste sobre satelital) ─────
static const Color _kColorPuebla     = Color(0xFF6366F1); // índigo — límite estatal
static const Color _kColorAtlixco    = Color(0xFF10D177); // emerald brillante — el valle
static const Color _kColorUsoSuelo   = Color(0xFFF59E0B); // ámbar dorado — cosecha
static const Color _kColorEdafologia = Color(0xFFB85C38); // terracota — el suelo mismo

  // Mapa — Coordenadas del Valle de Atlixco
  final MapController _mapController = MapController();
  final LatLng _initialCenter = const LatLng(18.9075, -98.4373); // Valle de Atlixco
  final double _initialZoom = 11.5;
  double _currentZoom = 11.5;
  bool _mapExpanded = false;

  // Carrusel infinito
  final ScrollController _carouselScrollDesktop = ScrollController();
  final ScrollController _carouselScrollMobile  = ScrollController();
  static const double _cardWidth       = 370.0;
  static const double _cardWidthMobile = 280.0;
  static const double _carouselSpeed   = 40.0;

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
  bool inside = false;
  int j = polygon.length - 1;
  for (int i = 0; i < polygon.length; i++) {
    final xi = polygon[i].longitude, yi = polygon[i].latitude;
    final xj = polygon[j].longitude, yj = polygon[j].latitude;
    final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
    j = i;
  }
  return inside;
}

void _handleMapTap(LatLng tapPoint) {
  // Recorre capas activas en orden inverso (la última pintada está arriba)
  for (final capa in _capas.reversed) {
    if (capa['activa'] != true || capa['loaded'] != true) continue;
    final parser = capa['parser'] as GeoJsonParser;
    for (final polygon in parser.polygons) {
      if (_pointInPolygon(tapPoint, polygon.points)) {
        // Necesitas las properties del feature — ver nota abajo
        _showFeatureInfo(
          {'capa': capa['nombre']}, // placeholder
          capa['nombre'] as String,
          capa['color'] as Color,
        );
        return;
      }
    }
  }
  _closeFeatureInfo();
}

  // Mobile sheets
  bool _mobileLayersOpen = false;
  bool _mobileChatOpen   = false;
  bool _mobileCropsOpen  = false;

  // Desktop: panel de capas flotante sobre el mapa
  bool _desktopLayersFloatOpen = false;

  // Inputs
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  // Feature info (cuando el usuario toca un polígono)
  Map<String, dynamic>? _selectedFeatureProps;
  String? _selectedFeatureLayerName;
  Color _selectedFeatureColor = _kPrimary;

  // ─── Capas
late final List<Map<String, dynamic>> _capas = [
  {
    'nombre': 'Estado de Puebla',
    'subtitulo': 'límite estatal y municipios',
    'color': const Color(0xFF6366F1), // índigo vibrante
    'asset': 'assets/geojson/mapaPuebla.geojson',
    'activa': false,
    'parser': _makeParser(const Color(0xFF6366F1), 'Estado de Puebla'),
    'loaded': false,
  },
  {
    'nombre': 'Valle de Atlixco',
    'subtitulo': 'zona agrícola del valle',
    'color': const Color(0xFF10D177), // emerald brillante
    'asset': 'assets/geojson/ValleAtlixco.geojson',
    'activa': false,
    'parser': _makeParser(const Color(0xFF10D177), 'Valle de Atlixco'),
    'loaded': false,
  },
  {
    'nombre': 'Edafología',
    'subtitulo': 'tipos y perfiles de suelo',
    'color': const Color(0xFFB85C38), // terracota / barro
    'asset': 'assets/geojson/valleAtlixco_edafología.geojson',
    'activa': false,
    'parser': _makeParser(const Color(0xFFB85C38), 'Edafología'),
    'loaded': false,
  },
  {
    'nombre': 'Uso de suelo',
    'subtitulo': 'cobertura y uso del territorio',
    'color': const Color(0xFFF59E0B), // ámbar dorado / cosecha
    'asset': 'assets/geojson/valleAtlixco_usoSuelo.geojson',
    'activa': false,
    'parser': _makeParser(const Color(0xFFF59E0B), 'Uso de suelo'),
    'loaded': false,
  },
];

GeoJsonParser _makeParser(Color color, String layerName) {
  final parser = GeoJsonParser(
    defaultPolygonBorderColor: color,
    defaultPolygonFillColor:   color.withOpacity(0.22),
    defaultPolygonBorderStroke: 2.0,
    defaultPolylineColor: color,
    defaultPolylineStroke: 2.5,
    defaultMarkerColor: color,
  );

    parser.setDefaultMarkerTapCallback((Map<String, dynamic> properties) {
    _showFeatureInfo(properties, layerName, color);
  });

  return parser;
}

  void _showFeatureInfo(Map<String, dynamic> properties, String layerName, Color color) {
    if (!mounted) return;
    setState(() {
      _selectedFeatureProps = properties;
      _selectedFeatureLayerName = layerName;
      _selectedFeatureColor = color;
    });
  }

  void _closeFeatureInfo() {
    setState(() {
      _selectedFeatureProps = null;
      _selectedFeatureLayerName = null;
    });
  }

  // ─── KPIs (carrusel)
List<Map<String, dynamic>> _apis = [
  // ── Temperaturas actuales (rojo cálido)
  {'icono': Icons.thermostat_rounded,     'valor': '--',  'label': 'Temp. mínima hoy',    'tag': 'Cargando', 'color': const Color(0xFFEF4444)},
  {'icono': Icons.thermostat_outlined,    'valor': '--',  'label': 'Temp. mañana',         'tag': 'Cargando', 'color': const Color(0xFFF87171)},
  // ── Suelo (terracota — coincide con capa Edafología)
  {'icono': Icons.water_drop_rounded,     'valor': '--',  'label': 'Temp. suelo',          'tag': 'Cargando', 'color': const Color(0xFFB85C38)},
  // ── Riesgo / alerta (índigo — coincide con capa Puebla)
  {'icono': Icons.warning_amber_rounded,  'valor': '--',  'label': 'Riesgo helada',        'tag': 'Cargando', 'color': const Color(0xFF6366F1)},
  // ── Pronósticos mensuales (gradiente emerald → ámbar, como un calendario que avanza)
  {'icono': Icons.calendar_month_rounded, 'valor': '--',  'label': 'Pronóstico Mayo',      'tag': 'Cargando', 'color': const Color(0xFF10D177)},
  {'icono': Icons.calendar_month_rounded, 'valor': '--',  'label': 'Pronóstico Junio',     'tag': 'Cargando', 'color': const Color(0xFF65C97A)},
  {'icono': Icons.calendar_month_rounded, 'valor': '--',  'label': 'Pronóstico Julio',     'tag': 'Cargando', 'color': const Color(0xFFF59E0B)},
  // ── Anomalía / análisis (ámbar — coincide con capa Uso de suelo)
  {'icono': Icons.show_chart_rounded,     'valor': '--',  'label': 'Anomalía Mayo',        'tag': 'Cargando', 'color': const Color(0xFFD97706)},
];
  int _carouselKey = 0;

  // ─── Distribución de cultivos
  final List<_CropData> _cultivos = const [
    _CropData('Maíz',     320.5, Color(0xFFD4A017)),
    _CropData('Frijol',   180.2, Color(0xFFCC4444)),
    _CropData('Aguacate', 240.7, Color(0xFF2EA855)),
    _CropData('Café',     120.4, Color(0xFF9E6B45)),
    _CropData('Caña',      95.3, Color(0xFF6B55CC)),
    _CropData('Tomate',    65.9, Color(0xFF2E9BAA)),
  ];

  final List<Map<String, dynamic>> _chatMessages = [
    {'from': 'bot', 'text': '👋 ¡Hola! Soy GreenBot.\n¿En qué puedo ayudarte hoy con tu parcela?'},
  ];

  // Historial en formato Gemini para mantener contexto
  final List<Map<String, dynamic>> _geminiHistory = [];
  bool _isBotTyping = false;

  late final TextStyle _displayStyle;
  late final TextStyle _bodyStyle;

  late final AnimationController _carouselCtrl;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeHeader;
  late final Animation<double> _fadeCarousel;
  late final Animation<double> _fadeCrops;
  late final Animation<double> _fadeMap;
  late final Animation<double> _fadeChat;
  late final Animation<double> _fadeSidebar;

  @override
  void initState() {
    super.initState();
    _loadClimateData();

    _displayStyle = GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, letterSpacing: -0.8);
    _bodyStyle    = GoogleFonts.inter();

    _carouselCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _carouselCtrl.addListener(_onCarouselTick);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeSidebar  = _stagger(0.00, 0.45);
    _fadeHeader   = _stagger(0.05, 0.50);
    _fadeCarousel = _stagger(0.15, 0.65);
    _fadeCrops    = _stagger(0.25, 0.75);
    _fadeMap      = _stagger(0.35, 0.85);
    _fadeChat     = _stagger(0.45, 1.00);

    WidgetsBinding.instance.addPostFrameCallback((_) => _fadeCtrl.forward());
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _fadeCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _ensureCapaLoaded(int index) async {
    final capa = _capas[index];
    if (capa['loaded'] == true) return;
    try {
      final data = await rootBundle.loadString(capa['asset'] as String);
      (capa['parser'] as GeoJsonParser).parseGeoJsonAsString(data);
      capa['loaded'] = true;
    } catch (e) {
      debugPrint('❌ Error cargando ${capa['asset']}: $e');
    }
  }

  Future<void> _toggleCapa(int index) async {
    final capa = _capas[index];
    final nuevaActiva = !(capa['activa'] as bool);
    if (nuevaActiva && !(capa['loaded'] as bool)) {
      await _ensureCapaLoaded(index);
    }
    if (!mounted) return;
    setState(() => _capas[index]['activa'] = nuevaActiva);
  }

  void _onCarouselTick() {
    final secs = (_carouselCtrl.lastElapsedDuration ?? Duration.zero).inMicroseconds / 1e6;
    _scrollTo(_carouselScrollDesktop, secs, _cardWidth);
    _scrollTo(_carouselScrollMobile,  secs, _cardWidthMobile);
  }

  void _scrollTo(ScrollController sc, double totalSecs, double cardW) {
    if (!sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    if (max <= 0) return;
    final pos = (_carouselSpeed * totalSecs) % (max + cardW);
    sc.jumpTo(pos.clamp(0.0, max));
  }

  void _recenterMap() {
    _mapController.move(_initialCenter, _initialZoom);
    setState(() => _currentZoom = _initialZoom);
  }

  Future<void> _loadClimateData() async {
    try {
      debugPrint('🌡️ Cargando datos del backend...');

      // Llama a ambos endpoints en paralelo
      final results = await Future.wait([
        ApiService.getFrostCheck(lat: _initialCenter.latitude, lon: _initialCenter.longitude),
        ApiService.getMonthlyRisk(lat: _initialCenter.latitude, lon: _initialCenter.longitude, monthsAhead: 3),
      ]);

      final frost   = results[0];
      final monthly = results[1];
      debugPrint('✅ frost-check: $frost');
      debugPrint('✅ monthly-risk: $monthly');

      // ── Datos de frost-check ──────────────────────────
      final todayMin    = frost['air_temperature']['today_min_celsius'];
      final tomorrowMin = frost['air_temperature']['tomorrow_min_celsius'];
      final soilTemp    = frost['soil_temperature']['lst_celsius'];
      final frostRisk   = frost['frost_risk'] as String? ?? '';
      final geeError    = frost['metadata']['gee_error'];

      final riskLabel = frostRisk == 'LOW'    ? 'Sin riesgo'
                      : frostRisk == 'MEDIUM' ? '⚠️ Precaución'
                      : frostRisk == 'HIGH'   ? '🚨 Alto'
                      : 'N/D';
      final riskColor = frostRisk == 'LOW'    ? const Color(0xFF2EA855)
                      : frostRisk == 'MEDIUM' ? const Color(0xFFCC9500)
                      : const Color(0xFFCC4444);

      // ── Datos de monthly-risk ─────────────────────────
      final forecasts = monthly['forecasts'] as List? ?? [];
      final f0 = forecasts.isNotEmpty ? forecasts[0] : null;
      final f1 = forecasts.length > 1 ? forecasts[1] : null;
      final f2 = forecasts.length > 2 ? forecasts[2] : null;

      String _frostTag(String? risk) =>
          risk == 'LOW' ? 'Sin riesgo' : risk == 'MEDIUM' ? '⚠️ Precaución' : risk == 'HIGH' ? '🚨 Alto' : 'N/D';

      setState(() {
        // Card 0 — Temp mínima hoy
        _apis[0] = Map.from(_apis[0])
          ..['valor'] = todayMin != null ? '$todayMin°C' : '--'
          ..['tag']   = riskLabel
          ..['color'] = const Color(0xFFE07A3A);

        // Card 1 — Temp mínima mañana
        _apis[1] = Map.from(_apis[1])
          ..['valor'] = tomorrowMin != null ? '$tomorrowMin°C' : '--'
          ..['tag']   = riskLabel;

        // Card 2 — Temp suelo
        _apis[2] = Map.from(_apis[2])
          ..['valor'] = soilTemp != null ? '$soilTemp°C' : (geeError != null ? 'N/D' : '--')
          ..['tag']   = soilTemp != null ? 'GEE/ERA5' : 'No disponible';

        // Card 3 — Riesgo helada
        _apis[3] = Map.from(_apis[3])
          ..['valor'] = frostRisk.isNotEmpty ? frostRisk : '--'
          ..['tag']   = riskLabel
          ..['color'] = riskColor;

        // Card 4 — Pronóstico mes 1
        if (f0 != null) {
          _apis[4] = Map.from(_apis[4])
            ..['valor'] = '${f0['temp_min_forecast_celsius']}°C'
            ..['label'] = f0['month_label'] ?? 'Mes 1'
            ..['tag']   = _frostTag(f0['frost_risk']);
        }

        // Card 5 — Pronóstico mes 2
        if (f1 != null) {
          _apis[5] = Map.from(_apis[5])
            ..['valor'] = '${f1['temp_min_forecast_celsius']}°C'
            ..['label'] = f1['month_label'] ?? 'Mes 2'
            ..['tag']   = _frostTag(f1['frost_risk']);
        }

        // Card 6 — Pronóstico mes 3
        if (f2 != null) {
          _apis[6] = Map.from(_apis[6])
            ..['valor'] = '${f2['temp_min_forecast_celsius']}°C'
            ..['label'] = f2['month_label'] ?? 'Mes 3'
            ..['tag']   = _frostTag(f2['frost_risk']);
        }

        // Card 7 — Anomalía mes 1
        if (f0 != null) {
          final anomaly = f0['temp_anomaly_celsius'] as num?;
          final sign    = anomaly != null && anomaly >= 0 ? '+' : '';
          _apis[7] = Map.from(_apis[7])
            ..['valor'] = anomaly != null ? '$sign${anomaly}°C' : '--'
            ..['label'] = 'Anomalía ${f0['month_label'] ?? ''}'
            ..['tag']   = anomaly != null && anomaly.abs() < 0.5 ? 'Normal'
                        : anomaly != null && anomaly > 0 ? 'Más cálido'
                        : 'Más frío';
        }

        _carouselKey++;
      });

      debugPrint('🔄 Carrusel actualizado con ${_apis.length} cards');
    } catch (e) {
      debugPrint('❌ Error cargando clima: $e');
    }
  }

  @override
  void dispose() {
    _carouselCtrl.removeListener(_onCarouselTick);
    _carouselCtrl.dispose();
    _fadeCtrl.dispose();
    _carouselScrollDesktop.dispose();
    _carouselScrollMobile.dispose();
    _chatController.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isBotTyping) return;

    // 1. Muestra el mensaje del usuario inmediatamente
    setState(() {
      _chatMessages.add({'from': 'user', 'text': text});
      _isBotTyping = true;
      _chatController.clear();
    });

    // 2. Agrega al historial de Gemini
    _geminiHistory.add({'role': 'user', 'text': text});

    try {
      // 3. Llama a Gemini (con function calling automático al backend)
      final botReply = await GeminiService.sendMessage(
        userMessage: text,
        history: _geminiHistory.length > 1
            ? _geminiHistory.sublist(0, _geminiHistory.length - 1)
            : [],
      );

      // 4. Guarda la respuesta en el historial
      _geminiHistory.add({'role': 'model', 'text': botReply});

      if (!mounted) return;
      setState(() {
        _chatMessages.add({'from': 'bot', 'text': botReply});
        _isBotTyping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add({
          'from': 'bot',
          'text': '⚠️ Error al conectar con GreenBot. Verifica tu conexión e intenta de nuevo.',
        });
        _isBotTyping = false;
      });
    }
  }

  Widget _fadeIn(Animation<double> anim, Widget child, {double dy = 12}) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * dy),
          child: child,
        ),
      ),
    );
  }

  // Logo widget reusable
  Widget _logoWidget({double size = 44, double radius = 12}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withOpacity(0.40),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.08),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Image.asset(
          'assets/logoTlali.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: false,
      floatingActionButton: LayoutBuilder(
        builder: (context, _) {
          final isMobile = MediaQuery.of(context).size.width < 720;
          if (!isMobile) return const SizedBox.shrink();
          return _ChatFab(
            primary: _kPrimary,
            primaryDark: _kPrimaryDark,
            onTap: () => setState(() => _mobileChatOpen = true),
          );
        },
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 720;
            return Stack(
              children: [
                if (isMobile) _buildMobileLayout(context) else _buildDesktopLayout(),
                if (isMobile) ...[
                  if (_mobileLayersOpen)
                    _MobileSheet(
                      onClose: () => setState(() => _mobileLayersOpen = false),
                      title: 'Bases de datos',
                      child: _buildLayersList(compact: true),
                    ),
                  if (_mobileChatOpen)
                    _MobileSheet(
                      onClose: () => setState(() => _mobileChatOpen = false),
                      title: 'GreenBot',
                      fullHeight: true,
                      child: _buildChatBody(),
                    ),
                  if (_mobileCropsOpen)
                    _MobileSheet(
                      onClose: () => setState(() => _mobileCropsOpen = false),
                      title: 'Distribución de cultivos',
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: _CropsCard(
                          cultivos: _cultivos,
                          bodyStyle: _bodyStyle,
                          displayStyle: _displayStyle,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // DESKTOP LAYOUT
  // ─────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Sidebar
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
          width: _mapExpanded ? 0 : 300,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: 300,
              minWidth: 300,
              child: _fadeIn(_fadeSidebar, _buildSidebar(), dy: 0),
            ),
          ),
        ),
        // ── Contenido principal
        Expanded(
          child: Column(
            children: [
              // Header + carrusel (se ocultan al expandir mapa)
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                child: _mapExpanded
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _fadeIn(_fadeHeader, _buildTopHeader()),
                          const SizedBox(height: 4),
                          _fadeIn(
                            _fadeCarousel,
                            _buildInfiniteCarousel(
                              scrollController: _carouselScrollDesktop,
                              leftPad: 24,
                              height: 168,
                              cardWidth: _cardWidth,
                            ),
                          ),
                        ],
                      ),
              ),

              // ── Fila inferior: [Mapa + Cultivos (col izq)] [Chat (col der)]
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _mapExpanded ? 16 : 24,
                    _mapExpanded ? 16 : 10,
                    _mapExpanded ? 16 : 24,
                    _mapExpanded ? 16 : 24,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Columna izquierda: Mapa + Card Cultivos
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Mapa ocupa el espacio disponible
                            Expanded(
                              child: _fadeIn(_fadeMap, _buildMapCard()),
                            ),
                            // Card de cultivos debajo del mapa (sólo desktop)
                            if (!_mapExpanded) ...[
                              const SizedBox(height: 14),
                              _fadeIn(
                                _fadeCrops,
                                _CropsCard(
                                  cultivos: _cultivos,
                                  bodyStyle: _bodyStyle,
                                  displayStyle: _displayStyle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Separador
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        width: _mapExpanded ? 0 : 20,
                      ),

                      // ── Columna derecha: Chat
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        width: _mapExpanded ? 0 : 420,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerRight,
                            maxWidth: 420,
                            minWidth: 420,
                            child: _fadeIn(_fadeChat, _buildChatPanel()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────
  // MOBILE LAYOUT
  // ─────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SingleChildScrollView(
      child: Column(
        children: [
          _fadeIn(
            _fadeHeader,
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  _logoWidget(size: 44, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tlali',
                      style: _displayStyle.copyWith(fontSize: 30, color: _kInk),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kPrimaryGhost,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _kBorder, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_rounded, color: _kPrimaryDark, size: 16),
                        const SizedBox(width: 5),
                        Text(
                          'Atlixco',
                          style: _bodyStyle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          _fadeIn(
            _fadeCarousel,
            _buildInfiniteCarousel(
              scrollController: _carouselScrollMobile,
              leftPad: 16,
              height: 134,
              cardWidth: _cardWidthMobile,
            ),
          ),

          // En móvil NO mostramos el card de cultivos aquí (sólo el mapa con FABs)
          SizedBox(
            height: math.max(
              520,
              size.height - 280,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: _fadeIn(
                _fadeMap,
                Stack(
                  children: [
                    _buildMapCard(),

                    // ─── FAB de cultivos: arriba-izquierda (círculo)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: _CropsFab(
                        primary: _kPrimary,
                        primaryDark: _kPrimaryDark,
                        accent: _kAccent,
                        onTap: () => setState(() => _mobileCropsOpen = true),
                      ),
                    ),

                    // ─── FAB de capas: abajo-izquierda
                    Positioned(
                      bottom: 14,
                      left: 14,
                      child: _LayersFab(
                        primary: _kPrimary,
                        primaryDark: _kPrimaryDark,
                        accent: _kAccent,
                        activeCount: _capas.where((c) => c['activa'] == true).length,
                        onTap: () => setState(() => _mobileLayersOpen = true),
                      ),
                    ),

                    // ─── Botón recentrar: abajo-derecha
                    Positioned(
                      bottom: 14,
                      right: 14,
                      child: _RecenterFab(
                        primary: _kPrimary,
                        primaryDark: _kPrimaryDark,
                        accent: _kAccent,
                        onTap: _recenterMap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // SIDEBAR
  // ─────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: _kSidebar,
        border: Border(right: BorderSide(color: _kBorder, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kDivider, width: 0.8)),
            ),
            child: Row(
              children: [
                _logoWidget(size: 46, radius: 12),
                const SizedBox(width: 12),
                Text(
                  'Tlali',
                  style: _displayStyle.copyWith(
                    fontSize: 30,
                    color: _kInk,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          // Título sección
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_kPrimarySoft, _kPrimary, _kPrimaryDark],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'BASES DE DATOS',
                  style: _bodyStyle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),

          Expanded(child: _buildLayersList()),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kDivider, width: 0.8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: _kInkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toca un área del mapa para ver detalles',
                    style: _bodyStyle.copyWith(fontSize: 15, color: _kInkMid, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayersList({bool compact = false}) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 12, vertical: compact ? 8 : 4),
      itemCount: _capas.length,
      itemBuilder: (context, i) {
        final capa = _capas[i];
        final activa = capa['activa'] as bool;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 320 + (i * 60)),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _toggleCapa(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: activa ? _kSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: activa ? _kBorder : Colors.transparent,
                    width: 0.8,
                  ),
                  boxShadow: activa
                      ? [BoxShadow(color: _kAccent.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: activa
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  capa['color'],
                                  Color.lerp(capa['color'], Colors.black, 0.3)!,
                                ],
                              )
                            : null,
                        color: activa ? null : _kBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: activa ? Colors.transparent : _kBorder,
                          width: 1.5,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: activa
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18, key: ValueKey(true))
                            : const SizedBox.shrink(key: ValueKey(false)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            capa['nombre'],
                            style: _bodyStyle.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _kInk,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            capa['subtitulo'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _bodyStyle.copyWith(
                              fontSize: 15,
                              color: _kInkMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: activa ? 1.0 : 0.0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: capa['color'],
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (capa['color'] as Color).withOpacity(0.7),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────
  Widget _buildTopHeader() {
    final now = DateTime.now();
    const dias  = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    const meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
    final fechaStr = '${now.day} de ${meses[now.month - 1]}, ${now.year}';
    final diaStr   = dias[now.weekday - 1];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bienvenido de vuelta',
              style: _displayStyle.copyWith(fontSize: 40, color: _kInk),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _kPrimaryGhost,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(diaStr, style: _bodyStyle.copyWith(fontSize: 17, color: _kInk, fontWeight: FontWeight.w700)),
                Container(width: 1, height: 16, color: _kBorder, margin: const EdgeInsets.symmetric(horizontal: 10)),
                Text(fechaStr, style: _bodyStyle.copyWith(fontSize: 17, color: _kInkMid)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: _kPrimaryGhost,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kBorder, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_rounded, color: _kPrimaryDark, size: 17),
                const SizedBox(width: 6),
                Text(
                  'Valle de Atlixco, Puebla',
                  style: _bodyStyle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // CARRUSEL INFINITO
  // ─────────────────────────────────────────────────
  Widget _buildInfiniteCarousel({
    required ScrollController scrollController,
    required double leftPad,
    required double height,
    required double cardWidth,
  }) {
    const repeats = 50;
    final totalItems = _apis.length * repeats;

    return SizedBox(
      height: height,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ListView.builder(
          key: ValueKey(_carouselKey),
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.only(left: leftPad, right: 8),
          itemCount: totalItems,
          itemExtent: cardWidth,
          itemBuilder: (context, i) {
            final api = _apis[i % _apis.length];
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 12),
              child: _ApiCard(
                icon:         api['icono'],
                valor:        api['valor'],
                label:        api['label'],
                tag:          api['tag'],
                accent:       api['color'],
                bodyStyle:    _bodyStyle,
                displayStyle: _displayStyle,
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // MAPA
  // ─────────────────────────────────────────────────
  List<Widget> _buildActiveLayers() {
    final widgets = <Widget>[];
    for (final capa in _capas) {
      final activa = capa['activa'] as bool;
      final loaded = capa['loaded'] as bool;
      if (!activa || !loaded) continue;
      final parser = capa['parser'] as GeoJsonParser;
      widgets.add(PolygonLayer(polygons: parser.polygons));
      widgets.add(PolylineLayer(polylines: parser.polylines));
      widgets.add(MarkerLayer(markers: parser.markers));
    }
    return widgets;
  }

  Widget _buildMapCard() {
    final isMobile = MediaQuery.of(context).size.width < 720;
    final activeLayersCount = _capas.where((c) => c['activa'] == true).length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kBorder, width: 0.9),
          boxShadow: [
            BoxShadow(color: _kAccent.withOpacity(0.18), blurRadius: 32, offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _currentZoom,
                minZoom: 4.0,
                maxZoom: 18.0,
                onTap: (tapPosition, latLng) => _handleMapTap(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.tlaliapp',
                  maxZoom: 19,
                ),
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.tlaliapp',
                  maxZoom: 19,
                ),
                ..._buildActiveLayers(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _initialCenter,
                      width: 50,
                      height: 50,
                      child: const _PulsingMarker(color: _kPrimary),
                    ),
                  ],
                ),
              ],
            ),

            // Zoom +/-
            Positioned(
              top: 16,
              left: 16,
              child: _GlassControlStack(
                children: [
                  _GlassIconButton(
                    icon: Icons.add_rounded,
                    standalone: false,
                    onTap: () {
                      setState(() => _currentZoom++);
                      _mapController.move(_mapController.camera.center, _currentZoom);
                    },
                  ),
                  Container(height: 0.5, color: Colors.black.withOpacity(0.12)),
                  _GlassIconButton(
                    icon: Icons.remove_rounded,
                    standalone: false,
                    onTap: () {
                      setState(() => _currentZoom--);
                      _mapController.move(_mapController.camera.center, _currentZoom);
                    },
                  ),
                ],
              ),
            ),

            // Botón fullscreen + capas (sólo desktop) + recentrar — esquina superior derecha
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  if (!isMobile) ...[
                    // Botón de capas dentro del mapa (desktop)
                    _GlassIconButtonWithBadge(
                      icon: Icons.layers_rounded,
                      badgeCount: activeLayersCount,
                      onTap: () => setState(() => _desktopLayersFloatOpen = !_desktopLayersFloatOpen),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Botón recentrar (desktop, dentro del map header)
                  if (!isMobile) ...[
                    _GlassIconButton(
                      icon: Icons.my_location_rounded,
                      size: 38,
                      onTap: _recenterMap,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _GlassIconButton(
                    icon: _mapExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    size: 38,
                    onTap: () => setState(() => _mapExpanded = !_mapExpanded),
                  ),
                ],
              ),
            ),

            // Panel flotante de capas (desktop, sobre el mapa)
            if (!isMobile && _desktopLayersFloatOpen)
              Positioned(
                top: 64,
                right: 16,
                child: _DesktopLayersFloatPanel(
                  child: SizedBox(
                    width: 280,
                    height: 360,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                          child: Row(
                            children: [
                              Text(
                                'Capas',
                                style: _displayStyle.copyWith(
                                  fontSize: 20,
                                  color: _kInk,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _desktopLayersFloatOpen = false),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: _kPrimaryGhost,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 18, color: _kInk),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 0.6, color: _kBorder),
                        Expanded(child: _buildLayersList(compact: true)),
                      ],
                    ),
                  ),
                ),
              ),

            // Panel flotante con info de feature seleccionado
            if (_selectedFeatureProps != null)
              Positioned(
                left: isMobile ? 14 : 16,
                bottom: isMobile ? 80 : 16,
                right: isMobile ? 14 : null,
                child: _FeatureInfoPanel(
                  properties: _selectedFeatureProps!,
                  layerName: _selectedFeatureLayerName ?? 'Información',
                  color: _selectedFeatureColor,
                  bodyStyle: _bodyStyle,
                  displayStyle: _displayStyle,
                  onClose: _closeFeatureInfo,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // CHAT
  // ─────────────────────────────────────────────────
  Widget _buildChatPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder, width: 0.9),
        boxShadow: [
          BoxShadow(color: _kAccent.withOpacity(0.16), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _buildChatBody(),
      ),
    );
  }

  Widget _buildChatBody() {
    return Column(
      children: [
        // Header del chat
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
          decoration: BoxDecoration(
            color: _kPrimary,
            border: const Border(bottom: BorderSide(color: _kBorder, width: 0.8)),
          ),
          child: Row(
            children: [
              _BotAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GreenBot',
                      style: _displayStyle.copyWith(color: Colors.white, fontSize: 22, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const _OnlineDot(),
                        const SizedBox(width: 7),
                        Text(
                          'Asistente agrícola',
                          style: _bodyStyle.copyWith(color: Colors.white.withOpacity(0.90), fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Mensajes
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length + (_isBotTyping ? 1 : 0),
            itemBuilder: (context, i) {
              // Indicador "escribiendo..." al final
              if (_isBotTyping && i == _chatMessages.length) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: _kPrimaryGhost,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                        bottomLeft: Radius.circular(4),
                      ),
                      border: Border.all(color: _kBorder, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulseDot(color: _kPrimaryDark),
                        SizedBox(width: 6),
                        _PulseDot(color: _kPrimary),
                        SizedBox(width: 6),
                        _PulseDot(color: _kPrimaryDark),
                      ],
                    ),
                  ),
                );
              }
              final msg    = _chatMessages[i];
              final isUser = msg['from'] == 'user';
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(isUser ? (1 - t) * 14 : -(1 - t) * 14, 0),
                    child: child,
                  ),
                ),
                child: Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isUser ? _kPrimary : _kPrimaryGhost,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(16),
                        topRight:    const Radius.circular(16),
                        bottomLeft:  Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      border: isUser ? null : Border.all(color: _kBorder, width: 0.8),
                      boxShadow: isUser
                          ? [BoxShadow(color: _kAccent.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))]
                          : null,
                    ),
                    child: Text(
                      msg['text']!,
                      style: _bodyStyle.copyWith(
                        fontSize: 17,
                        height: 1.45,
                        color: isUser ? Colors.white : _kInk,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _kBorder, width: 0.8)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _chatFocus.hasFocus ? _kPrimary : _kBorder,
                      width: _chatFocus.hasFocus ? 1.5 : 0.8,
                    ),
                    boxShadow: _chatFocus.hasFocus
                        ? [BoxShadow(color: _kAccent.withOpacity(0.20), blurRadius: 10, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: TextField(
                    controller: _chatController,
                    focusNode: _chatFocus,
                    onTap: () => setState(() {}),
                    onSubmitted: (_) => _sendMessage(),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    style: _bodyStyle.copyWith(fontSize: 18, color: _kInk, letterSpacing: -0.2),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      hintText: 'Escribe tu pregunta...',
                      hintStyle: _bodyStyle.copyWith(fontSize: 18, color: _kInkSoft, letterSpacing: -0.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SendButton(onTap: _sendMessage, primary: _kPrimary, primaryDark: _kPrimaryDark, accent: _kAccent),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// PANEL DE INFORMACIÓN DE FEATURE (al tocar un polígono)
// ═══════════════════════════════════════════════════

class _FeatureInfoPanel extends StatefulWidget {
  final Map<String, dynamic> properties;
  final String layerName;
  final Color color;
  final TextStyle bodyStyle;
  final TextStyle displayStyle;
  final VoidCallback onClose;

  const _FeatureInfoPanel({
    required this.properties,
    required this.layerName,
    required this.color,
    required this.bodyStyle,
    required this.displayStyle,
    required this.onClose,
  });

  @override
  State<_FeatureInfoPanel> createState() => _FeatureInfoPanelState();
}

class _FeatureInfoPanelState extends State<_FeatureInfoPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _formatKey(String key) {
    // Convierte "tipo_suelo" → "Tipo suelo"; "NOMBRE" → "Nombre"
    final spaced = key.replaceAll('_', ' ').replaceAll('-', ' ');
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  String _formatValue(dynamic value) {
    if (value == null) return '—';
    if (value is num) {
      if (value % 1 == 0) return value.toInt().toString();
      return value.toStringAsFixed(2);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Filtra props vacías o nulas
    final entries = widget.properties.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .toList();

    final isMobile = MediaQuery.of(context).size.width < 720;
    final maxWidth = isMobile ? double.infinity : 360.0;
    final maxHeight = isMobile ? 280.0 : 380.0;

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: widget.color.withOpacity(0.4), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withOpacity(0.22),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                widget.color.withOpacity(0.15),
                                widget.color.withOpacity(0.05),
                              ],
                            ),
                            border: Border(
                              bottom: BorderSide(color: widget.color.withOpacity(0.3), width: 0.8),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.color,
                                      Color.lerp(widget.color, Colors.black, 0.3)!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.color.withOpacity(0.45),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.info_rounded, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.layerName,
                                      style: widget.displayStyle.copyWith(
                                        fontSize: 17,
                                        color: const Color(0xFF0F2D1A),
                                        letterSpacing: -0.3,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${entries.length} ${entries.length == 1 ? "atributo" : "atributos"}',
                                      style: widget.bodyStyle.copyWith(
                                        fontSize: 13,
                                        color: const Color(0xFF3D7A55),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: widget.onClose,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: widget.color.withOpacity(0.3), width: 0.8),
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF0F2D1A)),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Lista de propiedades
                        Flexible(
                          child: entries.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'Esta área no tiene atributos asociados.',
                                    style: widget.bodyStyle.copyWith(
                                      fontSize: 14,
                                      color: const Color(0xFF3D7A55),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 14,
                                    thickness: 0.6,
                                    color: const Color(0xFFB5DCC2).withOpacity(0.6),
                                  ),
                                  itemBuilder: (context, i) {
                                    final e = entries[i];
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            _formatKey(e.key),
                                            style: widget.bodyStyle.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1F4F33),
                                              letterSpacing: -0.1,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _formatValue(e.value),
                                            style: widget.bodyStyle.copyWith(
                                              fontSize: 14,
                                              color: const Color(0xFF0F2D1A),
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: -0.1,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// PANEL FLOTANTE DE CAPAS (DESKTOP, sobre el mapa)
// ═══════════════════════════════════════════════════

class _DesktopLayersFloatPanel extends StatefulWidget {
  final Widget child;
  const _DesktopLayersFloatPanel({required this.child});

  @override
  State<_DesktopLayersFloatPanel> createState() => _DesktopLayersFloatPanelState();
}

class _DesktopLayersFloatPanelState extends State<_DesktopLayersFloatPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: Transform.scale(
              scale: 0.96 + 0.04 * t,
              alignment: Alignment.topRight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB5DCC2), width: 0.9),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7BC99A).withOpacity(0.30),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// CULTIVOS — Card con donut chart + leyenda
// ═══════════════════════════════════════════════════

class _CropData {
  final String name;
  final double hectareas;
  final Color color;
  const _CropData(this.name, this.hectareas, this.color);
}

class _CropsCard extends StatelessWidget {
  final List<_CropData> cultivos;
  final TextStyle bodyStyle;
  final TextStyle displayStyle;

  const _CropsCard({
    required this.cultivos,
    required this.bodyStyle,
    required this.displayStyle,
  });

  @override
  Widget build(BuildContext context) {
    final total = cultivos.fold<double>(0, (sum, c) => sum + c.hectareas);
    final isMobile = MediaQuery.of(context).size.width < 720;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 18 : 24,
        isMobile ? 18 : 20,
        isMobile ? 18 : 24,
        isMobile ? 18 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB5DCC2), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7BC99A).withOpacity(0.20),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFB8E5C9), Color(0xFF4CAF7A), Color(0xFF1E6B45)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Distribución de cultivos',
                  style: displayStyle.copyWith(
                    fontSize: isMobile ? 22 : 26,
                    color: const Color(0xFF0F2D1A),
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (!isMobile)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF8F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB5DCC2), width: 0.8),
                  ),
                  child: Text(
                    '${cultivos.length} cultivos',
                    style: bodyStyle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F4F33),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? 140 : 170,
                height: isMobile ? 140 : 170,
                child: _DonutChart(
                  data: cultivos,
                  total: total,
                  bodyStyle: bodyStyle,
                  displayStyle: displayStyle,
                  centerSize: isMobile ? 28 : 34,
                  labelSize:  isMobile ? 15 : 16,
                ),
              ),
              SizedBox(width: isMobile ? 16 : 22),
              Expanded(
                child: _CropsLegend(
                  cultivos: cultivos,
                  total: total,
                  bodyStyle: bodyStyle,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CropsLegend extends StatelessWidget {
  final List<_CropData> cultivos;
  final double total;
  final TextStyle bodyStyle;
  final bool isMobile;

  const _CropsLegend({
    required this.cultivos,
    required this.total,
    required this.bodyStyle,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final cols = isMobile ? 1 : 2;
    final rows = (cultivos.length / cols).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (r) {
        return Padding(
          padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : (isMobile ? 10 : 12)),
          child: Row(
            children: List.generate(cols, (c) {
              final idx = r * cols + c;
              if (idx >= cultivos.length) return const Expanded(child: SizedBox());
              final cultivo = cultivos[idx];
              final pct = (cultivo.hectareas / total * 100).toStringAsFixed(1);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: c == cols - 1 ? 0 : 14),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: cultivo.color,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: cultivo.color.withOpacity(0.5), blurRadius: 5),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cultivo.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle.copyWith(
                                fontSize: isMobile ? 18 : 19,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F2D1A),
                                letterSpacing: -0.2,
                                height: 1.2,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '$pct%',
                                  style: bodyStyle.copyWith(
                                    fontSize: isMobile ? 15 : 16,
                                    fontWeight: FontWeight.w700,
                                    color: cultivo.color,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                Text(
                                  '  ${cultivo.hectareas.toStringAsFixed(1)} ha',
                                  style: bodyStyle.copyWith(
                                    fontSize: isMobile ? 15 : 16,
                                    color: const Color(0xFF3D7A55),
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _DonutChart extends StatefulWidget {
  final List<_CropData> data;
  final double total;
  final TextStyle bodyStyle;
  final TextStyle displayStyle;
  final double centerSize;
  final double labelSize;

  const _DonutChart({
    required this.data,
    required this.total,
    required this.bodyStyle,
    required this.displayStyle,
    required this.centerSize,
    required this.labelSize,
  });

  @override
  State<_DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<_DonutChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final progress = Curves.easeOutCubic.transform(_c.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _DonutPainter(
                data: widget.data,
                total: widget.total,
                progress: progress,
              ),
            ),
            Opacity(
              opacity: progress,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.total.toStringAsFixed(0),
                    style: widget.displayStyle.copyWith(
                      fontSize: widget.centerSize,
                      color: const Color(0xFF0F2D1A),
                      letterSpacing: -0.6,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'hectáreas',
                    style: widget.bodyStyle.copyWith(
                      fontSize: widget.labelSize,
                      color: const Color(0xFF3D7A55),
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_CropData> data;
  final double total;
  final double progress;

  _DonutPainter({required this.data, required this.total, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.30;
    final r = radius - stroke / 2;

    final track = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, r, track);

    double startAngle = -math.pi / 2;
    const gap = 0.025;

    for (final c in data) {
      final fullSweep = (c.hectareas / total) * (2 * math.pi) - gap;
      final sweep = fullSweep * progress;
      if (sweep > 0) {
        final paint = Paint()
          ..color = c.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          startAngle,
          sweep,
          false,
          paint,
        );
      }
      startAngle += fullSweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.data != data || old.total != total;
}

// ═══════════════════════════════════════════════════
// COMPONENTES
// ═══════════════════════════════════════════════════

class _ApiCard extends StatefulWidget {
  final IconData icon;
  final String valor;
  final String label;
  final String tag;
  final Color accent;
  final TextStyle bodyStyle;
  final TextStyle displayStyle;

  const _ApiCard({
    required this.icon,
    required this.valor,
    required this.label,
    required this.tag,
    required this.accent,
    required this.bodyStyle,
    required this.displayStyle,
  });

  @override
  State<_ApiCard> createState() => _ApiCardState();
}

class _ApiCardState extends State<_ApiCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(opacity: t, child: child);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.accent.withOpacity(0.30), width: 1.1),
          boxShadow: [
            BoxShadow(color: widget.accent.withOpacity(0.14), blurRadius: 16, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accent.withOpacity(0.35), width: 1.0),
              ),
              child: Icon(widget.icon, color: widget.accent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.displayStyle.copyWith(
                      fontSize: 28,
                      color: const Color(0xFF0F2D1A),
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.bodyStyle.copyWith(
                      fontSize: 16,
                      color: const Color(0xFF3D7A55),
                      letterSpacing: -0.1,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: widget.accent.withOpacity(0.35), width: 0.7),
                    ),
                    child: Text(
                      widget.tag,
                      style: widget.bodyStyle.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color.lerp(widget.accent, Colors.black, 0.40),
                        letterSpacing: -0.1,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassControlStack extends StatelessWidget {
  final List<Widget> children;
  const _GlassControlStack({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7BC99A).withOpacity(0.45), width: 0.9),
            boxShadow: [
              BoxShadow(color: const Color(0xFF7BC99A).withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool standalone;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.standalone = true,
  });

  @override
  State<_GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<_GlassIconButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final core = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel:   () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : (_hovered ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _hovered ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 180),
            child: Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              color: Colors.transparent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                transitionBuilder: (c, a) => RotationTransition(
                  turns: Tween(begin: 0.85, end: 1.0).animate(a),
                  child: ScaleTransition(scale: a, child: c),
                ),
                child: Icon(
                  widget.icon,
                  key: ValueKey(widget.icon),
                  color: const Color(0xFF0F2D1A),
                  size: widget.size * 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.standalone) return core;

    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF7BC99A).withOpacity(0.40), width: 0.9),
            boxShadow: [
              BoxShadow(color: const Color(0xFF7BC99A).withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 3)),
            ],
          ),
          child: core,
        ),
      ),
    );
  }
}

// Variante con badge (para botón de capas dentro del mapa, desktop)
class _GlassIconButtonWithBadge extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _GlassIconButtonWithBadge({
    required this.icon,
    required this.onTap,
    required this.badgeCount,
  });

  @override
  State<_GlassIconButtonWithBadge> createState() => _GlassIconButtonWithBadgeState();
}

class _GlassIconButtonWithBadgeState extends State<_GlassIconButtonWithBadge> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF7BC99A).withOpacity(0.40), width: 0.9),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF7BC99A).withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 3)),
                ],
              ),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit:  (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp:   (_) => setState(() => _pressed = false),
                  onTapCancel:   () => setState(() => _pressed = false),
                  onTap: widget.onTap,
                  child: AnimatedScale(
                    scale: _pressed ? 0.9 : (_hovered ? 1.04 : 1.0),
                    duration: const Duration(milliseconds: 130),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      child: Icon(widget.icon, color: const Color(0xFF0F2D1A), size: 19),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.badgeCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E6B45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF1E6B45).withOpacity(0.45), blurRadius: 6),
                ],
              ),
              child: Text(
                '${widget.badgeCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BotAvatar extends StatefulWidget {
  @override
  State<_BotAvatar> createState() => _BotAvatarState();
}

class _BotAvatarState extends State<_BotAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.6),
              blurRadius: 10,
            ),
          ],
        ),
        child: Transform.rotate(
          angle: 0.05 * (0.5 - (_c.value % 1.0)).abs(),
          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1E6B45), size: 23),
        ),
      ),
    );
  }
}

class _OnlineDot extends StatefulWidget {
  const _OnlineDot();

  @override
  State<_OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<_OnlineDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.5 + 0.4 * _c.value),
              blurRadius: 4 + 4 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.4 + 0.6 * _c.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PulsingMarker extends StatefulWidget {
  final Color color;
  const _PulsingMarker({required this.color});

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 50 * _c.value,
            height: 50 * _c.value,
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.30 * (1 - _c.value)),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [widget.color, Color.lerp(widget.color, Colors.black, 0.3)!],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(color: widget.color.withOpacity(0.65), blurRadius: 12, offset: const Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color primary;
  final Color primaryDark;
  final Color accent;

  const _SendButton({
    required this.onTap,
    required this.primary,
    required this.primaryDark,
    required this.accent,
  });

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel:   () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : (_hovered ? 1.06 : 1.0),
          duration: const Duration(milliseconds: 130),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [widget.accent, widget.primary, widget.primaryDark],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withOpacity(_hovered ? 0.60 : 0.40),
                  blurRadius: _hovered ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _LayersFab extends StatefulWidget {
  final VoidCallback onTap;
  final Color primary;
  final Color primaryDark;
  final Color accent;
  final int activeCount;

  const _LayersFab({
    required this.onTap,
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.activeCount,
  });

  @override
  State<_LayersFab> createState() => _LayersFabState();
}

class _LayersFabState extends State<_LayersFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel:   () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [widget.accent, widget.primary, widget.primaryDark],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: widget.accent.withOpacity(0.55), blurRadius: 22, offset: const Offset(0, 7)),
                ],
              ),
              child: const Icon(Icons.layers_rounded, color: Colors.white, size: 28),
            ),
            if (widget.activeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6B45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1E6B45).withOpacity(0.5), blurRadius: 8),
                    ],
                  ),
                  child: Text(
                    '${widget.activeCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// FAB de cultivos (móvil) — círculo arriba-izquierda
class _CropsFab extends StatefulWidget {
  final VoidCallback onTap;
  final Color primary;
  final Color primaryDark;
  final Color accent;

  const _CropsFab({
    required this.onTap,
    required this.primary,
    required this.primaryDark,
    required this.accent,
  });

  @override
  State<_CropsFab> createState() => _CropsFabState();
}

class _CropsFabState extends State<_CropsFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel:   () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.accent, widget.primary, widget.primaryDark],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: widget.accent.withOpacity(0.55), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: const Icon(Icons.pie_chart_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

// FAB recentrar (móvil) — abajo-derecha
class _RecenterFab extends StatefulWidget {
  final VoidCallback onTap;
  final Color primary;
  final Color primaryDark;
  final Color accent;

  const _RecenterFab({
    required this.onTap,
    required this.primary,
    required this.primaryDark,
    required this.accent,
  });

  @override
  State<_RecenterFab> createState() => _RecenterFabState();
}

class _RecenterFabState extends State<_RecenterFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel:   () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: widget.primary.withOpacity(0.35), width: 1.2),
            boxShadow: [
              BoxShadow(color: widget.accent.withOpacity(0.40), blurRadius: 16, offset: const Offset(0, 5)),
            ],
          ),
          child: Icon(Icons.my_location_rounded, color: widget.primaryDark, size: 26),
        ),
      ),
    );
  }
}

class _ChatFab extends StatefulWidget {
  final VoidCallback onTap;
  final Color primary;
  final Color primaryDark;

  const _ChatFab({required this.onTap, required this.primary, required this.primaryDark});

  @override
  State<_ChatFab> createState() => _ChatFabState();
}

class _ChatFabState extends State<_ChatFab> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel:   () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB8E5C9), Color(0xFF4CAF7A), Color(0xFF1E6B45)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7BC99A).withOpacity(0.45 + 0.25 * _glow.value),
                  blurRadius: 20 + 10 * _glow.value,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class _MobileSheet extends StatefulWidget {
  final VoidCallback onClose;
  final String title;
  final Widget child;
  final bool fullHeight;

  const _MobileSheet({
    required this.onClose,
    required this.title,
    required this.child,
    this.fullHeight = false,
  });

  @override
  State<_MobileSheet> createState() => _MobileSheetState();
}

class _MobileSheetState extends State<_MobileSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 360))..forward();
  }

  Future<void> _close() async {
    await _c.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq            = MediaQuery.of(context);
    final size          = mq.size;
    final keyboardHeight = mq.viewInsets.bottom;
    final hasKeyboard   = keyboardHeight > 0;
    final baseHeight    = widget.fullHeight ? size.height * 0.85 : size.height * 0.55;
    final sheetHeight   = hasKeyboard
        ? (size.height - keyboardHeight - 24).clamp(300.0, size.height)
        : baseHeight;

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Stack(
          children: [
            GestureDetector(
              onTap: _close,
              child: Container(color: Colors.black.withOpacity(0.40 * t)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboardHeight - sheetHeight * (1 - t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                height: sheetHeight,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  boxShadow: [
                    BoxShadow(color: Color(0x35000000), blurRadius: 32, offset: Offset(0, -8)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 11, bottom: 6),
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB5DCC2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F2D1A),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _close,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5EC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.close_rounded, color: Color(0xFF0F2D1A), size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 0.8, color: const Color(0xFFB5DCC2)),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}