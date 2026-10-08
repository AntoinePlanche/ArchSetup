#!/usr/bin/env python3
"""Weather for the desktop widget, as JSON on stdout.

Location: IP geolocation (ip-api.com, fallback ipwho.is), cached 6 h in ~/.cache.
Forecast: Open-Meteo (no API key). Override the location with WEATHER_LAT/WEATHER_LON/WEATHER_CITY.
"""
import json
import os
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "qs-weather-location.json"
# Last good forecast: shown right away at login while the network is still coming up
LAST = CACHE.with_name("qs-weather-last.json")
FORECAST = ("https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&timezone=auto"
            "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"
            "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
            "&forecast_days=6&forecast_hours=30")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 qs-weather"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def location():
    if os.environ.get("WEATHER_LAT"):
        return {"city": os.environ.get("WEATHER_CITY", ""), "lat": float(os.environ["WEATHER_LAT"]),
                "lon": float(os.environ["WEATHER_LON"])}
    try:
        c = json.loads(CACHE.read_text())
        if time.time() - c["t"] < 6 * 3600:
            return c
    except Exception:
        pass
    loc = None
    try:
        d = get("http://ip-api.com/json/?fields=status,city,lat,lon")
        if d.get("status") == "success":
            loc = {"city": d["city"], "lat": d["lat"], "lon": d["lon"]}
    except Exception:
        pass
    if not loc:
        d = get("https://ipwho.is/")
        loc = {"city": d["city"], "lat": d["latitude"], "lon": d["longitude"]}
    loc["t"] = time.time()
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(loc))
    return loc


# WMO code -> (label, day glyph, night glyph, kind). Glyphs: Material Design Icons (Nerd Font).
SUN, MOON, PARTLY, PARTLY_N, CLOUD, FOG = "\U000F0599", "\U000F0594", "\U000F0595", "\U000F0F31", "\U000F0590", "\U000F0591"
RAIN, POUR, SNOW, SLEET, STORM = "\U000F0597", "\U000F0596", "\U000F0598", "\U000F067F", "\U000F0593"
WMO = {
    0: ("Clear", SUN, MOON, "clear"),
    1: ("Mostly Clear", SUN, MOON, "clear"),
    2: ("Partly Cloudy", PARTLY, PARTLY_N, "partly"),
    3: ("Cloudy", CLOUD, CLOUD, "cloudy"),
    45: ("Fog", FOG, FOG, "fog"), 48: ("Freezing Fog", FOG, FOG, "fog"),
    51: ("Light Drizzle", RAIN, RAIN, "rain"), 53: ("Drizzle", RAIN, RAIN, "rain"), 55: ("Heavy Drizzle", RAIN, RAIN, "rain"),
    56: ("Freezing Drizzle", SLEET, SLEET, "rain"), 57: ("Freezing Drizzle", SLEET, SLEET, "rain"),
    61: ("Light Rain", RAIN, RAIN, "rain"), 63: ("Rain", RAIN, RAIN, "rain"), 65: ("Heavy Rain", POUR, POUR, "rain"),
    66: ("Freezing Rain", SLEET, SLEET, "rain"), 67: ("Freezing Rain", SLEET, SLEET, "rain"),
    71: ("Light Snow", SNOW, SNOW, "snow"), 73: ("Snow", SNOW, SNOW, "snow"), 75: ("Heavy Snow", SNOW, SNOW, "snow"),
    77: ("Snow Grains", SNOW, SNOW, "snow"),
    80: ("Showers", RAIN, RAIN, "rain"), 81: ("Showers", POUR, POUR, "rain"), 82: ("Heavy Showers", POUR, POUR, "rain"),
    85: ("Snow Showers", SNOW, SNOW, "snow"), 86: ("Snow Showers", SNOW, SNOW, "snow"),
    95: ("Thunderstorm", STORM, STORM, "storm"), 96: ("Thunderstorm", STORM, STORM, "storm"), 99: ("Thunderstorm", STORM, STORM, "storm"),
}
# Apple-like multicolour glyph tints
TINT = {SUN: "#ffd60a", MOON: "#e5e5ea", PARTLY: "#ffe27a", PARTLY_N: "#e5e5ea", CLOUD: "#f2f2f7", FOG: "#d1d1d6",
        RAIN: "#7cc4ff", POUR: "#64b5ff", SNOW: "#ffffff", SLEET: "#a8d8ff", STORM: "#ffd60a"}


def cond(code, day=True):
    label, g_day, g_night, kind = WMO.get(code, ("—", CLOUD, CLOUD, "cloudy"))
    g = g_day if day else g_night
    return {"label": label, "glyph": g, "color": TINT[g], "kind": kind}


def main():
    loc = location()
    w = get(FORECAST.format(lat=loc["lat"], lon=loc["lon"]))
    cur, hourly, daily = w["current"], w["hourly"], w["daily"]
    now = datetime.fromisoformat(cur["time"])

    hours = []
    for i, t in enumerate(hourly["time"]):
        ts = datetime.fromisoformat(t)
        if ts < now.replace(minute=0):
            continue
        c = cond(hourly["weather_code"][i], bool(hourly["is_day"][i]))
        hours.append({"label": "Now" if not hours else ts.strftime("%H"), "temp": round(hourly["temperature_2m"][i]),
                      "glyph": c["glyph"], "color": c["color"], "pop": hourly["precipitation_probability"][i] or 0})
        if len(hours) == 6:
            break

    days = []
    for i, t in enumerate(daily["time"][:5]):
        c = cond(daily["weather_code"][i])
        days.append({"label": "Today" if i == 0 else datetime.fromisoformat(t).strftime("%a"),
                     "lo": round(daily["temperature_2m_min"][i]), "hi": round(daily["temperature_2m_max"][i]),
                     "glyph": c["glyph"], "color": c["color"]})

    c = cond(cur["weather_code"], bool(cur["is_day"]))
    out = {
        "updated": int(time.time() * 1000),
        "city": loc["city"],
        "temp": round(cur["temperature_2m"]),
        "feels": round(cur["apparent_temperature"]),
        "humidity": cur["relative_humidity_2m"],
        "wind": round(cur["wind_speed_10m"]),
        "isDay": bool(cur["is_day"]),
        "condition": c,
        "hi": days[0]["hi"], "lo": days[0]["lo"],
        "hours": hours,
        "days": days,
    }
    LAST.write_text(json.dumps(out, ensure_ascii=False))
    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(e, file=sys.stderr)
        # Offline (e.g. right after login): show the last forecast; exit 1 so the widget retries soon
        try:
            out = json.loads(LAST.read_text())
            out["stale"] = True
            json.dump(out, sys.stdout, ensure_ascii=False)
        except Exception:
            pass
        sys.exit(1)
