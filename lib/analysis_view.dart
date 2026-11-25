import 'dart:math' as math;
import 'package:flutter/material.dart';

class HydroAnalysisView extends StatefulWidget {
  final Map<String, dynamic> provincesData;
  final double turkeyAvgFill;
  final int totalSources;

  const HydroAnalysisView({
    super.key,
    required this.provincesData,
    required this.turkeyAvgFill,
    required this.totalSources,
  });

  @override
  State<HydroAnalysisView> createState() => _HydroAnalysisViewState();
}

class _HydroAnalysisViewState extends State<HydroAnalysisView> {
  // Simülatör Parametreleri
  String _simProvince = 'Türkiye Geneli';
  double _rainChangePct = 0.0; // -50% ile +50%
  double _tempAnomalyC = 0.0; // 0°C ile +4°C
  double _savingRatePct = 10.0; // 0% ile 30%

  // İki İl Karşılaştırma Seçimleri
  String _compareCityA = 'İstanbul';
  String _compareCityB = 'Konya';

  List<String> get _sortedProvinceNames {
    final names = widget.provincesData.keys.toList()..sort();
    return names;
  }

  _SimProvinceStats _getStats(String name) {
    if (name == 'Türkiye Geneli' || widget.provincesData.isEmpty) {
      double sumStress = 0, sumPoll = 0, sumRaw = 0, sumRain = 0;
      int n = 0;
      for (final val in widget.provincesData.values) {
        if (val is Map && val['weighted_fill_pct'] != null) {
          final f = (val['weighted_fill_pct'] as num).toDouble();
          sumStress += (val['water_stress_pct'] as num?)?.toDouble() ??
              (100.0 - f * 0.85).clamp(8.0, 98.0);
          sumPoll += (val['pollution_pct'] as num?)?.toDouble() ?? 24.0;
          sumRaw += (val['raw_water_risk_pct'] as num?)?.toDouble() ?? 42.0;
          sumRain += (val['rainfall_7d_mm'] as num?)?.toDouble() ?? 6.5;
          n++;
        }
      }
      return _SimProvinceStats(
        name: 'Türkiye Geneli',
        fillPct: widget.turkeyAvgFill,
        waterStressPct: n > 0 ? sumStress / n : 48.0,
        pollutionPct: n > 0 ? sumPoll / n : 24.0,
        rawRiskPct: n > 0 ? sumRaw / n : 42.0,
        rainfall7dMm: n > 0 ? sumRain / n : 6.5,
        sourceCount: widget.totalSources,
      );
    }

    final entry = widget.provincesData[name] as Map<String, dynamic>?;
    final fill =
        (entry?['weighted_fill_pct'] as num?)?.toDouble() ?? widget.turkeyAvgFill;
    return _SimProvinceStats(
      name: name,
      fillPct: fill,
      waterStressPct: (entry?['water_stress_pct'] as num?)?.toDouble() ??
          (100.0 - fill * 0.85).clamp(8.0, 98.0),
      pollutionPct: (entry?['pollution_pct'] as num?)?.toDouble() ?? 24.0,
      rawRiskPct: (entry?['raw_water_risk_pct'] as num?)?.toDouble() ?? 42.0,
      rainfall7dMm: (entry?['rainfall_7d_mm'] as num?)?.toDouble() ?? 5.0,
      sourceCount: (entry?['source_count'] as num?)?.toInt() ?? 4,
    );
  }

  /// Gerçekçi hidrolojik su bütçesi modeli
  _SimulationResult _runProjection(_SimProvinceStats base) {
    const double seasonalNormalPct = 65.0;

    final double baseInflow =
        9.0 + ((base.rainfall7dMm - 8.0) * 0.12).clamp(-2.0, 2.5);
    final double monthlyInflowPct =
        math.max(0.5, baseInflow * (1.0 + _rainChangePct / 100.0));

    const double baseMonthlyConsumptionPct = 10.0;
    final double evapLossPct =
        _tempAnomalyC > 0 ? 1.85 * math.pow(_tempAnomalyC, 1.15) : 0.0;
    final double heatDemandSurgePct = _tempAnomalyC * 0.85;
    final double grossConsumptionPct =
        baseMonthlyConsumptionPct + heatDemandSurgePct;

    final double savedPct = grossConsumptionPct * (_savingRatePct / 100.0);
    final double netConsumptionPct = grossConsumptionPct - savedPct;

    final double netMonthlyDelta =
        monthlyInflowPct - (netConsumptionPct + evapLossPct);

    final d0 = base.fillPct.clamp(0.0, 100.0);
    final d30 = (d0 + netMonthlyDelta).clamp(0.0, 100.0);
    final d60 = (d0 + netMonthlyDelta * 2.0).clamp(0.0, 100.0);
    final d90 = (d0 + netMonthlyDelta * 3.0).clamp(0.0, 100.0);

    // 1) Mevcut rezervi korumak (netMonthlyDelta >= 0) için gereken tasarruf oranı
    final double allowedConsumptionForBalance =
        monthlyInflowPct - evapLossPct;
    double requiredSavingToHoldPct;
    if (allowedConsumptionForBalance >= grossConsumptionPct) {
      requiredSavingToHoldPct = 0.0;
    } else if (allowedConsumptionForBalance <= 0) {
      requiredSavingToHoldPct = 100.0;
    } else {
      requiredSavingToHoldPct =
          ((1.0 - (allowedConsumptionForBalance / grossConsumptionPct)) * 100.0)
              .clamp(0.0, 100.0);
    }

    // 2) 90 gün sonunda mevsim normallerine (%65) ulaşmak veya korumak için gereken tasarruf oranı
    final double target90 = math.max(seasonalNormalPct, d0);
    final double neededMonthlyDelta = (target90 - d0) / 3.0;
    final double allowedConsumptionForNormal =
        monthlyInflowPct - evapLossPct - neededMonthlyDelta;
    double requiredSavingForNormalPct;
    if (allowedConsumptionForNormal >= grossConsumptionPct) {
      requiredSavingForNormalPct = 0.0;
    } else if (allowedConsumptionForNormal <= 0) {
      requiredSavingForNormalPct = 100.0;
    } else {
      requiredSavingForNormalPct =
          ((1.0 - (allowedConsumptionForNormal / grossConsumptionPct)) * 100.0)
              .clamp(0.0, 100.0);
    }

    int? daysToCritical;
    if (d0 <= 15.0) {
      daysToCritical = 0;
    } else if (netMonthlyDelta < -0.1) {
      final dailyLoss = (-netMonthlyDelta) / 30.0;
      daysToCritical = ((d0 - 15.0) / dailyLoss).round().clamp(1, 999);
    }

    return _SimulationResult(
      day0: d0,
      day30: d30,
      day60: d60,
      day90: d90,
      monthlyInflowPct: monthlyInflowPct,
      evapLossPct: evapLossPct,
      netConsumptionPct: netConsumptionPct,
      netMonthlyDelta: netMonthlyDelta,
      daysToCritical: daysToCritical,
      requiredSavingToHoldPct: requiredSavingToHoldPct,
      requiredSavingForNormalPct: requiredSavingForNormalPct,
      seasonalNormalPct: seasonalNormalPct,
    );
  }

  _DetailedScenarioReport _buildDetailedReport(
      _SimProvinceStats stats, _SimulationResult sim) {
    final double totalChange90 = sim.day90 - sim.day0;
    final double extraSavingNeededForHold =
        math.max(0.0, sim.requiredSavingToHoldPct - _savingRatePct);

    String balanceTitle;
    String balanceText;
    Color balanceColor;

    if (sim.netMonthlyDelta < 0 && sim.requiredSavingToHoldPct > 45.0) {
      balanceTitle = 'Tek Başına Tasarruf Yetersiz — Acil Havza Transferi Şart';
      balanceColor = const Color(0xFFEF4444);
      balanceText =
          'Yağışların %${_rainChangePct.abs().round()} azaldığı ve sıcaklığın +${_tempAnomalyC.toStringAsFixed(1)}°C arttığı bu senaryoda, su kaybını tamamen durdurmak için bile %${sim.requiredSavingToHoldPct.toStringAsFixed(0)} düzeyinde olağanüstü kısıtlama gerekiyor. Mevcut %${_savingRatePct.round()} tasarruf oranı ile 90 günde rezerv %${totalChange90.abs().toStringAsFixed(1)} puan eriyor; kademeli su kesintisi ve komşu havza takviyesi planlanmalı.';
    } else if (sim.netMonthlyDelta < 0) {
      balanceTitle =
          'Rezerv Erimesini Durdurmak İçin Tasarruf +%${extraSavingNeededForHold.toStringAsFixed(1)} Artırılmalı';
      balanceColor = const Color(0xFFF59E0B);
      balanceText =
          'Mevcut %${_savingRatePct.round()} tasarruf düzeyi bu iklim baskısını karşılamaya yetmiyor ve 90 günde rezerv %${totalChange90.abs().toStringAsFixed(1)} puan azalıyor. Mevcut doluluk seviyesini (%${sim.day0.toStringAsFixed(1)}) korumak için tasarrufu en az %${sim.requiredSavingToHoldPct.toStringAsFixed(1)} seviyesine çıkarmak gerekiyor.';
    } else if (sim.day90 < sim.seasonalNormalPct) {
      final normalTargetLabel = sim.requiredSavingForNormalPct > 65.0
          ? '%65+ (ek yağış takviyesiyle)'
          : '%${sim.requiredSavingForNormalPct.toStringAsFixed(1)}';
      balanceTitle =
          'Rezerv Toparlanıyor (+%${totalChange90.toStringAsFixed(1)} Puan) — Mevsim Normali Hedefi: %${sim.seasonalNormalPct.round()}';
      balanceColor = const Color(0xFF0EA5E9);
      balanceText =
          'Mevcut %${_savingRatePct.round()} tasarruf oranıyla rezervuar aylık +${sim.netMonthlyDelta.toStringAsFixed(1)} puan artarak 90 günde %${sim.day90.toStringAsFixed(1)} seviyesine yükseliyor. 90 gün sonunda doğrudan %${sim.seasonalNormalPct.round()} mevsim normaline ulaşmak için tasarruf oranının $normalTargetLabel düzeyinde tutulması gerekir.';
    } else {
      balanceTitle = 'Tasarruf Hedefi Yeterli — Rezerv Mevsim Normallerinde';
      balanceColor = const Color(0xFF10B981);
      balanceText =
          'Uygulanan %${_savingRatePct.round()} tasarruf oranı, yağış ve sıcaklık değişimlerinin yarattığı baskıyı dengeliyor. 90 gün sonunda doluluk oranı %${sim.day90.toStringAsFixed(1)} ile güvenli mevsim normallerinin üzerinde seyrediyor.';
    }

    String agriTitle;
    String agriText;
    Color agriColor;

    if (sim.day90 < 30.0 || (_rainChangePct <= -15 && _tempAnomalyC >= 2.0)) {
      agriTitle = 'Yüksek Kuraklık Baskısı: Tarımsal Sulama Kotası Daralacak';
      agriColor = const Color(0xFFEF4444);
      agriText =
          'Bu tablo 90 gün devam ederse barajlardan tarıma ayrılan sulama suyunda %35–50 oranında kısıntıya gidilmesi kaçınılmaz olur. Özellikle su tüketimi yüksek mısır, ayçiçeği, şeker pancarı, çeltik ve açık alan sebze üretiminde %20–30 bandında rekolte kaybı riski doğar; basınçlı damla sulamaya geçilmesi ve kuraklığa dayanıklı hububat ekimine öncelik verilmesi gerekir.';
    } else if (sim.day90 < 50.0 || _tempAnomalyC >= 1.5 || _rainChangePct < 0) {
      agriTitle = 'Orta Düzey Sulama Stresi: Bitki Su Tüketimi Artıyor';
      agriColor = const Color(0xFFF59E0B);
      agriText =
          'Sıcaklık artışı (+${_tempAnomalyC.toStringAsFixed(1)}°C) toprak nemini hızla buharlaştırarak bitkilerin sulama ihtiyacını aylık %${(_tempAnomalyC * 6.5).toStringAsFixed(0)} artırıyor. İkinci ürün ekimlerinin sınırlandırılması ve gece saatlerinde sulama yapılması tarımsal verim kaybını önleyecektir.';
    } else {
      agriTitle = 'Tarımsal Sulama Arzı Güvende — Planlı Üretim Sürdürülebilir';
      agriColor = const Color(0xFF10B981);
      agriText =
          'Rezervuar projeksiyonu tarımsal sulama takvimini kesintisiz karşılayacak düzeyde. Mevcut tasarruf disiplini korunduğu sürece sulu tarım havzalarında rekolte kaybı beklenmiyor.';
    }

    String urbanTitle;
    String urbanText;

    if (sim.day90 < 35.0) {
      urbanTitle = 'Kentsel Şebeke & Yeraltı Suyu Alarmı';
      urbanText =
          'Rezervuar kotasının düşmesiyle birlikte dip savak çekimine yaklaşılır; bu durum ham suda mangan, demir ve alg yoğunluğunu artırarak arıtma maliyetlerini yükseltir. Şebekede gece basınç düşürme ve yeraltı derin kuyularının devreye alınması gerekir.';
    } else if (sim.netMonthlyDelta < 0) {
      urbanTitle = 'Kademeli Rezerv Erimesi & Kayıp-Kaçak Kontrolü';
      urbanText =
          'Aylık net ${sim.netMonthlyDelta.toStringAsFixed(1)} puanlık rezerv kaybı, özellikle yaz pik tüketim aylarında şebeke baskısını artırır. Belediyelerin fiziksel kayıp-kaçak oranını %20 altına çekmesi ve gri su geri kazanımını teşvik etmesi kritik önem taşır.';
    } else {
      urbanTitle = 'Kentsel İçme Suyu Arzı & Ekosistem Dengesi Stabil';
      urbanText =
          'İçme ve kullanma suyu şebekelerinde kesinti riski bulunmuyor; akarsu ekosistemleri için gereken can suyu salınımı tam kapasite sürdürülebilir.';
    }

    return _DetailedScenarioReport(
      balanceTitle: balanceTitle,
      balanceText: balanceText,
      balanceColor: balanceColor,
      agriTitle: agriTitle,
      agriText: agriText,
      agriColor: agriColor,
      urbanTitle: urbanTitle,
      urbanText: urbanText,
    );
  }

  List<_ActionRecommendation> _generateRecommendations(
      _SimProvinceStats stats, _SimulationResult sim) {
    final list = <_ActionRecommendation>[];

    if (sim.day90 < 30.0 || stats.fillPct < 25.0) {
      list.add(_ActionRecommendation(
        priority: 'YÜKSEK ÖNCELİK',
        color: const Color(0xFFEF4444),
        icon: Icons.priority_high,
        title: 'Kademeli Tarımsal & Kentsel Su Kısıtlaması',
        detail:
            '${stats.name} için 90 günlük projeksiyon %${sim.day90.toStringAsFixed(1)} seviyesine işaret ediyor. Park/bahçe sulamalarının durdurulması ve basınç regülasyonu ile şebeke kayıp-kaçaklarının %15 azaltılması önerilir.',
      ));
    }

    if (stats.pollutionPct >= 30.0 || stats.rawRiskPct >= 45.0) {
      list.add(_ActionRecommendation(
        priority: 'KALİTE & ARITMA',
        color: const Color(0xFFF59E0B),
        icon: Icons.science_outlined,
        title: 'İleri Ozonlama & Aktif Karbon Arıtma Takviyesi',
        detail:
            'Bulanıklık ve sediman oranı (%${stats.pollutionPct.toStringAsFixed(0)}) yüksek seyrediyor. Dip su çekim kotunun yükseltilmesi ve koagülasyon dozajının artırılması gerekir.',
      ));
    }

    if (_tempAnomalyC >= 2.0) {
      list.add(_ActionRecommendation(
        priority: 'BUHARLAŞMA KONTROLÜ',
        color: const Color(0xFFF97316),
        icon: Icons.wb_sunny,
        title: 'Açık Yüzey Buharlaşma Önlemleri',
        detail:
            '+${_tempAnomalyC.toStringAsFixed(1)}°C sıcaklık artışı senaryosunda açık rezervuarlarda aylık %${sim.evapLossPct.toStringAsFixed(1)} buharlaşma kaybı oluşur. Yüzer güneş paneli (FPV) örtüleme değerlendirilmelidir.',
      ));
    }

    if (list.isEmpty) {
      list.add(_ActionRecommendation(
        priority: 'DENGELİ YÖNETİM',
        color: const Color(0xFF10B981),
        icon: Icons.verified_outlined,
        title: 'Mevcut Rezerv Koruma & Yeraltı Besleme',
        detail:
            '${stats.name} havzasında rezerv dengesi stabil. Yağışlı dönem akışlarının yeraltı akifer besleme kuyularına yönlendirilmesi uzun vadeli güvenliği artıracaktır.',
      ));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final provinceNames = _sortedProvinceNames;
    final dropdownItems = ['Türkiye Geneli', ...provinceNames];

    if (provinceNames.isNotEmpty) {
      if (!provinceNames.contains(_compareCityA)) {
        _compareCityA = provinceNames.first;
      }
      if (!provinceNames.contains(_compareCityB)) {
        _compareCityB =
            provinceNames.length > 1 ? provinceNames[1] : provinceNames.first;
      }
    }

    final simStats = _getStats(_simProvince);
    final simResult = _runProjection(simStats);
    final detailedReport = _buildDetailedReport(simStats, simResult);
    final recommendations = _generateRecommendations(simStats, simResult);

    final statsA = _getStats(_compareCityA);
    final statsB = _getStats(_compareCityB);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hydro AI Karar Destek & Gelecek Simülasyonu',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '90 günlük kuraklık/yağış senaryoları, havzalar arası kıyaslama ve 4 bölgeli risk matrisi',
            style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // ===================================================================
          // 1. "NE OLURSA?" (WHAT-IF) KURAKLIK & YAĞIŞ SENARYO SİMÜLATÖRÜ
          // ===================================================================
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
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.tune,
                                  color: Color(0xFF38BDF8), size: 18),
                            ),
                          ),
                          const TextSpan(
                            text: '90 Günlük Su Rezervi Senaryo Simülatörü',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: _buildCompactDropdown(
                        value: dropdownItems.contains(_simProvince)
                            ? _simProvince
                            : 'Türkiye Geneli',
                        items: dropdownItems,
                        onChanged: (v) {
                          if (v != null) setState(() => _simProvince = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Kontrol Kaydırıcıları (Sliders)
                _buildSliderRow(
                  label: 'Yağış Değişimi',
                  valueText:
                      '${_rainChangePct >= 0 ? '+' : ''}${_rainChangePct.round()}%',
                  value: _rainChangePct,
                  min: -50,
                  max: 50,
                  divisions: 20,
                  activeColor: const Color(0xFF0EA5E9),
                  onChanged: (v) => setState(() => _rainChangePct = v),
                ),
                _buildSliderRow(
                  label: 'Sıcaklık Artışı (Buharlaşma & Sulama Talebi)',
                  valueText: '+${_tempAnomalyC.toStringAsFixed(1)}°C',
                  value: _tempAnomalyC,
                  min: 0,
                  max: 4.0,
                  divisions: 8,
                  activeColor: const Color(0xFFF97316),
                  onChanged: (v) => setState(() => _tempAnomalyC = v),
                ),
                _buildSliderRow(
                  label: 'Kentsel & Tarımsal Tasarruf',
                  valueText: '%${_savingRatePct.round()}',
                  value: _savingRatePct,
                  min: 0,
                  max: 30,
                  divisions: 15,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) => setState(() => _savingRatePct = v),
                ),
                const SizedBox(height: 10),

                // Projeksiyon Sonuç Özeti & Grafik
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B111A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text(
                            '90. Gün Tahmini Doluluk: %${simResult.day90.toStringAsFixed(1)} (${simResult.netMonthlyDelta >= 0 ? '+' : ''}${simResult.netMonthlyDelta.toStringAsFixed(1)} puan/ay)',
                            style: TextStyle(
                              color: simResult.day90 < 25
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: simResult.daysToCritical != null
                                  ? const Color(0xFFEF4444).withOpacity(0.18)
                                  : const Color(0xFF10B981).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              simResult.daysToCritical != null
                                  ? (simResult.daysToCritical == 0
                                      ? 'Kritik Eşik (%15) Altında!'
                                      : 'Kritik Eşik (%15) Süresi: ~${simResult.daysToCritical} Gün')
                                  : '90 Gün Boyunca Kritik Eşik Üzerinde',
                              style: TextStyle(
                                color: simResult.daysToCritical != null
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFF6EE7B7),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 145,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _ProjectionChartPainter(simResult),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Aylık Net Su Bütçesi Şeridi (Sıfır taşma garantili Text.rich)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111927),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            _budgetPill(
                              'Yağış Beslemesi',
                              '+%${simResult.monthlyInflowPct.toStringAsFixed(1)}/ay',
                              const Color(0xFF38BDF8),
                            ),
                            _budgetPill(
                              'Buharlaşma',
                              '-%${simResult.evapLossPct.toStringAsFixed(1)}/ay',
                              const Color(0xFFF97316),
                            ),
                            _budgetPill(
                              'Net Tüketim',
                              '-%${simResult.netConsumptionPct.toStringAsFixed(1)}/ay',
                              const Color(0xFFA855F7),
                            ),
                            _budgetPill(
                              'Denge Tasarruf Eşiği',
                              simResult.requiredSavingToHoldPct > 65
                                  ? '%65+ (Olağanüstü)'
                                  : '%${simResult.requiredSavingToHoldPct.toStringAsFixed(1)}',
                              const Color(0xFF10B981),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Detaylı Senaryo Etki Raporu Kartları
                      const Row(
                        children: [
                          Icon(Icons.analytics_outlined,
                              color: Color(0xFF38BDF8), size: 16),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Hydro AI Detaylı Senaryo Etki Raporu',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _reportBlock(
                        icon: Icons.savings_outlined,
                        color: detailedReport.balanceColor,
                        title: detailedReport.balanceTitle,
                        body: detailedReport.balanceText,
                      ),
                      const SizedBox(height: 8),
                      _reportBlock(
                        icon: Icons.agriculture_outlined,
                        color: detailedReport.agriColor,
                        title: detailedReport.agriTitle,
                        body: detailedReport.agriText,
                      ),
                      const SizedBox(height: 8),
                      _reportBlock(
                        icon: Icons.water_damage_outlined,
                        color: const Color(0xFF38BDF8),
                        title: detailedReport.urbanTitle,
                        body: detailedReport.urbanText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===================================================================
          // 2. İKİ İL / HAVZA KARŞILAŞTIRMA MODÜLÜ
          // ===================================================================
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
                    Icon(Icons.compare_arrows,
                        color: Color(0xFF38BDF8), size: 19),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'İki İl / Havza Karşılaştırmalı Analizi',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (provinceNames.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactDropdown(
                          value: _compareCityA,
                          items: provinceNames,
                          accent: const Color(0xFF0EA5E9),
                          onChanged: (v) {
                            if (v != null) setState(() => _compareCityA = v);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFF8A9BB2),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildCompactDropdown(
                          value: _compareCityB,
                          items: provinceNames,
                          accent: const Color(0xFFA855F7),
                          onChanged: (v) {
                            if (v != null) setState(() => _compareCityB = v);
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                _buildComparisonMetricRow(
                  label: 'Baraj Doluluk Oranı',
                  valA: statsA.fillPct,
                  valB: statsB.fillPct,
                  unit: '%',
                ),
                _buildComparisonMetricRow(
                  label: 'Su Stresi İndeksi',
                  valA: statsA.waterStressPct,
                  valB: statsB.waterStressPct,
                  unit: '%',
                ),
                _buildComparisonMetricRow(
                  label: 'Kirlilik & Bulanıklık',
                  valA: statsA.pollutionPct,
                  valB: statsB.pollutionPct,
                  unit: '%',
                ),
                _buildComparisonMetricRow(
                  label: 'Arıtmasız Ham Su Riski',
                  valA: statsA.rawRiskPct,
                  valB: statsB.rawRiskPct,
                  unit: '%',
                ),
                _buildComparisonMetricRow(
                  label: '7 Günlük Yağış (mm)',
                  valA: statsA.rainfall7dMm,
                  valB: statsB.rainfall7dMm,
                  unit: ' mm',
                  maxScale: 50.0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===================================================================
          // 3. STRATEJİK 4 BÖLGELİ HAVZA RİSK MATRİSİ & COĞRAFİ KÜMELEME
          // ===================================================================
          _buildQuadrantMatrixCard(),
          const SizedBox(height: 16),

          // ===================================================================
          // 4. HYDRO AI YÖNETİM & TASARRUF EYLEM ÖNERİLERİ
          // ===================================================================
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
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hydro AI Stratejik Eylem Önerileri (${simStats.name})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...recommendations.map((rec) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: rec.color.withOpacity(0.45)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: rec.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(rec.icon, color: rec.color, size: 18),
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
                                      rec.title,
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
                                        color: rec.color.withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        rec.priority,
                                        style: TextStyle(
                                          color: rec.color,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rec.detail,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wrap içinde sıfır taşma garantili bilgi rozeti
  Widget _budgetPill(String label, String val, Color color) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.8),
          ),
          TextSpan(
            text: val,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 10.8),
          ),
        ],
      ),
    );
  }

  Widget _reportBlock({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF111927),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11.8,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuadrantMatrixCard() {
    final urgent = <_QuadrantCityItem>[];
    final pollutionRisk = <_QuadrantCityItem>[];
    final recovering = <_QuadrantCityItem>[];
    final safe = <_QuadrantCityItem>[];

    widget.provincesData.forEach((name, val) {
      if (val is Map && val['weighted_fill_pct'] != null) {
        final fill = (val['weighted_fill_pct'] as num).toDouble();
        final poll = (val['pollution_pct'] as num?)?.toDouble() ?? 24.0;
        final rain = (val['rainfall_7d_mm'] as num?)?.toDouble() ?? 0.0;

        final item = _QuadrantCityItem(
          name: name,
          fillPct: fill,
          pollutionPct: poll,
          rain7dMm: rain,
          regionAxis: _classifyGeoAxis(name),
        );

        if (fill < 30 && rain >= 10.0) {
          recovering.add(item);
        } else if (fill < 30) {
          urgent.add(item);
        } else if (poll >= 32.0) {
          pollutionRisk.add(item);
        } else {
          safe.add(item);
        }
      }
    });

    urgent.sort((a, b) => a.fillPct.compareTo(b.fillPct));
    recovering.sort((a, b) => b.rain7dMm.compareTo(a.rain7dMm));
    pollutionRisk.sort((a, b) => b.pollutionPct.compareTo(a.pollutionPct));
    safe.sort((a, b) => b.fillPct.compareTo(a.fillPct));

    return Container(
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
              Icon(Icons.grid_view_rounded,
                  color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '81 İl Stratejik Havza Risk Matrisi & Coğrafi Kümeleme',
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
            'Doluluk, kirlilik ve haftalık yağış verilerine göre illerin 4 stratejik sınıfa ve coğrafi eksenlere dağılımı',
            style: TextStyle(color: Color(0xFF8A9BB2), fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 760;

              final tile1 = _quadrantTile(
                title: 'Acil Müdahale Bölgesi',
                subtitle: 'Düşük Doluluk (<%30) + Düşük Yağış',
                items: urgent,
                color: const Color(0xFFEF4444),
                icon: Icons.warning_amber_rounded,
              );
              final tile2 = _quadrantTile(
                title: 'Yağışla Toparlananlar',
                subtitle: 'Düşük Doluluk + Yüksek Yağış (>10mm)',
                items: recovering,
                color: const Color(0xFF0EA5E9),
                icon: Icons.water_drop,
              );
              final tile3 = _quadrantTile(
                title: 'Kirlilik & Arıtma Riski',
                subtitle: 'Yeterli Rezerv + Yüksek Bulanıklık',
                items: pollutionRisk,
                color: const Color(0xFFF59E0B),
                icon: Icons.science_outlined,
              );
              final tile4 = _quadrantTile(
                title: 'Güvenli Havzalar',
                subtitle: 'Yüksek Doluluk + Düşük Stres',
                items: safe,
                color: const Color(0xFF10B981),
                icon: Icons.shield_outlined,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    tile1,
                    const SizedBox(height: 10),
                    tile2,
                    const SizedBox(height: 10),
                    tile3,
                    const SizedBox(height: 10),
                    tile4,
                  ],
                );
              }

              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: tile1),
                        const SizedBox(width: 10),
                        Expanded(child: tile2),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: tile3),
                        const SizedBox(width: 10),
                        Expanded(child: tile4),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _classifyGeoAxis(String city) {
    const west = {
      'İstanbul', 'Edirne', 'Kırklareli', 'Tekirdağ', 'Çanakkale', 'Balıkesir',
      'Bursa', 'Yalova', 'Kocaeli', 'Sakarya', 'Bilecik', 'İzmir', 'Manisa',
      'Aydın', 'Denizli', 'Muğla', 'Uşak', 'Kütahya', 'Afyonkarahisar'
    };
    const north = {
      'Düzce', 'Bolu', 'Zonguldak', 'Karabük', 'Bartın', 'Kastamonu', 'Sinop',
      'Çankırı', 'Çorum', 'Amasya', 'Samsun', 'Ordu', 'Giresun', 'Trabzon',
      'Rize', 'Artvin', 'Gümüşhane', 'Bayburt', 'Tokat'
    };
    const south = {
      'Antalya', 'Isparta', 'Burdur', 'Mersin', 'Adana', 'Osmaniye', 'Hatay',
      'Kahramanmaraş', 'Gaziantep', 'Kilis', 'Şanlıurfa', 'Adıyaman'
    };
    const east = {
      'Erzurum', 'Erzincan', 'Kars', 'Ardahan', 'Iğdır', 'Ağrı', 'Van',
      'Muş', 'Bitlis', 'Bingöl', 'Tunceli', 'Elazığ', 'Malatya', 'Diyarbakır',
      'Mardin', 'Batman', 'Siirt', 'Şırnak', 'Hakkâri'
    };

    if (west.contains(city)) return 'Batı (Marmara & Ege)';
    if (north.contains(city)) return 'Kuzey (Karadeniz Hattı)';
    if (south.contains(city)) return 'Güney (Akdeniz & Güneydoğu)';
    if (east.contains(city)) return 'Doğu (Doğu Anadolu)';
    return 'Merkez (İç Anadolu)';
  }

  String _summarizeGeoSpread(List<_QuadrantCityItem> items) {
    if (items.isEmpty) return 'Coğrafi yoğunluk verisi yok.';
    final counts = <String, int>{};
    for (final it in items) {
      counts[it.regionAxis] = (counts[it.regionAxis] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.length == 1) {
      return 'Yoğunluk ekseni: Tamamı ${sorted.first.key} koridorunda toplanıyor.';
    }
    final top1 = sorted[0];
    final top2 = sorted[1];
    return 'Coğrafi dağılım: En yoğun ${top1.key} (${top1.value} il) ve ${top2.key} (${top2.value} il) hattında ilerliyor.';
  }

  Widget _quadrantTile({
    required String title,
    required String subtitle,
    required List<_QuadrantCityItem> items,
    required Color color,
    required IconData icon,
  }) {
    final avgFill = items.isEmpty
        ? 0.0
        : items.fold(0.0, (s, e) => s + e.fillPct) / items.length;
    final avgRain = items.isEmpty
        ? 0.0
        : items.fold(0.0, (s, e) => s + e.rain7dMm) / items.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${items.length} İl',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style:
                    const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
              const SizedBox(height: 8),

              if (items.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15202E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Grup Ort. Doluluk: %${avgFill.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Ort. 7G Yağış: ${avgRain.toStringAsFixed(1)} mm',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Bu kategoride şu an il bulunmuyor.',
                    style:
                        TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                  ),
                )
              else
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: items.map((cityItem) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6.5, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162235),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF243449)),
                      ),
                      child: Text(
                        '${cityItem.name} %${cityItem.fillPct.round()}',
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.explore_outlined, color: color, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _summarizeGeoSpread(items),
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 10.8,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style:
                    const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              style: TextStyle(
                color: activeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: activeColor,
            inactiveTrackColor: const Color(0xFF1E293B),
            thumbColor: activeColor,
            overlayColor: activeColor.withOpacity(0.18),
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonMetricRow({
    required String label,
    required double valA,
    required double valB,
    required String unit,
    double maxScale = 100.0,
  }) {
    final normA = (valA / maxScale).clamp(0.0, 1.0);
    final normB = (valB / maxScale).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${valA.toStringAsFixed(1)}$unit',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Flexible(
                child: Text(
                  label,
                  style:
                      const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${valB.toStringAsFixed(1)}$unit',
                style: const TextStyle(
                  color: Color(0xFFC084FC),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: normA,
                    child: Container(
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0EA5E9),
                        borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: normB,
                    child: Container(
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFA855F7),
                        borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    Color accent = const Color(0xFF2E425B),
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          dropdownColor: const Color(0xFF1C293B),
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SimProvinceStats {
  final String name;
  final double fillPct;
  final double waterStressPct;
  final double pollutionPct;
  final double rawRiskPct;
  final double rainfall7dMm;
  final int sourceCount;

  _SimProvinceStats({
    required this.name,
    required this.fillPct,
    required this.waterStressPct,
    required this.pollutionPct,
    required this.rawRiskPct,
    required this.rainfall7dMm,
    required this.sourceCount,
  });
}

class _SimulationResult {
  final double day0;
  final double day30;
  final double day60;
  final double day90;
  final double monthlyInflowPct;
  final double evapLossPct;
  final double netConsumptionPct;
  final double netMonthlyDelta;
  final int? daysToCritical;
  final double requiredSavingToHoldPct;
  final double requiredSavingForNormalPct;
  final double seasonalNormalPct;

  _SimulationResult({
    required this.day0,
    required this.day30,
    required this.day60,
    required this.day90,
    required this.monthlyInflowPct,
    required this.evapLossPct,
    required this.netConsumptionPct,
    required this.netMonthlyDelta,
    required this.daysToCritical,
    required this.requiredSavingToHoldPct,
    required this.requiredSavingForNormalPct,
    required this.seasonalNormalPct,
  });
}

class _DetailedScenarioReport {
  final String balanceTitle;
  final String balanceText;
  final Color balanceColor;
  final String agriTitle;
  final String agriText;
  final Color agriColor;
  final String urbanTitle;
  final String urbanText;

  _DetailedScenarioReport({
    required this.balanceTitle,
    required this.balanceText,
    required this.balanceColor,
    required this.agriTitle,
    required this.agriText,
    required this.agriColor,
    required this.urbanTitle,
    required this.urbanText,
  });
}

class _QuadrantCityItem {
  final String name;
  final double fillPct;
  final double pollutionPct;
  final double rain7dMm;
  final String regionAxis;

  _QuadrantCityItem({
    required this.name,
    required this.fillPct,
    required this.pollutionPct,
    required this.rain7dMm,
    required this.regionAxis,
  });
}

class _ActionRecommendation {
  final String priority;
  final Color color;
  final IconData icon;
  final String title;
  final String detail;

  _ActionRecommendation({
    required this.priority,
    required this.color,
    required this.icon,
    required this.title,
    required this.detail,
  });
}

class _ProjectionChartPainter extends CustomPainter {
  final _SimulationResult sim;

  _ProjectionChartPainter(this.sim);

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 24.0;
    const rightPad = 24.0;
    const topPad = 20.0;
    const bottomPad = 24.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // %15 Kritik Eşik Çizgisi
    final critY = topPad + chartH * (1.0 - 0.15);
    final critPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.55)
      ..strokeWidth = 1.2;
    canvas.drawLine(
        Offset(leftPad, critY), Offset(size.width - rightPad, critY), critPaint);

    final vals = [sim.day0, sim.day30, sim.day60, sim.day90];
    final labels = ['Bugün', '30. Gün', '60. Gün', '90. Gün'];
    final pts = <Offset>[];

    for (int i = 0; i < vals.length; i++) {
      final x = leftPad + (chartW / (vals.length - 1)) * i;
      final y = topPad + chartH * (1.0 - (vals[i] / 100.0).clamp(0.0, 1.0));
      pts.add(Offset(x, y));
    }

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final ctrlX = (pts[i].dx + pts[i + 1].dx) / 2;
      path.cubicTo(ctrlX, pts[i].dy, ctrlX, pts[i + 1].dy, pts[i + 1].dx,
          pts[i + 1].dy);
    }

    final areaPath = Path.from(path)
      ..lineTo(pts.last.dx, topPad + chartH)
      ..lineTo(pts.first.dx, topPad + chartH)
      ..close();

    final lineColor =
        sim.day90 < 25 ? const Color(0xFFEF4444) : const Color(0xFF0EA5E9);

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.32), lineColor.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..isAntiAlias = true,
    );

    for (int i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 4.2, Paint()..color = lineColor);
      _drawText(
        canvas,
        '%${vals[i].toStringAsFixed(1)}',
        Offset(pts[i].dx, pts[i].dy - 15),
        Colors.white,
        10.0,
      );
      _drawText(
        canvas,
        labels[i],
        Offset(pts[i].dx, topPad + chartH + 6),
        const Color(0xFF94A3B8),
        10.0,
      );
    }
  }

  void _drawText(
      Canvas canvas, String text, Offset centerTop, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style:
            TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centerTop.dx - tp.width / 2, centerTop.dy));
  }

  @override
  bool shouldRepaint(covariant _ProjectionChartPainter oldDelegate) => true;
}