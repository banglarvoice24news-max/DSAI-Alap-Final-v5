# Current state

Slice 1 offline nearby encrypted text is implemented in the existing Flutter client. Backend, OTP login, API URLs, signing, and licence were not changed.

## Working

- Local `DeviceIdentity` on first launch without OTP, SIM, or internet
- Private identity key only in flutter_secure_storage; existing UUID reused
- Optional link from an existing online account phone number to the local identity
- Settings shows local display name, device id, public key, and link status
- Nearby Connections reused through `NearbyTransport`
- Mutual accept, public identity exchange, 6-digit safety code, trusted contact
- Prototype encryption: Ed25519, ephemeral X25519, HKDF-SHA256, AES-256-GCM
- Encrypted outbox, authenticated ACK, Delivered status
- Restart recovery and retry on app resume / peer reconnect
- Nearby tab chat plus Auth/Settings entry (`Use offline nearby without OTP`)

## Not in Slice 1

- Voice, WebRTC, backend group, PTT, telecom, QR scanner, WorkManager
- Independent cryptographic review
- Real two-phone acceptance (manual guide only)
