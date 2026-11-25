import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TurkeyInteractiveMapCard extends StatefulWidget {
  final ValueChanged<String>? onProvinceSelected;
  final Map<String, dynamic>? provincesData;

  const TurkeyInteractiveMapCard({
    super.key,
    this.onProvinceSelected,
    this.provincesData,
  });

  @override
  State<TurkeyInteractiveMapCard> createState() =>
      _TurkeyInteractiveMapCardState();
}

class _TurkeyInteractiveMapCardState extends State<TurkeyInteractiveMapCard> {
  final TransformationController _transformController =
      TransformationController();
  List<_ProvinceShape> _provinces = [];
  Map<String, double> _fillRates = {};
  Map<String, dynamic> _staticProvinces = {};
  String _selectedProvince = '81 İl (Tümü)';
  bool _isLoading = true;
  bool _isZoomed = false;
  double _currentScale = 1.0;

  static const Map<String, String> _displayAliases = {
    'afyon': 'Afyonkarahisar',
    'içel': 'Mersin',
    'icel': 'Mersin',
    'antakya': 'Hatay',
    'adapazarı': 'Sakarya',
    'adapazari': 'Sakarya',
  };

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
    _loadMapAndReportData();
  }

  @override
  void didUpdateWidget(covariant TurkeyInteractiveMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_provinces.isNotEmpty) {
      final newRates = _computeFillRates(_provinces);
      if (!mapEquals(_fillRates, newRates)) {
        setState(() => _fillRates = newRates);
      }
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if ((zoomed != _isZoomed || (scale - _currentScale).abs() > 0.12) &&
        mounted) {
      setState(() {
        _isZoomed = zoomed;
        _currentScale = scale;
      });
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    setState(() {
      _isZoomed = false;
      _currentScale = 1.0;
    });
  }

  String _canonicalProvinceName(String rawName) {
    final lower = _normalizeTr(rawName);
    return _displayAliases[lower] ?? rawName.trim();
  }

  Future<void> _loadMapAndReportData() async {
    try {
      final geoRaw =
          await rootBundle.loadString('assets/maps/turkey_provinces.json');
      final Map<String, dynamic> geoJson = json.decode(geoRaw);

      Map<String, dynamic> staticProvinces = {};
      try {
        final reportRaw =
            await rootBundle.loadString('assets/data/doluluk_raporu.json');
        final Map<String, dynamic> reportJson = json.decode(reportRaw);
        staticProvinces =
            (reportJson['provinces'] as Map<String, dynamic>?) ?? {};
      } catch (e) {
        debugPrint('Statik doluluk raporu okunamadı: $e');
      }

      final List<dynamic> features = geoJson['features'] ?? [];
      final List<_ProvinceShape> parsedShapes = [];

      for (final f in features) {
        final props = (f['properties'] as Map<String, dynamic>?) ?? {};
        final rawName = (props['name'] ??
                props['NAME_1'] ??
                props['il_adi'] ??
                props['Il_Adi'] ??
                'Bilinmeyen')
            .toString();

        // GeoJSON'daki "Afyon" gibi kısa isimleri resmi il adına çevir
        final canonicalName = _canonicalProvinceName(rawName);

        final geom = f['geometry'] as Map<String, dynamic>;
        final type = geom['type'] as String;
        final coords = geom['coordinates'] as List<dynamic>;

        final List<List<Offset>> polygons = [];
        if (type == 'Polygon') {
          for (final ring in coords) {
            polygons.add(_parseRing(ring as List<dynamic>));
          }
        } else if (type == 'MultiPolygon') {
          for (final poly in coords) {
            for (final ring in (poly as List<dynamic>)) {
              polygons.add(_parseRing(ring as List<dynamic>));
            }
          }
        }

        if (polygons.isNotEmpty) {
          parsedShapes.add(_ProvinceShape(
            name: canonicalName,
            normalizedName: _normalizeTr(canonicalName),
            polygons: polygons,
          ));
        }
      }

      parsedShapes.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _staticProvinces = staticProvinces;
          _provinces = parsedShapes;
          _fillRates = _computeFillRates(parsedShapes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Harita yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Offset> _parseRing(List<dynamic> ring) {
    return ring.map((pt) {
      final list = pt as List<dynamic>;
      final lon = (list[0] as num).toDouble();
      final lat = (list[1] as num).toDouble();
      return Offset(lon, lat);
    }).toList();
  }

  String _normalizeTr(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('û', 'u')
        .trim();
  }

  Map<String, dynamic> get _effectiveData {
    final live = widget.provincesData;
    if (live != null && live.isNotEmpty) return live;
    return _staticProvinces;
  }

  Map<String, double> _computeFillRates(List<_ProvinceShape> shapes) {
    final data = _effectiveData;
    final rates = <String, double>{};
    for (final shape in shapes) {
      final pct = _resolveFillPct(shape.name, data);
      if (pct != null) rates[shape.normalizedName] = pct;
    }
    return rates;
  }

  double? _resolveFillPct(String provinceName, Map<String, dynamic> data) {
    final targetName = _canonicalProvinceName(provinceName);

    if (data.containsKey(targetName)) {
      return (data[targetName]?['weighted_fill_pct'] as num?)?.toDouble();
    }
    final targetLower = _normalizeTr(targetName);
    for (final entry in data.entries) {
      if (_normalizeTr(entry.key) == targetLower) {
        return (entry.value?['weighted_fill_pct'] as num?)?.toDouble();
      }
    }
    return null;
  }

  Color _getFillColor(double? pct) {
    if (pct == null) return const Color(0xFF1E2D40);
    if (pct < 20) return const Color(0xFFDC2626);
    if (pct < 40) return const Color(0xFFEA580C);
    if (pct < 65) return const Color(0xFFEAB308);
    if (pct < 85) return const Color(0xFF0284C7);
    return const Color(0xFF0D9488);
  }

  void _selectProvince(String name) {
    setState(() => _selectedProvince = name);
    widget.onProvinceSelected?.call(
      name == '81 İl (Tümü)' ? 'Türkiye Geneli' : name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dropdownItems = ['81 İl (Tümü)', ..._provinces.map((e) => e.name)];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15202E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF243449)),
      ),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                const Text(
                  'Türkiye Su Rezervi ve Doluluk Haritası',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '81 İl Uydu Yüzey Analizi • Dokunarak detay inceleyin',
                  style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 11),
                ),
                const SizedBox(height: 8),
                _buildProvinceDropdown(dropdownItems, fullWidth: true),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Türkiye Su Rezervi ve Doluluk Haritası',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '81 İl Uydu Yüzey Analizi • Dokunarak detay inceleyin',
                            style: TextStyle(
                                color: Color(0xFF8A9BB2), fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildProvinceDropdown(dropdownItems, fullWidth: false),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF0EA5E9)))
                    : Stack(
                        children: [
                          LayoutBuilder(
                            builder: (context, mapBox) {
                              final dpr = MediaQuery.of(context)
                                  .devicePixelRatio
                                  .clamp(2.0, 4.0);
                              final renderSize = Size(
                                mapBox.biggest.width * dpr,
                                mapBox.biggest.height * dpr,
                              );

                              return GestureDetector(
                                onTapUp: (details) =>
                                    _handleMapTap(details, mapBox.biggest),
                                child: InteractiveViewer(
                                  transformationController:
                                      _transformController,
                                  minScale: 1.0,
                                  maxScale: 6.0,
                                  boundaryMargin: const EdgeInsets.all(24),
                                  child: SizedBox(
                                    width: mapBox.biggest.width,
                                    height: mapBox.biggest.height,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: CustomPaint(
                                        isComplex: true,
                                        willChange: false,
                                        size: renderSize,
                                        painter: _TurkeyGeoPainter(
                                          provinces: _provinces,
                                          fillRates: _fillRates,
                                          selectedProvince: _selectedProvince,
                                          zoomScale: _currentScale,
                                          dprScale: dpr,
                                          colorResolver: _getFillColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow ? 8 : 10,
                                vertical: isNarrow ? 6 : 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF0E1621).withOpacity(0.88),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFF243449)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _legendRow(const Color(0xFFDC2626),
                                      'Kritik (%0-20)', isNarrow),
                                  _legendRow(const Color(0xFFEA580C),
                                      'Düşük (%20-40)', isNarrow),
                                  _legendRow(const Color(0xFFEAB308),
                                      'Orta (%40-65)', isNarrow),
                                  _legendRow(const Color(0xFF0284C7),
                                      'İyi (%65-85)', isNarrow),
                                  _legendRow(const Color(0xFF0D9488),
                                      'Yüksek (%85+)', isNarrow),
                                ],
                              ),
                            ),
                          ),
                          if (_isZoomed)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(
                                        color: Color(0xFF38BDF8)),
                                  ),
                                ),
                                onPressed: _resetZoom,
                                icon: const Icon(Icons.zoom_out_map,
                                    size: 15, color: Color(0xFF38BDF8)),
                                label: const Text(
                                  'Uzaklaştır / Sıfırla',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProvinceDropdown(List<String> dropdownItems,
      {required bool fullWidth}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1C293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E425B)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: fullWidth,
          value: dropdownItems.contains(_selectedProvince)
              ? _selectedProvince
              : '81 İl (Tümü)',
          dropdownColor: const Color(0xFF1C293B),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Color(0xFF8A9BB2), size: 18),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: dropdownItems
              .map((name) => DropdownMenuItem(value: name, child: Text(name)))
              .toList(),
          onChanged: (val) {
            if (val != null) _selectProvince(val);
          },
        ),
      ),
    );
  }

  void _handleMapTap(TapUpDetails details, Size logicalSize) {
    final matrix = _transformController.value;
    final inverted = Matrix4.inverted(matrix);
    final scenePoint =
        MatrixUtils.transformPoint(inverted, details.localPosition);

    final mapper = _GeoProjector(logicalSize, dprScale: 1.0);
    for (final prov in _provinces) {
      for (final ring in prov.polygons) {
        final path = Path();
        for (int i = 0; i < ring.length; i++) {
          final pt = mapper.project(ring[i]);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        if (path.contains(scenePoint)) {
          _selectProvince(prov.name);
          return;
        }
      }
    }
  }

  Widget _legendRow(Color color, String text, bool compact) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1.5 : 2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 8 : 10,
            height: compact ? 8 : 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: const Color(0xFFCBD5E1),
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvinceShape {
  final String name;
  final String normalizedName;
  final List<List<Offset>> polygons;

  _ProvinceShape({
    required this.name,
    required this.normalizedName,
    required this.polygons,
  });
}

class _GeoProjector {
  final Size size;
  final double dprScale;
  static const double minLon = 25.5;
  static const double maxLon = 45.0;
  static const double minLat = 35.8;
  static const double maxLat = 42.3;

  late final double scale;
  late final double offsetX;
  late final double offsetY;

  _GeoProjector(this.size, {this.dprScale = 1.0}) {
    const lonSpan = maxLon - minLon;
    const latSpan = (maxLat - minLat) * 1.28;
    final scaleX = size.width / lonSpan;
    final scaleY = size.height / latSpan;
    scale = math.min(scaleX, scaleY) * 0.94;

    final mapWidth = lonSpan * scale;
    final mapHeight = latSpan * scale;
    offsetX = (size.width - mapWidth) / 2;
    offsetY = (size.height - mapHeight) / 2 + (12 * dprScale);
  }

  Offset project(Offset lonLat) {
    final x = offsetX + (lonLat.dx - minLon) * scale;
    final y = offsetY + (maxLat - lonLat.dy) * 1.28 * scale;
    return Offset(x, y);
  }
}

class _TurkeyGeoPainter extends CustomPainter {
  final List<_ProvinceShape> provinces;
  final Map<String, double> fillRates;
  final String selectedProvince;
  final double zoomScale;
  final double dprScale;
  final Color Function(double?) colorResolver;

  _TurkeyGeoPainter({
    required this.provinces,
    required this.fillRates,
    required this.selectedProvince,
    required this.zoomScale,
    required this.dprScale,
    required this.colorResolver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mapper = _GeoProjector(size, dprScale: dprScale);
    final effectiveStroke = ((0.9 * dprScale) / zoomScale).clamp(0.4, 2.5);

    final borderPaint = Paint()
      ..color = const Color(0xFF0D141F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = effectiveStroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    final selectedBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = ((2.0 * dprScale) / zoomScale).clamp(1.0, 5.0)
      ..strokeJoin = StrokeJoin.round
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    for (final prov in provinces) {
      final isSelected = prov.name == selectedProvince;
      final pct = fillRates[prov.normalizedName];
      final fillPaint = Paint()
        ..color = colorResolver(pct)
        ..style = PaintingStyle.fill
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true;

      for (final ring in prov.polygons) {
        final path = Path();
        for (int i = 0; i < ring.length; i++) {
          final pt = mapper.project(ring[i]);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, isSelected ? selectedBorderPaint : borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TurkeyGeoPainter oldDelegate) {
    return oldDelegate.selectedProvince != selectedProvince ||
        !mapEquals(oldDelegate.fillRates, fillRates) ||
        oldDelegate.provinces.length != provinces.length ||
        oldDelegate.dprScale != dprScale ||
        (oldDelegate.zoomScale - zoomScale).abs() > 0.12;
  }
}