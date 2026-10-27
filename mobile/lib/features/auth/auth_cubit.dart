import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_store.dart';
import '../../offline_slice1/data/identity_service.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({ApiClient? api, SecureStore? store})
      : _api = api ?? ApiClient(),
        _store = store ?? SecureStore(),
        super(const AuthState());

  final ApiClient _api;
  final SecureStore _store;

  static const offlineUnlocked = 'offline_unlocked';

  Future<void> bootstrap() async {
    final token = await _store.read(SecureStore.accessToken);
    final offline = await _store.read(offlineUnlocked);
    await IdentityService(store: _store).loadOrCreate();
    emit(state.copyWith(
      status: (token != null || offline == '1')
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
    ));
  }

  Future<void> continueOffline() async {
    var deviceId = await _store.read(SecureStore.deviceId);
    deviceId ??= const Uuid().v4();
    await _store.write(SecureStore.deviceId, deviceId);
    await _store.write(offlineUnlocked, '1');
    await IdentityService(store: _store).loadOrCreate();
    emit(state.copyWith(status: AuthStatus.authenticated));
  }

  Future<void> requestOtp(String phone) async {
    await _api.post('/api/auth/otp/request', data: {'phoneNumber': phone});
    emit(state.copyWith(status: AuthStatus.codeSent, phone: phone));
  }

  Future<void> verifyOtp(String otp, {required String publicKey}) async {
    var deviceId = await _store.read(SecureStore.deviceId);
    deviceId ??= const Uuid().v4();
    await _store.write(SecureStore.deviceId, deviceId);
    final res = await _api.post('/api/auth/otp/verify', data: {
      'phoneNumber': state.phone,
      'otp': otp,
      'deviceId': deviceId,
      'publicKey': publicKey,
    });
    final data = res['data'] as Map;
    await _store.write(SecureStore.accessToken, data['accessToken'] as String);
    final refresh = data['refreshToken'] as String?;
    if (refresh != null) {
      await _store.write(SecureStore.refreshToken, refresh);
    }
    final identity = IdentityService(store: _store);
    await identity.loadOrCreate(linkedAccountHint: state.phone);
    emit(state.copyWith(status: AuthStatus.authenticated));
  }

  Future<void> restoreWithBackup(String phone, String backupKey) async {
    var deviceId = await _store.read(SecureStore.deviceId);
    deviceId ??= const Uuid().v4();
    await _store.write(SecureStore.deviceId, deviceId);
    final start = await _api.post('/api/auth/backup/restore/start', data: {
      'phoneNumber': phone,
    });
    final complete = await _api.post('/api/auth/backup/restore/complete', data: {
      'challengeId': start['data']['challengeId'],
      'backupKey': backupKey,
      'deviceId': deviceId,
    });
    final completeData = complete['data'] as Map;
    await _store.write(SecureStore.accessToken, completeData['accessToken'] as String);
    final restoreRefresh = completeData['refreshToken'] as String?;
    if (restoreRefresh != null) {
      await _store.write(SecureStore.refreshToken, restoreRefresh);
    }
    await IdentityService(store: _store).loadOrCreate(linkedAccountHint: phone);
    emit(state.copyWith(status: AuthStatus.authenticated, phone: phone));
  }
}
