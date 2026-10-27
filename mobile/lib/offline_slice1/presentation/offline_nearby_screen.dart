import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_tokens.dart';
import '../data/session_engine.dart';
import '../domain/models.dart';
import 'offline_slice_cubit.dart';

class OfflineNearbyScreen extends StatefulWidget {
  const OfflineNearbyScreen({super.key, this.linkedAccountHint});

  final String? linkedAccountHint;

  @override
  State<OfflineNearbyScreen> createState() => _OfflineNearbyScreenState();
}

class _OfflineNearbyScreenState extends State<OfflineNearbyScreen> {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cubit = context.read<OfflineSliceCubit>();
    if (cubit.identity == null) {
      cubit.bootstrap(linkedAccountHint: widget.linkedAccountHint);
    } else {
      cubit.retryPending();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OfflineSliceCubit, OfflineSessionState>(
      listenWhen: (prev, next) =>
          prev.pendingRequest != next.pendingRequest ||
          prev.safetyCode != next.safetyCode ||
          prev.error != next.error,
      listener: (context, state) {
        if (state.pendingRequest != null) {
          _showAcceptDialog(context, state);
        }
        if (state.phase == OfflineUiPhase.verifyCode && state.safetyCode != null) {
          _showSafetyDialog(context, state.safetyCode!);
        }
        if (state.error != null && state.error!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!)),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<OfflineSliceCubit>();
        final discovering = state.phase == OfflineUiPhase.discovering ||
            state.phase == OfflineUiPhase.peerFound;
        return Scaffold(
          backgroundColor: AppTokens.canvas,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Offline nearby'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _StatusCard(state: state),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: discovering
                            ? () => cubit.stopDiscovery()
                            : () => cubit.startDiscovery(),
                        child: Text(discovering ? 'Stop discovery' : 'Start discovery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Discovered peers',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 8),
                if (state.peers.isEmpty)
                  const Text(
                    'No peers yet. Keep Bluetooth and Wi-Fi on. Airplane mode is OK.',
                    style: TextStyle(color: AppTokens.textSecondary),
                  )
                else
                  for (final peer in state.peers) _PeerRow(peer: peer),
                const SizedBox(height: 16),
                if (state.trusted != null) ...[
                  Text(
                    'Trusted: ${state.trusted!.displayName}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final line in state.lines) _LineTile(line: line),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          decoration: const InputDecoration(
                            hintText: 'Encrypted message',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final text = _input.text.trim();
                          if (text.isEmpty) return;
                          cubit.sendText(text);
                          _input.clear();
                        },
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAcceptDialog(BuildContext context, OfflineSessionState state) {
    final req = state.pendingRequest;
    if (req == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Accept connection?'),
          content: Text('${req.displayName} wants to pair. Both devices must accept.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<OfflineSliceCubit>().rejectIncoming();
              },
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<OfflineSliceCubit>().acceptIncoming();
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  void _showSafetyDialog(BuildContext context, String code) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Verify safety code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Compare this 6-digit code on both phones. Do not auto-trust.'),
              const SizedBox(height: 12),
              Text(
                code,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<OfflineSliceCubit>().rejectSafetyCode();
              },
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<OfflineSliceCubit>().confirmSafetyCode();
              },
              child: const Text('Confirm verification'),
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final OfflineSessionState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.mesh.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.status, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Transport: ${state.transportState.name}',
            style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
          ),
          if (state.localDeviceId != null)
            Text(
              'Device ${state.localDeviceId!.substring(0, state.localDeviceId!.length.clamp(0, 8))}',
              style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer});
  final PeerDescriptor peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  peer.state.name,
                  style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => context.read<OfflineSliceCubit>().connect(peer),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});
  final ChatLine line;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: line.mine ? AppTokens.primary.withValues(alpha: 0.45) : AppTokens.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.body),
            Text(
              line.statusLabel,
              style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
