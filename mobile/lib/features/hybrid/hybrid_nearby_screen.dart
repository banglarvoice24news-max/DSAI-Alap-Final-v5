import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/offline/offline_cubit.dart';
import '../../core/offline/offline_session.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/transport/p2p_transport.dart';
import '../../offline_slice1/presentation/offline_nearby_screen.dart';

class HybridNearbyScreen extends StatefulWidget {
  const HybridNearbyScreen({super.key});

  @override
  State<HybridNearbyScreen> createState() => _HybridNearbyScreenState();
}

class _HybridNearbyScreenState extends State<HybridNearbyScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final TextEditingController _composer = TextEditingController();
  String? _shownIncomingId;
  String? _shownSafetyCode;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<OfflineCubit>().start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<OfflineCubit>().onResume();
    }
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    context.read<OfflineCubit>().sendText(text);
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      body: SafeArea(
        child: BlocConsumer<OfflineCubit, OfflineSessionState>(
          listenWhen: (prev, next) =>
              prev.incomingRequest?.endpointId != next.incomingRequest?.endpointId ||
              prev.safetyCode != next.safetyCode ||
              prev.phase != next.phase ||
              prev.error != next.error,
          listener: (context, state) {
            if (state.incomingRequest != null &&
                _shownIncomingId != state.incomingRequest!.endpointId) {
              _shownIncomingId = state.incomingRequest!.endpointId;
              _showIncoming(state);
            }
            if (state.phase == SessionUiPhase.verifyCode &&
                state.safetyCode != null &&
                _shownSafetyCode != state.safetyCode) {
              _shownSafetyCode = state.safetyCode;
              _showSafety(state);
            }
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.error!), backgroundColor: AppTokens.surface),
              );
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    children: [
                      _StatusHeader(state: state),
                      const SizedBox(height: 12),
                      const _OfflineSliceCard(),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.nearbyOfflineHint,
                        style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(AppStrings.nearbySectionPrivate),
                      const SizedBox(height: 8),
                      if (state.peers.isEmpty)
                        _EmptyPeers(state: state)
                      else
                        for (final p in state.peers) _PeerTile(peer: p, state: state),
                      if (state.messages.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionLabel(AppStrings.nearbyOfflineHello),
                        const SizedBox(height: 8),
                        for (final m in state.messages) _MessageRow(message: m),
                      ],
                    ],
                  ),
                ),
                if (state.phase == SessionUiPhase.trusted)
                  _Composer(controller: _composer, onSend: _send),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showIncoming(OfflineSessionState state) {
    final req = state.incomingRequest;
    if (req == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTokens.surface,
          title: const Text(AppStrings.nearbyIncomingTitle),
          content: Text(req.displayName),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.read<OfflineCubit>().rejectIncoming();
              },
              child: const Text(AppStrings.nearbyReject),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.read<OfflineCubit>().acceptIncoming();
              },
              child: const Text(AppStrings.nearbyAccept),
            ),
          ],
        );
      },
    );
  }

  void _showSafety(OfflineSessionState state) {
    final code = state.safetyCode;
    if (code == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTokens.surface,
          title: const Text(AppStrings.nearbySafetyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.nearbyConfirmCode,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTokens.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.read<OfflineCubit>().rejectSafety();
              },
              child: const Text(AppStrings.nearbyReject),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.read<OfflineCubit>().confirmSafety();
              },
              child: const Text(AppStrings.nearbyAccept),
            ),
          ],
        );
      },
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.state});
  final OfflineSessionState state;

  String get _label {
    return switch (state.phase) {
      SessionUiPhase.idle => AppStrings.nearbyNoPeers,
      SessionUiPhase.discovering => AppStrings.nearbyScanning,
      SessionUiPhase.peerFound => 'Peer Found',
      SessionUiPhase.connecting => 'Connecting',
      SessionUiPhase.verifyCode => 'Verify Code',
      SessionUiPhase.trusted => AppStrings.nearbyTrusted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final trusted = state.phase == SessionUiPhase.trusted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTokens.mesh.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            trusted ? Icons.verified_user : Icons.radar,
            color: trusted ? AppTokens.success : AppTokens.mesh,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  state.trustedName ?? 'Nearby Connections',
                  style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppStrings.nearbyStartDiscovery,
            onPressed: () => context.read<OfflineCubit>().start(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({required this.state});
  final OfflineSessionState state;

  @override
  Widget build(BuildContext context) {
    final isError = state.error != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            isError ? Icons.warning_amber_outlined : Icons.radar_outlined,
            color: isError ? AppTokens.danger : AppTokens.textSecondary,
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            isError ? state.error! : AppStrings.nearbyNoPeers,
            textAlign: TextAlign.center,
            style: TextStyle(color: isError ? AppTokens.danger : AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, required this.state});
  final PeerDescriptor peer;
  final OfflineSessionState state;

  @override
  Widget build(BuildContext context) {
    final trusted = state.trustedDeviceId != null && state.activePeer?.endpointId == peer.endpointId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTokens.mesh.withValues(alpha: 0.18),
            child: Text(
              peer.displayName.isEmpty ? '?' : peer.displayName[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  trusted ? AppStrings.nearbyTrusted : peer.endpointId,
                  style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
          if (!trusted)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.mesh,
                side: const BorderSide(color: AppTokens.mesh),
              ),
              onPressed: () => context.read<OfflineCubit>().connect(peer),
              child: const Text(AppStrings.nearbyConnect),
            ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});
  final OfflineChatMessage message;

  String get _stateLabel {
    return switch (message.state) {
      MessageUiState.queued => AppStrings.nearbyQueued,
      MessageUiState.sending => AppStrings.nearbySending,
      MessageUiState.waitingAck => AppStrings.nearbyWaitingAck,
      MessageUiState.delivered => AppStrings.nearbyDelivered,
      MessageUiState.failed => AppStrings.nearbyFailed,
      MessageUiState.expired => AppStrings.nearbyExpired,
      MessageUiState.received => AppStrings.nearbyDelivered,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: message.mine ? AppTokens.mesh.withValues(alpha: 0.18) : AppTokens.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(message.body.isEmpty ? '•' : message.body),
            const SizedBox(height: 2),
            Text(
              _stateLabel,
              style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: const Border(top: BorderSide(color: AppTokens.glassStroke)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: AppStrings.threadComposerHint,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            style: IconButton.styleFrom(backgroundColor: AppTokens.mesh, foregroundColor: Colors.black),
            icon: const Icon(Icons.send),
            tooltip: AppStrings.threadSend,
          ),
        ],
      ),
    );
  }
}

class _OfflineSliceCard extends StatelessWidget {
  const _OfflineSliceCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.mesh.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const OfflineNearbyScreen(),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: AppTokens.mesh),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline encrypted chat',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Discover, verify a 6-digit code, then send encrypted text without SIM or internet.',
                      style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppTokens.textSecondary,
      ),
    );
  }
}
