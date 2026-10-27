import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/dsaialap_glass.dart';
import 'chats_cubit.dart';

class E2eeCloudHubScreen extends StatefulWidget {
  const E2eeCloudHubScreen({super.key});

  @override
  State<E2eeCloudHubScreen> createState() => _E2eeCloudHubScreenState();
}

class _E2eeCloudHubScreenState extends State<E2eeCloudHubScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    context.read<ChatsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<ChatsCubit, ChatsState>(
      builder: (context, state) {
        if (state.loading) {
          return const Center(child: CircularProgressIndicator(color: DsaialapTokens.neonCyan));
        }
        if (state.threads.isEmpty) {
          return const Center(
            child: GlassCard(
              child: Text('No E2EE threads yet.\nStart a secure cloud session.', textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: state.threads.length,
          itemBuilder: (context, i) {
            final t = state.threads[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                glow: t.online ? DsaialapTokens.neonLime : DsaialapTokens.neonCyan,
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: DsaialapTokens.neonCyan.withValues(alpha: 0.2),
                      child: Text(t.title.isEmpty ? '?' : t.title[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(t.preview, style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const NeonBadge(label: 'E2EE', color: DsaialapTokens.neonLime),
                        if (t.unread > 0) ...[
                          const SizedBox(height: 6),
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: DsaialapTokens.neonCyan,
                            child: Text('${t.unread}', style: const TextStyle(fontSize: 11, color: Colors.black)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
