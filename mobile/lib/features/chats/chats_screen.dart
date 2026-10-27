import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import 'chats_cubit.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ChatsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatsTitle),
        actions: [
          IconButton(onPressed: () => context.read<ChatsCubit>().load(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: BlocBuilder<ChatsCubit, ChatsState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.threads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.chatsEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: state.threads.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = state.threads[i];
              return ListTile(
                leading: CircleAvatar(child: Text(t.title.isEmpty ? '?' : t.title[0].toUpperCase())),
                title: Text(t.title),
                subtitle: Text(t.preview),
                trailing: t.online
                    ? Text(l10n.chatsOnline, style: const TextStyle(color: Colors.green))
                    : Text(l10n.chatsOffline),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.lock_outline),
      ),
    );
  }
}
