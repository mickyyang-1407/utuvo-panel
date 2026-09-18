#!/usr/bin/env python3
"""Pull a waiting submission, swap build + screenshots, submit again.
usage: resubmit.py <build-version> <screenshot-dir> <name> [<name> ...]   (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)"""
import hashlib, json, sys, time, urllib.request
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from asc import request

APP, VER = "6812964840", "cf1e60dc-8f70-4775-9f80-ddbf01ba5966"
build_version, shot_dir, names = sys.argv[1], sys.argv[2], sys.argv[3:]


def ok(tag, st, d):
    print(tag, st)
    if st >= 300:
        raise SystemExit(json.dumps(d, ensure_ascii=False)[:600])
    return d


# 1. cancel any live submission
st, d = request("GET", f"/v1/apps/{APP}/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW,READY_FOR_REVIEW,UNRESOLVED_ISSUES")
for rs in d.get("data", []):
    if rs["attributes"]["state"] == "WAITING_FOR_REVIEW":
        ok(f"cancel {rs['id']}", *request("PATCH", f"/v1/reviewSubmissions/{rs['id']}",
                                         {"data": {"type": "reviewSubmissions", "id": rs["id"], "attributes": {"canceled": True}}}))
for _ in range(40):
    st, v = request("GET", f"/v1/appStoreVersions/{VER}")
    state = v["data"]["attributes"]["appVersionState"]
    if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "READY_FOR_REVIEW"):
        break
    time.sleep(5)
print("version state", state)

# 2. attach the new build
st, b = request("GET", f"/v1/builds?filter[app]={APP}&filter[version]={build_version}&limit=1")
build = b["data"][0]
assert build["attributes"]["processingState"] == "VALID", build["attributes"]["processingState"]
ok("attach build", *request("PATCH", f"/v1/appStoreVersions/{VER}/relationships/build", {"data": {"type": "builds", "id": build["id"]}}))

# 3. replace screenshots in every locale's 6.9"/6.7" set
st, l = request("GET", f"/v1/appStoreVersions/{VER}/appStoreVersionLocalizations?include=appScreenshotSets")
for loc in l["data"]:
    for s in loc["relationships"]["appScreenshotSets"]["data"] or []:
        st, ss = request("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
        for shot in ss.get("data", []):
            ok(f"  delete {shot['attributes']['fileName']}", *request("DELETE", f"/v1/appScreenshots/{shot['id']}"))
        for i, n in enumerate(names):
            data = open(f"{shot_dir}/{n}.png", "rb").read()
            r = ok(f"  reserve {n}", *request("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                   "attributes": {"fileName": f"panel-{i + 1}-{n}.png", "fileSize": len(data)},
                   "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}}))
            sid = r["data"]["id"]
            for op in r["data"]["attributes"]["uploadOperations"]:
                req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                             headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                urllib.request.urlopen(req, timeout=120).read()
            ok(f"  commit {n}", *request("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
               "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}))
    print("locale done", loc["attributes"]["locale"])

# 4. wait for screenshot processing, then submit
for _ in range(40):
    pending = 0
    for loc in l["data"]:
        for s in loc["relationships"]["appScreenshotSets"]["data"] or []:
            st, ss = request("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
            pending += sum(1 for x in ss["data"] if (x["attributes"].get("assetDeliveryState") or {}).get("state") != "COMPLETE")
    if not pending:
        break
    time.sleep(5)
print("screenshots pending", pending)
d = ok("new submission", *request("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
       "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}}))
rs = d["data"]["id"]
ok("add version", *request("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
   "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VER}}}}}))
ok("submit", *request("PATCH", f"/v1/reviewSubmissions/{rs}", {"data": {"type": "reviewSubmissions", "id": rs, "attributes": {"submitted": True}}}))
st, v = request("GET", f"/v1/appStoreVersions/{VER}")
print("DONE submission", rs, "version", v["data"]["attributes"]["appVersionState"])
