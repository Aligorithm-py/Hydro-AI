import json
import os
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import requests

CDSE_CLIENT_ID = os.environ.get("CDSE_CLIENT_ID", "")
CDSE_CLIENT_SECRET = os.environ.get("CDSE_CLIENT_SECRET", "")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")

DISPLAY_ALIASES = {
    "afyon": "Afyonkarahisar",
    "içel": "Mersin",
    "icel": "Mersin",
    "antakya": "Hatay",
    "adapazarı": "Sakarya",
    "adapazari": "Sakarya",
}


def canonical_province(name: str) -> str:
    low = name.replace("İ", "i").replace("I", "ı").lower().strip()
    return DISPLAY_ALIASES.get(low, name.strip())


def load_81_province_bboxes(geojson_path: str) -> dict[str, list[float]]:
    with open(geojson_path, "r", encoding="utf-8") as f:
        geo = json.load(f)

    bboxes: dict[str, list[float]] = {}
    for feat in geo.get("features", []):
        props = feat.get("properties", {})
        raw_name = str(
            props.get("name")
            or props.get("NAME_1")
            or props.get("il_adi")
            or props.get("Il_Adi")
            or ""
        )
        if not raw_name:
            continue
        prov = canonical_province(raw_name)
        geom = feat.get("geometry", {})
        gtype = geom.get("type")
        coords = geom.get("coordinates", [])

        lons, lats = [], []
        if gtype == "Polygon":
            for ring in coords:
                for pt in ring:
                    lons.append(float(pt[0]))
                    lats.append(float(pt[1]))
        elif gtype == "MultiPolygon":
            for poly in coords:
                for ring in poly:
                    for pt in ring:
                        lons.append(float(pt[0]))
                        lats.append(float(pt[1]))

        if lons and lats:
            bboxes[prov] = [
                round(min(lons), 4),
                round(min(lats), 4),
                round(max(lons), 4),
                round(max(lats), 4),
            ]
    return bboxes


def get_copernicus_token() -> str:
    if not CDSE_CLIENT_ID or not CDSE_CLIENT_SECRET:
        return ""
    resp = requests.post(
        "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token",
        data={
            "grant_type": "client_credentials",
            "client_id": CDSE_CLIENT_ID,
            "client_secret": CDSE_CLIENT_SECRET,
        },
        timeout=20,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def fetch_sentinel_stats(token: str, bbox: list[float], res_m: int = 120) -> dict | None:
    if not token or not bbox:
        return None

    end_dt = datetime.now(timezone.utc)
    start_dt = end_dt - timedelta(days=12)

    evalscript = """
    //VERSION=3
    function setup() {
      return {
        input: [{ bands: ["B03", "B04", "B08", "SCL", "dataMask"] }],
        output: [
          { id: "ndwi", bands: 1, sampleType: "FLOAT32" },
          { id: "ndti", bands: 1, sampleType: "FLOAT32" },
          { id: "dataMask", bands: 1 }
        ]
      };
    }
    function evaluatePixel(s) {
      const isCloud = s.SCL === 3 || s.SCL === 8 || s.SCL === 9 || s.SCL === 10;
      const valid = s.dataMask === 1 && !isCloud ? 1 : 0;
      const ndwi = (s.B03 - s.B08) / (s.B03 + s.B08 + 1e-6);
      const ndti = (s.B04 - s.B03) / (s.B04 + s.B03 + 1e-6);
      return { ndwi: [ndwi], ndti: [ndti], dataMask: [valid] };
    }
    """

    payload = {
        "input": {"bounds": {"bbox": bbox}, "data": [{"type": "sentinel-2-l2a"}]},
        "aggregation": {
            "timeRange": {
                "from": start_dt.strftime("%Y-%m-%dT00:00:00Z"),
                "to": end_dt.strftime("%Y-%m-%dT23:59:59Z"),
            },
            "aggregationInterval": {"of": "P12D"},
            "evalscript": evalscript,
            "resx": res_m,
            "resy": res_m,
        },
    }

    resp = requests.post(
        "https://sh.dataspace.copernicus.eu/api/v1/statistics",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=payload,
        timeout=30,
    )
    if resp.status_code != 200:
        return None

    data = resp.json().get("data", [])
    if not data:
        return None

    latest = data[-1]
    outputs = latest.get("outputs", {})
    ndwi_mean = outputs.get("ndwi", {}).get("bands", {}).get("B0", {}).get("stats", {}).get("mean")
    ndti_mean = outputs.get("ndti", {}).get("bands", {}).get("B0", {}).get("stats", {}).get("mean")
    scene_date = latest.get("interval", {}).get("to", "")[:10]

    if ndwi_mean is None:
        return None

    return {
        "ndwi_mean": float(ndwi_mean),
        "ndti_mean": float(ndti_mean or 0.0),
        "scene_date": scene_date,
    }


def upsert_batch(table_name: str, rows: list[dict], chunk_size: int = 100):
    if not rows:
        return
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL veya SUPABASE_SERVICE_KEY tanımlı değil.")

    url = f"{SUPABASE_URL}/rest/v1/{table_name}"
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }

    for i in range(0, len(rows), chunk_size):
        chunk = rows[i : i + chunk_size]
        resp = requests.post(url, headers=headers, json=chunk, timeout=30)
        resp.raise_for_status()


def main():
    bboxes_81 = load_81_province_bboxes("assets/maps/turkey_provinces.json")
    with open("assets/data/doluluk_raporu.json", "r", encoding="utf-8") as f:
        report_json = json.load(f)

    reservoirs = report_json.get("reservoirs", {})
    base_provinces = report_json.get("provinces", {})
    token = get_copernicus_token()
    now_iso = datetime.now(timezone.utc).isoformat()
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # 81 il için Sentinel-2 uydu verisini bir kez çekip önbelleğe al (hızlı ve kota dostu)
    prov_sat_cache: dict[str, dict | None] = {}
    if token:
        print("Copernicus Sentinel-2 uydu verileri 81 il için taranıyor...")
        for prov, bbox in bboxes_81.items():
            prov_sat_cache[prov] = fetch_sentinel_stats(token, bbox, res_m=150)
            time.sleep(0.1)

    source_rows = []
    prov_agg = defaultdict(lambda: {"fills": [], "polls": [], "weights": [], "ndwis": [], "scene": today_str})

    # 342 su kaynağının (reservoirs) tamamını işle
    for res_id, item in reservoirs.items():
        s_name = str(item.get("name") or res_id)
        raw_provs = item.get("provinces") or ["Bilinmiyor"]
        primary_prov = canonical_province(str(raw_provs[0]))

        fill = float(item.get("volumetric_fill_pct") or item.get("surface_area_pct") or 50.0)
        poll = float(item.get("pollution_pct") or round(max(6.0, min(88.0, 100.0 - fill * 0.72)), 1))
        weight = float(item.get("max_surface_area_m2") or 1.0)
        s_lat = item.get("lat") or item.get("latitude")
        s_lon = item.get("lon") or item.get("longitude")

        sat = prov_sat_cache.get(primary_prov)
        s_ndwi = None
        s_ndti = None
        scene_date = today_str

        if sat:
            s_ndwi = round(sat["ndwi_mean"], 4)
            s_ndti = round(sat["ndti_mean"], 4)
            scene_date = sat["scene_date"] or today_str
            fill = round(max(4.0, min(99.5, fill + sat["ndwi_mean"] * 10.0)), 1)
            poll = round(max(4.0, min(92.0, poll + sat["ndti_mean"] * 12.0)), 1)

        if (s_lat is None or s_lon is None) and primary_prov in bboxes_81:
            b = bboxes_81[primary_prov]
            s_lat = round((b[1] + b[3]) / 2, 4)
            s_lon = round((b[0] + b[2]) / 2, 4)

        source_rows.append({
            "source_id": str(res_id),
            "province_name": primary_prov,
            "source_name": s_name,
            "latitude": float(s_lat) if s_lat is not None else None,
            "longitude": float(s_lon) if s_lon is not None else None,
            "fill_pct": fill,
            "pollution_pct": poll,
            "ndwi_mean": s_ndwi,
            "ndti_mean": s_ndti,
            "satellite_scene_date": scene_date,
            "updated_at": now_iso,
        })

        for rp in raw_provs:
            cp = canonical_province(str(rp))
            prov_agg[cp]["fills"].append(fill)
            prov_agg[cp]["polls"].append(poll)
            prov_agg[cp]["weights"].append(weight)
            if s_ndwi is not None:
                prov_agg[cp]["ndwis"].append(s_ndwi)
            prov_agg[cp]["scene"] = scene_date

    # 81 ilin tamamını oluştur (hiç kaynağı olmayan iller dahil)
    all_81_provinces = set(bboxes_81.keys()) | set(prov_agg.keys()) | {
        canonical_province(k) for k in base_provinces.keys()
    }

    province_rows = []
    for prov in sorted(all_81_provinces):
        agg = prov_agg.get(prov)
        base_m = base_provinces.get(prov, {})

        if agg and agg["fills"]:
            w_sum = sum(agg["weights"]) or len(agg["fills"])
            w_fill = round(
                sum(f * w for f, w in zip(agg["fills"], agg["weights"])) / w_sum, 1
            )
            w_poll = round(
                sum(p * w for p, w in zip(agg["polls"], agg["weights"])) / w_sum, 1
            )
            src_cnt = len(agg["fills"])
            mean_ndwi = round(sum(agg["ndwis"]) / len(agg["ndwis"]), 4) if agg["ndwis"] else None
            scene_dt = agg["scene"]
        else:
            w_fill = float(base_m.get("weighted_fill_pct", 52.0))
            w_poll = float(base_m.get("pollution_pct", 22.0))
            src_cnt = int(base_m.get("source_count", 0))
            sat = prov_sat_cache.get(prov)
            mean_ndwi = round(sat["ndwi_mean"], 4) if sat else None
            scene_dt = sat["scene_date"] if sat else today_str

        risk = round(max(8.0, min(96.0, (100.0 - w_fill) * 0.55 + w_poll * 0.45)), 1)

        province_rows.append({
            "province_name": prov,
            "weighted_fill_pct": w_fill,
            "pollution_pct": w_poll,
            "raw_water_risk_pct": risk,
            "source_count": src_cnt,
            "ndwi_mean": mean_ndwi,
            "satellite_scene_date": scene_dt,
            "updated_at": now_iso,
        })

    # Önce 81 il (Foreign Key ana tablo), sonra 342 kaynak (alt tablo) yazılır
    upsert_batch("province_satellite_metrics", province_rows)
    upsert_batch("water_source_metrics", source_rows)
    print(
        f"Tamamlandı: {len(province_rows)} il ve toplam {len(source_rows)} su kaynağı Supabase'e işlendi."
    )


if __name__ == "__main__":
    main()