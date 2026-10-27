// Thread screen — per-message transport + delivery badges.
//
// First-pass prototype over deterministic sample data. Sending is local-only:
// it appends a message marked pending with an honest reason ("waiting for a
// mesh peer") instead of a generic clock. The composer picks which transport
// the next message should attempt, and the transport strip simulates the
// active leg so the UI has a live value to render; production feeds it from
// the real router (core/transport/transport_status.dart).

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/storage/secure_database.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/transport/transport_status.dart';
import 'hybrid_models.dart';
import 'widgets/transport_ui.dart';

class HybridThreadScreen extends StatefulWidget {
  const HybridThreadScreen({super.key, required this.thread, this.outbox});

  final HybridThread thread;

  /// Injected for tests; production uses the shared encrypted outbox.
  final OutboxStore? outbox;

  @override
  State<HybridThreadScreen> createState() => _HybridThreadScreenState();
}

class _HybridThreadScreenState extends State<HybridThreadScreen> {
  final TextEditingController _composer = TextEditingController();
  late final OutboxStore _outbox = widget.outbox ?? OutboxStore();
  late final TransportStatusController _leg = TransportStatusController(
    TransportSnapshot(
      activeTransport: CallTransport.mesh,
      activity: TransportActivity.active,
      available: const {CallTransport.mesh, CallTransport.voip},
      hops: 1,
    ),
  );

  late final List<HybridMessage> _messages = List.of(widget.thread.messages);

  CallTransport _nextTransport = CallTransport.mesh;

  @override
  void initState() {
    super.initState();
    _restoreOutbox();
  }

  @override
  void dispose() {
    _composer.dispose();
    _leg.dispose();
    super.dispose();
  }

  Future<void> _restoreOutbox() async {
    try {
      final entries = await _outbox.forThread(widget.thread.id);
      if (!mounted || entries.isEmpty) return;
      setState(() {
        for (final entry in entries) {
          final transport = _transportFromName(entry.transport);
          _messages.add(
            HybridMessage(
              id: entry.id,
              mine: true,
              text: entry.body,
              state: DeliveryState.pending,
              transport: transport,
              pendingReason: _pendingReason(transport),
              sentAt: entry.createdAt,
            ),
          );
        }
      });
    } catch (_) {
      // Encrypted outbox unavailable (unsupported platform): keep the UI.
    }
  }

  CallTransport _transportFromName(String name) => CallTransport.values
      .firstWhere((t) => t.name == name, orElse: () => CallTransport.voip);

  String _pendingReason(CallTransport transport) => switch (transport) {
        CallTransport.mesh => AppStrings.waitingForMeshPeer,
        CallTransport.voip => AppStrings.retryingOverVoip,
        CallTransport.gsm => AppStrings.queuedOverGsm,
      };

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final message = HybridMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      mine: true,
      text: text,
      state: DeliveryState.pending,
      transport: _nextTransport,
      pendingReason: _pendingReason(_nextTransport),
      sentAt: DateTime.now(),
    );
    setState(() => _messages.add(message));
    _composer.clear();
    try {
      await _outbox.enqueue(
        OutboxEntry(
          id: message.id,
          threadId: widget.thread.id,
          body: message.text,
          transport: _nextTransport.name,
          createdAt: message.sentAt,
        ),
      );
    } catch (_) {
      // Best-effort persistence; the in-memory bubble still renders.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.thread.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            if (widget.thread.subtitle != null)
              Text(widget.thread.subtitle!, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text(AppStrings.prototypeBanner))),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text(AppStrings.prototypeBanner))),
            icon: const Icon(Icons.videocam_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LiveTransportStrip(controller: _leg),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                itemCount: _messages.length,
                itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
              ),
            ),
            _ComposerBar(
              controller: _composer,
              transport: _nextTransport,
              onTransport: (t) => setState(() => _nextTransport = t),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.transport,
    required this.onTransport,
    required this.onSend,
  });

  final TextEditingController controller;
  final CallTransport transport;
  final ValueChanged<CallTransport> onTransport;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: const Border(top: BorderSide(color: AppTokens.glassStroke)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.inCallSwitchTransport, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
              const SizedBox(width: 8),
              for (final t in CallTransport.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(transportLabel(t)),
                    selected: transport == t,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: transport == t ? Colors.black : transportColor(t),
                    ),
                    selectedColor: transportColor(t),
                    backgroundColor: AppTokens.canvas,
                    side: BorderSide(color: transportColor(t).withValues(alpha: 0.6)),
                    onSelected: (_) => onTransport(t),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    hintText: AppStrings.threadComposerHint,
                    filled: true,
                    fillColor: AppTokens.canvas,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSend,
                style: IconButton.styleFrom(backgroundColor: AppTokens.primaryBright, foregroundColor: Colors.black),
                icon: const Icon(Icons.send),
                tooltip: AppStrings.threadSend,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final HybridMessage message;

  String _time(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final pending = message.state == DeliveryState.pending;
    final bubbleColor = mine ? AppTokens.primaryBright.withValues(alpha: 0.22) : AppTokens.surface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.transport != null) ...[
            Padding(
              padding: EdgeInsets.only(bottom: 3, left: mine ? 0 : 4, right: mine ? 4 : 0),
              child: TransportChip(transport: message.transport!, dim: true),
            ),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: Border.all(color: AppTokens.glassStroke),
            ),
            child: Text(message.text, style: const TextStyle(fontSize: 15, height: 1.35)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_time(message.sentAt), style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary)),
                const SizedBox(width: 5),
                if (mine) DeliveryTicks(state: message.state),
              ],
            ),
          ),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                message.pendingReason ?? deliveredCaption(message),
                style: const TextStyle(fontSize: 11, color: AppTokens.warn, fontStyle: FontStyle.italic),
                textAlign: mine ? TextAlign.end : TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }
}
