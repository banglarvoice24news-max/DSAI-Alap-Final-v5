import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import 'mesh_cubit.dart';
import 'mesh_models.dart';

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  @override
  void initState() {
    super.initState();
    context.read<MeshCubit>().start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.meshTitle),
            Text(l10n.meshSubtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: BlocBuilder<MeshCubit, MeshState>(
        builder: (context, state) {
          if (!state.permissionsGranted && state.error != null) {
            return _Message(text: state.error!, onRetry: () => context.read<MeshCubit>().start());
          }
          if (state.peers.isEmpty) {
            return _Message(
              text: state.scanning ? l10n.meshScanning : l10n.meshNoPeers,
              onRetry: () => context.read<MeshCubit>().start(),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.peers.length,
            itemBuilder: (context, i) => _PeerTile(peer: state.peers[i]),
          );
        },
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});
  final MeshPeer peer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(peer.name, style: Theme.of(context).textTheme.titleMedium)),
                Text(l10n.meshDistance(peer.distanceMeters)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${l10n.meshRssi} ${peer.rssi} dBm'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: peer.signalQuality, minHeight: 8),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: () => context.read<MeshCubit>().connect(peer),
                  child: Text(peer.status == MeshPeerStatus.connected ? l10n.meshConnected : l10n.meshConnect),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => context.read<MeshCubit>().startCall(peer, asHost: true),
                  child: Text(l10n.meshCall),
                ),
              ],
            ),
            if (peer.status == MeshPeerStatus.dropped)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.meshDropped, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(AppLocalizations.of(context).commonRetry)),
        ],
      ),
    );
  }
}
