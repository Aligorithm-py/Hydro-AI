import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'turkey_interactive_map.dart';
import 'reports_view.dart';
import 'analysis_view.dart';

void main() {
  runApp(const HydroAiApp());
}

class HydroAiApp extends StatelessWidget {
  const HydroAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hydro AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D141F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          surface: Color(0xFF15202E),
        ),
      ),
      home: const HydroDashboardScreen(),
    );
  }
}

class HydroDashboardScreen extends StatefulWidget {
  const HydroDashboardScreen({super.key});

  @override
  State<HydroDashboardScreen> createState() => _HydroDashboardScreenState();
}

class _HydroDashboardScreenState extends State<HydroDashboardScreen> {
  String _activeTab = 'Harita';
  String _selectedProvince = 'Türkiye Geneli';

  // Baz uydu verisi ve canlı meteorolojiyle harmanlanmış güncel veri
  Map<String, dynamic> _baseProvincesData = {};
  Map<String, dynamic> _provincesData = {};
  double _turkeyAvgFill = 52.4;
  int _totalSources = 342;

  // 15 Dakikalık Otomatik Senkronizasyon Durumu
  Timer? _autoSyncTimer;
  bool _isSyncingLive = false;
  DateTime? _lastSyncTime;

  // 81 İl Merkez Koordinatları (Canlı 7 Günlük Yağış ve Buharlaşma Hesabı İçin)
  static const Map<String, List<double>> _turkey81Coords = {
    'Adana': [37.0000, 35.3213],
    'Adıyaman': [37.7648, 38.2786],
    'Afyonkarahisar': [38.7507, 30.5567],
    'Ağrı': [39.7191, 43.0503],
    'Aksaray': [38.3687, 34.0370],
    'Amasya': [40.6499, 35.8353],
    'Ankara': [39.9334, 32.8597],
    'Antalya': [36.8969, 30.7133],
    'Ardahan': [41.1105, 42.7022],
    'Artvin': [41.1828, 41.8183],
    'Aydın': [37.8560, 27.8416],
    'Balıkesir': [39.6484, 27.8826],
    'Bartın': [41.6344, 32.3375],
    'Batman': [37.8812, 41.1351],
    'Bayburt': [40.2552, 40.2249],
    'Bilecik': [40.1451, 29.9799],
    'Bingöl': [38.8854, 40.4966],
    'Bitlis': [38.4006, 42.1095],
    'Bolu': [40.7392, 31.6089],
    'Burdur': [37.7203, 30.2908],
    'Bursa': [40.1885, 29.0610],
    'Çanakkale': [40.1553, 26.4142],
    'Çankırı': [40.6013, 33.6134],
    'Çorum': [40.5506, 34.9556],
    'Denizli': [37.7765, 29.0864],
    'Diyarbakır': [37.9144, 40.2306],
    'Düzce': [40.8438, 31.1565],
    'Edirne': [41.6771, 26.5557],
    'Elazığ': [38.6810, 39.2264],
    'Erzincan': [39.7500, 39.5000],
    'Erzurum': [39.9000, 41.2700],
    'Eskişehir': [39.7767, 30.5206],
    'Gaziantep': [37.0662, 37.3833],
    'Giresun': [40.9128, 38.3895],
    'Gümüşhane': [40.4386, 39.5086],
    'Hakkâri': [37.5833, 43.7333],
    'Hatay': [36.4018, 36.3498],
    'Iğdır': [39.9167, 44.0333],
    'Isparta': [37.7648, 30.5566],
    'İstanbul': [41.0082, 28.9784],
    'İzmir': [38.4192, 27.1287],
    'Kahramanmaraş': [37.5858, 36.9371],
    'Karabük': [41.2061, 32.6204],
    'Karaman': [37.1759, 33.2287],
    'Kars': [40.6167, 43.1000],
    'Kastamonu': [41.3887, 33.7827],
    'Kayseri': [38.7312, 35.4787],
    'Kırıkkale': [39.8468, 33.5153],
    'Kırklareli': [41.7333, 27.2167],
    'Kırşehir': [39.1425, 34.1709],
    'Kilis': [36.7184, 37.1212],
    'Kocaeli': [40.8533, 29.8815],
    'Konya': [37.8667, 32.4833],
    'Kütahya': [39.4167, 29.9833],
    'Malatya': [38.3552, 38.3095],
    'Manisa': [38.6191, 27.4289],
    'Mardin': [37.3212, 40.7245],
    'Mersin': [36.8000, 34.6333],
    'Muğla': [37.2153, 28.3636],
    'Muş': [38.9462, 41.7539],
    'Nevşehir': [38.6939, 34.6857],
    'Niğde': [37.9667, 34.6833],
    'Ordu': [40.9839, 37.8764],
    'Osmaniye': [37.0742, 36.2478],
    'Rize': [41.0201, 40.5234],
    'Sakarya': [40.7569, 30.3783],
    'Samsun': [41.2867, 36.3300],
    'Siirt': [37.9333, 41.9500],
    'Sinop': [42.0231, 35.1531],
    'Sivas': [39.7477, 37.0179],
    'Şanlıurfa': [37.1591, 38.7969],
    'Şırnak': [37.5164, 42.4611],
    'Tekirdağ': [40.9833, 27.5167],
    'Tokat': [40.3167, 36.5500],
    'Trabzon': [41.0015, 39.7178],
    'Tunceli': [39.1079, 39.5401],
    'Uşak': [38.6823, 29.4082],
    'Van': [38.4891, 43.4089],
    'Yalova': [40.6500, 29.2667],
    'Yozgat': [39.8181, 34.8147],
    'Zonguldak': [41.4564, 31.7987],
  };

  @override
  void initState() {
    super.initState();
    _initializeLivePipeline();
    // Her 15 dakikada bir otomatik canlı veri senkronizasyonu
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refreshFullPipeline(),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  /// Supabase uydu tabanını + Open-Meteo canlı verisini sırayla yeniler.
  Future<void> _refreshFullPipeline() async {
    await _loadBaseSatelliteReport();
    await _syncLiveHydroData();
  }

  Future<void> _initializeLivePipeline() async {
    await _loadBaseSatelliteReport();
    await _syncLiveHydroData();
  }

  static const String _supabaseUrl = 'https://wtytkgudfshwefntzguy.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0eXRrZ3VkZnNod2VmbnR6Z3V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU2MTUxNTcsImV4cCI6MjExMTE5MTE1N30.AFhnRImGVowvEUpjUk8i3z9HYq88K34f4cTWsQjAWrk';

  Future<void> _loadBaseSatelliteReport() async {
    try {
      Map<String, dynamic> provs = {};

      // 1) Supabase: province_satellite_metrics tablosu
      try {
        final uri = Uri.parse(
          '$_supabaseUrl/rest/v1/province_satellite_metrics?select=*',
        );
        final response = await http.get(uri, headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
        }).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is List) {
            for (final row in decoded) {
              if (row is! Map<String, dynamic>) continue;
              final name =
                  (row['province'] ?? row['province_name'] ?? row['name'])
                      ?.toString();
              if (name == null || name.isEmpty) continue;
              provs[name] = row;
            }
          }
        }
      } catch (_) {}

      // 2) Supabase ulaşılamazsa yerel JSON yedeği
      if (provs.isEmpty) {
        final raw =
            await rootBundle.loadString('assets/data/doluluk_raporu.json');
        final Map<String, dynamic> data = json.decode(raw);
        provs = (data['provinces'] as Map<String, dynamic>?) ?? {};
      }

      // Harita kısa adları için alias kopyaları da oluştur (Afyon -> Afyonkarahisar)
      final enriched = Map<String, dynamic>.from(provs);
      if (enriched.containsKey('Afyonkarahisar') &&
          !enriched.containsKey('Afyon')) {
        enriched['Afyon'] = Map<String, dynamic>.from(enriched['Afyonkarahisar']);
      }

      if (mounted) {
        setState(() {
          _baseProvincesData = enriched;
          _provincesData = Map<String, dynamic>.from(enriched);
          _recalculateNationalAverage();
        });
      }
    } catch (_) {}
  }

  /// Open-Meteo API üzerinden 81 ilin son 7 günlük gerçek yağış ve sıcaklık
  /// verilerini tek seferde çekip baz uydu ölçümleriyle harmanlar.
  Future<void> _syncLiveHydroData() async {
    if (_isSyncingLive) return;
    if (mounted) setState(() => _isSyncingLive = true);

    final cities = _turkey81Coords.keys.toList();
    final lats = cities.map((c) => _turkey81Coords[c]![0].toString()).join(',');
    final lons = cities.map((c) => _turkey81Coords[c]![1].toString()).join(',');

    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lats&longitude=$lons'
      '&past_days=7&forecast_days=1'
      '&daily=precipitation_sum,temperature_2m_max'
      '&timezone=Europe%2FIstanbul',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = json.decode(response.body);
      final List<dynamic> list = decoded is List ? decoded : [decoded];

      final updated = Map<String, dynamic>.from(_baseProvincesData);

      for (int i = 0; i < cities.length && i < list.length; i++) {
        final city = cities[i];
        final daily = list[i]['daily'] as Map<String, dynamic>?;
        if (daily == null) continue;

        final precipList = (daily['precipitation_sum'] as List?) ?? [];
        final tempList = (daily['temperature_2m_max'] as List?) ?? [];

        double rain7d = 0.0;
        for (int p = 0; p < math.min(7, precipList.length); p++) {
          rain7d += (precipList[p] as num?)?.toDouble() ?? 0.0;
        }

        double tempSum = 0.0;
        int tempCnt = 0;
        for (int t = 0; t < math.min(7, tempList.length); t++) {
          if (tempList[t] != null) {
            tempSum += (tempList[t] as num).toDouble();
            tempCnt++;
          }
        }
        final avgMaxTemp = tempCnt > 0 ? (tempSum / tempCnt) : 18.0;

        // Baz uydu verisini bul
        final baseEntry = (_baseProvincesData[city] as Map<String, dynamic>?) ??
            <String, dynamic>{};
        final double baseFill =
            (baseEntry['weighted_fill_pct'] as num?)?.toDouble() ?? 50.0;
        final double basePoll =
            (baseEntry['pollution_pct'] as num?)?.toDouble() ?? 24.0;
        final double baseRawRisk =
            (baseEntry['raw_water_risk_pct'] as num?)?.toDouble() ?? 42.0;
        final int sourceCount =
            (baseEntry['source_count'] as num?)?.toInt() ?? 4;

        // Hidrolojik canlı düzeltme:
        // 15 mm referans yağışın üzerindeki her 10 mm yağış ~%1.4 havza beslemesi sağlar,
        // 22°C üzeri sıcaklık ise buharlaşma kaybı yaratır.
        final double rainGain = ((rain7d - 12.0) * 0.14).clamp(-3.5, 6.5);
        final double evapLoss =
            avgMaxTemp > 22.0 ? ((avgMaxTemp - 22.0) * 0.22).clamp(0.0, 3.5) : 0.0;

        final double liveFill =
            (baseFill + rainGain - evapLoss).clamp(4.0, 99.5);
        final double liveStress =
            (100.0 - liveFill * 0.85 - (rain7d * 0.12)).clamp(6.0, 98.0);
        // Yoğun yağış yüzey akışıyla geçici bulanıklığı hafif artırır
        final double livePoll =
            (basePoll + (rain7d > 25.0 ? 2.5 : -0.5)).clamp(5.0, 92.0);
        final double liveRawRisk =
            (baseRawRisk + (liveFill < 25.0 ? 3.5 : 0.0)).clamp(8.0, 96.0);

        final String liveSummary = rain7d >= 20.0
            ? '$city havzasında son 7 günde ${rain7d.toStringAsFixed(1)} mm yağış kaydedildi; yüzey akışı rezervuar doluluğunu %${liveFill.toStringAsFixed(1)} bandına taşıdı.'
            : (rain7d < 3.0
                ? '$city genelinde son 7 gün kurak geçti (${rain7d.toStringAsFixed(1)} mm); buharlaşma baskısıyla doluluk %${liveFill.toStringAsFixed(1)} seviyesinde izleniyor.'
                : '$city için uydu yüzey alanı ve son 7 günlük ${rain7d.toStringAsFixed(1)} mm yağış verisi birleştirilerek güncel analiz hesaplandı.');

        final newEntry = <String, dynamic>{
          ...baseEntry,
          'weighted_fill_pct': double.parse(liveFill.toStringAsFixed(1)),
          'water_stress_pct': double.parse(liveStress.toStringAsFixed(1)),
          'pollution_pct': double.parse(livePoll.toStringAsFixed(1)),
          'raw_water_risk_pct': double.parse(liveRawRisk.toStringAsFixed(1)),
          'rainfall_7d_mm': double.parse(rain7d.toStringAsFixed(1)),
          'rainfall_label': 'Son 7 gün: ${rain7d.toStringAsFixed(1)} mm',
          'source_count': sourceCount,
          'ai_summary': liveSummary,
        };

        updated[city] = newEntry;
        if (city == 'Afyonkarahisar') {
          updated['Afyon'] = Map<String, dynamic>.from(newEntry);
        }
      }

      if (mounted) {
        setState(() {
          _provincesData = updated;
          _lastSyncTime = DateTime.now();
          _isSyncingLive = false;
          _recalculateNationalAverage();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSyncingLive = false);
      }
    }
  }

  void _recalculateNationalAverage() {
    double sum = 0;
    int count = 0;
    _provincesData.forEach((key, entry) {
      if (key != 'Afyon' && entry is Map && entry['weighted_fill_pct'] != null) {
        sum += (entry['weighted_fill_pct'] as num).toDouble();
        count++;
      }
    });
    if (count > 0) {
      _turkeyAvgFill = sum / count;
    }
  }

  Map<String, dynamic>? _getProvinceMetrics(String provinceName) {
    if (provinceName == 'Türkiye Geneli') {
      return {
        'weighted_fill_pct': _turkeyAvgFill,
        'source_count': _totalSources,
      };
    }

    const aliases = {
      'afyon': 'Afyonkarahisar',
      'içel': 'Mersin',
      'icel': 'Mersin',
      'antakya': 'Hatay',
      'adapazarı': 'Sakarya',
      'adapazari': 'Sakarya',
    };

    final normInput = _normalizeTr(provinceName);
    final resolvedName = aliases[normInput] ?? provinceName;

    if (_provincesData.containsKey(resolvedName)) {
      return _provincesData[resolvedName] as Map<String, dynamic>;
    }
    final norm = _normalizeTr(resolvedName);
    for (final e in _provincesData.entries) {
      if (_normalizeTr(e.key) == norm) {
        return e.value as Map<String, dynamic>;
      }
    }
    return null;
  }

  String _normalizeTr(String t) => t
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u')
      .trim();

  _ProvinceHydroMetrics _computeMetrics() {
    final entry = _getProvinceMetrics(_selectedProvince);
    final double fillPct =
        (entry?['weighted_fill_pct'] as num?)?.toDouble() ?? _turkeyAvgFill;
    final int sourceCount = (entry?['source_count'] as num?)?.toInt() ?? 0;

    if (_selectedProvince == 'Türkiye Geneli' && _provincesData.isNotEmpty) {
      double sumStress = 0, sumPoll = 0, sumRaw = 0, sumRain = 0;
      int n = 0;
      _provincesData.forEach((key, val) {
        if (key != 'Afyon' && val is Map && val['water_stress_pct'] != null) {
          sumStress += (val['water_stress_pct'] as num).toDouble();
          sumPoll += (val['pollution_pct'] as num).toDouble();
          sumRaw += (val['raw_water_risk_pct'] as num).toDouble();
          sumRain += (val['rainfall_7d_mm'] as num?)?.toDouble() ?? 0.0;
          n++;
        }
      });
      if (n > 0) {
        final avgRain = (sumRain / n).toStringAsFixed(1);
        return _ProvinceHydroMetrics(
          provinceName: 'Türkiye Geneli',
          sourceCount: _totalSources,
          fillPct: _turkeyAvgFill,
          waterStressPct: sumStress / n,
          pollutionPct: sumPoll / n,
          rawWaterRiskPct: sumRaw / n,
          rainfallText: 'Ort. 7 gün: $avgRain mm',
          aiNote:
              '81 ilin uydu yüzey ölçümleri ve 15 dakikada bir güncellenen canlı meteorolojik yağış verileri birleştirilerek ülke geneli ağırlıklı su durumu hesaplandı.',
        );
      }
    }

    final double waterStressPct =
        (entry?['water_stress_pct'] as num?)?.toDouble() ??
            (100.0 - fillPct * 0.85).clamp(8.0, 98.0);
    final double pollutionPct =
        (entry?['pollution_pct'] as num?)?.toDouble() ?? 24.0;
    final double rawWaterRiskPct =
        (entry?['raw_water_risk_pct'] as num?)?.toDouble() ?? 42.0;
    final String rainfallText =
        (entry?['rainfall_label'] as String?) ?? 'Son 7 gün: Veri bekleniyor';
    final String aiNote = (entry?['ai_summary'] as String?) ??
        'Uydu yüzey alanı ve haftalık yağış verilerine göre analiz güncellendi.';

    return _ProvinceHydroMetrics(
      provinceName: _selectedProvince == 'Afyon'
          ? 'Afyonkarahisar'
          : _selectedProvince,
      sourceCount: sourceCount,
      fillPct: fillPct,
      waterStressPct: waterStressPct,
      pollutionPct: pollutionPct,
      rawWaterRiskPct: rawWaterRiskPct,
      rainfallText: rainfallText,
      aiNote: aiNote,
    );
  }

  String _formatSyncClock() {
    if (_lastSyncTime == null) return 'Senkronize ediliyor...';
    final h = _lastSyncTime!.hour.toString().padLeft(2, '0');
    final m = _lastSyncTime!.minute.toString().padLeft(2, '0');
    return 'Canlı • $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _computeMetrics();
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Harita ve alt görünümlere 'Afyon' duplicate anahtarını temizleyerek gönder
    final cleanProvincesData = Map<String, dynamic>.from(_provincesData)
      ..remove('Afyon');

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(54),
        child: Container(
          color: const Color(0xFF131D2B),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 12),
          child: SafeArea(
            child: Row(
              children: [
                Icon(Icons.water_drop,
                    color: const Color(0xFF0EA5E9), size: isMobile ? 16 : 20),
                const SizedBox(width: 4),
                Text(
                  'HYDRO AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    fontSize: isMobile ? 11.5 : 14,
                  ),
                ),
                SizedBox(width: isMobile ? 6 : 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['Harita', 'Hava Durumu', 'Raporlar', 'Analiz']
                        .map((tab) => Flexible(
                              child: _buildTopNavTab(tab, isMobile),
                            ))
                        .toList(),
                  ),
                ),
                // Canlı 15 dk senkronizasyon durumu & manuel yenileme butonu
                if (!isMobile)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _isSyncingLive
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formatSyncClock(),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Verileri Şimdi Güncelle (Otomatik: 15 dk)',
                  onPressed: _isSyncingLive ? null : _syncLiveHydroData,
                  icon: _isSyncingLive
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF38BDF8),
                          ),
                        )
                      : const Icon(Icons.refresh,
                          size: 17, color: Color(0xFF38BDF8)),
                ),
                if (_activeTab == 'Harita' &&
                    _selectedProvince != 'Türkiye Geneli')
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Türkiye Geneline Dön',
                      onPressed: () =>
                          setState(() => _selectedProvince = 'Türkiye Geneli'),
                      icon: const Icon(Icons.public,
                          size: 17, color: Color(0xFF38BDF8)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBodyByTab(metrics, cleanProvincesData, isMobile),
    );
  }

  Widget _buildBodyByTab(
    _ProvinceHydroMetrics metrics,
    Map<String, dynamic> cleanProvincesData,
    bool isMobile,
  ) {
    if (_activeTab == 'Hava Durumu') {
      return RegionalWeatherView(provincesData: cleanProvincesData);
    }

    if (_activeTab == 'Raporlar') {
      return HydroReportsView(
        provincesData: cleanProvincesData,
        turkeyAvgFill: _turkeyAvgFill,
        totalSources: _totalSources,
      );
    }

    if (_activeTab == 'Analiz') {
      return HydroAnalysisView(
        provincesData: cleanProvincesData,
        turkeyAvgFill: _turkeyAvgFill,
        totalSources: _totalSources,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 65,
                  child: TurkeyInteractiveMapCard(
                    provincesData: cleanProvincesData,
                    onProvinceSelected: (name) {
                      setState(() => _selectedProvince = name);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 35,
                  child: _buildRightMetricsPanel(metrics),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SizedBox(
                height: isMobile ? 430 : 380,
                child: TurkeyInteractiveMapCard(
                  provincesData: cleanProvincesData,
                  onProvinceSelected: (name) {
                    setState(() => _selectedProvince = name);
                  },
                ),
              ),
              const SizedBox(height: 12),
              _buildRightMetricsPanel(metrics, isScrollableParent: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRightMetricsPanel(_ProvinceHydroMetrics m,
      {bool isScrollableParent = false}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF15202E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF243449)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.location_city,
                        color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m.provinceName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2D40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${m.sourceCount} Kaynak',
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _RadialMetricCard(
                title: 'Doluluk Oranı',
                subtitle: 'Uydu + Canlı Yağış',
                percentage: m.fillPct,
                ringColor: const Color(0xFF0EA5E9),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RadialMetricCard(
                title: 'Su Stresi',
                subtitle: 'Kuraklık & Baskı',
                percentage: m.waterStressPct,
                ringColor: const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _RadialMetricCard(
                title: 'Kirlilik Oranı',
                subtitle: 'Bulanıklık & Sediman',
                percentage: m.pollutionPct,
                ringColor: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RadialMetricCard(
                title: 'Arıtmasız Risk',
                subtitle: 'Ham Su Tüketim',
                percentage: m.rawWaterRiskPct,
                ringColor: const Color(0xFFA855F7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF15202E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF243449)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          color: Color(0xFF38BDF8), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Hydro AI Haftalık Analiz',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    m.rainfallText,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                m.aiNote,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '* Veriler otomatik olarak 15 dakikada bir canlı meteoroloji akışıyla güncellenir (${_formatSyncClock()}).',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (isScrollableParent) return content;
    return SingleChildScrollView(child: content);
  }

  Widget _buildTopNavTab(String title, bool isMobile) {
    final isActive = _activeTab == title;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = title),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 1.5 : 3),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 5 : 11,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E3A5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? const Border(
                  bottom: BorderSide(color: Color(0xFF38BDF8), width: 2))
              : null,
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF8A9BB2),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: isMobile ? 10.5 : 12.5,
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// BÖLGE BAZLI, 7 GÜNLÜK & SAAT SAAT CANLI HAVA DURUMU EKRANI
/// ============================================================================
class RegionalWeatherView extends StatefulWidget {
  final Map<String, dynamic> provincesData;

  const RegionalWeatherView({super.key, required this.provincesData});

  @override
  State<RegionalWeatherView> createState() => _RegionalWeatherViewState();
}

class _RegionalWeatherViewState extends State<RegionalWeatherView> {
  String? _selectedRegion;
  bool _isLoadingForecast = false;
  String? _errorMsg;
  Map<String, List<_DailyForecast>> _cityForecasts = {};
  Map<String, Map<String, List<_HourlyForecast>>> _cityHourlyForecasts = {};
  final Map<String, String> _selectedDayByCity = {};

  static const Map<String, Map<String, List<double>>> _regionsCities = {
    'Marmara Bölgesi': {
      'İstanbul': [41.0082, 28.9784],
      'Bursa': [40.1885, 29.0610],
      'Kocaeli': [40.8533, 29.8815],
      'Balıkesir': [39.6484, 27.8826],
      'Tekirdağ': [40.9833, 27.5167],
      'Sakarya': [40.7569, 30.3783],
      'Çanakkale': [40.1553, 26.4142],
      'Edirne': [41.6771, 26.5557],
      'Kırklareli': [41.7333, 27.2167],
      'Yalova': [40.6500, 29.2667],
      'Bilecik': [40.1451, 29.9799],
    },
    'Ege Bölgesi': {
      'İzmir': [38.4192, 27.1287],
      'Manisa': [38.6191, 27.4289],
      'Aydın': [37.8560, 27.8416],
      'Denizli': [37.7765, 29.0864],
      'Muğla': [37.2153, 28.3636],
      'Afyonkarahisar': [38.7507, 30.5567],
      'Kütahya': [39.4167, 29.9833],
      'Uşak': [38.6823, 29.4082],
    },
    'Akdeniz Bölgesi': {
      'Antalya': [36.8969, 30.7133],
      'Adana': [37.0000, 35.3213],
      'Mersin': [36.8000, 34.6333],
      'Hatay': [36.4018, 36.3498],
      'Kahramanmaraş': [37.5858, 36.9371],
      'Osmaniye': [37.0742, 36.2478],
      'Isparta': [37.7648, 30.5566],
      'Burdur': [37.7203, 30.2908],
    },
    'İç Anadolu Bölgesi': {
      'Ankara': [39.9334, 32.8597],
      'Konya': [37.8667, 32.4833],
      'Kayseri': [38.7312, 35.4787],
      'Eskişehir': [39.7767, 30.5206],
      'Sivas': [39.7477, 37.0179],
      'Yozgat': [39.8181, 34.8147],
      'Aksaray': [38.3687, 34.0370],
      'Niğde': [37.9667, 34.6833],
      'Nevşehir': [38.6939, 34.6857],
      'Kırıkkale': [39.8468, 33.5153],
      'Karaman': [37.1759, 33.2287],
      'Kırşehir': [39.1425, 34.1709],
      'Çankırı': [40.6013, 33.6134],
    },
    'Karadeniz Bölgesi': {
      'Samsun': [41.2867, 36.3300],
      'Trabzon': [41.0015, 39.7178],
      'Ordu': [40.9839, 37.8764],
      'Zonguldak': [41.4564, 31.7987],
      'Tokat': [40.3167, 36.5500],
      'Çorum': [40.5506, 34.9556],
      'Giresun': [40.9128, 38.3895],
      'Düzce': [40.8438, 31.1565],
      'Kastamonu': [41.3887, 33.7827],
      'Rize': [41.0201, 40.5234],
      'Amasya': [40.6499, 35.8353],
      'Bolu': [40.7392, 31.6089],
      'Karabük': [41.2061, 32.6204],
      'Bartın': [41.6344, 32.3375],
      'Sinop': [42.0231, 35.1531],
      'Artvin': [41.1828, 41.8183],
      'Gümüşhane': [40.4386, 39.5086],
      'Bayburt': [40.2552, 40.2249],
    },
    'Doğu Anadolu Bölgesi': {
      'Van': [38.4891, 43.4089],
      'Erzurum': [39.9000, 41.2700],
      'Malatya': [38.3552, 38.3095],
      'Elazığ': [38.6810, 39.2264],
      'Ağrı': [39.7191, 43.0503],
      'Muş': [38.9462, 41.7539],
      'Bitlis': [38.4006, 42.1095],
      'Kars': [40.6167, 43.1000],
      'Hakkâri': [37.5833, 43.7333],
      'Bingöl': [38.8854, 40.4966],
      'Erzincan': [39.7500, 39.5000],
      'Iğdır': [39.9167, 44.0333],
      'Ardahan': [41.1105, 42.7022],
      'Tunceli': [39.1079, 39.5401],
    },
    'Güneydoğu Anadolu Bölgesi': {
      'Şanlıurfa': [37.1591, 38.7969],
      'Gaziantep': [37.0662, 37.3833],
      'Diyarbakır': [37.9144, 40.2306],
      'Mardin': [37.3212, 40.7245],
      'Batman': [37.8812, 41.1351],
      'Adıyaman': [37.7648, 38.2786],
      'Şırnak': [37.5164, 42.4611],
      'Siirt': [37.9333, 41.9500],
      'Kilis': [36.7184, 37.1212],
    },
  };

  Future<void> _selectRegion(String regionName) async {
    setState(() {
      _selectedRegion = regionName;
      _isLoadingForecast = true;
      _errorMsg = null;
      _cityForecasts = {};
      _cityHourlyForecasts = {};
      _selectedDayByCity.clear();
    });

    final citiesMap = _regionsCities[regionName]!;
    final cityNames = citiesMap.keys.toList();
    final lats = cityNames.map((c) => citiesMap[c]![0].toString()).join(',');
    final lons = cityNames.map((c) => citiesMap[c]![1].toString()).join(',');

    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lats&longitude=$lons'
      '&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum'
      '&hourly=weathercode,temperature_2m,precipitation'
      '&forecast_days=7&timezone=Europe%2FIstanbul',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = json.decode(response.body);
      final List<dynamic> list = decoded is List ? decoded : [decoded];
      final Map<String, List<_DailyForecast>> parsedDaily = {};
      final Map<String, Map<String, List<_HourlyForecast>>> parsedHourly = {};

      for (int i = 0; i < cityNames.length && i < list.length; i++) {
        final city = cityNames[i];
        final daily = list[i]['daily'] as Map<String, dynamic>;
        final dates = (daily['time'] as List).cast<String>();
        final codes = (daily['weathercode'] as List);
        final tMax = (daily['temperature_2m_max'] as List);
        final tMin = (daily['temperature_2m_min'] as List);
        final precip = (daily['precipitation_sum'] as List);

        final days = <_DailyForecast>[];
        for (int d = 0; d < dates.length; d++) {
          days.add(_DailyForecast(
            dateStr: dates[d],
            weatherCode: (codes[d] as num?)?.toInt() ?? 0,
            maxTemp: (tMax[d] as num?)?.toDouble() ?? 0.0,
            minTemp: (tMin[d] as num?)?.toDouble() ?? 0.0,
            precipMm: (precip[d] as num?)?.toDouble() ?? 0.0,
          ));
        }
        parsedDaily[city] = days;

        final hourly = list[i]['hourly'] as Map<String, dynamic>?;
        final Map<String, List<_HourlyForecast>> byDay = {};
        if (hourly != null) {
          final hTimes = (hourly['time'] as List).cast<String>();
          final hCodes = (hourly['weathercode'] as List);
          final hTemps = (hourly['temperature_2m'] as List);
          final hPrecip = (hourly['precipitation'] as List);

          for (int h = 0; h < hTimes.length; h++) {
            final full = hTimes[h];
            final split = full.split('T');
            if (split.length == 2) {
              final dayKey = split[0];
              final hourStr = split[1];
              byDay.putIfAbsent(dayKey, () => []).add(_HourlyForecast(
                    hourStr: hourStr,
                    weatherCode: (hCodes[h] as num?)?.toInt() ?? 0,
                    temp: (hTemps[h] as num?)?.toDouble() ?? 0.0,
                    precipMm: (hPrecip[h] as num?)?.toDouble() ?? 0.0,
                  ));
            }
          }
        }
        parsedHourly[city] = byDay;
      }

      if (mounted) {
        setState(() {
          _cityForecasts = parsedDaily;
          _cityHourlyForecasts = parsedHourly;
          _isLoadingForecast = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingForecast = false;
          _errorMsg = 'Hava durumu tahmini alınamadı: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedRegion != null) {
      return _buildRegionCitiesForecastView(_selectedRegion!);
    }
    return _buildRegionsGridView();
  }

  Widget _buildRegionsGridView() {
    final regionNames = _regionsCities.keys.toList();

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.cloud_outlined,
                    color: Color(0xFF38BDF8), size: 20),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bölgesel Hava Durumu & 7 Günlük Yağış Tahmini',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Önümüzdeki 7 günlük il bazlı sıcaklık ve yağış tahminlerini incelemek için bir bölge seçin.',
            style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth >= 1000
                    ? 4
                    : constraints.maxWidth >= 650
                        ? 2
                        : 1;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: crossCount == 1 ? 2.8 : 1.85,
                  ),
                  itemCount: regionNames.length,
                  itemBuilder: (context, idx) {
                    final region = regionNames[idx];
                    final cities = _regionsCities[region]!.keys.toList();

                    double sumFill = 0;
                    int cnt = 0;
                    for (final c in cities) {
                      final entry = widget.provincesData[c];
                      if (entry is Map && entry['weighted_fill_pct'] != null) {
                        sumFill +=
                            (entry['weighted_fill_pct'] as num).toDouble();
                        cnt++;
                      }
                    }
                    final avgFill = cnt > 0 ? (sumFill / cnt) : 0.0;

                    return InkWell(
                      onTap: () => _selectRegion(region),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF15202E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF243449)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    region,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E3A5F),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${cities.length} İl',
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              cities.take(5).join(', ') +
                                  (cities.length > 5 ? '...' : ''),
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Ort. Baraj Doluluğu: %${avgFill.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 11,
                                  ),
                                ),
                                const Row(
                                  children: [
                                    Text(
                                      '7 Günlük Tahmin',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios,
                                        size: 11, color: Color(0xFF38BDF8)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionCitiesForecastView(String regionName) {
    final cityNames = _regionsCities[regionName]!.keys.toList();

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _selectedRegion = null),
                icon: const Icon(Icons.arrow_back,
                    size: 16, color: Color(0xFF38BDF8)),
                label: const Text(
                  'Bölgeler',
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$regionName — 7 Günlük Tahmin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoadingForecast)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF0EA5E9)),
                    SizedBox(height: 12),
                    Text(
                      '7 günlük ve saatlik tahminler çekiliyor...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_errorMsg != null)
            Expanded(
              child: Center(
                child: Text(_errorMsg!,
                    style: const TextStyle(color: Color(0xFFEF4444))),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: cityNames.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final city = cityNames[idx];
                  final days = _cityForecasts[city] ?? [];
                  final total7dPrecip =
                      days.fold<double>(0.0, (sum, d) => sum + d.precipMm);
                  final selectedDate = _selectedDayByCity[city];
                  final hourlyList = selectedDate != null
                      ? (_cityHourlyForecasts[city]?[selectedDate] ?? [])
                      : <_HourlyForecast>[];

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15202E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF243449)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on,
                                    color: Color(0xFF38BDF8), size: 17),
                                const SizedBox(width: 4),
                                Text(
                                  city,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: total7dPrecip >= 15
                                    ? const Color(0xFF1E3A5F)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '7 Gün Yağış: ${total7dPrecip.toStringAsFixed(1)} mm',
                                style: TextStyle(
                                  color: total7dPrecip >= 15
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _HorizontalArrowScroller(
                          height: 126,
                          scrollStep: 230,
                          children: days.map((d) {
                            final isSelected = selectedDate == d.dateStr;
                            return _buildDayForecastChip(
                              d,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedDayByCity.remove(city);
                                  } else {
                                    _selectedDayByCity[city] = d.dateStr;
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        if (selectedDate != null && hourlyList.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B111A),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFF1E3A5F)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 14,
                                              color: Color(0xFF38BDF8)),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              '$city — ${_formatShortDateTr(selectedDate)} Saatlik',
                                              style: const TextStyle(
                                                color: Color(0xFF38BDF8),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setState(
                                          () => _selectedDayByCity.remove(city)),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(Icons.close,
                                            size: 16,
                                            color: Color(0xFF64748B)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _HorizontalArrowScroller(
                                  height: 112,
                                  scrollStep: 250,
                                  children: hourlyList
                                      .map((h) => _buildHourlyChip(h))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayForecastChip(_DailyForecast d,
      {required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF172B44)
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : const Color(0xFF1E293B),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatShortDateTr(d.dateStr),
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Icon(
              _weatherIcon(d.weatherCode),
              color: _weatherIconColor(d.weatherCode),
              size: 20,
            ),
            const SizedBox(height: 3),
            Text(
              _weatherLabelTr(d.weatherCode),
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 9.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              '${d.maxTemp.round()}° / ${d.minTemp.round()}°',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.water_drop,
                    size: 10, color: Color(0xFF38BDF8)),
                const SizedBox(width: 2),
                Text(
                  '${d.precipMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyChip(_HourlyForecast h) {
    return Container(
      width: 74,
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            h.hourStr,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            _weatherIcon(h.weatherCode),
            color: _weatherIconColor(h.weatherCode),
            size: 17,
          ),
          const SizedBox(height: 3),
          Text(
            _weatherLabelTr(h.weatherCode),
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 8.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            '${h.temp.round()}°',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${h.precipMm.toStringAsFixed(1)} mm',
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortDateTr(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final dt = DateTime.tryParse(isoDate);
    const daysTr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final dayName = dt != null ? daysTr[dt.weekday - 1] : '';
    return '${parts[2]}.${parts[1]} $dayName';
  }

  String _weatherLabelTr(int code) {
    if (code <= 1) return 'Güneşli';
    if (code == 2) return 'Parçalı Bulutlu';
    if (code == 3) return 'Kapalı';
    if (code <= 48) return 'Sisli';
    if (code <= 57) return 'Çiseleme';
    if (code <= 67) return 'Yağmurlu';
    if (code <= 77) return 'Karlı';
    if (code <= 82) return 'Sağanak';
    if (code <= 86) return 'Kar Sağanağı';
    return 'Gök Gürültülü';
  }

  IconData _weatherIcon(int code) {
    if (code <= 1) return Icons.wb_sunny;
    if (code == 2) return Icons.wb_sunny_outlined;
    if (code == 3) return Icons.wb_cloudy;
    if (code <= 48) return Icons.foggy;
    if (code <= 67 || (code >= 80 && code <= 82)) return Icons.grain;
    if (code <= 77 || (code >= 85 && code <= 86)) return Icons.ac_unit;
    return Icons.thunderstorm;
  }

  Color _weatherIconColor(int code) {
    if (code <= 2) return const Color(0xFFFBBF24);
    if (code == 3) return const Color(0xFF94A3B8);
    if (code <= 67 || (code >= 80 && code <= 82)) return const Color(0xFF38BDF8);
    if (code <= 77) return const Color(0xFFE2E8F0);
    return const Color(0xFFA855F7);
  }
}

class _HorizontalArrowScroller extends StatefulWidget {
  final List<Widget> children;
  final double height;
  final double scrollStep;

  const _HorizontalArrowScroller({
    required this.children,
    required this.height,
    required this.scrollStep,
  });

  @override
  State<_HorizontalArrowScroller> createState() =>
      _HorizontalArrowScrollerState();
}

class _HorizontalArrowScrollerState extends State<_HorizontalArrowScroller> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          _arrowBtn(Icons.chevron_left, () => _scrollBy(-widget.scrollStep)),
          const SizedBox(width: 4),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: widget.children,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _arrowBtn(Icons.chevron_right, () => _scrollBy(widget.scrollStep)),
        ],
      ),
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 26,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF243449)),
          ),
          child: Icon(icon, color: const Color(0xFF38BDF8), size: 18),
        ),
      ),
    );
  }
}

class _DailyForecast {
  final String dateStr;
  final int weatherCode;
  final double maxTemp;
  final double minTemp;
  final double precipMm;

  _DailyForecast({
    required this.dateStr,
    required this.weatherCode,
    required this.maxTemp,
    required this.minTemp,
    required this.precipMm,
  });
}

class _HourlyForecast {
  final String hourStr;
  final int weatherCode;
  final double temp;
  final double precipMm;

  _HourlyForecast({
    required this.hourStr,
    required this.weatherCode,
    required this.temp,
    required this.precipMm,
  });
}

class _ProvinceHydroMetrics {
  final String provinceName;
  final int sourceCount;
  final double fillPct;
  final double waterStressPct;
  final double pollutionPct;
  final double rawWaterRiskPct;
  final String rainfallText;
  final String aiNote;

  _ProvinceHydroMetrics({
    required this.provinceName,
    required this.sourceCount,
    required this.fillPct,
    required this.waterStressPct,
    required this.pollutionPct,
    required this.rawWaterRiskPct,
    required this.rainfallText,
    required this.aiNote,
  });
}

class _RadialMetricCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double percentage;
  final Color ringColor;

  const _RadialMetricCard({
    required this.title,
    required this.subtitle,
    required this.percentage,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15202E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF243449)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF8A9BB2), fontSize: 10),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _CircularRingPainter(
                percentage: percentage,
                color: ringColor,
              ),
              child: Center(
                child: Text(
                  '%${percentage.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularRingPainter extends CustomPainter {
  final double percentage;
  final Color color;

  _CircularRingPainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;

    final trackPaint = Paint()
      ..color = const Color(0xFF223146)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweepAngle = 2 * math.pi * (percentage.clamp(0.0, 100.0) / 100.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularRingPainter oldDelegate) {
    return oldDelegate.percentage != percentage || oldDelegate.color != color;
  }
}