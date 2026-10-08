#!/usr/bin/env python3
"""Market snapshot for the desktop widget, as JSON on stdout (Yahoo Finance chart API).

For each market: last price, change vs previous close, and ~1 month of daily closes
for the sparkline. Edit MARKETS to change what the widget shows.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

MARKETS = [
    # (name, subtitle, Yahoo symbol)
    ("MSCI World", "Index", "^990100-USD-STRD"),
    ("Nasdaq 100", "Index", "^NDX"),
    ("Euro Stoxx 50", "Index", "^STOXX50E"),
    ("EM ex China", "ETF · EMXC", "EMXC"),  # no free index feed; the ETF tracks MSCI EM ex China
]
RATES = [
    # (country, bond name, CNBC symbol) — 10-year government bond yields
    ("France", "OAT", "FR10Y-EU"),
    ("Germany", "Bund", "DE10Y-EU"),
    ("United States", "Treasury", "US10Y"),
]
CNBC_QUOTE = ("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
              "?symbols={}&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json")
CNBC_CHART = "https://ts-api.cnbc.com/harmony/app/charts/1M.json?symbol={}"
URL = "https://query1.finance.yahoo.com/v8/finance/chart/{}?range=1mo&interval=1d"


def fetch(market):
    name, subtitle, symbol = market
    req = urllib.request.Request(URL.format(urllib.parse.quote(symbol)), headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        res = json.load(r)["chart"]["result"][0]
    meta = res["meta"]
    stamps = res["timestamp"]
    closes = res["indicators"]["quote"][0]["close"]
    series = [(t, c) for t, c in zip(stamps, closes) if c is not None]
    price = meta["regularMarketPrice"]

    # Previous close: the last daily close before the current trading day
    day = lambda t: datetime.fromtimestamp(t, timezone.utc).date()
    current_day = day(meta["regularMarketTime"])
    before = [c for t, c in series if day(t) < current_day]
    prev = before[-1] if before else meta.get("chartPreviousClose", price)

    points = [c for _, c in series]
    if not series or day(series[-1][0]) < current_day:
        points.append(price)
    return {
        "name": name,
        "subtitle": subtitle,
        "symbol": symbol,
        "price": price,
        "currency": meta.get("currency") or ("USD" if "USD" in symbol else ""),
        "change": (price / prev - 1) * 100 if prev else 0,
        "points": points[-23:],
        "marketTime": meta["regularMarketTime"] * 1000,
    }


def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def fetch_rate(rate):
    """10Y yield from CNBC: level in %, daily change in basis points, ~1 month of daily closes."""
    name, subtitle, symbol = rate
    q = _get(CNBC_QUOTE.format(urllib.parse.quote(symbol)))["FormattedQuoteResult"]["FormattedQuote"][0]
    price = float(q["last"].rstrip("%"))
    prev = float(q["previous_day_closing"].rstrip("%"))
    bars = _get(CNBC_CHART.format(urllib.parse.quote(symbol)))["barData"]["priceBars"]
    points = [float(b["close"]) for b in bars if b.get("close")]
    if not points or abs(points[-1] - price) > 1e-9:
        points.append(price)
    return {
        "name": name,
        "subtitle": subtitle,
        "symbol": symbol,
        "kind": "yield",
        "url": "https://www.cnbc.com/quotes/" + symbol,
        "price": price,
        "currency": "",
        "changeBp": round((price - prev) * 100, 1),
        "change": (price - prev),
        "points": points[-23:],
    }


# Last good row per symbol: shown right away at login while the network is still coming up
LAST = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "qs-markets-last.json"


def main():
    with ThreadPoolExecutor(len(MARKETS) + len(RATES)) as pool:
        mk = pool.map(lambda m: _safe(fetch, m), MARKETS)
        rt = pool.map(lambda r: _safe(fetch_rate, r), RATES)
        results, rates = list(mk), list(rt)

    try:
        last = json.loads(LAST.read_text())
    except Exception:
        last = {}
    failed = False
    for rows in (results, rates):
        for i, row in enumerate(rows):
            key = row.get("symbol") or row.get("name")
            if row.get("error"):
                failed = True
                if key in last:
                    rows[i] = {**last[key], "stale": True}
            elif key:
                last[key] = row
    try:
        LAST.parent.mkdir(parents=True, exist_ok=True)
        LAST.write_text(json.dumps(last))
    except Exception:
        pass

    json.dump({"updated": int(datetime.now().timestamp() * 1000), "markets": results, "rates": rates}, sys.stdout)
    sys.exit(1 if failed else 0)  # 1 = some rows failed: the widget retries soon


def _safe(fn, market):
    try:
        return fn(market)
    except Exception as e:  # keep the other rows if one symbol fails
        print(f"{market[2]}: {e}", file=sys.stderr)
        return {"name": market[0], "subtitle": market[1], "symbol": market[2], "error": True}


if __name__ == "__main__":
    main()
