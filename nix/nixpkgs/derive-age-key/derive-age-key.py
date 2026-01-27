#!/usr/bin/env python3
"""Derive an age private key from 32 bytes of hex input on stdin."""

import argparse
import sys

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def bech32_polymod(values: list[int]) -> int:
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ v
        for i in range(5):
            chk ^= gen[i] if ((b >> i) & 1) else 0
    return chk


def bech32_hrp_expand(hrp: str) -> list[int]:
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def bech32_checksum(hrp: str, data: list[int]) -> list[int]:
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0] * 6) ^ 1
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def to_5bit(data: bytes) -> list[int]:
    acc, bits, ret = 0, 0, []
    for val in data:
        acc = (acc << 8) | val
        bits += 8
        while bits >= 5:
            bits -= 5
            ret.append((acc >> bits) & 31)
    if bits:
        ret.append((acc << (5 - bits)) & 31)
    return ret


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Derive an age private key from 32 bytes of hex input.",
        epilog="Example: echo -n 'serial' | argon2 'salt' -id -t 4 -m 16 -p 2 -l 32 -r | derive-age-key",
    )
    parser.parse_args()

    hex_input = sys.stdin.read().strip()
    if len(hex_input) != 64:
        sys.exit(f"Error: Expected 64 hex characters (32 bytes), got {len(hex_input)}")

    raw = bytes.fromhex(hex_input)
    hrp = "age-secret-key-"
    data5 = to_5bit(raw)
    cs = bech32_checksum(hrp, data5)
    key = hrp + "1" + "".join(CHARSET[d] for d in data5 + cs)
    print(key.upper())


if __name__ == "__main__":
    main()
