#!/usr/bin/env python3
"""One-line App Store review status for the morning brief.
usage: review-status.py [--format brief]      (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)

Prints nothing and exits 2 when the app has no version in flight; exits 1 on any API failure so
the caller can say "讀不到" out loud instead of silently printing nothing.
"""
import datetime, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import request

APP = "6812964840"
VER = "cf1e60dc-8f70-4775-9f80-ddbf01ba5966"

# What each state means for Micky. Anything not listed is surfaced verbatim.
ACTION = {
    "WAITING_FOR_REVIEW": ("⏳", "排隊中，沒事可做"),
    "IN_REVIEW": ("🔎", "審核員正在看"),
    "PENDING_DEVELOPER_RELEASE": ("🎉", "**過了！releaseType 是 MANUAL，要你親手按發布**"),
    "READY_FOR_DISTRIBUTION": ("✅", "已發布"),
    "REJECTED": ("🔴", "**被退件——去 ASC 的 Resolution Center 看理由，信箱 mickymaster@me.com**"),
    "DEVELOPER_REJECTED": ("🟠", "你自己撤回了"),
    "METADATA_REJECTED": ("🔴", "**metadata 被退——看 Resolution Center**"),
    "INVALID_BINARY": ("🔴", "**binary 無效，要重新上傳**"),
    "PREPARE_FOR_SUBMISSION": ("📝", "還沒送出"),
}


def days_since(iso):
    if not iso:
        return None
    t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return (datetime.datetime.now(datetime.timezone.utc) - t).days


def main():
    st, v = request("GET", f"/v1/appStoreVersions/{VER}?include=build")
    if st >= 300:
        raise SystemExit(1)
    a = v["data"]["attributes"]
    state = a["appVersionState"]
    build = next((i["attributes"]["version"] for i in v.get("included", []) if i["type"] == "builds"), "—")

    st, rs = request("GET", f"/v1/apps/{APP}/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&limit=1")
    if st >= 300:
        raise SystemExit(1)
    sub = rs["data"][0] if rs.get("data") else None
    waited = days_since(sub["attributes"].get("submittedDate")) if sub else None

    icon, what = ACTION.get(state, ("❓", "沒看過的狀態，去 ASC 看一眼"))
    line = f"{icon} Panel 審核：{state}（{a['versionString']} build {build}"
    if waited is not None:
        line += f"，已等 {waited} 天"
    line += f"）— {what}"
    print(line)
    if state in ("PENDING_DEVELOPER_RELEASE", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
        print("   → 這條要處理，處理完跟任一條線說一聲，我把監看關掉")


if __name__ == "__main__":
    main()
