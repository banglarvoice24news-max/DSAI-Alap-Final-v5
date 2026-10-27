import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/features/chats/chat_models.dart';
import 'package:nexus_comm/features/chats/chats_cubit.dart';
import 'package:nexus_comm/features/chats/chats_screen.dart';
import 'package:nexus_comm/features/chats/cpaas_chat_repository.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';

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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<ChatsCubit>.value(value: cubit, child: const ChatsScreen()),
  );
}

void main() {
  testWidgets('shows empty state when the backend returns no threads', (tester) async {
    final cubit = ChatsCubit(repository: _FakeChatRepository(const []));

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('No conversations yet. Start a secure chat.'), findsOneWidget);
  });

  testWidgets('renders a thread returned by the repository', (tester) async {
    final cubit = ChatsCubit(
      repository: _FakeChatRepository(const [
        ChatThread(id: '+8801700000000', title: '+8801700000000', preview: 'VOIP • COMPLETED', unread: 0, online: false),
      ]),
    );

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('+8801700000000'), findsOneWidget);
    expect(find.text('VOIP • COMPLETED'), findsOneWidget);
  });
}
