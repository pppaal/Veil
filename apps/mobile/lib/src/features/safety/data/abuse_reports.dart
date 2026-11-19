import '../../../core/network/veil_api_client.dart';

/// Why an account is reported: the reasons the server takes
/// (AbuseReportReason), in the order the report sheet lists them.
enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  impersonation('impersonation'),
  csam('csam'),
  violence('violence'),
  scam('scam'),
  other('other');

  const ReportReason(this.wire);

  /// The value the API takes.
  final String wire;
}

/// Who is reported, and from where: a chat ([conversationId]), one of its
/// messages ([messageId] as well), or the contacts list (neither).
/// [offerBlock] is whether the report sheet offers to block them too: in a
/// 1:1 and from the contacts list, where a block stops what they send; not
/// from a group, where it would not.
class ReportTarget {
  const ReportTarget({
    required this.userId,
    required this.handle,
    this.conversationId,
    this.messageId,
    this.offerBlock = false,
  }) : assert(messageId == null || conversationId != null, 'a message is reported with its chat');

  final String userId;
  final String handle;
  final String? conversationId;
  final String? messageId;
  final bool offerBlock;
}

/// Files abuse reports (POST /safety/reports). A report holds the reported
/// account, the reason and, when it was filed from a chat or a message,
/// which one; never any text: VeilApiClient.fileAbuseReport has no field for
/// it, and what a message says stays on this phone.
class AbuseReports {
  AbuseReports({required VeilApiClient api, required String? Function() accessToken})
      : _api = api,
        _accessToken = accessToken;

  final VeilApiClient _api;
  final String? Function() _accessToken;

  /// False when the server refused the report (it takes six a minute) or
  /// could not be reached.
  Future<bool> file(ReportTarget target, ReportReason reason) async {
    final token = _accessToken();
    if (token == null) return false;
    try {
      await _api.fileAbuseReport(
        token,
        reportedUserId: target.userId,
        reason: reason.wire,
        conversationId: target.conversationId,
        messageId: target.messageId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
