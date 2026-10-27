// Chats tab — chat list bound to the real E2EE thread store.
//
// The list shows thread metadata only (counterpart, unread count, last-message
// time) from GET /api/messages/threads. Message bodies are end-to-end
// encrypted and there is no client decrypt layer yet, so a thread opens with no
// local bubbles — see the GAP NOTE in cpaas_chat_repository.dart. We never fake
// plaintext.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../chats/chat_models.dart';
import '../chats/chats_cubit.dart';
import 'hybrid_models.dart';
import 'hybrid_thread_screen.dart';

class HybridChatsScreen extends StatefulWidget {
  const HybridChatsScreen({super.key});

  @override
  State<HybridChatsScreen> createState() => _HybridChatsScreenState();
}

class _HybridChatsScreenState extends State<HybridChatsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ChatsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: AppStrings.chatsSearchHint,
                  prefixIcon: const Icon(Icons.search, color: AppTokens.textSecondary),
                  filled: true,
                  fillColor: AppTokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatsCubit, ChatsState>(
                builder: (context, state) {
                  if (state.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.threads.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(AppStrings.chatsEmpty, textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: state.threads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ThreadRow(thread: state.threads[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTokens.primaryBright,
        foregroundColor: Colors.black,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.prototypeBanner)),
          );
        },
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});
  final ChatThread thread;

  String _time(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final at = thread.lastMessageAt;
    return Material(
      color: AppTokens.surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HybridThreadScreen(
                thread: HybridThread(id: thread.id, title: thread.title, messages: const []),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTokens.primary.withValues(alpha: 0.25),
                child: Text(
                  thread.title.isEmpty ? '?' : thread.title[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(thread.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    const Icon(Icons.lock_outline, size: 14, color: AppTokens.textSecondary),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    at == null ? '' : _time(at),
                    style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
                  ),
                  if (thread.unread > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: const BoxDecoration(color: AppTokens.primaryBright, shape: BoxShape.circle),
                      child: Text('${thread.unread}', style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
