# Integration map (Slice 1)

```
AuthCubit.bootstrap
  -> IdentityService.loadOrCreate (flutter_secure_storage)
NexusApp
  -> OfflineCubit (Nearby tab)
  -> OfflineSliceCubit (resume retry)
  -> AuthScreen / HybridNearbyScreen / HybridSettingsScreen
       -> OfflineNearbyScreen
            -> NearbyTransport (nearby_connections)
            -> OfflineSessionEngine
                 -> SqlSlice1Repository (SQLCipher)
                 -> Slice1Crypto (cryptography)
```

## Reused

- `nearby_connections` via `NearbyTransport`
- `cryptography` 2.7.0
- `flutter_secure_storage` for private identity key
- `sqflite_sqlcipher` for encrypted outbox / inbox / trusted contacts
- Existing OTP UI and production Nearby tab

## Not wired

- Backend `/api/*`
- Mesh voice TCP bridge
- CPaaS / signaling

## Next-slice extension: QR pairing

QR is not required in Slice 1. A later slice can encode `deviceId + identity public key` in a QR payload, skip discovery selection, then continue with the same safety-code confirm step.
