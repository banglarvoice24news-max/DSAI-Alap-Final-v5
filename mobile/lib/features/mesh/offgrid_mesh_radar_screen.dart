import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants.dart';
import '../../core/theme/dsaialap_glass.dart';
import 'mesh_cubit.dart';
import 'mesh_models.dart';
import 'mesh_radar_widget.dart';

class OffgridMeshRadarScreen extends StatefulWidget {
  const OffgridMeshRadarScreen({super.key});

  @override
  State<OffgridMeshRadarScreen> createState() => _OffgridMeshRadarScreenState();
}

class _OffgridMeshRadarScreenState extends State<OffgridMeshRadarScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    context.read<MeshCubit>().start();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<MeshCubit, MeshState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              GlassCard(
                child: Row(
                  children: [
                    const NeonBadge(label: 'BLE / Wi-Fi Direct', color: DsaialapTokens.neonCyan),
                    const Spacer(),
                    Text(
                      state.scanning ? 'SCANNING ${AppConstants.meshRangeMeters}m' : 'IDLE',
                      style: const TextStyle(letterSpacing: 1.1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(8),
                  child: MeshRadarWidget(
                    peers: state.peers,
                    rangeMeters: AppConstants.meshRangeMeters,
                    scanning: state.scanning,
                    onPeerTap: (peer) => context.read<MeshCubit>().connect(peer),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.peers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = state.peers[i];
                    return GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('RSSI ${p.rssi} dBm  •  ${p.distanceMeters}m'),
                            ],
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: DsaialapTokens.neonCyan,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => context.read<MeshCubit>().startCall(p, asHost: true),
                            child: Text(p.status == MeshPeerStatus.connected ? 'CALL' : 'LINK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
