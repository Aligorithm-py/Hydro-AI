import json
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "assets" / "data"
GEOJSON_PATH = BASE_DIR / "assets" / "maps" / "turkey_provinces.json"
RAPOR_PATH = DATA_DIR / "doluluk_raporu.json"


def normalize_tr(text: str) -> str:
    return (
        text.replace("İ", "i")
        .replace("I", "ı")
        .lower()
        .replace("â", "a")
        .replace("î", "i")
        .replace("û", "u")
        .strip()
    )


def extract_all_points(coords, out_pts: list):
    if not isinstance(coords, list) or not coords:
        return
    if isinstance(coords[0], (int, float)) and len(coords) >= 2:
        lon, lat = float(coords[0]), float(coords[1])
        if 35.0 <= lat <= 43.0 and 25.0 <= lon <= 45.0:
            out_pts.append((lat, lon))
    else:
        for item in coords:
            extract_all_points(item, out_pts)


def load_coords_from_geojson() -> dict[str, tuple[float, float]]:
    """assets/maps/turkey_provinces.json içindeki 81 ilin poligon merkez koordinatlarını çıkarır."""
    if not GEOJSON_PATH.exists():
        print(f"[Uyarı] GeoJSON bulunamadı: {GEOJSON_PATH}")
        return {}

    with open(GEOJSON_PATH, "r", encoding="utf-8") as f:
        geo = json.load(f)

    coords_map = {}
    for feat in geo.get("features", []):
        props = feat.get("properties", {})
        raw_name = (
            props.get("name")
            or props.get("NAME_1")
            or props.get("il")
            or props.get("province")
            or ""
        )
        if not raw_name:
            continue

        pts = []
        extract_all_points(feat.get("geometry", {}).get("coordinates", []), pts)
        if pts:
            avg_lat = sum(p[0] for p in pts) / len(pts)
            avg_lon = sum(p[1] for p in pts) / len(pts)
            coords_map[normalize_tr(raw_name)] = (avg_lat, avg_lon)

    return coords_map


def fetch_bulk_weekly_rainfall(city_list: list[str], city_coords: dict) -> dict[str, float]:
    """81 ilin tamamının son 7 günlük yağışını tek bir toplu API isteğiyle çeker."""
    lats = [f"{city_coords[c][0]:.4f}" for c in city_list]
    lons = [f"{city_coords[c][1]:.4f}" for c in city_list]

    url = (
        f"https://api.open-meteo.com/v1/forecast?"
        f"latitude={','.join(lats)}&longitude={','.join(lons)}"
        f"&daily=precipitation_sum&past_days=7&forecast_days=1&timezone=Europe%2FIstanbul"
    )

    req = urllib.request.Request(url, headers={"User-Agent": "HydroAI-BulkPipeline/1.0"})
    with urllib.request.urlopen(req, timeout=25) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    results = {}
    items = payload if isinstance(payload, list) else [payload]
    for idx, city in enumerate(city_list):
        if idx < len(items):
            daily_precip = items[idx].get("daily", {}).get("precipitation_sum", [])
            valid_days = [float(x) for x in daily_precip[:7] if x is not None]
            results[city] = round(sum(valid_days), 1)
        else:
            results[city] = 0.0
    return results


def compute_hydro_metrics(city: str, fill_pct: float, rainfall_7d_mm: float, ndti_raw: float | None):
    rain_relief = min(rainfall_7d_mm * 0.25, 14.0)
    water_stress = max(6.0, min(98.0, round(100.0 - (fill_pct * 0.85) - rain_relief, 1)))

    if ndti_raw is not None:
        base_turbidity = ((ndti_raw + 0.3) / 0.7) * 100.0
    else:
        runoff_mud = min(rainfall_7d_mm * 0.45, 28.0) if rainfall_7d_mm > 15.0 else rainfall_7d_mm * 0.15
        low_water_sediment = max(0.0, (45.0 - fill_pct) * 0.42)
        base_turbidity = 14.0 + runoff_mud + low_water_sediment

    pollution_pct = max(8.0, min(92.0, round(base_turbidity, 1)))
    stagnation_risk = max(0.0, (50.0 - fill_pct) * 0.25) if rainfall_7d_mm < 5.0 else 4.0
    raw_water_risk = max(18.0, min(96.0, round(pollution_pct * 1.12 + stagnation_risk, 1)))

    if rainfall_7d_mm >= 25.0:
        rain_label = f"Son 7 gün: {rainfall_7d_mm} mm (Şiddetli Yağış)"
        ai_summary = (
            f"{city} havzasında son hafta {rainfall_7d_mm} mm yağış kaydedildi. "
            f"Yüzey akışıyla barajlara taşınan alüvyon ve toprak nedeniyle geçici bulanıklık (çamurlaşma) artışı gözleniyor."
        )
    elif rainfall_7d_mm >= 8.0:
        rain_label = f"Son 7 gün: {rainfall_7d_mm} mm (Mevsim Normalleri)"
        ai_summary = (
            f"{city} genelinde haftalık {rainfall_7d_mm} mm yağış rezerv dengesini destekliyor. "
            f"Yüzey bulanıklığı kontrollü seyretse de ham su arıtma tesislerinden geçmeden tüketime uygun değil."
        )
    else:
        rain_label = f"Son 7 gün: {rainfall_7d_mm} mm (Düşük Yağış)"
        if fill_pct < 25.0:
            ai_summary = (
                f"{city} barajlarında %{fill_pct:.1f} ile kritik rezerv seviyesi ve kurak hafta ({rainfall_7d_mm} mm) "
                f"su stresini yükseltiyor. Azalan su hacminde dip sediman yoğunluğu arttığından arıtmasız tüketim riski yüksek."
            )
        else:
            ai_summary = (
                f"{city} havzasında son hafta yağış zayıf ({rainfall_7d_mm} mm) kaldı. "
                f"Mevcut %{fill_pct:.1f} doluluk kısa vadede yeterli görünse de durgunlaşma kaynaklı ham su riski izleniyor."
            )

    return {
        "rainfall_7d_mm": rainfall_7d_mm,
        "rainfall_label": rain_label,
        "water_stress_pct": water_stress,
        "pollution_pct": pollution_pct,
        "raw_water_risk_pct": raw_water_risk,
        "ai_summary": ai_summary,
    }


def main():
    if not RAPOR_PATH.exists():
        print(f"Hata: {RAPOR_PATH} bulunamadı.")
        return

    with open(RAPOR_PATH, "r", encoding="utf-8") as f:
        rapor = json.load(f)

    geo_coords = load_coords_from_geojson()
    provinces = rapor.get("provinces", {})
    city_list = list(provinces.keys())
    city_coords = {}
    matched_count = 0

    for city in city_list:
        pt = geo_coords.get(normalize_tr(city))
        if pt:
            city_coords[city] = pt
            matched_count += 1
        else:
            city_coords[city] = (39.0, 35.0)

    print(f"Koordinat eşleşmesi: {matched_count}/{len(city_list)} il bulundu.")
    print("81 ilin gerçek haftalık yağış verisi çekiliyor...\n")

    bulk_rain = fetch_bulk_weekly_rainfall(city_list, city_coords)

    for idx, city in enumerate(city_list, start=1):
        info = provinces[city]
        fill_pct = float(info.get("weighted_fill_pct", 0.0))
        ndti_raw = info.get("ndti_mean")
        rain_mm = bulk_rain.get(city, 0.0)

        enriched = compute_hydro_metrics(city, fill_pct, rain_mm, ndti_raw)
        info.update(enriched)

        print(
            f"[{idx:02d}/81] {city:<15} | Doluluk: %{fill_pct:5.1f} | Yağış: {rain_mm:4.1f} mm | "
            f"Stres: %{enriched['water_stress_pct']:4.1f} | Kirlilik: %{enriched['pollution_pct']:4.1f}"
        )

    rapor["enriched_with_weather"] = True
    with open(RAPOR_PATH, "w", encoding="utf-8") as f:
        json.dump(rapor, f, ensure_ascii=False, indent=2)

    print("\nTamamlandı! assets/data/doluluk_raporu.json 81 ilin kendi koordinatındaki yağış verileriyle güncellendi.")


if __name__ == "__main__":
    main()