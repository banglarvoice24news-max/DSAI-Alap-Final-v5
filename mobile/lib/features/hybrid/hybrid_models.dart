// Presentation models for the hybrid-UI prototype.
//
// These are deliberately UI-facing, not storage/crypto models. The real message
// store keeps only ciphertext (features/chats/chat_models.dart); a thread
// screen must hydrate plain text from the local decrypted store before it can
// render bubbles. Same for per-message transport + delivery state — nothing
// today records which transport carried a given message, so `transport` on
// HybridMessage is what the backend/CDR work must eventually supply.
//
// GAP NOTE: HybridMessage.text is the DECRYPTED view. Do not treat these as a
// replacement for chat_models.dart; they are the prototype contract for what
// the real binding layer has to hand the UI.

import 'package:equatable/equatable.dart';

import '../../core/transport/transport_status.dart';

/// Honest delivery state for a message.
///
/// `pending` is never shown as a generic grey clock: the UI renders a concrete
/// reason (`pendingReason`, e.g. "waiting for a mesh peer") when present.
enum DeliveryState { pending, sent, delivered, read }

class HybridMessage extends Equatable {
  const HybridMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.state,
    required this.sentAt,
    this.transport,
    this.pendingReason,
  });

  final String id;
  final bool mine;
  final String text;
  final DeliveryState state;

  /// Which transport actually carried this message (mesh / voip / gsm).
  final CallTransport? transport;

  /// Plain-language reason shown while [state] == pending.
  final String? pendingReason;

  final DateTime sentAt;

  @override
  List<Object?> get props => [id, mine, text, state, transport, pendingReason, sentAt];
}

class HybridThread extends Equatable {
  const HybridThread({
    required this.id,
    required this.title,
    required this.messages,
    this.subtitle,
    this.lastTransport,
    this.unread = 0,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// Transport of the most recent message; rendered as a chip in the list.
  final CallTransport? lastTransport;

  final List<HybridMessage> messages;
  final int unread;

  HybridMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  @override
  List<Object?> get props => [id, title, subtitle, lastTransport, messages, unread];
}

class CallRecord extends Equatable {
  const CallRecord({
    required this.id,
    required this.name,
    required this.number,
    required this.startedAt,
    this.durationSec,
    this.missed = false,
    this.favorite = false,
    this.transport = CallTransport.voip,
  });

  final String id;
  final String name;
  final String number;
  final CallTransport transport;
  final DateTime startedAt;
  final int? durationSec;
  final bool missed;
  final bool favorite;

  CallRecord copyWith({bool? favorite}) {
    return CallRecord(
      id: id,
      name: name,
      number: number,
      transport: transport,
      startedAt: startedAt,
      durationSec: durationSec,
      missed: missed,
      favorite: favorite ?? this.favorite,
    );
  }

  @override
  List<Object?> get props => [id, name, number, transport, startedAt, durationSec, missed, favorite];
}

// ---------------------------------------------------------------------------
// Deterministic sample data for the visual walkthrough. Clearly labelled demo
// content; production bindings replace it.
// ---------------------------------------------------------------------------

final DateTime _now = DateTime.now();

HybridMessage _msg({
  required String id,
  required bool mine,
  required String text,
  required DeliveryState state,
  CallTransport? transport,
  String? pendingReason,
  required Duration age,
}) {
  return HybridMessage(
    id: id,
    mine: mine,
    text: text,
    state: state,
    transport: transport,
    pendingReason: pendingReason,
    sentAt: _now.subtract(age),
  );
}

List<HybridThread> get sampleThreads => [
      HybridThread(
        id: 't-mesh',
        title: 'Rahim (mesh)',
        subtitle: '200m relay • 1 hop',
        lastTransport: CallTransport.mesh,
        unread: 0,
        messages: [
          _msg(
            id: 'm1',
            mine: true,
            text: 'Apnar kemon? Sathe asen to?',
            state: DeliveryState.read,
            transport: CallTransport.mesh,
            age: const Duration(minutes: 40),
          ),
          _msg(
            id: 'm2',
            mine: false,
            text: 'Jete parle ekhon dariye thako, ami aschi.',
            state: DeliveryState.delivered,
            transport: CallTransport.mesh,
            age: const Duration(minutes: 38),
          ),
          _msg(
            id: 'm3',
            mine: true,
            text: 'Mesh peer chole geche — VoIP diye pathacchi.',
            state: DeliveryState.pending,
            transport: CallTransport.voip,
            pendingReason: 'Waiting for network — retrying over VoIP',
            age: const Duration(minutes: 1),
          ),
        ],
      ),
      HybridThread(
        id: 't-gsm',
        title: 'Karim',
        subtitle: 'SIM fallback',
        lastTransport: CallTransport.gsm,
        unread: 2,
        messages: [
          _msg(
            id: 'g1',
            mine: true,
            text: 'Internet band. Eta GSM path diye jacche.',
            state: DeliveryState.delivered,
            transport: CallTransport.gsm,
            age: const Duration(hours: 3),
          ),
          _msg(
            id: 'g2',
            mine: false,
            text: 'Pechlam. Ei mesh patho cholbe.',
            state: DeliveryState.read,
            transport: CallTransport.gsm,
            age: const Duration(hours: 2, minutes: 55),
          ),
          _msg(
            id: 'g3',
            mine: true,
            text: 'Mesh peer abar dekha jacchena — abar GSM diye pathalam.',
            state: DeliveryState.pending,
            transport: CallTransport.gsm,
            pendingReason: 'Waiting for a mesh peer — queued over GSM',
            age: const Duration(minutes: 5),
          ),
        ],
      ),
      HybridThread(
        id: 't-voip',
        title: 'Nexus support',
        subtitle: 'Cloud / VoIP',
        lastTransport: CallTransport.voip,
        unread: 0,
        messages: [
          _msg(
            id: 'v1',
            mine: false,
            text: 'Data saver on thakle audio low-bitrate hoy. Settings e dekhen.',
            state: DeliveryState.delivered,
            transport: CallTransport.voip,
            age: const Duration(days: 1),
          ),
        ],
      ),
    ];

List<CallRecord> get sampleCalls => [
      CallRecord(
        id: 'c1',
        name: 'Rahim (mesh)',
        number: '+8801711xxxx01',
        transport: CallTransport.mesh,
        startedAt: _now.subtract(const Duration(hours: 2)),
        durationSec: 342,
      ),
      CallRecord(
        id: 'c2',
        name: 'Apu',
        number: '+8801811xxxx02',
        transport: CallTransport.gsm,
        startedAt: _now.subtract(const Duration(hours: 6)),
        durationSec: 58,
        favorite: true,
      ),
      CallRecord(
        id: 'c3',
        name: 'Nusrat',
        number: '+8801911xxxx03',
        transport: CallTransport.voip,
        startedAt: _now.subtract(const Duration(days: 1)),
        durationSec: 900,
        favorite: true,
      ),
      CallRecord(
        id: 'c4',
        name: 'Rahim (mesh)',
        number: '+8801711xxxx01',
        transport: CallTransport.mesh,
        startedAt: _now.subtract(const Duration(days: 2)),
        missed: true,
      ),
    ];
