import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../settings/connection_priority.dart';
import '../../core/transport/transport_router.dart';
import '../../core/transport/transport_status.dart';

class DialerContact extends Equatable {
  const DialerContact({required this.name, required this.phone});
  final String name;
  final String phone;
  @override
  List<Object?> get props => [name, phone];
}

class DialerState extends Equatable {
  const DialerState({
    this.digits = '',
    this.contacts = const [],
    this.promptSimFallback = false,
    this.error,
  });

  final String digits;
  final List<DialerContact> contacts;
  final bool promptSimFallback;
  final String? error;

  DialerState copyWith({
    String? digits,
    List<DialerContact>? contacts,
    bool? promptSimFallback,
    String? error,
    bool clearError = false,
  }) {
    return DialerState(
      digits: digits ?? this.digits,
      contacts: contacts ?? this.contacts,
      promptSimFallback: promptSimFallback ?? this.promptSimFallback,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [digits, contacts, promptSimFallback, error];
}

class DialerCubit extends Cubit<DialerState> {
  DialerCubit({Connectivity? connectivity, TransportRouter? router, TransportStatusController? transportStatus})
      : _connectivity = connectivity ?? Connectivity(),
        _router = router ?? const TransportRouter(),
        _transportStatus = transportStatus,
        super(const DialerState());

  final Connectivity _connectivity;
  final TransportRouter _router;
  final TransportStatusController? _transportStatus;

  void pushDigit(String d) {
    if (state.digits.length >= 18) return;
    emit(state.copyWith(digits: '${state.digits}$d', promptSimFallback: false, clearError: true));
  }

  void backspace() {
    if (state.digits.isEmpty) return;
    emit(state.copyWith(digits: state.digits.substring(0, state.digits.length - 1)));
  }

  void setNumber(String n) => emit(state.copyWith(digits: n, promptSimFallback: false));

  Future<void> loadContacts() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return;
    final raw = await FlutterContacts.getContacts(withProperties: true);
    final mapped = <DialerContact>[];
    for (final c in raw) {
      if (c.phones.isEmpty) continue;
      mapped.add(DialerContact(name: c.displayName, phone: c.phones.first.number));
    }
    emit(state.copyWith(contacts: mapped));
  }

  Future<void> placeCall(ConnectionPriority priority) async {
    final number = state.digits.replaceAll(RegExp(r'[^\d+]'), '');
    if (number.length < 3) {
      emit(state.copyWith(error: 'invalid'));
      return;
    }
    final net = await _connectivity.checkConnectivity();
    final online = net.any((r) => r != ConnectivityResult.none);
    final caps = TransportCapabilities.forPlatform();
    final available = <CallTransport>{
      if (online && caps.supports(CallTransport.voip)) CallTransport.voip,
      if (caps.supports(CallTransport.gsm)) CallTransport.gsm,
      // TODO(P2-ROUTER-MESH): add CallTransport.mesh from MeshCubit peer state.
    };
    final decision = _router.decide(
      available: available,
      preference: switch (priority) {
        ConnectionPriority.auto => TransportPreference.auto,
        ConnectionPriority.meshOnly => TransportPreference.meshOnly,
        ConnectionPriority.internetOnly => TransportPreference.voipOnly,
        ConnectionPriority.simOnly => TransportPreference.gsmOnly,
      },
    );
    if (!decision.hasRoute) {
      emit(state.copyWith(error: 'no_route'));
      return;
    }
    _transportStatus?.publish(decision.chosen!);
    if (decision.chosen == CallTransport.gsm) {
      emit(state.copyWith(promptSimFallback: true));
      return;
    }
    // TODO(P2-VOIP-SDK): open the VoIP/media leg once the licensed gateway SDK
    // is wired to the app. The chosen transport is recorded; no fake success.
  }

  Future<void> confirmSimCall() async {
    final number = state.digits.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: number);
    emit(state.copyWith(promptSimFallback: false));
    _transportStatus?.publish(CallTransport.gsm);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      emit(state.copyWith(error: 'dial_failed'));
    }
  }

  void dismissPrompt() => emit(state.copyWith(promptSimFallback: false));
}
