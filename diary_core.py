"""
diary_core.py — Phase 1: Local Python Prototype Algorithm Validation
Privacy Diary App Core Logic (Multimedia + Key-based Encryption)
"""

import json
import base64
import hashlib
import os
import struct
import datetime

# Optional: PIL for test image generation
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


# ---------------------------------------------------------------------------
# 1. Multimedia Package Format
# ---------------------------------------------------------------------------

def build_diary_dict(text: str, photo_base64: str = "", video_base64: str = "") -> dict:
    return {
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "text": text,
        "photo_base64": photo_base64,
        "video_base64": video_base64,
    }


# ---------------------------------------------------------------------------
# 2. Base64-variant Encryption (key-derived XOR + alphabet shuffle)
# ---------------------------------------------------------------------------

def _derive_key_stream(key: str, length: int) -> bytes:
    """Expand an arbitrary string key into a byte stream via SHA-256 chaining."""
    stream = bytearray()
    seed = key.encode("utf-8")
    block = hashlib.sha256(seed).digest()
    while len(stream) < length:
        stream.extend(block)
        block = hashlib.sha256(block + seed).digest()
    return bytes(stream[:length])


def _build_custom_alphabet(key: str) -> bytes:
    """Deterministically shuffle the Base64 alphabet using the key."""
    std = bytearray(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    seed_int = int(hashlib.md5(key.encode()).hexdigest(), 16)
    # Fisher-Yates with seeded LCG
    a, c, m = seed_int | 1, 0x3039, 2**32
    state = seed_int
    for i in range(len(std) - 1, 0, -1):
        state = (a * state + c) % m
        j = state % (i + 1)
        std[i], std[j] = std[j], std[i]
    return bytes(std)


def _translate_b64(data: bytes, src_alpha: bytes, dst_alpha: bytes) -> bytes:
    table = bytes.maketrans(src_alpha, dst_alpha)
    return data.translate(table)


_STD_ALPHA = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def encrypt_diary(data_dict: dict, key: str) -> str:
    """
    Encrypt a diary dict to an obfuscated ciphertext string.

    Pipeline:
      JSON bytes → XOR with key-stream → standard Base64 → alphabet-shuffle Base64
    The result looks like random noise / a system token stream.
    """
    plaintext = json.dumps(data_dict, ensure_ascii=False).encode("utf-8")
    key_stream = _derive_key_stream(key, len(plaintext))
    xored = bytes(p ^ k for p, k in zip(plaintext, key_stream))
    std_b64 = base64.b64encode(xored)
    custom_alpha = _build_custom_alphabet(key)
    shuffled = _translate_b64(std_b64, _STD_ALPHA, custom_alpha)
    return shuffled.decode("ascii")


def decrypt_diary(cipher_text: str, key: str) -> dict:
    """
    Decrypt a ciphertext string back to the original diary dict.
    """
    custom_alpha = _build_custom_alphabet(key)
    std_b64 = _translate_b64(cipher_text.encode("ascii"), custom_alpha, _STD_ALPHA)
    xored = base64.b64decode(std_b64)
    key_stream = _derive_key_stream(key, len(xored))
    plaintext = bytes(x ^ k for x, k in zip(xored, key_stream))
    return json.loads(plaintext.decode("utf-8"))


# ---------------------------------------------------------------------------
# 3. One-click Global Key Update
# ---------------------------------------------------------------------------

def rekey_diary_store(cipher_list: list[str], old_key: str, new_key: str) -> list[str]:
    """Re-encrypt every entry in cipher_list from old_key to new_key."""
    updated = []
    for ct in cipher_list:
        data = decrypt_diary(ct, old_key)
        updated.append(encrypt_diary(data, new_key))
    return updated


# ---------------------------------------------------------------------------
# 4. Test Image Generation
# ---------------------------------------------------------------------------

def _generate_test_image_base64(path: str = "test_image.png") -> str:
    """Generate a 100×100 gradient PNG and return its Base64 encoding."""
    if HAS_PIL:
        img = Image.new("RGB", (100, 100))
        pixels = img.load()
        for y in range(100):
            for x in range(100):
                pixels[x, y] = (x * 2, y * 2, 128)
        img.save(path)
    else:
        # Minimal valid 100×100 solid-blue PNG written without PIL
        _write_minimal_png(path)

    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def _write_minimal_png(path: str):
    """Write a 100×100 solid blue PNG using only stdlib."""
    import zlib

    def u32(n):
        return struct.pack(">I", n)

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = tag + data
        return u32(len(data)) + c + u32(zlib.crc32(c) & 0xFFFFFFFF)

    ihdr_data = struct.pack(">IIBBBBB", 100, 100, 8, 2, 0, 0, 0)
    raw_rows = b"".join(b"\x00" + b"\x00\x00\xFF" * 100 for _ in range(100))
    idat_data = zlib.compress(raw_rows)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr_data)
    png += chunk(b"IDAT", idat_data)
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------------------
# 5. Automated Test Runner
# ---------------------------------------------------------------------------

def _separator(title: str = ""):
    line = "─" * 60
    print(f"\n{line}")
    if title:
        print(f"  {title}")
        print(line)


def run_tests():
    OLD_KEY = "MySecret@2024"
    NEW_KEY = "N3wP@ssphrase!iOS"
    IMAGE_PATH = "test_diary_image.png"

    _separator("STEP 1 — Generate test image")
    photo_b64 = _generate_test_image_base64(IMAGE_PATH)
    print(f"  Generated: {IMAGE_PATH}  ({len(photo_b64)} chars Base64)")

    _separator("STEP 2 — Build 3 sample diary entries")
    entries_plain = [
        build_diary_dict("Today was a great day hiking in the mountains.", photo_b64, ""),
        build_diary_dict("Finished reading 'Atomic Habits'. Highly recommended.", "", ""),
        build_diary_dict("Secret recipe: flour 200g, butter 100g, sugar 80g.", photo_b64, ""),
    ]
    for i, e in enumerate(entries_plain, 1):
        print(f"  Entry {i}: {e['timestamp']}  |  text[:40]: {e['text'][:40]}")

    _separator("STEP 3 — Encrypt all entries with OLD_KEY")
    cipher_store = [encrypt_diary(e, OLD_KEY) for e in entries_plain]
    for i, ct in enumerate(cipher_store, 1):
        print(f"  Cipher {i} (first 80 chars): {ct[:80]}…")

    _separator("STEP 4 — Decrypt and verify round-trip")
    all_ok = True
    for i, (ct, original) in enumerate(zip(cipher_store, entries_plain), 1):
        recovered = decrypt_diary(ct, OLD_KEY)
        match = (recovered == original)
        all_ok = all_ok and match
        print(f"  Entry {i} round-trip {'✓ PASS' if match else '✗ FAIL'}")
    print(f"\n  Overall: {'ALL PASSED' if all_ok else 'FAILURES DETECTED'}")

    _separator("STEP 5 — Re-key store: OLD_KEY → NEW_KEY")
    new_cipher_store = rekey_diary_store(cipher_store, OLD_KEY, NEW_KEY)
    print(f"  {'Entry':<8}  {'Old cipher (first 40)':<42}  {'New cipher (first 40)'}")
    print(f"  {'─'*7}  {'─'*42}  {'─'*42}")
    for i, (old_ct, new_ct) in enumerate(zip(cipher_store, new_cipher_store), 1):
        print(f"  {i:<8}  {old_ct[:40]:<42}  {new_ct[:40]}")

    _separator("STEP 6 — Verify new ciphertexts with NEW_KEY")
    all_ok2 = True
    for i, (new_ct, original) in enumerate(zip(new_cipher_store, entries_plain), 1):
        recovered = decrypt_diary(new_ct, NEW_KEY)
        match = (recovered == original)
        all_ok2 = all_ok2 and match
        print(f"  Entry {i} post-rekey round-trip {'✓ PASS' if match else '✗ FAIL'}")
    print(f"\n  Overall: {'ALL PASSED' if all_ok2 else 'FAILURES DETECTED'}")

    _separator("AI DECRYPTION PROMPT MANUAL")
    print(AI_PROMPT_MANUAL)

    # Cleanup temp image
    if os.path.exists(IMAGE_PATH):
        os.remove(IMAGE_PATH)
        print(f"\n  Cleaned up: {IMAGE_PATH}")


# ---------------------------------------------------------------------------
# 6. Multimodal AI Decryption Prompt Manual
# ---------------------------------------------------------------------------

AI_PROMPT_MANUAL = """
┌─────────────────────────────────────────────────────────────┐
│         DECRYPTION PROMPT MANUAL FOR MULTIMODAL AI          │
│              diary_core.py  —  Version 1.0                  │
└─────────────────────────────────────────────────────────────┘

PURPOSE
  This manual tells any AI assistant (GPT-4o, Gemini, Claude, etc.)
  exactly how to decrypt a Privacy Diary ciphertext produced by
  diary_core.py and reconstruct the original multimedia diary entry.

ALGORITHM OVERVIEW
  The encryption pipeline has two layers:

  Layer 1 — XOR with a key-derived stream
    • The key string is hashed with SHA-256 iteratively to produce
      a byte stream of arbitrary length.
    • The UTF-8 JSON payload is XOR-ed byte-by-byte with this stream.

  Layer 2 — Custom Base64 alphabet shuffle
    • The standard Base64 alphabet (A–Z a–z 0–9 + /) is shuffled
      with a Fisher-Yates algorithm seeded by MD5(key).
    • The XOR result is encoded in standard Base64, then each
      character is translated to the shuffled alphabet.

DECRYPTION STEPS (implement in any language)
  1. Derive the custom alphabet:
       seed = int(MD5(key).hexdigest, base=16)
       Shuffle "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
       using Fisher-Yates with LCG  state = (seed|1 * state + 0x3039) % 2^32

  2. Translate the ciphertext back to standard Base64:
       apply str.translate(custom_alphabet → standard_alphabet)

  3. Base64-decode → XOR bytes
       key_stream = SHA-256 chain of key bytes (same expansion as above)
       plaintext  = [ct_byte XOR ks_byte for each byte]

  4. UTF-8 decode → JSON parse → obtain dict with keys:
       timestamp    — ISO-8601 string (UTC)
       text         — diary text (plain string)
       photo_base64 — standard Base64-encoded PNG/JPEG bytes (may be empty)
       video_base64 — standard Base64-encoded MP4 bytes (may be empty)

  5. To recover the image:
       image_bytes = base64.decode(entry["photo_base64"])
       save as .png or .jpg and display.

PYTHON ONE-LINER DECRYPTION (requires diary_core module)
  import diary_core, json
  entry = diary_core.decrypt_diary(cipher_text, key)
  print(json.dumps(entry, indent=2, ensure_ascii=False))

SECURITY NOTES
  • The key is NEVER stored in the ciphertext. Without the correct
    key, decryption yields garbage — partial XOR errors cascade.
  • Changing the key via rekey_diary_store() produces visually
    different ciphertexts while preserving all data.
  • For production iOS use, replace the XOR layer with AES-256-GCM
    (key = PBKDF2(user_passphrase, random_salt, 310000 iterations)).

CONTACT / INTEGRATION
  If you are an AI processing an encrypted diary blob:
  1. Ask the user for their decryption key (never log or store it).
  2. Run the steps above to recover the JSON.
  3. Render text and decode any embedded Base64 media for display.
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    run_tests()
