"""Keeps one Apple Development certificate for the device lane.

Every runner is a fresh Mac. Left alone, Xcode's automatic signing makes a
new development certificate on each run, and Apple caps how many an
account may hold. So this script creates one certificate once, through the
App Store Connect API, and keeps it encrypted in the GitHub Actions cache
(ci/.signing/dev.enc). The password is derived from the API key secret, so
the cached file is useless to anyone without that secret. Later runs
decrypt it, check that Apple still knows the certificate, and import it into
a throwaway keychain where Xcode finds it and stops minting new ones.

Needs only the Python standard library and the system openssl.

    python3 ci/dev_cert.py   # env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, RUNNER_TEMP
Writes "created=true|false" to $GITHUB_OUTPUT.
"""

import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
HERE = Path(__file__).resolve().parent
STORE = HERE / ".signing"
ENC = STORE / "dev.enc"
OPENSSL = "/usr/bin/openssl"  # LibreSSL on macOS: its p12 is what `security` imports


def run(*args, data=None):
    return subprocess.run(args, input=data, check=True, capture_output=True).stdout


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """ES256 JWTs want r||s, openssl gives an ASN.1 DER sequence."""
    def read_int(buf, i):
        assert buf[i] == 0x02
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 3
    r, i = read_int(sig, i)
    s, _ = read_int(sig, i)
    return r + s


def token() -> str:
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}".encode()
    der = run(OPENSSL, "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"], data=signing_input)
    return signing_input.decode() + "." + b64url(der_to_raw(der))


def api(method: str, path: str, body=None):
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read() or b"{}")


def secret(label: str) -> str:
    """A stable password derived from the API key secret."""
    key = Path(os.environ["ASC_KEY_PATH"]).read_bytes()
    return hashlib.sha256(key + b"ma-dev-cert:" + label.encode()).hexdigest()


def create(work: Path):
    run(OPENSSL, "genrsa", "-out", str(work / "dev.key"), "2048")
    run(OPENSSL, "req", "-new", "-key", str(work / "dev.key"), "-out", str(work / "dev.csr"), "-subj", "/CN=Ma CI/")
    csr = (work / "dev.csr").read_text()
    status, body = api("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DEVELOPMENT", "csrContent": csr}}})
    if status != 201:
        detail = json.dumps(body.get("errors", body))[:600]
        if "maximum" in detail.lower() or status == 409:
            print("::error::Apple's limit for development certificates is reached. Revoke the old "
                  "'Apple Development' certificates made by CI under Certificates in the developer portal, "
                  "then run the device lane again. Details: " + detail)
        else:
            print(f"::error::Creating the development certificate failed ({status}): {detail}")
        sys.exit(1)
    cert_id = body["data"]["id"]
    der = base64.b64decode(body["data"]["attributes"]["certificateContent"])
    (work / "dev.cer").write_bytes(der)
    run(OPENSSL, "x509", "-inform", "DER", "-in", str(work / "dev.cer"), "-out", str(work / "dev.pem"))
    run(OPENSSL, "pkcs12", "-export", "-inkey", str(work / "dev.key"), "-in", str(work / "dev.pem"),
        "-out", str(work / "dev.p12"), "-passout", "pass:" + secret("p12"))
    bundle = json.dumps({"id": cert_id, "p12": base64.b64encode((work / "dev.p12").read_bytes()).decode()}).encode()
    STORE.mkdir(exist_ok=True)
    run(OPENSSL, "enc", "-aes-256-cbc", "-md", "sha256", "-salt", "-pass", "pass:" + secret("cache"),
        "-out", str(ENC), data=bundle)
    print(f"Created development certificate {cert_id}")
    return work / "dev.p12"


def restore(work: Path):
    if not ENC.exists():
        return None
    try:
        bundle = json.loads(run(OPENSSL, "enc", "-d", "-aes-256-cbc", "-md", "sha256", "-pass",
                                "pass:" + secret("cache"), "-in", str(ENC)))
    except (subprocess.CalledProcessError, ValueError):
        print("::warning::Cached certificate could not be decrypted, making a new one")
        return None
    status, _ = api("GET", "/certificates/" + bundle["id"])
    if status != 200:
        print(f"::warning::Cached certificate {bundle['id']} is gone at Apple ({status}), making a new one")
        return None
    (work / "dev.p12").write_bytes(base64.b64decode(bundle["p12"]))
    print(f"Reusing development certificate {bundle['id']}")
    return work / "dev.p12"


def install(p12: Path, work: Path):
    keychain = str(work / "ma-signing.keychain-db")
    kc_pass = secret("keychain")
    run("security", "create-keychain", "-p", kc_pass, keychain)
    run("security", "set-keychain-settings", "-lut", "21600", keychain)
    run("security", "unlock-keychain", "-p", kc_pass, keychain)
    run("security", "import", str(p12), "-k", keychain, "-P", secret("p12"),
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", "-T", "/usr/bin/productbuild")
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", kc_pass, keychain)
    existing = run("security", "list-keychains", "-d", "user").decode().split()
    existing = [k.strip().strip('"') for k in existing]
    run("security", "list-keychains", "-d", "user", "-s", keychain, *existing)
    print(run("security", "find-identity", "-v", "-p", "codesigning", keychain).decode())


def main():
    work = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "ma-signing"
    work.mkdir(parents=True, exist_ok=True)
    p12 = restore(work)
    created = p12 is None
    if created:
        p12 = create(work)
    install(p12, work)
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write(f"created={'true' if created else 'false'}\n")


if __name__ == "__main__":
    main()
