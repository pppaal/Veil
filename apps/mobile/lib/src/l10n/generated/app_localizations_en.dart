// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VEIL';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonDone => 'Done';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonIUnderstand => 'I understand';

  @override
  String get pillDeviceBound => 'Device-bound';

  @override
  String get pillNoRecovery => 'No recovery';

  @override
  String get pillNoPasswordReset => 'No password reset';

  @override
  String get pillOldDeviceRequired => 'Old device required';

  @override
  String get pillPrivateBeta => 'Private beta';

  @override
  String get pillDeviceBoundMessenger => 'Device-bound messenger';

  @override
  String get pillNoContactSync => 'No contact sync';

  @override
  String get pillHandleDiscovery => 'Handle discovery';

  @override
  String get pillSessionLocked => 'Session locked';

  @override
  String get pillPreviewObscured => 'Preview obscured';

  @override
  String get privacyShieldEyebrow => 'PRIVACY SHIELD';

  @override
  String get privacyShieldTitle => 'VEIL is hidden while inactive.';

  @override
  String get privacyShieldBody =>
      'Recent-app previews are obscured and the local barrier is re-armed when the app leaves the foreground.';

  @override
  String get splashEyebrow => 'PRIVATE BETA';

  @override
  String get splashBody => 'No backup. No recovery. No leaks.';

  @override
  String get splashErrorTitle => 'Runtime configuration blocked';

  @override
  String get splashPreparingTitle => 'Preparing local state';

  @override
  String get splashPreparingBody =>
      'Checking onboarding, session binding, and local security state.';

  @override
  String get onboardingWarnEyebrow => 'PRODUCT RULES';

  @override
  String get onboardingWarnTitle => 'No backup.\nNo recovery.\nNo leaks.';

  @override
  String get onboardingWarnBody =>
      'VEIL is device-bound by design. Loss is final. Restore is unavailable. This is not a cloud inbox.';

  @override
  String get onboardingWarnDestructiveTitle => 'Unrecoverable by design';

  @override
  String get onboardingWarnDestructiveBody =>
      'If you lose your device, your account and messages are gone. VEIL cannot restore your access.';

  @override
  String get onboardingWarnIdentityTitle => 'Identity';

  @override
  String get onboardingWarnIdentityLine1 =>
      'This device becomes your identity.';

  @override
  String get onboardingWarnIdentityLine2 =>
      'Your private material stays on the device.';

  @override
  String get onboardingWarnIdentityLine3 => 'There is no password reset path.';

  @override
  String get onboardingWarnTransferTitle => 'Transfer';

  @override
  String get onboardingWarnTransferLine1 =>
      'Transfer works only while the old device still exists.';

  @override
  String get onboardingWarnTransferLine2 =>
      'The old device must approve the move.';

  @override
  String get onboardingWarnTransferLine3 => 'No old device means no transfer.';

  @override
  String get privacyConsentTitle => 'Privacy Notice';

  @override
  String get privacyConsentSubtitle => 'Read before using VEIL';

  @override
  String get privacyConsentEyebrow => 'PRIVACY PROTECTION';

  @override
  String get privacyConsentHeroTitle => 'Privacy &\nData Protection';

  @override
  String get privacyConsentHeroBody =>
      'VEIL complies with Korea\'s PIPA. Please review the notice below before using the service.';

  @override
  String get privacyConsentAgree =>
      'I agree to the collection and use of personal information above. (Required)\nI agree to the collection and use of personal information as described above. (Required)';

  @override
  String get privacyConsentAccept => 'Agree and continue';

  @override
  String get privacyConsentCollectTitle => 'Information we collect';

  @override
  String get privacyConsentCollectItem1 => 'User handle (unique identifier)';

  @override
  String get privacyConsentCollectItem2 =>
      'Device info (platform, device name)';

  @override
  String get privacyConsentCollectItem3 =>
      'Public key (for encrypted communication)';

  @override
  String get privacyConsentPurposeTitle => 'Purpose of collection';

  @override
  String get privacyConsentPurposeItem1 =>
      'Provide end-to-end encrypted messaging';

  @override
  String get privacyConsentPurposeItem2 =>
      'Device authentication and session management';

  @override
  String get privacyConsentPurposeItem3 =>
      'Contact discovery and conversation routing';

  @override
  String get privacyConsentRetentionTitle => 'Retention period';

  @override
  String get privacyConsentRetentionItem1 =>
      'Deleted immediately on account deletion request';

  @override
  String get privacyConsentRetentionItem2 =>
      'Device data removed when device is unpaired';

  @override
  String get privacyConsentRetentionItem3 =>
      'Expired messages are auto-deleted';

  @override
  String get privacyConsentRightsTitle => 'Your rights';

  @override
  String get privacyConsentRightsItem1 =>
      'Right to access, correct, and delete your information';

  @override
  String get privacyConsentRightsItem2 =>
      'Full deletion available from Settings → Delete account';

  @override
  String get privacyConsentRightsItem3 =>
      'Withdrawing consent terminates service access';

  @override
  String get privacyConsentNotCollectedTitle => 'What we do not collect';

  @override
  String get privacyConsentNotCollectedItem1 =>
      'Message contents (end-to-end encrypted, unreadable by server)';

  @override
  String get privacyConsentNotCollectedItem2 => 'Location data';

  @override
  String get privacyConsentNotCollectedItem3 =>
      'Contacts, call logs, or other device personal data';

  @override
  String get privacyConsentThirdPartyTitle => 'Third-party disclosure';

  @override
  String get privacyConsentThirdPartyBody =>
      'VEIL does not share collected personal information with third parties, except as required by applicable law.';

  @override
  String get authCreateTitle => 'Create Account';

  @override
  String get authCreateEyebrow => 'DEVICE BINDING';

  @override
  String get authCreateHeroTitle => 'This device becomes your identity.';

  @override
  String get authCreateHeroBody =>
      'VEIL binds access to the hardware in your hand. If the device is lost, the account is lost with it.';

  @override
  String get authCreateRestoreTitle => 'No restore path';

  @override
  String get authCreateRestoreBody =>
      'If you lose this device, your account and messages are gone. VEIL cannot restore access. This is intentional.';

  @override
  String get authCreateMetricIdentity => 'Identity';

  @override
  String get authCreateMetricIdentityValue => 'Local';

  @override
  String get authCreateMetricRecovery => 'Recovery';

  @override
  String get authCreateMetricRecoveryValue => 'None';

  @override
  String get authCreateMetricTransfer => 'Transfer';

  @override
  String get authCreateMetricTransferValue => 'Old device';

  @override
  String get authCreateFieldLabel => 'PROFILE LABEL';

  @override
  String get authCreateFieldCaption =>
      'Handles are the discovery layer. This label is presentation only.';

  @override
  String get authCreateDisplayName => 'Display name';

  @override
  String get authCreateDisplayHint => 'Optional label for this account';

  @override
  String get authCreateTransferLabel => 'Transfer from old device';

  @override
  String get authHandleTitle => 'Choose Handle';

  @override
  String get authHandleEyebrow => 'HANDLE REGISTRATION';

  @override
  String get authHandleHeroTitle => 'Phone numbers stay out.';

  @override
  String get authHandleHeroBody =>
      'Pick a direct handle for discovery. VEIL binds the handle to this device after local identity material is generated.';

  @override
  String get authHandleFieldLabel => 'HANDLE';

  @override
  String get authHandleFieldCaption =>
      'Lowercase. Minimal. Permanent enough to matter.';

  @override
  String get authHandleInputLabel => 'Handle';

  @override
  String get authHandleInputHint => 'cold.operator';

  @override
  String get authHandleChoosePrompt => 'Choose a handle';

  @override
  String get authHandleBindingSection => 'BINDING FLOW';

  @override
  String get authHandleStep1Title => 'Generate local identity';

  @override
  String get authHandleStep1Body =>
      'Create device-bound material and keep the private side on this device.';

  @override
  String get authHandleStep2Title => 'Register handle';

  @override
  String get authHandleStep2Body =>
      'Publish only public device material and handle metadata.';

  @override
  String get authHandleStep3Title => 'Challenge device';

  @override
  String get authHandleStep3Body =>
      'Request a short-lived server challenge for this registered device.';

  @override
  String get authHandleStep4Title => 'Verify and bind';

  @override
  String get authHandleStep4Body =>
      'Complete verification and activate the device session.';

  @override
  String get authHandleFailedTitle => 'Binding failed';

  @override
  String get authHandleBindCta => 'Bind this device';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsEyebrow => 'LOCAL DEVICE';

  @override
  String get settingsNoDeviceBound => 'No active device session is bound.';

  @override
  String settingsCurrentDevice(String deviceId) {
    return 'Current device session: $deviceId';
  }

  @override
  String get settingsPillPrivateByDesign => 'Private by design';

  @override
  String get settingsSectionDeviceGraph => 'TRUSTED DEVICE GRAPH';

  @override
  String get settingsLoadingDeviceGraph => 'Loading device graph';

  @override
  String get settingsLoadingDeviceGraphBody =>
      'Reviewing the bound devices known to this account.';

  @override
  String get settingsDeviceGraphUnavailable => 'Device graph unavailable';

  @override
  String get settingsNoTrustedDevices => 'No trusted devices visible';

  @override
  String get settingsAppLockTitle => 'App lock';

  @override
  String get settingsAppLockSubtitle =>
      'Biometric and PIN barrier on this device only';

  @override
  String get settingsDeviceTransferTitle => 'Device transfer';

  @override
  String get settingsDeviceTransferSubtitle =>
      'Old device must initiate and approve';

  @override
  String get settingsSecurityStatusTitle => 'Security status';

  @override
  String get settingsSecurityStatusSubtitle =>
      'Review local guardrails and runtime state';

  @override
  String get settingsNoRecoveryPath => 'No recovery path';

  @override
  String get settingsLockNow => 'Lock now';

  @override
  String get settingsWipeLocal => 'Wipe local device state';

  @override
  String get settingsWipeConfirmTitle => 'Wipe this device locally?';

  @override
  String get settingsRevokeTitle => 'Revoke this device';

  @override
  String get settingsRevokeConfirmTitle => 'Revoke this device?';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsIrreversible => 'This cannot be undone';

  @override
  String get settingsDeleteAccountTitle => 'Delete account';

  @override
  String get settingsDeleteAccountBody =>
      'Permanently removes your account, messages, and contacts. This cannot be undone.';

  @override
  String get settingsDeleteAccountConfirmLabel => 'Type DELETE to confirm';

  @override
  String get settingsDeleteAccountAction => 'Delete my account';

  @override
  String get settingsDeleteAccountConfirmHeadline => 'Delete your account?';

  @override
  String get chatEmptyTitle => 'No messages yet';

  @override
  String get chatEmptyBody =>
      'Send the first message — it\'s encrypted end-to-end.';

  @override
  String get chatComposeHint => 'Type a message';

  @override
  String get chatSendAction => 'Send';

  @override
  String get chatAttachAction => 'Attach';

  @override
  String get chatLoadingTitle => 'Opening session';

  @override
  String get chatLoadingBody => 'Preparing encrypted channel…';

  @override
  String get chatConversationNotFound => 'Conversation not found';

  @override
  String get chatRelockTitle => 'Session locked';

  @override
  String get chatRelockBody => 'Unlock the app to continue this conversation.';

  @override
  String get chatTitleFallback => 'Secure conversation';

  @override
  String get chatHeroEyebrow => 'SECURE CONVERSATION';

  @override
  String get chatHeroBody =>
      'Direct 1:1 exchange only. Message bodies remain opaque to the server and expire locally when configured.';

  @override
  String get chatSubtitleOnline => 'Online now';

  @override
  String get chatSubtitleEmbedded =>
      'Local search stays on this device. Message bodies remain opaque to the relay.';

  @override
  String get chatSubtitleStandalone =>
      'Direct 1:1 exchange only. Message bodies remain opaque to the server.';

  @override
  String get chatSearchHint => 'Search cached messages on this device';

  @override
  String get chatSearchClearTooltip => 'Clear search';

  @override
  String get chatPillAttachmentsEncrypted => 'Attachments encrypted';

  @override
  String get chatPillLocalSearchOnly => 'Local search only';

  @override
  String get chatMetricRelay => 'Relay';

  @override
  String get chatMetricRelayLinked => 'Linked';

  @override
  String get chatMetricRelayRecovering => 'Recovering';

  @override
  String get chatMetricLoaded => 'Loaded';

  @override
  String get chatMetricHistory => 'History';

  @override
  String get chatMetricHistoryLoading => 'Loading older';

  @override
  String get chatMetricHistoryPaged => 'Paged';

  @override
  String get chatMetricHistoryComplete => 'Complete';

  @override
  String get chatMetricSearch => 'Search';

  @override
  String get chatMetricSearchIdle => 'Idle';

  @override
  String chatMetricSearchHits(int count) {
    return '$count hits';
  }

  @override
  String get chatBannerHistoryLoadingTitle => 'Syncing older history';

  @override
  String get chatBannerHistoryLoadingBody =>
      'Pulling older encrypted history from the relay for this trusted device.';

  @override
  String get chatBannerHistoryCompleteTitle => 'Conversation window complete';

  @override
  String get chatBannerHistoryCompleteBody =>
      'The currently trusted device-local window is fully loaded. Older history is not pending right now.';

  @override
  String get chatBannerConversationIssue => 'Conversation issue';

  @override
  String get chatBannerRelayReconnecting => 'Relay reconnecting';

  @override
  String get chatBannerDeliveryStalled => 'Delivery stalled';

  @override
  String get chatBannerQueuedLocally => 'Queued locally';

  @override
  String chatBannerFailedSends(int count) {
    return '$count message(s) failed to send. Retry when the relay is reachable.';
  }

  @override
  String chatBannerUploadingAttachments(int count) {
    return '$count attachment message(s) are uploading opaque blobs before send.';
  }

  @override
  String chatBannerQueuedMessages(int count) {
    return '$count message(s) are staged locally and will retry after reconnect.';
  }

  @override
  String get chatRetryFailedSendsAction => 'Retry failed sends';

  @override
  String get chatSearchBannerSearchingTitle => 'Searching locally';

  @override
  String get chatSearchBannerIdleTitle => 'Local message search';

  @override
  String get chatSearchBannerSearchingBody =>
      'Scanning cached message text on this device. Relay state does not change.';

  @override
  String get chatSearchBannerEmptyBody =>
      'No cached message text matched this query in the current conversation.';

  @override
  String chatSearchBannerResultBody(int count) {
    return 'Showing $count cached match(es). Clear search to return to full conversation context.';
  }

  @override
  String get chatComposerExpiryOff =>
      'This send does not expire unless you change the rule.';

  @override
  String chatComposerExpiryOn(String duration) {
    return 'This send expires in $duration on every device that sees it.';
  }

  @override
  String get chatLoadOlder => 'Load older';

  @override
  String get chatLoadingOlder => 'Loading older';

  @override
  String get chatSearchEmptyTitle => 'No local matches';

  @override
  String get chatSearchEmptyBody =>
      'This device did not find a matching cached message in the current conversation.';

  @override
  String get chatTtlSheetTitle => 'Disappearing messages';

  @override
  String get chatTtlOff => 'Off';

  @override
  String get chatTtlOffCaption => 'Messages remain until manually deleted.';

  @override
  String get chatTtl10s => '10 seconds';

  @override
  String get chatTtl10sCaption =>
      'Strongest ephemerality. Expect the recipient to be looking.';

  @override
  String get chatTtl1m => '1 minute';

  @override
  String get chatTtl5m => '5 minutes';

  @override
  String get chatTtl1h => '1 hour';

  @override
  String get chatTtl1d => '1 day';

  @override
  String get chatTtl1dCaption => 'Default for casual private conversations.';

  @override
  String get chatTtlCustom => 'Custom TTL';

  @override
  String get chatTtlDisabledLabel => 'Disappear off';

  @override
  String get chatAttachmentTicketTitle => 'Attachment ticket ready';

  @override
  String chatAttachmentTicketBody(String summary) {
    return 'A short-lived local download ticket was resolved for this device.\n\nSummary: $summary\n\nCopying and sharing the raw ticket is intentionally disabled.';
  }

  @override
  String get chatAttachmentTicketFailed => 'Attachment ticket failed';

  @override
  String get chatAttachmentResolveAction => 'Resolve download ticket';

  @override
  String get chatAttachmentResolvingAction => 'Resolving ticket';

  @override
  String get chatAttachmentEncryptedImage => 'Encrypted image';

  @override
  String get chatAttachmentEncryptedVideo => 'Encrypted video';

  @override
  String get chatAttachmentEncryptedAudio => 'Encrypted audio';

  @override
  String get chatAttachmentEncryptedDocument => 'Encrypted document';

  @override
  String get chatAttachmentEncryptedFile => 'Encrypted file';

  @override
  String get chatAttachmentStateBanner => 'Attachment state';

  @override
  String get chatReplyLocally => 'Reply locally';

  @override
  String get chatReplyPrimed =>
      'Composer primed for a quick response in this conversation.';

  @override
  String get chatScreenshotToast =>
      'Screenshot detected in this conversation. Veil cannot prevent it on this device — the other side has been notified.';

  @override
  String get chatScreenshotSystemNotice =>
      'Peer took a screenshot of this conversation on their device.';

  @override
  String get chatDecryptingEnvelope => 'Decrypting envelope...';

  @override
  String get chatDecryptingSystemNotice => 'Decrypting system notice...';

  @override
  String get chatRetrySend => 'Retry send';

  @override
  String get chatRetryUpload => 'Retry upload';

  @override
  String get chatCancelAction => 'Cancel';

  @override
  String get chatDeliveryQueued => 'Queued';

  @override
  String get chatDeliveryUploading => 'Uploading';

  @override
  String get chatDeliveryFailed => 'Retry required';

  @override
  String get chatDeliverySent => 'Sent';

  @override
  String get chatDeliveryDelivered => 'Delivered';

  @override
  String get chatDeliveryRead => 'Read';

  @override
  String get chatPhaseStaged => 'Staged';

  @override
  String get chatPhasePreparing => 'Preparing';

  @override
  String get chatPhaseUploading => 'Uploading';

  @override
  String get chatPhaseFinalizing => 'Finalizing';

  @override
  String get chatPhaseFailed => 'Retry required';

  @override
  String get chatPhaseCanceled => 'Canceled';

  @override
  String chatPhaseDescStaged(String sizeLabel) {
    return 'Opaque blob staged locally.$sizeLabel Upload begins when the relay is reachable.';
  }

  @override
  String get chatPhaseDescPreparing =>
      'Refreshing upload authorization and validating encrypted metadata.';

  @override
  String get chatPhaseDescUploading =>
      'Sending ciphertext-like bytes to object storage. The relay never sees plaintext.';

  @override
  String get chatPhaseDescFinalizing =>
      'Binding the uploaded blob into an encrypted message envelope.';

  @override
  String get chatPhaseDescFailed =>
      'Upload failed. Retry will reuse the local encrypted temp blob.';

  @override
  String get chatPhaseDescCanceled =>
      'Upload stopped on this device. Retry will request a fresh ticket and reuse the local blob.';

  @override
  String chatAttachmentSizeBytes(int count) {
    return ' $count bytes.';
  }

  @override
  String chatTypingSuffix(String handle) {
    return '@$handle is typing';
  }

  @override
  String get chatSemanticsSent => 'Sent';

  @override
  String get chatSemanticsReceived => 'Received';

  @override
  String chatSemanticsBubble(String direction, String stateSegment) {
    return '$direction message bubble.$stateSegment';
  }

  @override
  String chatSemanticsStateSegment(String state) {
    return ' $state.';
  }

  @override
  String chatNetworkRecoveryFailed(int count, String retryLabel) {
    return '$count message(s) are waiting on relay recovery. $retryLabel';
  }

  @override
  String chatNetworkRecoveryUploading(int count, String retryLabel) {
    return '$count attachment message(s) are paused while the relay reconnects. $retryLabel';
  }

  @override
  String chatNetworkRecoveryQueued(int count, String retryLabel) {
    return '$count message(s) remain queued on this device. $retryLabel';
  }

  @override
  String get chatRetryResumes => 'Retry resumes when the relay reconnects.';

  @override
  String chatRetryNextIn(String countdown) {
    return 'Next retry in $countdown.';
  }

  @override
  String chatDurationDays(int count) {
    return '$count day(s)';
  }

  @override
  String chatDurationHours(int count) {
    return '$count hour(s)';
  }

  @override
  String chatDurationMinutes(int count) {
    return '$count minute(s)';
  }

  @override
  String chatDurationSeconds(int count) {
    return '$count second(s)';
  }

  @override
  String get conversationsTitle => 'Conversations';

  @override
  String get conversationsEmptyTitle => 'No conversations yet';

  @override
  String get conversationsEmptyBody =>
      'Find someone by handle and send the first encrypted message.';

  @override
  String get conversationsSearchHint => 'Search conversations and archive';

  @override
  String get conversationsNewChat => 'New direct chat';

  @override
  String get conversationsNewGroup => 'New group';

  @override
  String get conversationsArchiveSection => 'Archive results';

  @override
  String get conversationsLoadingArchive => 'Searching archive…';

  @override
  String get conversationsQueuedOne => '1 message queued locally';

  @override
  String conversationsQueuedMany(int count) {
    return '$count messages queued locally';
  }

  @override
  String get notificationNewMessageTitle => 'VEIL';

  @override
  String get notificationNewMessageBody => 'New encrypted message';
}
