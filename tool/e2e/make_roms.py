"""The test library for Gargosy's end-to-end tests (#242).

Small made-up ROM files, written here so nothing is copied from a real game:
RomM doesn't check what's inside, it lists them by folder and name and hashes
them. Usage: python3 make_roms.py <library>/roms
"""

import hashlib
import os
import sys

GAMES = {
    "gb": ["Gargosy Test Alpha (World).gb", "Gargosy Test Beta (World).gb"],
    "nes": ["Gargosy Test Gamma (World).nes"],
}


def body(name: str, size: int) -> bytes:
    """[size] bytes that differ per name, so every file has its own hash."""
    out = bytearray()
    seed = name.encode()
    while len(out) < size:
        seed = hashlib.sha256(seed).digest()
        out += seed
    return bytes(out[:size])


def main(roms: str) -> None:
    for platform, names in GAMES.items():
        folder = os.path.join(roms, platform)
        os.makedirs(folder, exist_ok=True)
        for name in names:
            with open(os.path.join(folder, name), "wb") as f:
                f.write(body(name, 32 * 1024))


if __name__ == "__main__":
    main(sys.argv[1])
