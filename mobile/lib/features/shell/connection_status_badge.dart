import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/dsaialap_glass.dart';
import '../mesh/mesh_cubit.dart';
import '../mesh/mesh_models.dart';
import '../settings/connection_priority.dart';
import '../settings/settings_cubit.dart';

enum LinkEngine { cloud, mesh, sim }

class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({super.key});

  static LinkEngine resolve({
    required ConnectionPriority priority,
    required MeshState mesh,
  }) {
    if (priority == ConnectionPriority.simOnly) return LinkEngine.sim;
    if (priority == ConnectionPriority.meshOnly || mesh.inCall || mesh.scanning) {
      return LinkEngine.mesh;
    }
    if (priority == ConnectionPriority.internetOnly) return LinkEngine.cloud;
    if (mesh.peers.any((p) => p.status == MeshPeerStatus.connected)) return LinkEngine.mesh;
    return LinkEngine.cloud;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsSnapshot>(
      builder: (context, settings) {
        return BlocBuilder<MeshCubit, MeshState>(
          builder: (context, mesh) {
            final engine = resolve(priority: settings.priority, mesh: mesh);
            final color = switch (engine) {
              LinkEngine.cloud => DsaialapTokens.neonLime,
              LinkEngine.mesh => DsaialapTokens.neonCyan,
              LinkEngine.sim => DsaialapTokens.neonOrange,
            };
            final label = switch (engine) {
              LinkEngine.cloud => 'CLOUD',
              LinkEngine.mesh => '200m MESH',
              LinkEngine.sim => 'SIM FALLBACK',
            };
            return NeonBadge(label: label, color: color);
          },
        );
      },
    );
  }
}
