#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate GTM documentation CSV files from a Google Tag Manager container JSON export.

The script writes these files:
  1. triggers_from_gtm.csv
  2. trigger_parameters.csv
  3. tag_trigger_map_from_gtm.csv
  4. tag_trigger_eventtype_issues.csv
  5. tag_params_from_gtm.csv
  6. tag_params_extraction_issues.csv

Usage:
  python generate_gtm_documentation_csv.py --input GTM-KJCRRRRC_workspace221.json --output ./gtm_docs

Notes:
  - CSV delimiter is semicolon (;), because it is usually easier for Russian/KZ Excel locales.
  - Encoding is utf-8-sig, so Excel opens Cyrillic correctly.
  - The script intentionally does NOT create unified event names. That mapping is a manual/business dictionary.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

CSV_DELIMITER = ";"
CSV_ENCODING = "utf-8-sig"

# --------------------------------------------------------------------------------------
# Generic helpers
# --------------------------------------------------------------------------------------


def read_gtm_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def ensure_container_version(data: Dict[str, Any]) -> Dict[str, Any]:
    if "containerVersion" not in data:
        raise ValueError("JSON does not look like a GTM container export: missing 'containerVersion'.")
    return data["containerVersion"]


def write_csv(path: Path, rows: List[Dict[str, Any]], fieldnames: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding=CSV_ENCODING, newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
            delimiter=CSV_DELIMITER,
            extrasaction="ignore",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def json_cell(value: Any) -> str:
    """Compact JSON for a CSV cell. Empty list/dict becomes empty string."""
    if value in (None, [], {}):
        return ""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def natural_id(value: Any) -> Tuple[int, str]:
    text = str(value or "")
    return (int(text), text) if text.isdigit() else (10**12, text)


def param_value(param: Optional[Dict[str, Any]]) -> str:
    if not param:
        return ""
    if "value" in param:
        return str(param.get("value", ""))
    # MAP/LIST values are not flat; keep them as compact JSON.
    return json_cell(param)


def get_param_obj(obj: Dict[str, Any], key: str) -> Optional[Dict[str, Any]]:
    for p in obj.get("parameter", []) or []:
        if p.get("key") == key:
            return p
    return None


def get_param_value(obj: Dict[str, Any], key: str) -> str:
    return param_value(get_param_obj(obj, key))


def map_to_dict(m: Dict[str, Any]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for item in m.get("map", []) or []:
        out[str(item.get("key", ""))] = param_value(item)
    return out


def list_maps(param_obj: Optional[Dict[str, Any]]) -> List[Dict[str, str]]:
    if not param_obj:
        return []
    return [map_to_dict(x) for x in (param_obj.get("list") or []) if x.get("type") == "MAP"]


def get_html(tag: Dict[str, Any]) -> str:
    return get_param_value(tag, "html")


def destination(tag: Dict[str, Any]) -> str:
    name = tag.get("name", "") or ""
    typ = tag.get("type", "") or ""
    if typ == "gaawe":
        return "GA4"
    if typ == "googtag":
        return "Google tag"
    if typ == "cvt_184219294_11":
        return "Amplitude"
    if typ == "cvt_184219294_261":
        return "Mixpanel"
    if name.startswith("YM") or "Yandex" in name:
        return "Yandex Metrika"
    if name.startswith("SA -"):
        return "SuperApp bridge"
    if name.startswith("AF SA") or name.startswith("AF -") or "AppsFlyer" in name:
        return "AppsFlyer"
    if name.startswith("CS -"):
        return "ClickStream"
    if name.startswith("Meta"):
        return "Meta"
    if name.startswith("TikTok"):
        return "TikTok"
    if name.startswith("DataLayer"):
        return "DataLayer"
    return "HTML/Other"


# --------------------------------------------------------------------------------------
# GTM trigger parsing
# --------------------------------------------------------------------------------------

OPERATOR_HUMAN = {
    "EQUALS": "=",
    "CONTAINS": "contains",
    "STARTS_WITH": "starts with",
    "ENDS_WITH": "ends with",
    "MATCH_REGEX": "matches regex",
    "CSS_SELECTOR": "matches CSS selector",
    "LESS_THAN": "<",
    "LESS_EQUALS": "<=",
    "GREATER_THAN": ">",
    "GREATER_EQUALS": ">=",
}


def condition_args(condition: Dict[str, Any]) -> Dict[str, str]:
    args: Dict[str, str] = {}
    for p in condition.get("parameter", []) or []:
        key = p.get("key", "")
        args[key] = param_value(p)
    return args


def condition_summary(condition: Dict[str, Any]) -> str:
    args = condition_args(condition)
    ctype = condition.get("type", "")
    left = args.get("arg0", "")
    right = args.get("arg1", "")
    negate = str(args.get("negate", "")).lower() == "true"

    if ctype == "EQUALS" and negate:
        op = "!="
    elif ctype == "CONTAINS" and negate:
        op = "does not contain"
    elif ctype == "MATCH_REGEX" and negate:
        op = "does not match regex"
    else:
        op = OPERATOR_HUMAN.get(ctype, ctype.lower() if ctype else "")

    if left or right:
        return f"{left} {op} {right}".strip()
    return json_cell(condition)


def conditions_summary(conditions: Optional[List[Dict[str, Any]]]) -> str:
    if not conditions:
        return ""
    return " AND ".join(condition_summary(c) for c in conditions)


def generate_triggers(cv: Dict[str, Any], out_dir: Path) -> Tuple[int, int]:
    triggers = cv.get("trigger", []) or []

    trigger_rows: List[Dict[str, Any]] = []
    parameter_rows: List[Dict[str, Any]] = []

    for tr in triggers:
        filters = tr.get("filter", []) or []
        custom_filters = tr.get("customEventFilter", []) or []
        params = tr.get("parameter", []) or []

        trigger_rows.append(
            {
                "accountId": tr.get("accountId", ""),
                "containerId": tr.get("containerId", ""),
                "triggerId": tr.get("triggerId", ""),
                "name": tr.get("name", ""),
                "type": tr.get("type", ""),
                "fingerprint": tr.get("fingerprint", ""),
                "parentFolderId": tr.get("parentFolderId", ""),
                "filter": json_cell(filters),
                "customEventFilter": json_cell(custom_filters),
                "filter_summary": conditions_summary(filters),
                "customEventFilter_summary": conditions_summary(custom_filters),
                "parameter": json_cell(params),
            }
        )

        for p in params:
            parameter_rows.append(
                {
                    "triggerId": tr.get("triggerId", ""),
                    "trigger_name": tr.get("name", ""),
                    "trigger_type": tr.get("type", ""),
                    "parameter_key": p.get("key", ""),
                    "parameter_value": param_value(p),
                    "parameter_type": p.get("type", ""),
                }
            )

    trigger_rows.sort(key=lambda r: natural_id(r["triggerId"]))
    parameter_rows.sort(key=lambda r: (natural_id(r["triggerId"]), r["parameter_key"]))

    write_csv(
        out_dir / "triggers_from_gtm.csv",
        trigger_rows,
        [
            "accountId",
            "containerId",
            "triggerId",
            "name",
            "type",
            "fingerprint",
            "parentFolderId",
            "filter",
            "customEventFilter",
            "filter_summary",
            "customEventFilter_summary",
            "parameter",
        ],
    )
    write_csv(
        out_dir / "trigger_parameters.csv",
        parameter_rows,
        ["triggerId", "trigger_name", "trigger_type", "parameter_key", "parameter_value", "parameter_type"],
    )

    return len(trigger_rows), len(parameter_rows)


# --------------------------------------------------------------------------------------
# Minimal JS object parsing for HTML tags
# This is not a full JavaScript parser. It is a pragmatic extractor for GTM templates.
# --------------------------------------------------------------------------------------


def find_balanced_after(text: str, pattern: str) -> Optional[str]:
    """Find first balanced {...} object after a regex pattern and return its inner text."""
    m = re.search(pattern, text, flags=re.S)
    if not m:
        return None
    start = text.find("{", m.end() - 1)
    if start == -1:
        return None

    i = start
    depth = 0
    quote: Optional[str] = None
    esc = False

    while i < len(text):
        ch = text[i]

        # GTM variables look like {{Page URL}}. Treat them as an atom, not as JS braces.
        if not quote and text.startswith("{{", i):
            end = text.find("}}", i + 2)
            if end != -1:
                i = end + 2
                continue

        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = None
        else:
            if ch in ('"', "'", "`"):
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start + 1 : i]
        i += 1
    return None


def split_top_level(s: str, sep: str = ",") -> List[str]:
    parts: List[str] = []
    buf: List[str] = []
    depth = 0
    quote: Optional[str] = None
    esc = False
    i = 0

    while i < len(s):
        ch = s[i]

        if not quote and s.startswith("{{", i):
            end = s.find("}}", i + 2)
            if end != -1:
                buf.append(s[i : end + 2])
                i = end + 2
                continue

        if quote:
            buf.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = None
        else:
            if ch in ('"', "'", "`"):
                quote = ch
                buf.append(ch)
            elif ch in "([{":
                depth += 1
                buf.append(ch)
            elif ch in ")]}":
                depth -= 1
                buf.append(ch)
            elif ch == sep and depth == 0:
                part = "".join(buf).strip()
                if part:
                    parts.append(part)
                buf = []
            else:
                buf.append(ch)
        i += 1

    part = "".join(buf).strip()
    if part:
        parts.append(part)
    return parts


def split_key_val(pair: str) -> Tuple[Optional[str], Optional[str]]:
    depth = 0
    quote: Optional[str] = None
    esc = False
    i = 0

    while i < len(pair):
        ch = pair[i]

        if not quote and pair.startswith("{{", i):
            end = pair.find("}}", i + 2)
            if end != -1:
                i = end + 2
                continue

        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = None
        else:
            if ch in ('"', "'", "`"):
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == ":" and depth == 0:
                return pair[:i].strip(), pair[i + 1 :].strip()
        i += 1
    return None, None


def clean_key(k: Optional[str]) -> str:
    if k is None:
        return ""
    k = k.strip()
    if len(k) >= 2 and k[0] == k[-1] and k[0] in ('"', "'", "`"):
        k = k[1:-1]
    return k.strip()


def clean_value(v: Optional[str]) -> str:
    if v is None:
        return ""
    v = v.strip()
    if v.endswith(";"):
        v = v[:-1].strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'", "`"):
        return v[1:-1]
    return v


def parse_obj(obj_text: Optional[str]) -> List[Tuple[str, str]]:
    if not obj_text:
        return []
    rows: List[Tuple[str, str]] = []
    for pair in split_top_level(obj_text):
        key, val = split_key_val(pair)
        key = clean_key(key)
        if key:
            rows.append((key, clean_value(val)))
    return rows


def obj_pairs_to_dict(pairs: Iterable[Tuple[str, str]]) -> Dict[str, str]:
    return {k: v for k, v in pairs}


def nested_obj_value(value: str) -> Optional[str]:
    value = value.strip()
    if value.startswith("{") and value.endswith("}"):
        return value[1:-1]
    return None


# --------------------------------------------------------------------------------------
# HTML event/parameter parsers
# --------------------------------------------------------------------------------------


def parse_ym(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # ym(id, 'reachGoal', 'event_name', {param: value})
    m = re.search(r"ym\s*\(\s*[^,]+,\s*['\"]reachGoal['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*,\s*\{", html, flags=re.S)
    if not m:
        return "", []
    event = m.group(1)
    obj = find_balanced_after(html[m.start() :], r"\{") or ""
    rows = [(k, v, "html_ym_reachGoal") for k, v in parse_obj(obj) if k and k != "event_name"]
    return event, rows


def parse_event_data(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # SuperApp bridge style: var eventData = { name: '...', params: {...} }
    obj = find_balanced_after(html, r"eventData\s*=\s*\{")
    if not obj:
        return "", []
    pairs = parse_obj(obj)
    d = obj_pairs_to_dict(pairs)
    event = clean_value(d.get("name", ""))
    rows: List[Tuple[str, str, str]] = []
    for k, v in pairs:
        if k in ("name", "backup"):
            continue
        if k == "params":
            nested = nested_obj_value(v)
            if nested:
                for nk, nv in parse_obj(nested):
                    rows.append((nk, nv, "html_eventData_params"))
            else:
                rows.append((k, v, "html_eventData"))
        else:
            rows.append((k, v, "html_eventData"))
    return event, rows


def parse_var_event_payload(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # AppsFlyer-like: var eventName = '...'; var payload = {...}
    m = re.search(r"var\s+eventName\s*=\s*['\"]([^'\"]+)['\"]", html, flags=re.S)
    if not m:
        return "", []
    event = m.group(1)
    obj = find_balanced_after(html, r"payload\s*=\s*\{") or ""
    rows = [(k, v, "html_eventName_payload") for k, v in parse_obj(obj) if k != "eventName"]
    return event, rows


def parse_payload_event_name(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # ClickStream-like: var payload = { eventName: '...', ... }
    obj = find_balanced_after(html, r"payload\s*=\s*\{")
    if not obj:
        return "", []
    pairs = parse_obj(obj)
    d = obj_pairs_to_dict(pairs)
    event = clean_value(d.get("eventName", ""))
    if not event:
        return "", []
    rows = [(k, v, "html_payload") for k, v in pairs if k != "eventName"]
    return event, rows


def parse_fbq(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # Meta Pixel: fbq('track', 'Event', {...})
    m = re.search(r"fbq\s*\(\s*['\"]track['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*(?:,\s*\{)?", html, flags=re.S)
    if not m:
        return "", []
    event = m.group(1)
    params: List[Tuple[str, str, str]] = []
    rest = html[m.end() - 1 :]
    if rest.lstrip().startswith("{"):
        obj = find_balanced_after(rest, r"\{")
        params = [(k, v, "html_meta_fbq") for k, v in parse_obj(obj)] if obj else []
    return event, params


def parse_ttq(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # TikTok Pixel: ttq.track('Event', {...})
    m = re.search(r"ttq\.track\s*\(\s*['\"]([^'\"]+)['\"]\s*(?:,\s*\{)?", html, flags=re.S)
    if not m:
        return "", []
    event = m.group(1)
    params: List[Tuple[str, str, str]] = []
    rest = html[m.end() - 1 :]
    if rest.lstrip().startswith("{"):
        obj = find_balanced_after(rest, r"\{")
        params = [(k, v, "html_tiktok_ttq") for k, v in parse_obj(obj)] if obj else []
    return event, params


def parse_data_layer_push(html: str) -> Tuple[str, List[Tuple[str, str, str]]]:
    # All dataLayer.push({event:'...'}) calls. Some tags contain several possible events.
    events: List[str] = []
    params: List[Tuple[str, str, str]] = []

    for m in re.finditer(r"dataLayer\.push\s*\(\s*\{", html, flags=re.S):
        obj = find_balanced_after(html[m.start() :], r"\{")
        if not obj:
            continue
        pairs = parse_obj(obj)
        d = obj_pairs_to_dict(pairs)
        event = clean_value(d.get("event", ""))
        if event:
            events.append(event)
            params.extend((k, v, "html_dataLayer_push") for k, v in pairs if k != "event")

    # Keep one row with a combined eventType, because one tag can push alternative status events.
    event_combo = "|".join(dict.fromkeys(events))
    return event_combo, params


HTML_PARSERS = [
    parse_ym,
    parse_event_data,
    parse_var_event_payload,
    parse_payload_event_name,
    parse_fbq,
    parse_ttq,
    parse_data_layer_push,
]


def extract_event_and_params(tag: Dict[str, Any]) -> Tuple[str, List[Tuple[str, str, str]], str]:
    """Return eventType, params [(name, value, source)], extraction_method."""
    typ = tag.get("type", "") or ""

    if typ == "gaawe":
        event = get_param_value(tag, "eventName")
        params: List[Tuple[str, str, str]] = []
        for d in list_maps(get_param_obj(tag, "eventSettingsTable")):
            if d.get("parameter"):
                params.append((d.get("parameter", ""), d.get("parameterValue", ""), "ga4_eventSettingsTable"))
        return event, params, "gaawe/eventSettingsTable"

    if typ == "cvt_184219294_11":
        event = get_param_value(tag, "eventType")
        params = []
        for d in list_maps(get_param_obj(tag, "eventProperties")):
            if d.get("name"):
                params.append((d.get("name", ""), d.get("value", ""), "amplitude_eventProperties"))
        return event, params, "amplitude/eventProperties"

    if typ == "cvt_184219294_261":
        event = get_param_value(tag, "trackEventName")
        params = []
        for d in list_maps(get_param_obj(tag, "trackParameters")):
            if d.get("name"):
                params.append((d.get("name", ""), d.get("value", ""), "mixpanel_trackParameters"))
        return event, params, "mixpanel/trackParameters"

    if typ == "html":
        html = get_html(tag)
        for parser in HTML_PARSERS:
            event, params = parser(html)
            if event:
                return event, params, parser.__name__
        return "", [], ""

    if typ == "googtag":
        return "", [], "googtag/global"

    return "", [], ""


# --------------------------------------------------------------------------------------
# Tag -> trigger and tag -> parameter generation
# --------------------------------------------------------------------------------------


def generate_tag_trigger_map(cv: Dict[str, Any], out_dir: Path) -> Tuple[int, int]:
    tags = cv.get("tag", []) or []

    rows: List[Dict[str, Any]] = []
    issues: List[Dict[str, Any]] = []

    for tag in tags:
        event, _params, method = extract_event_and_params(tag)
        has_space = bool(event and event != event.strip())

        firing_ids = tag.get("firingTriggerId", []) or []
        if not firing_ids:
            # Keep a row for tags without firing triggers as a quality signal.
            firing_ids = [""]

        for firing_id in firing_ids:
            rows.append(
                {
                    "accountId": tag.get("accountId", ""),
                    "containerId": tag.get("containerId", ""),
                    "tagId": tag.get("tagId", ""),
                    "name": tag.get("name", ""),
                    "type": tag.get("type", ""),
                    "eventType": event,
                    "fingerprint": tag.get("fingerprint", ""),
                    "firingTriggerId": firing_id,
                    "parentFolderId": tag.get("parentFolderId", ""),
                    "tagFiringOption": tag.get("tagFiringOption", ""),
                    "paused": str(tag.get("paused", "")).lower() if "paused" in tag else "",
                }
            )

        if not event:
            issues.append(
                {
                    "tagId": tag.get("tagId", ""),
                    "tagName": tag.get("name", ""),
                    "issue_type": "eventType_not_detected_or_not_event_tag",
                    "eventType_raw_repr": "",
                    "eventType_clean": "",
                    "eventType_source": method,
                }
            )
        elif has_space:
            issues.append(
                {
                    "tagId": tag.get("tagId", ""),
                    "tagName": tag.get("name", ""),
                    "issue_type": "eventType_has_leading_or_trailing_space",
                    "eventType_raw_repr": repr(event),
                    "eventType_clean": event.strip(),
                    "eventType_source": method,
                }
            )

    rows.sort(key=lambda r: (natural_id(r["tagId"]), natural_id(r["firingTriggerId"])))
    issues.sort(key=lambda r: (r["issue_type"], natural_id(r["tagId"])))

    write_csv(
        out_dir / "tag_trigger_map_from_gtm.csv",
        rows,
        [
            "accountId",
            "containerId",
            "tagId",
            "name",
            "type",
            "eventType",
            "fingerprint",
            "firingTriggerId",
            "parentFolderId",
            "tagFiringOption",
            "paused",
        ],
    )
    write_csv(
        out_dir / "tag_trigger_eventtype_issues.csv",
        issues,
        ["tagId", "tagName", "issue_type", "eventType_raw_repr", "eventType_clean", "eventType_source"],
    )

    return len(rows), len(issues)


def generate_tag_params(cv: Dict[str, Any], out_dir: Path) -> Tuple[int, int]:
    tags = cv.get("tag", []) or []

    rows: List[Dict[str, Any]] = []
    issues: List[Dict[str, Any]] = []

    for tag in tags:
        event, params, method = extract_event_and_params(tag)
        dest = destination(tag)
        typ = tag.get("type", "") or ""

        # Deduplicate exact parameter rows inside one tag/event.
        seen = set()
        clean_params: List[Tuple[str, str, str]] = []
        for p, v, src in params:
            p = (p or "").strip()
            v = (v or "").strip()
            key = (p, v, src)
            if p and key not in seen:
                clean_params.append((p, v, src))
                seen.add(key)

        if event and clean_params:
            for p, v, _src in clean_params:
                rows.append(
                    {
                        "accountId": tag.get("accountId", ""),
                        "containerId": tag.get("containerId", ""),
                        "tagId": tag.get("tagId", ""),
                        "name": tag.get("name", ""),
                        "eventType": event,
                        "parameter": p,
                        "parameterValue": v,
                    }
                )
        elif event and not clean_params:
            issues.append(
                {
                    "issue_type": "event_without_extracted_params",
                    "accountId": tag.get("accountId", ""),
                    "containerId": tag.get("containerId", ""),
                    "tagId": tag.get("tagId", ""),
                    "name": tag.get("name", ""),
                    "type": typ,
                    "destination": dest,
                    "eventType": event,
                    "extractionMethod": method,
                    "note": "EventType was detected, but no event parameters were extracted.",
                }
            )
        else:
            # Log analytics-like HTML tags where event extraction failed; skip ordinary HTML/Other init tags.
            if typ == "html" and dest not in ("HTML/Other", "DataLayer"):
                issues.append(
                    {
                        "issue_type": "no_eventType_detected",
                        "accountId": tag.get("accountId", ""),
                        "containerId": tag.get("containerId", ""),
                        "tagId": tag.get("tagId", ""),
                        "name": tag.get("name", ""),
                        "type": typ,
                        "destination": dest,
                        "eventType": "",
                        "extractionMethod": method,
                        "note": "No eventType could be detected from HTML. May be init/user/global tag.",
                    }
                )

    rows.sort(key=lambda r: (natural_id(r["tagId"]), r["eventType"], r["parameter"]))
    issues.sort(key=lambda r: (r["issue_type"], natural_id(r["tagId"])))

    write_csv(
        out_dir / "tag_params_from_gtm.csv",
        rows,
        ["accountId", "containerId", "tagId", "name", "eventType", "parameter", "parameterValue"],
    )
    write_csv(
        out_dir / "tag_params_extraction_issues.csv",
        issues,
        ["issue_type", "accountId", "containerId", "tagId", "name", "type", "destination", "eventType", "extractionMethod", "note"],
    )

    return len(rows), len(issues)


# --------------------------------------------------------------------------------------
# Entrypoint
# --------------------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate GTM documentation CSV files from container JSON export.")
    parser.add_argument("--input", "-i", required=True, help="Path to GTM container JSON export.")
    parser.add_argument("--output", "-o", default="gtm_docs_export", help="Output folder for generated CSV files.")
    return parser


def main() -> None:
    args = build_arg_parser().parse_args()
    input_path = Path(args.input).expanduser().resolve()
    out_dir = Path(args.output).expanduser().resolve()

    if not input_path.exists():
        raise FileNotFoundError(f"Input JSON file not found: {input_path}")

    data = read_gtm_json(input_path)
    cv = ensure_container_version(data)

    trigger_count, trigger_parameter_count = generate_triggers(cv, out_dir)
    tag_trigger_count, tag_trigger_issue_count = generate_tag_trigger_map(cv, out_dir)
    tag_param_count, tag_param_issue_count = generate_tag_params(cv, out_dir)

    print("Done. CSV files generated:")
    print(f"  output folder: {out_dir}")
    print(f"  triggers_from_gtm.csv: {trigger_count} rows")
    print(f"  trigger_parameters.csv: {trigger_parameter_count} rows")
    print(f"  tag_trigger_map_from_gtm.csv: {tag_trigger_count} rows")
    print(f"  tag_trigger_eventtype_issues.csv: {tag_trigger_issue_count} rows")
    print(f"  tag_params_from_gtm.csv: {tag_param_count} rows")
    print(f"  tag_params_extraction_issues.csv: {tag_param_issue_count} rows")


if __name__ == "__main__":
    main()
