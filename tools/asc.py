#!/usr/bin/env python3
"""Minimal App Store Connect API client (ES256 JWT via cryptography). Usage: asc.py GET|PATCH|POST|DELETE <path> [json-body]"""
import base64, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
API="https://api.appstoreconnect.apple.com"
KEY_ID=os.environ.get("ASC_KEY_ID","$ASC_KEY_ID"); ISSUER=os.environ.get("ASC_ISSUER_ID","$ASC_ISSUER_ID")
KEY_PATH=Path(os.environ.get("ASC_KEY_PATH",f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")).expanduser()
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def token():
    now=int(time.time()); h=b64(json.dumps({"alg":"ES256","kid":KEY_ID,"typ":"JWT"},separators=(",",":")).encode())
    p=b64(json.dumps({"iss":ISSUER,"iat":now-20,"exp":now+1200,"aud":"appstoreconnect-v1"},separators=(",",":")).encode())
    key=serialization.load_pem_private_key(KEY_PATH.read_bytes(),password=None)
    r,s=decode_dss_signature(key.sign(f"{h}.{p}".encode(),ec.ECDSA(hashes.SHA256())))
    return f"{h}.{p}.{b64(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}"
def request(method,path,body=None,raw=None,ctype="application/json"):
    data=raw if raw is not None else (None if body is None else json.dumps(body).encode())
    req=urllib.request.Request(path if path.startswith("http") else API+path,data=data,method=method,
        headers={"Authorization":f"Bearer {token()}","Accept":"application/json","Content-Type":ctype})
    try:
        with urllib.request.urlopen(req,timeout=60) as r:
            b=r.read(); return r.status,(json.loads(b) if b else {})
    except urllib.error.HTTPError as e:
        b=e.read()
        try: return e.code,json.loads(b)
        except Exception: return e.code,{"raw":b[:500].decode(errors="replace")}
if __name__=="__main__":
    m,p=sys.argv[1],sys.argv[2]; body=json.loads(sys.argv[3]) if len(sys.argv)>3 else None
    st,d=request(m,p,body); print(st); print(json.dumps(d,indent=1,ensure_ascii=False)[:6000])
