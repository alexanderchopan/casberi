#!/usr/bin/env python3
"""aws-sigv4-vectors.py — an INDEPENDENT reference implementation of AWS
Signature Version 4, used only to derive fixed test vectors for
`scripts/aws-selftest.sh`. Mirrors `safetx-vectors.py`'s role for the Safe
signer: this script's job is not to be pretty, it is to be a SECOND
implementation of the published algorithm (AWS's "Signature Calculations"
spec) written from the spec text rather than copied from the app — so that
when it agrees with `Model/AWSBridge.swift`'s `AWSSigV4`, the agreement is
evidence, not a shared bug. `scripts/aws-selftest.sh` greps this script's OWN
printed output to prove the fixture values it pins are these values, not
typed-by-hand numbers that quietly drifted from what this script would say.

Uses only hashlib/hmac from the standard library — no boto3, no network, no
AWS SDK. The access key/secret key below are AWS's own published example
credentials (used throughout Amazon's SigV4 documentation), not a real
credential.

Algorithm, in full, for anyone re-deriving this without the docs open:

  1. Canonical request:
       METHOD \n
       CanonicalURI \n
       CanonicalQueryString \n
       CanonicalHeaders (each "name:value\n", sorted, trimmed, lowercased) \n
       SignedHeaders (";"-joined lowercase header names, sorted) \n
       HashedPayload (hex sha256 of the body, "" hashes to the well-known
       empty-string digest)
  2. String to sign:
       "AWS4-HMAC-SHA256" \n
       amzDate ("YYYYMMDDTHHMMSSZ") \n
       credentialScope ("YYYYMMDD/region/service/aws4_request") \n
       hex(sha256(canonical request))
  3. Signing key, an HMAC chain seeded with the literal "AWS4" + secret key:
       kDate    = HMAC-SHA256("AWS4" + secret, dateStamp)
       kRegion  = HMAC-SHA256(kDate, region)
       kService = HMAC-SHA256(kRegion, service)
       kSigning = HMAC-SHA256(kService, "aws4_request")
  4. Signature = hex(HMAC-SHA256(kSigning, string to sign))
"""
import hashlib
import hmac
import urllib.parse

ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
REGION = "us-east-1"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hmac_sha256(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def uri_encode(s: str, encode_slash: bool = True) -> str:
    safe = "" if encode_slash else "/"
    return urllib.parse.quote(s, safe=safe + "-_.~" if not encode_slash else "-_.~")


def canonical_query(params: dict) -> str:
    parts = []
    for k in sorted(params.keys()):
        parts.append(f"{uri_encode(k)}={uri_encode(params[k])}")
    return "&".join(parts)


def sign(method: str, host: str, path: str, query: dict, headers: dict,
         body: bytes, service: str, amz_date: str) -> dict:
    date_stamp = amz_date[:8]
    canonical_uri = path if path else "/"
    canonical_qs = canonical_query(query)
    # Every header name in this script's own vectors is already lowercase, so
    # sorting the dict directly is exact.
    canonical_headers = "".join(f"{n}:{v.strip()}\n" for n, v in
                                 sorted(headers.items(), key=lambda kv: kv[0]))
    signed_headers = ";".join(sorted(headers.keys()))
    hashed_payload = sha256_hex(body)

    canonical_request = "\n".join([
        method, canonical_uri, canonical_qs, canonical_headers,
        signed_headers, hashed_payload,
    ])

    credential_scope = f"{date_stamp}/{REGION}/{service}/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256", amz_date, credential_scope,
        sha256_hex(canonical_request.encode("utf-8")),
    ])

    k_date = hmac_sha256(("AWS4" + SECRET_KEY).encode("utf-8"), date_stamp)
    k_region = hmac_sha256(k_date, REGION)
    k_service = hmac_sha256(k_region, service)
    k_signing = hmac_sha256(k_service, "aws4_request")
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"),
                          hashlib.sha256).hexdigest()

    authorization = (
        f"AWS4-HMAC-SHA256 Credential={ACCESS_KEY}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    return {
        "canonical_request": canonical_request,
        "string_to_sign": string_to_sign,
        "signature": signature,
        "authorization": authorization,
    }


def main():
    # Vector 1 — a GET with a query string (EC2/RDS Query-protocol shape,
    # and S3's ListBuckets): DescribeDBInstances against RDS.
    amz_date_1 = "20250115T120000Z"
    headers_1 = {
        "host": "rds.us-east-1.amazonaws.com",
        "x-amz-date": amz_date_1,
    }
    query_1 = {"Action": "DescribeDBInstances", "Version": "2014-10-31"}
    v1 = sign("GET", "rds.us-east-1.amazonaws.com", "/", query_1, headers_1,
              b"", "rds", amz_date_1)

    # Vector 2 — a POST with a JSON body (CloudWatch/CodePipeline JSON 1.1
    # shape): DescribeAlarms against CloudWatch's monitoring endpoint.
    amz_date_2 = "20250115T120000Z"
    body_2 = b'{"StateValue":"ALARM"}'
    # The shipped Swift signer (`AWSSigV4.sign`) signs exactly THREE headers
    # unconditionally-plus-one: host, x-amz-date, and x-amz-content-sha256
    # whenever the body is non-empty. It deliberately does NOT sign
    # content-type — SigV4 does not require every sent header to be signed,
    # and Content-Type is sent as an ordinary (unsigned) header by
    # `IngestSupport.postJSON` instead. Matched here so the two
    # implementations sign the IDENTICAL header set.
    headers_2 = {
        "host": "monitoring.us-east-1.amazonaws.com",
        "x-amz-date": amz_date_2,
        "x-amz-content-sha256": sha256_hex(body_2),
    }
    v2 = sign("POST", "monitoring.us-east-1.amazonaws.com", "/", {},
              headers_2, body_2, "monitoring", amz_date_2)

    print("=== Vector 1: GET, query string, empty body (RDS) ===")
    print("canonical_request:")
    print(v1["canonical_request"])
    print("string_to_sign:")
    print(v1["string_to_sign"])
    print("signature:", v1["signature"])
    print()
    print("=== Vector 2: POST, JSON body (CloudWatch) ===")
    print("canonical_request:")
    print(v2["canonical_request"])
    print("string_to_sign:")
    print(v2["string_to_sign"])
    print("signature:", v2["signature"])


if __name__ == "__main__":
    main()
