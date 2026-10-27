# Threat model (Slice 1 prototype)

This is a Slice 1 prototype. It is not production-audited and is not Signal-equivalent. Public release requires an independent cryptographic review.

## In scope

- Nearby attacker who can observe or inject bytes on a connected endpoint
- Replay of an old envelope
- Duplicate delivery
- Wrong recipient
- Pairing without both users comparing the 6-digit code
- Identity private key stays in secure storage, not SQL, logs, or git

## Prototype protocol

- Ed25519 identity signatures
- Ephemeral X25519 key agreement
- HKDF-SHA256 session keys (`nexus-slice1-v1`)
- AES-256-GCM with a 12-byte CSPRNG nonce
- Envelope metadata as AEAD associated data
- Handshake transcript signed by identity keys
- Safety code = first 32 bits of SHA-256(transcript) as a 6-digit number
- Seen-id replay protection and key version field

## Remaining risks

- Safety code is 6 digits from a hash prefix, not a full SAS
- No double-ratchet / future secrecy
- Session key held in memory after verify
- Nearby Connections trust model is still the Google Play services fabric
- No QR out-of-band identity binding in this slice
- Logs must never contain plaintext, keys, or full ciphertext
- SQLCipher holds session keys at rest
- No reboot-time WorkManager retry
