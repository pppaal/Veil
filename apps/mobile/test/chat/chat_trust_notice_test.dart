import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/conversation_preview.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_trust_notice.dart';

// Which trust banner a chat shows (spec A12): at most one, a look-alike
// before a claim before the nudge; with an identity notice up, which has
// an action of its own, the claim loses its Verify and the nudge does not
// show at all.

void main() {
  const lookalike = ChatTrustNotice.lookalike(name: 'Sam Rivera', handle: 'sam.official');
  const nudge = ChatTrustNotice.nudge(name: 'Sam Rivera');

  test('only one trust banner shows: lookalike, then claim, then nudge', () {
    // Each alone.
    expect(pickTrustNotice(lookalike: lookalike, otherNotices: false), lookalike);
    expect(pickTrustNotice(claim: true, otherNotices: false), const ChatTrustNotice.claim());
    expect(pickTrustNotice(nudge: nudge, otherNotices: false), nudge);
    expect(pickTrustNotice(otherNotices: false), isNull);

    // Together: the look-alike first, then the claim, then the nudge.
    expect(pickTrustNotice(lookalike: lookalike, claim: true, nudge: nudge, otherNotices: false), lookalike);
    expect(pickTrustNotice(lookalike: lookalike, claim: true, otherNotices: false), lookalike);
    expect(pickTrustNotice(lookalike: lookalike, nudge: nudge, otherNotices: false), lookalike);
    expect(pickTrustNotice(claim: true, nudge: nudge, otherNotices: false), const ChatTrustNotice.claim());

    // Under an identity notice: the look-alike as it is (it has no action),
    // the claim without Verify, and no nudge.
    expect(pickTrustNotice(lookalike: lookalike, claim: true, nudge: nudge, otherNotices: true), lookalike);
    final claimUnder = pickTrustNotice(claim: true, nudge: nudge, otherNotices: true);
    expect(claimUnder?.kind, ChatTrustNoticeKind.claim);
    expect(claimUnder?.withAction, isFalse, reason: 'a chat never shows two banner actions');
    expect(pickTrustNotice(nudge: nudge, otherNotices: true), isNull, reason: 'the nudge never shows with a notice');

    // Only the look-alike and the claim are warnings: under them the
    // request bar's Accept is plain.
    expect(lookalike.warns, isTrue);
    expect(const ChatTrustNotice.claim().warns, isTrue);
    expect(nudge.warns, isFalse);
    expect(lookalike.withAction, isFalse, reason: 'the look-alike warning has no action');
    expect(nudge.withAction, isTrue);
  });

  test('the checks look at the one other party of a 1:1 or a two-person group only', () {
    ConversationPreview group(List<String> handles) => ConversationPreview(
          id: 'g',
          peerHandle: '',
          peerDisplayName: null,
          recipientBundle: const KeyBundle(
            userId: '',
            deviceId: '',
            handle: '',
            identityPublicKey: '',
            signedPrekeyBundle: '',
          ),
          lastEnvelope: null,
          updatedAt: DateTime.utc(2026, 4, 7),
          type: ConversationType.group,
          members: [for (final handle in handles) GroupMember(userId: 'user-$handle', handle: handle)],
        );
    expect(trustPeerOf(group(['alex', 'sam.official']), localUserId: 'user-alex'),
        (userId: 'user-sam.official', handle: 'sam.official'));
    expect(trustPeerOf(group(['alex', 'sam.official', 'ines.v']), localUserId: 'user-alex'), isNull);
  });
}
