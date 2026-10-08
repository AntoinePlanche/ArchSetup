#!/usr/bin/env python3
"""Print {"remote": bool, "events": [...]} for calendar events between two dates as JSON, read from evolution-data-server.

Accounts are added in Evolution (e.g. a Google account); EDS keeps them synced.
Usage: calendar-events.py YYYY-MM-DD YYYY-MM-DD   (end date exclusive)
"""
import json
import re
import sys
from datetime import datetime, timezone

import gi
gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "4.0")
from gi.repository import ECal, EDataServer, ICalGLib  # noqa: E402

LOCAL_TZ = datetime.now().astimezone().tzinfo


def hex_color(c):
    """EDS may store "rgb(r,g,b)", which Qt can't parse; normalize to #rrggbb."""
    m = re.fullmatch(r"\s*rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+).*\)\s*", c or "")
    return "#%02x%02x%02x" % tuple(int(v) for v in m.groups()) if m else (c or "#0a84ff")


def to_ts(t, fallback_zone):
    zone = t.get_timezone() or fallback_zone
    return t.as_timet_with_zone(zone)


def main():
    start = datetime.strptime(sys.argv[1], "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
    end = datetime.strptime(sys.argv[2], "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
    start_ts, end_ts = int(start.timestamp()), int(end.timestamp())
    utc = ICalGLib.Timezone.get_utc_timezone()

    registry = EDataServer.SourceRegistry.new_sync(None)
    events = []
    remote = False  # any online account (Google, CalDAV...) as opposed to the built-in local calendars
    for source in registry.list_enabled(EDataServer.SOURCE_EXTENSION_CALENDAR):
        ext = source.get_extension(EDataServer.SOURCE_EXTENSION_CALENDAR)
        remote |= ext.get_backend_name() not in ("local", "contacts", "weather")
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 1, None)
        except Exception as e:  # offline / account needs re-auth
            print(f"skip {source.get_display_name()}: {e}", file=sys.stderr)
            continue
        default_zone = client.get_default_timezone() or utc

        def on_instance(comp, inst_start, inst_end, *_):
            all_day = inst_start.is_date()
            if all_day:
                s = datetime(inst_start.get_year(), inst_start.get_month(), inst_start.get_day(), tzinfo=LOCAL_TZ)
                e = datetime(inst_end.get_year(), inst_end.get_month(), inst_end.get_day(), tzinfo=LOCAL_TZ)
                s_ts, e_ts = int(s.timestamp()), int(e.timestamp())
            else:
                s_ts, e_ts = to_ts(inst_start, default_zone), to_ts(inst_end, default_zone)
            events.append({
                "title": comp.get_summary() or "(No title)",
                "location": comp.get_location() or "",
                "start": s_ts * 1000,
                "end": e_ts * 1000,
                "allDay": all_day,
                "calendar": source.get_display_name(),
                "color": hex_color(ext.get_color()),
            })
            return True

        client.generate_instances_sync(start_ts, end_ts, None, on_instance)

    events.sort(key=lambda ev: (ev["start"], not ev["allDay"]))
    json.dump({"remote": remote, "events": events}, sys.stdout)


if __name__ == "__main__":
    main()
