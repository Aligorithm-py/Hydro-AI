import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class HydroReportsView extends StatefulWidget {
  final Map<String, dynamic> provincesData;
  final double turkeyAvgFill;
  final int totalSources;

  const HydroReportsView({
    super.key,
    required this.provincesData,
    required this.turkeyAvgFill,
    required this.totalSources,
  });

  @override
  State<HydroReportsView> createState() => _HydroReportsViewState();
}

class _HydroReportsViewState extends State<HydroReportsView> {
  String _searchQuery = '';
  String _statusFilter = 'Tümü';
  String _sortBy = 'Doluluk (Artan)';

  bool _isLoadingWaves = true;
  List<_SynopticWaveAlert> _waveBulletins = [];
  List<_WaveChartPoint> _waveChartPoints = [];

  @override
  void initState() {
    super.initState();
    _fetchSynopticWaveData();
  }

  /// Türkiye'nin stratejik meteorolojik giriş kapılarından canlı veri çekerek
  /// hava dalgası bültenleri ve 7 günlük dalga grafiği verisi üretir.
  Future<void> _fetchSynopticWaveData() async {
    // 1: Edirne/İstanbul (Balkan/Batı Girişi)
    // 2: İzmir (Ege Kıyı Cephesi)
    // 3: Ankara (İç Anadolu Merkezi)
    // 4: Trabzon (Karadeniz/Kafkasya Hattı)
    // 5: Şanlıurfa (Güneydoğu/Basra Sıcak Hava Hattı)
    // 6: Ağrı/Van (Doğu/Orta Asya Karasal Hattı)
    const lats = '41.01,38.42,39.93,41.00,37.16,39.72';
    const lons = '28.98,27.13,32.86,39.72,38.80,43.05';

    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lats&longitude=$lons'
      '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,windspeed_10m_max'
      '&forecast_days=7&timezone=Europe%2FIstanbul',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final decoded = json.decode(res.body) as List<dynamic>;

      double westPrecip = 0;
      double eastPrecip = 0;
      double southEastMaxTemp = 0;
      double northEastMinTemp = 99;
      double maxWind = 0;

      final List<String> dates =
          (decoded[0]['daily']['time'] as List).cast<String>();
      final List<double> dailyAvgRain = List.filled(dates.length, 0.0);
      final List<double> dailyAvgTemp = List.filled(dates.length, 0.0);

      for (int locIdx = 0; locIdx < decoded.length; locIdx++) {
        final daily = decoded[locIdx]['daily'] as Map<String, dynamic>;
        final pList = (daily['precipitation_sum'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
        final tMaxList = (daily['temperature_2m_max'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
        final tMinList = (daily['temperature_2m_min'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
        final wList = (daily['windspeed_10m_max'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();

        final sum7d = pList.fold(0.0, (a, b) => a + b);
        if (locIdx == 0 || locIdx == 1) westPrecip += sum7d / 2;
        if (locIdx == 3 || locIdx == 5) eastPrecip += sum7d / 2;
        if (locIdx == 4) {
          southEastMaxTemp = tMaxList.reduce(math.max);
        }
        if (locIdx == 5) {
          northEastMinTemp = tMinList.reduce(math.min);
        }
        maxWind = math.max(maxWind, wList.reduce(math.max));

        for (int d = 0; d < dates.length; d++) {
          dailyAvgRain[d] += pList[d] / decoded.length;
          dailyAvgTemp[d] +=
              ((tMaxList[d] + tMinList[d]) / 2) / decoded.length;
        }
      }

      final chartPts = <_WaveChartPoint>[];
      for (int d = 0; d < dates.length; d++) {
        final parts = dates[d].split('-');
        final label = parts.length == 3 ? '${parts[2]}.${parts[1]}' : dates[d];
        chartPts.add(_WaveChartPoint(
          dayLabel: label,
          avgPrecipMm: dailyAvgRain[d],
          avgTempC: dailyAvgTemp[d],
        ));
      }

      final bulletins = <_SynopticWaveAlert>[];

      // 1. Batı -> Doğu Yağış Dalgası Analizi
      if (westPrecip >= 12.0 || eastPrecip >= 12.0) {
        final direction = westPrecip >= eastPrecip
            ? 'Batıdan Doğuya İlerleyen Yağış Cephesi'
            : 'Doğu ve Karadeniz Hattında Yoğun Yağış Dalgası';
        bulletins.add(_SynopticWaveAlert(
          title: direction,
          tag: 'YAĞIŞ CEPHESİ',
          tagColor: const Color(0xFF0EA5E9),
          icon: Icons.water_drop,
          summary:
              'Marmara ve Ege girişinde 7 günlük ortalama ${westPrecip.toStringAsFixed(1)} mm, Doğu hattında ${eastPrecip.toStringAsFixed(1)} mm yağış kütlesi tespit edildi. Baraj havzalarına yüzey akışı katkısı bekleniyor.',
        ));
      } else {
        bulletins.add(_SynopticWaveAlert(
          title: 'Yüksek Basınç Etkisi: Yağışsız & Durgun Periyot',
          tag: 'KURAKLIK RİSKİ',
          tagColor: const Color(0xFFF59E0B),
          icon: Icons.wb_sunny_outlined,
          summary:
              'Önümüzdeki 7 gün boyunca ülke genelinde yağış geçişleri zayıf (Batı: ${westPrecip.toStringAsFixed(1)} mm, Doğu: ${eastPrecip.toStringAsFixed(1)} mm). Rezervuarlarda doğal beslenme düşük kalacak.',
        ));
      }

      // 2. Sıcak / Soğuk Hava Dalgası Analizi
      if (southEastMaxTemp >= 24.0) {
        bulletins.add(_SynopticWaveAlert(
          title: 'Orta Asya / Basra Kaynaklı Sıcak Hava Dalgası',
          tag: 'SICAK DALGA',
          tagColor: const Color(0xFFEF4444),
          icon: Icons.thermostat,
          summary:
              'Güneydoğu ve iç kesimlerde maksimum sıcaklıkların ${southEastMaxTemp.toStringAsFixed(1)}°C bandına ulaşması öngörülüyor. Açık su yüzeylerinde buharlaşma kaybı hızlanabilir.',
        ));
      } else if (northEastMinTemp <= 2.0) {
        bulletins.add(_SynopticWaveAlert(
          title: 'Balkanlar & Kafkasya Üzerinden Soğuk Hava Dalgası',
          tag: 'SOĞUK DALGA',
          tagColor: const Color(0xFF38BDF8),
          icon: Icons.ac_unit,
          summary:
              'Doğu ve yüksek rakımlı havzalarda gece sıcaklıkları ${northEastMinTemp.toStringAsFixed(1)}°C seviyesine geriliyor. Yüksek havzalarda yağışların kar formunda depolanması bekleniyor.',
        ));
      } else {
        bulletins.add(_SynopticWaveAlert(
          title: 'Mevsim Normallerinde Ilıman Hava Akımı',
          tag: 'DENGELİ SEYİR',
          tagColor: const Color(0xFF10B981),
          icon: Icons.air,
          summary:
              'Sıcaklıklar ${northEastMinTemp.toStringAsFixed(1)}°C ile ${southEastMaxTemp.toStringAsFixed(1)}°C aralığında seyrediyor. Ani buharlaşma veya don kaynaklı rezerv baskısı öngörülmüyor.',
        ));
      }

      // 3. Rüzgar & Buharlaşma / Taşınım Notu
      if (maxWind >= 35.0) {
        bulletins.add(_SynopticWaveAlert(
          title: 'Kuvvetli Rüzgâr & Cephe Geçiş Uyarısı',
          tag: 'RÜZGÂR AKIMI',
          tagColor: const Color(0xFFA855F7),
          icon: Icons.storm,
          summary:
              'Bölgesel rüzgâr hızlarının ${maxWind.toStringAsFixed(0)} km/sa seviyesine çıkması bekleniyor. Bulut sistemlerinin iç bölgelere taşınımı hızlanacak.',
        ));
      }

      if (mounted) {
        setState(() {
          _waveBulletins = bulletins;
          _waveChartPoints = chartPts;
          _isLoadingWaves = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingWaves = false;
          _waveBulletins = [
            _SynopticWaveAlert(
              title: 'Batıdan Doğuya Nemli Hava Akımı (Çevrimdışı Özet)',
              tag: 'SİNOPTİK ANALİZ',
              tagColor: const Color(0xFF0EA5E9),
              icon: Icons.cloud_sync,
              summary:
                  'Canlı atmosfer akış verisine şu an ulaşılamadı. Mevcut uydu doluluk verileri üzerinden havza bazlı değerlendirme aktif.',
            ),
          ];
        });
      }
    }
  }

  List<_ProvinceReportRow> _buildFilteredRows() {
    final rows = <_ProvinceReportRow>[];

    widget.provincesData.forEach((name, val) {
      if (val is Map) {
        final fill = (val['weighted_fill_pct'] as num?)?.toDouble() ?? 0.0;
        final stress = (val['water_stress_pct'] as num?)?.toDouble() ??
            (100.0 - fill * 0.85).clamp(8.0, 98.0);
        final poll = (val['pollution_pct'] as num?)?.toDouble() ?? 24.0;
        final rawRisk =
            (val['raw_water_risk_pct'] as num?)?.toDouble() ?? 42.0;
        final rain7d = (val['rainfall_7d_mm'] as num?)?.toDouble() ?? 0.0;
        final sources = (val['source_count'] as num?)?.toInt() ?? 0;

        String status;
        if (fill < 20) {
          status = 'Kritik';
        } else if (fill < 40) {
          status = 'Düşük';
        } else if (fill < 65) {
          status = 'Orta';
        } else {
          status = 'İyi / Yüksek';
        }

        rows.add(_ProvinceReportRow(
          provinceName: name,
          fillPct: fill,
          waterStressPct: stress,
          pollutionPct: poll,
          rawRiskPct: rawRisk,
          rainfall7dMm: rain7d,
          sourceCount: sources,
          status: status,
        ));
      }
    });

    final filtered = rows.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.provinceName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus =
          _statusFilter == 'Tümü' || r.status == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    switch (_sortBy) {
      case 'Doluluk (Azalan)':
        filtered.sort((a, b) => b.fillPct.compareTo(a.fillPct));
        break;
      case 'Su Stresi (Yüksek)':
        filtered.sort((a, b) => b.waterStressPct.compareTo(a.waterStressPct));
        break;
      case 'Kirlilik (Yüksek)':
        filtered.sort((a, b) => b.pollutionPct.compareTo(a.pollutionPct));
        break;
      case '7 Gün Yağış':
        filtered.sort((a, b) => b.rainfall7dMm.compareTo(a.rainfall7dMm));
        break;
      case 'Doluluk (Artan)':
      default:
        filtered.sort((a, b) => a.fillPct.compareTo(b.fillPct));
        break;
    }

    return filtered;
  }

  void _copyCsvReport(List<_ProvinceReportRow> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Il;Durum;Doluluk_Orani(%);Su_Stresi(%);Kirlilik(%);Aritmasiz_Risk(%);7Gun_Yagis(mm);Kaynak_Sayisi');
    for (final r in rows) {
      buffer.writeln(
        '${r.provinceName};${r.status};${r.fillPct.toStringAsFixed(1)};${r.waterStressPct.toStringAsFixed(1)};${r.pollutionPct.toStringAsFixed(1)};${r.rawRiskPct.toStringAsFixed(1)};${r.rainfall7dMm.toStringAsFixed(1)};${r.sourceCount}',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E3A5F),
        content: Text(
          '${rows.length} ilin raporu CSV formatında panoya kopyalandı!',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRows = _buildFilteredRows();
    final criticalCount = allRows.where((r) => r.fillPct < 20).length;

    _ProvinceReportRow? highestProv;
    _ProvinceReportRow? lowestProv;
    if (allRows.isNotEmpty) {
      final sortedByFill = [...allRows]
        ..sort((a, b) => a.fillPct.compareTo(b.fillPct));
      lowestProv = sortedByFill.first;
      highestProv = sortedByFill.last;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Başlık ve CSV Kopyala Butonu
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ulusal Su Rezervi & Sinoptik Hava Dalgası Raporu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '81 İl baraj doluluk karşılaştırması, kritik uyarılar ve atmosferik dalga akışları',
                    style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 12),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _copyCsvReport(allRows),
                icon: const Icon(Icons.copy_all, size: 16),
                label: const Text('CSV Raporu Kopyala',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Üst Özet KPI Kartları
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final kpiCards = [
                _buildKpiCard(
                  title: 'Türkiye Ort. Doluluk',
                  value: '%${widget.turkeyAvgFill.toStringAsFixed(1)}',
                  sub: '${widget.totalSources} aktif su kaynağı',
                  accent: const Color(0xFF0EA5E9),
                  icon: Icons.water,
                ),
                _buildKpiCard(
                  title: 'Kritik Seviye İl',
                  value: '$criticalCount İl',
                  sub: '%20 doluluk altı alarm',
                  accent: const Color(0xFFEF4444),
                  icon: Icons.warning_amber_rounded,
                ),
                _buildKpiCard(
                  title: 'En Yüksek Rezerv',
                  value: highestProv != null
                      ? '${highestProv.provinceName} (%${highestProv.fillPct.toStringAsFixed(0)})'
                      : '-',
                  sub: 'En güvenli havza durumu',
                  accent: const Color(0xFF10B981),
                  icon: Icons.trending_up,
                ),
                _buildKpiCard(
                  title: 'En Düşük Rezerv',
                  value: lowestProv != null
                      ? '${lowestProv.provinceName} (%${lowestProv.fillPct.toStringAsFixed(0)})'
                      : '-',
                  sub: 'Acil tasarruf önceliği',
                  accent: const Color(0xFFF59E0B),
                  icon: Icons.trending_down,
                ),
              ];

              if (isNarrow) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.85,
                  children: kpiCards,
                );
              }
              return Row(
                children: kpiCards
                    .map((c) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: c,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),

          // 2. Sinoptik Hava Dalgaları & Cephe Hareketleri Bülteni + Dalga Grafiği
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
                const Row(
                  children: [
                    Icon(Icons.waves, color: Color(0xFF38BDF8), size: 19),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Atmosferik Hava Dalgaları & Cephe Hareketleri Bülteni',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Balkanlar, Ege, Basra ve Orta Asya koridorlarından Türkiye’ye yönelen sıcaklık ve yağış dalgalarının canlı analizi',
                  style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 11.5),
                ),
                const SizedBox(height: 12),
                if (_isLoadingWaves)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF0EA5E9)),
                    ),
                  )
                else ...[
                  // Bülten Kartları
                  ..._waveBulletins.map((b) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: b.tagColor.withOpacity(0.45)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: b.tagColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(b.icon, color: b.tagColor, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        b.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: b.tagColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          b.tag,
                                          style: TextStyle(
                                            color: b.tagColor,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    b.summary,
                                    style: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),

                  // 7 Günlük Hava Dalgası Grafiği
                  if (_waveChartPoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B111A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '7 Günlük Ulusal Sıcaklık & Yağış Dalgası Eğrisi',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle,
                                      size: 8, color: Color(0xFF38BDF8)),
                                  SizedBox(width: 4),
                                  Text('Yağış Dalgası (mm)',
                                      style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 10.5)),
                                  SizedBox(width: 10),
                                  Icon(Icons.circle,
                                      size: 8, color: Color(0xFFF97316)),
                                  SizedBox(width: 4),
                                  Text('Sıcaklık Dalgası (°C)',
                                      style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 10.5)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 145,
                            width: double.infinity,
                            child: CustomPaint(
                              painter:
                                  _WeatherWaveChartPainter(_waveChartPoints),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Filtrelenebilir ve Sıralanabilir 81 İl Rapor Listesi
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
                const Text(
                  'İl Bazlı Detaylı Doluluk ve Risk Tablosu',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 10),
                // Arama ve Sıralama Çubuğu
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 38,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'İl ara (örn. İstanbul, Konya)...',
                          hintStyle: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 12),
                          prefixIcon: const Icon(Icons.search,
                              size: 17, color: Color(0xFF8A9BB2)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF243449)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF243449)),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF243449)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortBy,
                          dropdownColor: const Color(0xFF1C293B),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12.5),
                          items: const [
                            DropdownMenuItem(
                                value: 'Doluluk (Artan)',
                                child: Text('Sırala: Doluluk (En Düşük)')),
                            DropdownMenuItem(
                                value: 'Doluluk (Azalan)',
                                child: Text('Sırala: Doluluk (En Yüksek)')),
                            DropdownMenuItem(
                                value: 'Su Stresi (Yüksek)',
                                child: Text('Sırala: Su Stresi')),
                            DropdownMenuItem(
                                value: 'Kirlilik (Yüksek)',
                                child: Text('Sırala: Kirlilik Oranı')),
                            DropdownMenuItem(
                                value: '7 Gün Yağış',
                                child: Text('Sırala: 7 Günlük Yağış')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _sortBy = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Durum Filtre Çipleri
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'Tümü',
                      'Kritik',
                      'Düşük',
                      'Orta',
                      'İyi / Yüksek'
                    ].map((status) {
                      final active = _statusFilter == status;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(status),
                          selected: active,
                          selectedColor: const Color(0xFF1E3A5F),
                          backgroundColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: active
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF94A3B8),
                            fontSize: 11.5,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.normal,
                          ),
                          onSelected: (_) =>
                              setState(() => _statusFilter = status),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // Liste Satırları
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: allRows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final r = allRows[idx];
                    final statusColor = _statusColor(r.fillPct);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${idx + 1}. ${r.provinceName}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      r.status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '%${r.fillPct.toStringAsFixed(1)} Doluluk',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (r.fillPct / 100.0).clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: const Color(0xFF1E293B),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(statusColor),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              _miniMetric('Su Stresi',
                                  '%${r.waterStressPct.toStringAsFixed(0)}'),
                              _miniMetric('Kirlilik',
                                  '%${r.pollutionPct.toStringAsFixed(0)}'),
                              _miniMetric('Arıtmasız Risk',
                                  '%${r.rawRiskPct.toStringAsFixed(0)}'),
                              _miniMetric('7G Yağış',
                                  '${r.rainfall7dMm.toStringAsFixed(1)} mm'),
                              _miniMetric('Kaynak', '${r.sourceCount} adet'),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String sub,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF15202E),
        borderRadius: BorderRadius.circular(12),
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
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: accent, size: 16),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sub,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String val) {
    return Text(
      '$label: $val',
      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
    );
  }

  Color _statusColor(double pct) {
    if (pct < 20) return const Color(0xFFEF4444);
    if (pct < 40) return const Color(0xFFF97316);
    if (pct < 65) return const Color(0xFFEAB308);
    if (pct < 85) return const Color(0xFF0EA5E9);
    return const Color(0xFF10B981);
  }
}

class _SynopticWaveAlert {
  final String title;
  final String tag;
  final Color tagColor;
  final IconData icon;
  final String summary;

  _SynopticWaveAlert({
    required this.title,
    required this.tag,
    required this.tagColor,
    required this.icon,
    required this.summary,
  });
}

class _WaveChartPoint {
  final String dayLabel;
  final double avgPrecipMm;
  final double avgTempC;

  _WaveChartPoint({
    required this.dayLabel,
    required this.avgPrecipMm,
    required this.avgTempC,
  });
}

class _ProvinceReportRow {
  final String provinceName;
  final double fillPct;
  final double waterStressPct;
  final double pollutionPct;
  final double rawRiskPct;
  final double rainfall7dMm;
  final int sourceCount;
  final String status;

  _ProvinceReportRow({
    required this.provinceName,
    required this.fillPct,
    required this.waterStressPct,
    required this.pollutionPct,
    required this.rawRiskPct,
    required this.rainfall7dMm,
    required this.sourceCount,
    required this.status,
  });
}

/// 7 Günlük Sıcaklık ve Yağış Dalgası Eğrisi Çizicisi
class _WeatherWaveChartPainter extends CustomPainter {
  final List<_WaveChartPoint> points;

  _WeatherWaveChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const leftPad = 14.0;
    const rightPad = 14.0;
    const topPad = 18.0;
    const bottomPad = 24.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // Arka plan yatay kılavuz çizgileri
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = topPad + (chartH / 3) * i;
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
    }

    final maxRain = math.max(
        5.0, points.map((p) => p.avgPrecipMm).reduce(math.max) * 1.25);
    final minTemp = points.map((p) => p.avgTempC).reduce(math.min) - 3.0;
    final maxTemp =
        math.max(minTemp + 5.0, points.map((p) => p.avgTempC).reduce(math.max) + 3.0);

    final rainOffsets = <Offset>[];
    final tempOffsets = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final x = leftPad + (chartW / (points.length - 1)) * i;
      final rainNorm = (points[i].avgPrecipMm / maxRain).clamp(0.0, 1.0);
      final tempNorm =
          ((points[i].avgTempC - minTemp) / (maxTemp - minTemp)).clamp(0.0, 1.0);

      rainOffsets.add(Offset(x, topPad + chartH * (1.0 - rainNorm)));
      tempOffsets.add(Offset(x, topPad + chartH * (1.0 - tempNorm)));
    }

    // Yağış Dalgası Alan Dolgusu + Yumuşak Eğri
    final rainPath = _buildSmoothPath(rainOffsets);
    final areaPath = Path.from(rainPath)
      ..lineTo(rainOffsets.last.dx, topPad + chartH)
      ..lineTo(rainOffsets.first.dx, topPad + chartH)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF38BDF8).withOpacity(0.32),
          const Color(0xFF38BDF8).withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH));

    canvas.drawPath(areaPath, areaPaint);

    final rainStroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..isAntiAlias = true;
    canvas.drawPath(rainPath, rainStroke);

    // Sıcaklık Dalgası Eğrisi
    final tempPath = _buildSmoothPath(tempOffsets);
    final tempStroke = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..isAntiAlias = true;
    canvas.drawPath(tempPath, tempStroke);

    // Noktalar ve Etiketler
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(
          rainOffsets[i], 3.5, Paint()..color = const Color(0xFF38BDF8));
      canvas.drawCircle(
          tempOffsets[i], 3.5, Paint()..color = const Color(0xFFF97316));

      // Tarih etiketi
      _drawText(
        canvas,
        points[i].dayLabel,
        Offset(rainOffsets[i].dx, topPad + chartH + 6),
        const Color(0xFF94A3B8),
        9.5,
      );

      // Sıcaklık değeri etiketi
      _drawText(
        canvas,
        '${points[i].avgTempC.round()}°',
        Offset(tempOffsets[i].dx, tempOffsets[i].dy - 14),
        const Color(0xFFFDBA74),
        9.0,
      );
    }
  }

  Path _buildSmoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final ctrlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(ctrlX, p0.dy, ctrlX, p1.dy, p1.dx, p1.dy);
    }
    return path;
  }

  void _drawText(
      Canvas canvas, String text, Offset centerTop, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centerTop.dx - tp.width / 2, centerTop.dy));
  }

  @override
  bool shouldRepaint(covariant _WeatherWaveChartPainter oldDelegate) => true;
}