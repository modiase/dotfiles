#!/usr/bin/env python3
"""Sign JWT for GCP Workload Identity Federation using ES256."""

import base64
import json
import sys
import time
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def create_jwt(private_key_path: str, issuer: str, subject: str, audience: str) -> str:
    key_data = Path(private_key_path).read_bytes()
    private_key = serialization.load_pem_private_key(key_data, password=None)

    now = int(time.time())
    header = {"alg": "ES256", "typ": "JWT", "kid": subject}
    payload = {
        "iss": issuer,
        "sub": subject,
        "aud": audience,
        "iat": now,
        "exp": now + 3600,
    }

    header_b64 = b64url_encode(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    message = f"{header_b64}.{payload_b64}".encode()

    der_sig = private_key.sign(message, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_sig)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    signature_b64 = b64url_encode(signature)

    return f"{header_b64}.{payload_b64}.{signature_b64}"


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(
            "Usage: gcp-wif-token <private_key_path> <issuer> <subject> <audience>",
            file=sys.stderr,
        )
        sys.exit(1)

    jwt = create_jwt(
        private_key_path=sys.argv[1],
        issuer=sys.argv[2],
        subject=sys.argv[3],
        audience=sys.argv[4],
    )
    print(
        json.dumps(
            {
                "version": 1,
                "success": True,
                "token_type": "urn:ietf:params:oauth:token-type:jwt",
                "id_token": jwt,
                "expiration_time": int(time.time()) + 3600,
            }
        )
    )
