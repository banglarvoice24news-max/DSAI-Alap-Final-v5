// Chat data layer.
//
// Threads come from the E2EE message store, exposed as per-counterpart
// summaries at GET /api/messages/threads (JWT-authed via ApiClient). The
// endpoint returns metadata only — counterpart id/name, last message time and
// unread count — never plaintext, because message bodies stay encrypted and
// are only decryptable on-device.
//
// GAP NOTE: rendering message bubbles requires a client-side E2EE decrypt
// layer that does not exist yet; the list can only show thread metadata. The
// CPaaS /api/cpaas/logs endpoint is call/SMS audit data and MUST NOT be used as
// a chat source (an earlier revision did this and mislabelled calls as chats).

import '../../core/constants.dart';
import '../../core/network/api_client.dart';
import 'chat_models.dart';

class CpaasSendReceipt {
  const CpaasSendReceipt({required this.refId, required this.status});

  final String refId;
  final String status;
}

abstract class ChatRepository {
  Future<List<ChatThread>> loadThreads();

  Future<CpaasSendReceipt> sendMessage({
    required String to,
    required String body,
    bool consent,
  });
}

class CpaasChatRepository implements ChatRepository {
  CpaasChatRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  @override
  Future<List<ChatThread>> loadThreads() async {
    final res = await _api.get('/api/messages/threads', query: {'take': 50});
    final data = res['data'] as List? ?? const [];
    return data.cast<Map>().map((raw) => chatThreadFromSummary(raw)).toList();
  }

  @override
  Future<CpaasSendReceipt> sendMessage({
    required String to,
    required String body,
    bool consent = false,
  }) async {
    // TODO(P2-CHAT-E2EE-SEND): chat send must POST ciphertext to /api/messages
    // once the client encryption layer exists. This SMS path is retained only
    // for the CPaaS fallback channel and is currently unused by the UI.
    final res = await _api.post(
      '/api/cpaas/sms',
      data: {'to': to, 'body': body, 'consent': consent},
      headers: {'x-dsaialap-key': AppConstants.b2bApiKey},
    );
    final data = res['data'] as Map?;
    return CpaasSendReceipt(
      refId: (data?['refId'] as String?) ?? '',
      status: (data?['status'] as String?) ?? 'UNKNOWN',
    );
  }
}

/// Maps one `/api/messages/threads` summary into the list model. No plaintext
/// is available, so [ChatThread.preview] is intentionally left empty.
ChatThread chatThreadFromSummary(Map raw) {
  final counterpartId = (raw['counterpartId'] as String?) ?? '';
  final name = raw['counterpartName'] as String?;
  return ChatThread(
    id: counterpartId,
    title: (name == null || name.isEmpty) ? counterpartId : name,
    preview: '',
    unread: (raw['unreadCount'] as int?) ?? 0,
    online: false,
    lastMessageAt: DateTime.tryParse((raw['lastMessageAt'] as String?) ?? '')?.toLocal(),
    lastMessageMine: (raw['lastMessageMine'] as bool?) ?? false,
  );
}
