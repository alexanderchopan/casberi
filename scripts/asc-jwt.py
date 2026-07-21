#!/usr/bin/env python3
"""Mint a short-lived App Store Connect API JWT (ES256), no dependencies
beyond stdlib + the system `openssl` binary — this machine has neither
PyJWT nor `cryptography` installed, and installing packages for a one-line
token isn't worth it. Usage: asc-jwt.py <key_id> <issuer_id> <p8_path>
"""
import sys, json, base64, subprocess, time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def der_to_raw(der: bytes, size: int = 32) -> bytes:
    """ECDSA DER SEQUENCE(INTEGER r, INTEGER s) -> raw r||s for JWS."""
    assert der[0] == 0x30
    idx = 2
    if der[1] & 0x80:
        idx = 2 + (der[1] & 0x7f)

    def read_int(data, i):
        assert data[i] == 0x02
        ln = data[i + 1]
        i += 2
        val = data[i:i + ln]
        i += ln
        val = val.lstrip(b'\x00').rjust(size, b'\x00')
        return val, i

    r, idx = read_int(der, idx)
    s, idx = read_int(der, idx)
    return r + s


def main():
    key_id, issuer_id, key_path = sys.argv[1], sys.argv[2], sys.argv[3]
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1190, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(',', ':')).encode()) + "." +
        b64url(json.dumps(payload, separators=(',', ':')).encode())
    )
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), stdout=subprocess.PIPE, check=True,
    )
    raw_sig = der_to_raw(proc.stdout)
    print(signing_input + "." + b64url(raw_sig))


if __name__ == "__main__":
    main()
