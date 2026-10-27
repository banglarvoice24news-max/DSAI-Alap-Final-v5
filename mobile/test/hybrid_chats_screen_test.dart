import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/features/chats/chat_models.dart';
import 'package:nexus_comm/features/chats/chats_cubit.dart';
import 'package:nexus_comm/features/chats/cpaas_chat_repository.dart';
import 'package:nexus_comm/features/hybrid/hybrid_chats_screen.dart';

class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this._threads);

  final List<ChatThread> _threads;

  @override
  Future<List<ChatThread>> loadThreads() async => _threads;

  @override
  Future<CpaasSendReceipt> sendMessage({
    required String to,
    required String body,
    bool consent = false,
  }) async =>
      const CpaasSendReceipt(refId: 'ref-1', status: 'QUEUED');
}

Widget _harness(ChatsCubit cubit) {
  return MaterialApp(
    home: BlocProvider<ChatsCubit>.value(value: cubit, child: const HybridChatsScreen()),
  );
}

void main() {
  testWidgets('renders a real thread with its unread badge', (tester) async {
    final cubit = ChatsCubit(
      repository: _FakeChatRepository([
        ChatThread(
          id: 'u1',
          title: 'Alice',
          preview: '',
          unread: 2,
          online: false,
          lastMessageAt: DateTime(2026, 9, 11, 10, 5),
          lastMessageMine: true,
        ),
      ]),
    );

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('10:05'), findsOneWidget);
  });

  testWidgets('renders the empty state when there are no threads', (tester) async {
    final cubit = ChatsCubit(repository: _FakeChatRepository(const []));

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('কোনো কথোপকথন নেই'), findsOneWidget);
  });
}
