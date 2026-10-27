import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'cpaas_chat_repository.dart';
import 'chat_models.dart';

class ChatsState extends Equatable {
  const ChatsState({this.threads = const [], this.loading = false});

  final List<ChatThread> threads;
  final bool loading;

  @override
  List<Object?> get props => [threads, loading];
}

class ChatsCubit extends Cubit<ChatsState> {
  ChatsCubit({ChatRepository? repository})
      : _repo = repository ?? CpaasChatRepository(),
        super(const ChatsState());

  final ChatRepository _repo;

  Future<void> load() async {
    emit(const ChatsState(loading: true));
    try {
      final threads = await _repo.loadThreads();
      emit(ChatsState(threads: threads));
    } catch (_) {
      // TODO(P2-CHAT-ERROR-STATE): distinguish auth failure from empty history.
      emit(const ChatsState(threads: []));
    }
  }

  Future<CpaasSendReceipt?> send({
    required String to,
    required String body,
    bool consent = false,
  }) async {
    try {
      return await _repo.sendMessage(to: to, body: body, consent: consent);
    } catch (_) {
      // TODO(P2-CHAT-SEND-UI): surface send failures instead of dropping them.
      return null;
    }
  }
}
