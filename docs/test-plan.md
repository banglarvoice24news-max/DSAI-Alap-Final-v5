# Test plan (Slice 1)

## Unit

- Identity creation and secure reload
- Safety code determinism and mismatch
- Mutual accept and matching 6-digit confirm
- One-sided accept or confirm does not auto-trust
- Unknown peer cannot send
- Encrypt / decrypt
- Tampered ciphertext rejected
- Invalid signature rejected
- Wrong recipient rejected
- Replay rejected
- Duplicate message stored once
- Duplicate ACK idempotent
- Outbox state transitions
- Retry and expiry
- Restart recovery

## Build

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Manual two-device

See `docs/demo-offline.md`. Two physical Androids. This environment has no emulator/KVM.

Do not mark real-device acceptance passed from unit tests.

## Secret / log inspection

- Private key only under `flutter_secure_storage` keys `slice1_identity_priv`
- No plaintext message logging in Slice 1 code
- No private key in SQL tables
