import '../../../../core/network/veil_api_client.dart';
import '../conversation_models.dart';
import 'message_merge.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

typedef _Receipt = ({DateTime? deliveredAt, DateTime? readAt});

/// Delivery and read receipts: applied to the messages they name, held
/// back for messages not loaded yet, and sent for messages read here.
class ReceiptService {
  ReceiptService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required bool Function() readReceiptsEnabled,
  })  : _store = store,
        _session = session,
        _apiClient = apiClient,
        _readReceiptsEnabled = readReceiptsEnabled;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final VeilApiClient _apiClient;
  // Read on every use so a settings change applies at once.
  final bool Function() _readReceiptsEnabled;
  final Map<String, _Receipt> _backlog = {};

  /// Applies a receipt for [messageId]. Receipts only move a message's state
  /// forward, so they may arrive in any order. With read receipts off, a
  /// peer's read shows as delivered only: this device does not tell peers
  /// what it read, and does not learn it either.
  void apply(String messageId, {DateTime? deliveredAt, DateTime? readAt}) {
    if (!_readReceiptsEnabled() && readAt != null) {
      deliveredAt ??= readAt;
      readAt = null;
    }
    final receipt = (deliveredAt: deliveredAt, readAt: readAt);
    if (_store.updateMessagesWhere((message) => message.id == messageId, (message) => _withReceipt(message, receipt))) {
      return;
    }
    final held = _backlog[messageId];
    _backlog[messageId] = (
      deliveredAt: laterOf(held?.deliveredAt, deliveredAt),
      readAt: laterOf(held?.readAt, readAt),
    );
  }

  /// [messages] with the receipts that arrived before them.
  List<ChatMessage> applyBacklog(List<ChatMessage> messages) {
    if (_backlog.isEmpty) return messages;
    return [
      for (final message in messages)
        if (_backlog.remove(message.id) case final receipt?) _withReceipt(message, receipt) else message,
    ];
  }

  /// Tells the relay [messageId] was read here, when read receipts are on.
  Future<void> markRead(String messageId) async {
    final session = _session.authed;
    if (session == null || !_readReceiptsEnabled() || messageId.startsWith(localNoticeIdPrefix)) return;
    try {
      await _apiClient.markRead(session.accessToken, messageId);
      apply(messageId, readAt: DateTime.now());
    } catch (_) {
      // Server resync reconciles later.
    }
  }

  void clear() => _backlog.clear();

  static ChatMessage _withReceipt(ChatMessage message, _Receipt receipt) {
    final deliveredAt = laterOf(message.deliveredAt, receipt.deliveredAt);
    final readAt = laterOf(message.readAt, receipt.readAt);
    return message.copyWith(
      deliveryState: resolveDeliveryState(base: message.deliveryState, deliveredAt: deliveredAt, readAt: readAt),
      deliveredAt: deliveredAt,
      readAt: readAt,
    );
  }
}
