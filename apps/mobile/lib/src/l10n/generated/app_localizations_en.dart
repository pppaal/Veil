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
  String get appLockTitle => 'App Lock';

  @override
  String get appLockLoadingTitle => 'Checking local barrier';

  @override
  String get appLockLoadingBody =>
      'Looking for a stored PIN and biometric availability.';

  @override
  String get appLockHeroEyebrow => 'LOCAL BARRIER';

  @override
  String get appLockHeroTitle => 'VEIL never unlocks itself remotely.';

  @override
  String get appLockHeroBody =>
      'PIN and biometrics are checked on this device only. No server can reset or override them.';

  @override
  String get appLockPillLocalOnly => 'Local only';

  @override
  String get appLockPillNoRemoteReset => 'No remote reset';

  @override
  String get appLockNoRecoveryBody =>
      'If you forget the local barrier and lose the active device, VEIL cannot restore access.';

  @override
  String get appLockCompromisedTitle => 'Compromised device blocked';

  @override
  String get appLockCompromisedBody =>
      'This device appears rooted or jailbroken. VEIL blocks local unlock on compromised devices.';

  @override
  String appLockCompromisedReasons(String reasons) {
    return 'This device appears rooted or jailbroken. $reasons';
  }

  @override
  String get appLockLockoutTitle => 'PIN temporarily locked';

  @override
  String appLockLockoutBody(String retry) {
    return 'Too many failed PIN attempts on this device. $retry';
  }

  @override
  String get appLockRetryNow => 'Try again now.';

  @override
  String appLockRetrySeconds(int seconds) {
    return 'Try again in ${seconds}s.';
  }

  @override
  String appLockRetryMinutes(int minutes) {
    return 'Try again in ${minutes}m.';
  }

  @override
  String get appLockPinLabel => 'PIN';

  @override
  String get appLockMetricConfigured => 'Configured';

  @override
  String get appLockMetricRequired => 'Required';

  @override
  String get appLockMetricBiometrics => 'Biometrics';

  @override
  String get appLockMetricAvailable => 'Available';

  @override
  String get appLockMetricUnavailable => 'Unavailable';

  @override
  String get appLockMetricPreview => 'Preview';

  @override
  String get appLockMetricProtected => 'Protected';

  @override
  String get appLockMetricShielded => 'Shielded';

  @override
  String get appLockPillPinConfigured => 'PIN configured';

  @override
  String get appLockPillPinRequired => 'PIN required';

  @override
  String get appLockPillBiometricsAvailable => 'Biometrics available';

  @override
  String get appLockPillBiometricsUnavailable => 'Biometrics unavailable';

  @override
  String get appLockPillCaptureBlocked => 'Capture blocked';

  @override
  String get appLockPillPreviewShield => 'Preview shield only';

  @override
  String get appLockCaptionSet =>
      'Set a local numeric barrier before continuing. VEIL cannot reset it for you.';

  @override
  String get appLockCaptionUnlock =>
      'Unlock with this device\'s PIN or biometrics.';

  @override
  String get appLockFieldSetPin => 'Set PIN';

  @override
  String get appLockFieldPinHint => '6 to 12 digits';

  @override
  String get appLockFieldPinError => 'Use 6 to 12 digits only.';

  @override
  String get appLockFieldConfirm => 'Confirm PIN';

  @override
  String get appLockFieldConfirmHint => 'Repeat the same PIN';

  @override
  String get appLockConfirmMismatch => 'PIN confirmation does not match.';

  @override
  String get appLockStatusTitle => 'Lock status';

  @override
  String get appLockStatusUnlockedTitle => 'Unlocked';

  @override
  String get appLockStatusUnlocked => 'Unlocked.';

  @override
  String get appLockStatusBiometricFailed => 'Biometric unlock failed.';

  @override
  String get appLockStatusEnterPin => 'Enter a PIN first.';

  @override
  String get appLockStatusPinFormat => 'PIN must be 6 to 12 digits.';

  @override
  String get appLockStatusPinMismatch => 'PIN mismatch.';

  @override
  String appLockStatusPinMismatchAttempts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'PIN mismatch. $count attempts left before temporary lock.',
      one: 'PIN mismatch. 1 attempt left before temporary lock.',
    );
    return '$_temp0';
  }

  @override
  String get appLockStatusLocked => 'PIN locked temporarily.';

  @override
  String get appLockStatusCompromised =>
      'Unlock blocked on compromised device.';

  @override
  String get appLockUseBiometrics => 'Use biometrics';

  @override
  String get appLockSetAndUnlock => 'Set PIN and unlock';

  @override
  String get appLockUnlock => 'Unlock VEIL';

  @override
  String get splashEyebrow => 'PRIVATE BETA';

  @override
  String get splashBody => 'No backup. No recovery. No leaks.';

  @override
  String get splashErrorTitle => 'VEIL cannot start';

  @override
  String get splashPreparingTitle => 'Opening VEIL';

  @override
  String get splashPreparingBody =>
      'Checking this device\'s session and security state.';

  @override
  String get onboardingWarnEyebrow => 'PRODUCT RULES';

  @override
  String get onboardingWarnTitle => 'No backup.\nNo recovery.\nNo leaks.';

  @override
  String get onboardingWarnBody =>
      'VEIL is bound to this device by design. It is not a cloud inbox.';

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
      'Your private keys stay on this device.';

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
  String get privacyConsentHeroBody =>
      'VEIL complies with Korea\'s PIPA. Please review the notice below before using the service.';

  @override
  String get privacyConsentAgree =>
      'I agree to the collection and use of personal information as described above. (Required)';

  @override
  String get privacyConsentAccept => 'Agree and continue';

  @override
  String get privacyConsentCollectTitle => 'Information we collect';

  @override
  String get privacyConsentCollectItem1 =>
      'User handle, and the random account and device IDs linked to it';

  @override
  String get privacyConsentCollectItem2 =>
      'Device info (platform, device label) and push token; push wake-ups carry no message content';

  @override
  String get privacyConsentCollectItem3 =>
      'Public identity key and prekeys (for encrypted communication)';

  @override
  String get privacyConsentCollectItem4 =>
      'Your in-app contact list: which accounts you added (the names you give them stay on this device)';

  @override
  String get privacyConsentCollectItem5 =>
      'Conversation membership and delivery metadata: when messages arrived, delivery and read-receipt times, the day a device was last seen';

  @override
  String get privacyConsentCollectItem6 =>
      'Call records: conversation, who started the call, call type, start and end time, duration (kept 30 days)';

  @override
  String get privacyConsentCollectItem7 =>
      'Group and channel names and descriptions (stored readable), and the blocks, mutes and abuse reports you make (reports kept 90 days)';

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
      'Device data is removed when the device is unpaired, and its device record within about 30 days';

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
      'Your phone\'s address book, its call log, or other personal data stored on your device';

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
  String get authCreateRestoreTitle => 'No restore path';

  @override
  String get authCreateRestoreBody =>
      'If you lose this device, your account and messages are gone. VEIL cannot restore access. This is intentional.';

  @override
  String get authCreateFieldLabel => 'PROFILE';

  @override
  String get authCreateFieldCaption =>
      'People find you by your handle. This name is only shown, never searched.';

  @override
  String get authCreateDisplayName => 'Display name';

  @override
  String get authCreateDisplayHint => 'Optional';

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
      'Pick the handle people will find you by. VEIL binds it to this device once the device\'s keys are generated.';

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
  String get authStageGeneratingKeys => 'Generating local identity';

  @override
  String get authStageRegistering => 'Registering handle';

  @override
  String get authStageRequestingChallenge => 'Requesting challenge';

  @override
  String get authStageVerifying => 'Verifying device';

  @override
  String get authStageComplete => 'Bound';

  @override
  String get authDefaultDeviceName => 'VEIL Mobile';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsProfileTitle => 'Profile';

  @override
  String get settingsProfileSubtitle =>
      'Your handle, and the nickname this device calls you by';

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
  String get settingsSectionPrivacy => 'PRIVACY';

  @override
  String get settingsReadReceiptsTitle => 'Send read receipts';

  @override
  String get settingsReadReceiptsSubtitle =>
      'When off, contacts don\'t learn what you read, and you see their reads only as delivered.';

  @override
  String get settingsTypingIndicatorsTitle => 'Send typing indicators';

  @override
  String get settingsTypingIndicatorsSubtitle =>
      'Lets contacts see while you type. Off unless you turn it on.';

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
  String get settingsDeviceGraphLoadFailedBody =>
      'This device could not load the current trust graph. Local security controls remain available.';

  @override
  String get settingsNoTrustedDevicesBody =>
      'This account has no readable device graph yet. Bound-device controls still remain local and unrecoverable.';

  @override
  String get settingsRefreshDeviceGraph => 'Refresh device graph';

  @override
  String get settingsSectionSecurity => 'SECURITY';

  @override
  String get settingsSectionSession => 'SESSION';

  @override
  String get settingsDestructiveNoticeBody =>
      'Destructive device actions are permanent on this device. VEIL does not keep a backup or restore authority.';

  @override
  String get settingsLockNowSubtitle =>
      'Hide the current session behind the local barrier immediately';

  @override
  String get settingsWipeLocalSubtitle =>
      'Deletes local session state, local secrets, encrypted cache, PIN, and onboarding state on this device only.';

  @override
  String get settingsWipeConfirmBody =>
      'This erases local VEIL state on this device. It does not create a recovery path. If this is your only active device, access is gone.';

  @override
  String get settingsWipeConfirmAction => 'Wipe local state';

  @override
  String get settingsRevokeSubtitle =>
      'Destroys this bound device session and wipes local state on this device. No recovery exists.';

  @override
  String get settingsRevokeConfirmBody =>
      'This removes the active device binding for this account on this device and wipes local state here. VEIL cannot restore it.';

  @override
  String get settingsRevokeConfirmAction => 'Revoke device';

  @override
  String get settingsLogoutSubtitle =>
      'Clears this local session while leaving the onboarding acknowledgment and local barrier intact.';

  @override
  String settingsTypePhraseToContinue(String phrase) {
    return 'Type $phrase to continue.';
  }

  @override
  String settingsRevokeListedTitle(String deviceName) {
    return 'Revoke $deviceName?';
  }

  @override
  String settingsRevokeListedBody(String deviceName) {
    return 'This removes $deviceName from the trusted device graph. VEIL will not create a recovery path for that device.';
  }

  @override
  String settingsRevokeListedDone(String deviceName) {
    return '$deviceName was removed from the trusted graph.';
  }

  @override
  String get settingsRevokeListedFailed =>
      'The device could not be revoked. Try again.';

  @override
  String get settingsDeviceStateCurrent => 'This device';

  @override
  String get settingsDeviceStatePreferred => 'Preferred';

  @override
  String get settingsDeviceStateTrusted => 'Trusted';

  @override
  String get settingsDeviceStateStale => 'Stale';

  @override
  String get settingsDeviceStateRevoked => 'Revoked';

  @override
  String get settingsDeviceRevokeAction => 'Revoke';

  @override
  String settingsDeviceCreated(String when) {
    return 'Created $when';
  }

  @override
  String settingsDeviceSeen(String when) {
    return 'Seen $when';
  }

  @override
  String settingsDeviceSynced(String when) {
    return 'Synced $when';
  }

  @override
  String settingsDeviceActivity(String when) {
    return 'Activity $when';
  }

  @override
  String settingsDeviceTrustedAt(String when) {
    return 'Trusted $when';
  }

  @override
  String settingsDeviceJoinedFrom(String device) {
    return 'Joined from $device';
  }

  @override
  String settingsDeviceRevokedAt(String when) {
    return 'Revoked $when';
  }

  @override
  String get settingsDeviceNoteCurrent =>
      'This is the current trusted device. If every trusted device is lost, VEIL cannot restore access.';

  @override
  String get settingsDeviceNotePreferred =>
      'This trusted device is the current preferred routing device. It is not a cloud recovery anchor.';

  @override
  String get settingsDeviceNoteTrusted =>
      'This device remains trusted and can continue syncing while another trusted device exists.';

  @override
  String get settingsDeviceNoteStale =>
      'This device is still trusted but recent trusted activity has gone quiet. Revoke it if it should no longer retain access.';

  @override
  String get settingsDeviceNoteRevoked =>
      'This device is no longer trusted and cannot resume the session.';

  @override
  String get settingsGraphSummary => 'GRAPH SUMMARY';

  @override
  String settingsGraphTrustedCount(int count) {
    return '$count trusted';
  }

  @override
  String settingsGraphStaleCount(int count) {
    return '$count stale';
  }

  @override
  String settingsGraphRevokedCount(int count) {
    return '$count revoked';
  }

  @override
  String settingsGraphRecentActivity(String when) {
    return 'Recent trusted activity $when';
  }

  @override
  String get settingsGraphPreferredDiffersTitle => 'Preferred device differs';

  @override
  String settingsGraphPreferredDiffersBody(String preferred, String current) {
    return '$preferred is currently preferred for routing and directory compatibility. $current remains trusted.';
  }

  @override
  String get settingsGraphStaleTitle => 'Stale trusted devices present';

  @override
  String get settingsGraphStaleBody =>
      'Some trusted devices have no recent trusted activity. Stale does not mean revoked, but they should be reviewed deliberately.';

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
  String get chatSubtitleOnline => 'Online now';

  @override
  String get chatSubtitleEmbedded =>
      'Local search stays on this device. Message bodies remain opaque to the relay.';

  @override
  String get chatSearchHint => 'Search cached messages on this device';

  @override
  String get chatSearchClearTooltip => 'Clear search';

  @override
  String get chatSearchTooltip => 'Search messages';

  @override
  String chatSearchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches on this device',
      one: '1 match on this device',
      zero: 'No matches on this device',
    );
    return '$_temp0';
  }

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
  String get chatAttachmentTicketTitle => 'Download ticket issued';

  @override
  String chatAttachmentTicketBody(String summary) {
    return 'The relay issued a short-lived download ticket for this device.\n\nSummary: $summary\n\nThis build stops here: it does not fetch or open the file yet. The ticket itself is not shown, so it cannot be copied or shared.';
  }

  @override
  String get chatAttachmentTicketFailed => 'Download request failed';

  @override
  String get chatAttachmentResolveAction => 'Request download';

  @override
  String get chatAttachmentResolvingAction => 'Requesting download';

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
  String get chatAttachmentCannotOpen =>
      'This version cannot open attachments.';

  @override
  String get reactionsMoreTooltip => 'More reactions';

  @override
  String get attachmentTitle => 'Attachment';

  @override
  String get attachmentHeroEyebrow => 'ATTACHMENT';

  @override
  String get attachmentHeroTitle => 'Encrypted before it leaves.';

  @override
  String get attachmentHeroBody =>
      'This device encrypts locally, uploads an opaque blob, and then sends an encrypted message that points at it.';

  @override
  String get attachmentPillOpaqueBlob => 'Opaque blob';

  @override
  String get attachmentPillMetadataOnlyRelay => 'Metadata-only relay';

  @override
  String get attachmentPillNoPlaintextPush => 'No plaintext push';

  @override
  String get attachmentNameLabel => 'FILE NAME';

  @override
  String get attachmentNameCaption =>
      'This build has no file picker yet: it sends a small placeholder file under this name, along the path a real attachment will take.';

  @override
  String get attachmentNameInputLabel => 'File name';

  @override
  String get attachmentRelayPolicyTitle => 'Relay policy';

  @override
  String get attachmentRelayPolicyBody =>
      'Private beta currently allows JPEG, PNG, WEBP, PDF, and opaque binary payloads. The relay never receives plaintext filenames or attachment keys.';

  @override
  String get attachmentMetricType => 'Type';

  @override
  String get attachmentMetricUpload => 'Upload';

  @override
  String get attachmentMetricUploadValue => 'Ticketed';

  @override
  String get attachmentMetricBlob => 'Blob';

  @override
  String get attachmentMetricBlobValue => 'Opaque';

  @override
  String get attachmentStepsSection => 'SEND LIFECYCLE';

  @override
  String get attachmentStep1Title => 'Ticket';

  @override
  String get attachmentStep1Body =>
      'Request a scoped upload URL for the opaque blob.';

  @override
  String get attachmentStep2Title => 'Blob upload';

  @override
  String get attachmentStep2Body =>
      'Upload the opaque bytes. A retry reuses the local temporary blob and renews the upload ticket if it has expired.';

  @override
  String get attachmentStep3Title => 'Message';

  @override
  String get attachmentStep3Body =>
      'Queue the encrypted message that points at the upload, and clear the local temporary blob once it is finalized.';

  @override
  String get attachmentSendFailedTitle => 'Attachment send failed';

  @override
  String get attachmentQueuedTitle => 'Queued locally';

  @override
  String get attachmentQueuedBody =>
      'The attachment now continues inside the conversation. Progress, retry and cancel follow its message.';

  @override
  String get attachmentSendAction => 'Encrypt and send';

  @override
  String get attachmentSendingAction => 'Encrypting and sending';

  @override
  String get chatScreenshotToast =>
      'Screenshot detected in this conversation. Veil cannot prevent it on this device — a notice is being sent to the other side.';

  @override
  String get chatScreenshotSystemNotice =>
      'Peer took a screenshot of this conversation on their device.';

  @override
  String get chatDecryptingEnvelope => 'Decrypting envelope...';

  @override
  String get chatDecryptFailed => 'Couldn\'t decrypt this message';

  @override
  String get chatDecryptReplayed => 'Repeated or expired message';

  @override
  String get chatDecryptAwaitingKey => 'Waiting for the sender\'s key';

  @override
  String get chatDecryptSessionMissing => 'Waiting for a secure session';

  @override
  String get chatDecryptIdentityRejected =>
      'Held back: the sender\'s identity changed';

  @override
  String get chatLegacyUnverifiedBadge => 'Unverified sender (legacy)';

  @override
  String get chatNoticeIdentityChanged =>
      'A contact\'s safety number changed. Review it before trusting it again.';

  @override
  String get chatNoticeIdentityNewDevice =>
      'This contact started using a new device.';

  @override
  String get chatNoticeSenderKeysKept =>
      'The server listed this group without its group encryption keys. This device keeps using them.';

  @override
  String get chatNoticeGroupMemberAdded =>
      'Someone was added to this group. They can read messages sent from now on. Check the members in Safety number.';

  @override
  String get chatNoticeGroupMemberRemoved =>
      'Someone left this group or was removed from it.';

  @override
  String get chatIdentityChangedTitle => 'Safety number changed';

  @override
  String get chatIdentityChangedBody =>
      'Nothing is sent to the new key until you review it.';

  @override
  String get chatIdentityChangedReview => 'Review';

  @override
  String get chatAccountHoldOtherTitle => 'A different account';

  @override
  String chatAccountHoldOtherBody(String handle) {
    return 'This chat is listed as @$handle, but it is not the account you talked to as @$handle before. Nothing is sent or opened here until you confirm you want to talk to this account.';
  }

  @override
  String get chatAccountHoldUnissuedTitle => 'Name no VEIL server gives out';

  @override
  String get chatAccountHoldUnissuedBody =>
      'This chat is listed under a name no VEIL server issues, so it may only look like someone you know. Nothing is sent or opened here until you confirm you want to talk to this account.';

  @override
  String get chatAccountHoldOwnTitle => 'Another account under your name';

  @override
  String chatAccountHoldOwnBody(String handle) {
    return 'This chat is listed under your own name, @$handle, but with another account. No one else can have your name: the list this device received was altered, perhaps to pass someone off as you. Nothing is sent or opened here until you confirm you want to talk to this account.';
  }

  @override
  String chatAccountHoldOwnConfirmTitle(String handle) {
    return 'Talk to this other @$handle?';
  }

  @override
  String get chatAccountHoldOwnConfirmBody =>
      'No other VEIL account can have your name: the server showed this account under it. Continue only if you confirmed another way (in person, a call) whose account this is.';

  @override
  String get chatAccountHoldAcknowledge => 'Talk to this account';

  @override
  String get chatPeerVerified => 'Verified';

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
  String get chatExpiryExpired => 'Expired';

  @override
  String chatExpirySeconds(int count) {
    return 'Expires in ${count}s';
  }

  @override
  String chatExpiryMinutes(int count) {
    return 'Expires in ${count}m';
  }

  @override
  String chatExpiryHours(int count) {
    return 'Expires in ${count}h';
  }

  @override
  String chatExpiryDays(int count) {
    return 'Expires in ${count}d';
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
  String get conversationsPreviewEmpty => 'No messages yet';

  @override
  String get conversationsPreviewExpired => 'Expired locally';

  @override
  String get conversationsPreviewMessage => 'Encrypted message';

  @override
  String get conversationsPreviewImage => 'Encrypted image';

  @override
  String get conversationsPreviewAttachment => 'Encrypted attachment';

  @override
  String get conversationsPreviewSystem => 'System envelope';

  @override
  String get conversationsPreviewVoice => 'Encrypted voice note';

  @override
  String get conversationsPreviewSticker => 'Encrypted sticker';

  @override
  String get conversationsPreviewReaction => 'Encrypted reaction';

  @override
  String get conversationsPreviewCall => 'Encrypted call event';

  @override
  String get conversationsHeroEyebrow => 'DIRECT CONVERSATIONS';

  @override
  String get conversationsRelayConnectedBody =>
      'Relay connected. Opaque envelopes only.';

  @override
  String get conversationsRelayIdleBody =>
      'Relay idle. Pulling the latest encrypted state.';

  @override
  String get conversationsRelayLinked => 'Relay linked';

  @override
  String get conversationsRelayIdle => 'Relay idle';

  @override
  String conversationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations',
      one: '1 conversation',
    );
    return '$_temp0';
  }

  @override
  String get conversationsNoBackup => 'No backup';

  @override
  String get conversationsMetricIdle => 'Idle';

  @override
  String get conversationsMetricLocalSearch => 'Local search';

  @override
  String get conversationsMetricSearchActive => 'Active';

  @override
  String get conversationsMetricSearchReady => 'Ready';

  @override
  String get conversationsRefreshingTitle => 'Refreshing locally';

  @override
  String get conversationsRefreshingBody =>
      'Pulling the latest opaque conversation state while preserving local search context.';

  @override
  String get conversationsSyncIssueTitle => 'Sync issue';

  @override
  String get conversationsSearchIndexLabel => 'LOCAL SEARCH INDEX';

  @override
  String get conversationsSearchIndexCaption =>
      'Search stays on this device. Handles, cached previews, and decrypted local index entries only.';

  @override
  String get conversationsSearchFieldHint =>
      'Search conversations and cached messages';

  @override
  String get conversationsSearchHintCompact => 'Search chats and messages';

  @override
  String get conversationsSearchLocalNote => 'Search stays on this device.';

  @override
  String get conversationsFilterAllSenders => 'All senders';

  @override
  String get conversationsFilterMine => 'Mine';

  @override
  String get conversationsFilterTheirs => 'Theirs';

  @override
  String get conversationsFilterAllTypes => 'All types';

  @override
  String get conversationsFilterText => 'Text';

  @override
  String get conversationsFilterMedia => 'Media';

  @override
  String get conversationsFilterAnyDate => 'Any date';

  @override
  String get conversationsFilterLast7Days => 'Last 7d';

  @override
  String get conversationsFilterLast30Days => 'Last 30d';

  @override
  String get conversationsSearchActiveTitle => 'Local search active';

  @override
  String get conversationsSearchScanningBody =>
      'Scanning cached conversation labels and device-local message text.';

  @override
  String conversationsSearchFoundBody(int conversations, int messages) {
    return 'Found $conversations conversation match(es) and $messages message result(s) on this device. Search never leaves local state.';
  }

  @override
  String get conversationsSectionLabel => 'CONVERSATIONS';

  @override
  String conversationsMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get conversationsNoMatchTitle => 'No matching conversations';

  @override
  String get conversationsNoneYetTitle => 'No direct conversations yet';

  @override
  String get conversationsNoMatchBody =>
      'This device did not find a matching handle or display label.';

  @override
  String get conversationsNoneYetBody =>
      'Start with a handle. VEIL keeps discovery manual and private.';

  @override
  String get conversationsStartDirect => 'Start direct chat';

  @override
  String get conversationsStartGroup => 'Start group chat';

  @override
  String get conversationsPillDirect => 'Direct';

  @override
  String conversationsPillQueued(int count) {
    return '$count queued';
  }

  @override
  String get conversationsMessagesSection => 'MESSAGES';

  @override
  String conversationsResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get conversationsNoMessageMatchTitle => 'No local message matches';

  @override
  String get conversationsNoMessageMatchBody =>
      'This device did not find matching cached message text for the current filters.';

  @override
  String get conversationsResultFromYou => 'You';

  @override
  String get conversationsResultFromPeer => 'Peer';

  @override
  String get conversationsKindImage => 'Image';

  @override
  String get conversationsKindAttachment => 'Attachment';

  @override
  String get conversationsKindSystem => 'System';

  @override
  String get conversationsKindVoice => 'Voice';

  @override
  String get conversationsKindSticker => 'Sticker';

  @override
  String get conversationsKindReaction => 'Reaction';

  @override
  String get conversationsKindCall => 'Call';

  @override
  String get conversationsLoadingMore => 'Loading more';

  @override
  String get conversationsLoadMore => 'Load more results';

  @override
  String get conversationsChoosePaneTitle => 'Choose a direct conversation';

  @override
  String get conversationsChoosePaneBody =>
      'Wide layout keeps your conversation list visible while you read and send locally.';

  @override
  String get conversationsActiveEyebrow => 'ACTIVE CONVERSATION';

  @override
  String get conversationsActiveBody =>
      'Adaptive layout keeps conversation context and message flow visible at the same time.';

  @override
  String get conversationsPillOpaqueRelay => 'Opaque relay';

  @override
  String get conversationsNewTooltip => 'New conversation';

  @override
  String conversationsRowSemantics(String name) {
    return 'Conversation with $name';
  }

  @override
  String get conversationsGroupMark => 'Group';

  @override
  String get navChats => 'Chats';

  @override
  String get navContacts => 'Contacts';

  @override
  String get navStories => 'Stories';

  @override
  String get navCalls => 'Calls';

  @override
  String get navSettings => 'Settings';

  @override
  String get oneTimeLinkTitle => 'One-time secret link';

  @override
  String get oneTimeLinkSettingsSubtitle =>
      'An encrypted message that disappears once read. The recipient opens it without the app.';

  @override
  String get oneTimeLinkIntro =>
      'Create a message that disappears once it is read. The recipient does not need the app. The decryption key travels only in the link and is not sent to the server.';

  @override
  String get oneTimeLinkSecretLabel => 'Secret';

  @override
  String get oneTimeLinkSecretHint =>
      'A password, an account number, a sensitive note…';

  @override
  String get oneTimeLinkUsePassphrase =>
      'Add a passphrase (the key is kept out of the link: safer)';

  @override
  String get oneTimeLinkPassphraseLabel => 'Passphrase';

  @override
  String get oneTimeLinkCreate => 'Create secure link';

  @override
  String get oneTimeLinkFailed =>
      'The link could not be created. Try again in a moment.';

  @override
  String get oneTimeLinkCopy => 'Copy link';

  @override
  String get oneTimeLinkCopied => 'Link copied';

  @override
  String get oneTimeLinkPillEncrypted => 'End-to-end encrypted';

  @override
  String get oneTimeLinkPillServerBlind => 'Server sees no text or key';

  @override
  String get oneTimeLinkPillBurns => 'Gone once read';

  @override
  String get contactsNotice =>
      'The relay keeps which accounts you added. The names you give them stay on this device.';

  @override
  String get contactsSearchHint => 'Search contacts…';

  @override
  String get contactsAdd => 'Add contact';

  @override
  String get contactsWorking => 'Working…';

  @override
  String get contactsErrorTitle => 'Contacts error';

  @override
  String get contactsEmptyTitle => 'No contacts found';

  @override
  String get contactsEmptySearchBody => 'No contacts match your search.';

  @override
  String get contactsEmptyBody => 'Add contacts to start messaging securely.';

  @override
  String get contactsAddSheetBody =>
      'Enter the exact handle. VEIL does not scan address books.';

  @override
  String get contactsHandleLabel => 'Handle';

  @override
  String get contactsNicknameLabel => 'Nickname (optional)';

  @override
  String get contactsNicknameHint => 'Private label';

  @override
  String get contactsSave => 'Save contact';

  @override
  String contactsAdded(String handle) {
    return 'Contact @$handle added';
  }

  @override
  String get contactsStartChat => 'Start chat';

  @override
  String get contactsStartChatFailed => 'Could not start conversation';

  @override
  String get contactsViewProfile => 'View profile';

  @override
  String get contactsRemove => 'Remove contact';

  @override
  String contactsRemoved(String name) {
    return '$name removed from contacts';
  }

  @override
  String get contactsRemoveFailed => 'Could not remove contact';

  @override
  String contactsYourNickname(String nickname) {
    return 'Your nickname: $nickname';
  }

  @override
  String get callsMissed => 'Missed';

  @override
  String get callsDeclined => 'Declined';

  @override
  String get callsRinging => 'Ringing';

  @override
  String get callsIncoming => 'Incoming';

  @override
  String get callsOutgoing => 'Outgoing';

  @override
  String callsToday(String time) {
    return 'Today, $time';
  }

  @override
  String callsYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get callsUnavailableTitle => 'Call history unavailable';

  @override
  String get callsEmptyTitle => 'No call history';

  @override
  String get callsEmptyBody => 'Calls you make or receive will appear here.';

  @override
  String get callsNotAvailable => 'Calls are not available in this build yet.';

  @override
  String get notificationNewMessageTitle => 'VEIL';

  @override
  String get notificationNewMessageBody => 'New encrypted message';

  @override
  String get startDirectTitle => 'Find by Handle';

  @override
  String get startDirectEyebrow => 'DIRECT DISCOVERY';

  @override
  String get startDirectHeroTitle => 'No contact sync.';

  @override
  String get startDirectHeroBody =>
      'Enter the handle directly. VEIL does not scan contacts, phone books, or social graphs.';

  @override
  String get startDirectPillManual => 'Manual discovery';

  @override
  String get startDirectPillNoGraph => 'No social graph';

  @override
  String get startDirectPillDirectOnly => 'Direct only';

  @override
  String get startDirectBannerTitle => 'Deliberate discovery';

  @override
  String get startDirectBannerBody =>
      'Conversations open only when you know the exact handle. There is no graph expansion layer here.';

  @override
  String get startDirectMetricDiscovery => 'Discovery';

  @override
  String get startDirectMetricDiscoveryValue => 'Manual';

  @override
  String get startDirectMetricGraph => 'Graph';

  @override
  String get startDirectMetricGraphValue => 'None';

  @override
  String get startDirectMetricMode => 'Mode';

  @override
  String get startDirectMetricModeValue => 'Direct 1:1';

  @override
  String get startDirectFieldLabel => 'TARGET HANDLE';

  @override
  String get startDirectAwaitingInput => 'Awaiting input';

  @override
  String get startDirectFieldCaption =>
      'Discovery stays manual. Direct conversations only.';

  @override
  String get startDirectInputLabel => 'Handle';

  @override
  String get startDirectErrorTitle => 'Unable to open conversation';

  @override
  String get startDirectOpening => 'Opening conversation';

  @override
  String get startDirectOpenButton => 'Open direct conversation';

  @override
  String get startGroupTitle => 'Start Group Chat';

  @override
  String get startGroupEyebrow => 'GROUP CREATION';

  @override
  String get startGroupHeroTitle => 'Private by invitation.';

  @override
  String get startGroupHeroBody =>
      'Groups are explicit. Add members by handle — VEIL never expands invites through contact graphs.';

  @override
  String get startGroupPillInviteOnly => 'Invite-only';

  @override
  String get startGroupPillManualRoster => 'Manual roster';

  @override
  String get startGroupPillE2E => 'E2E encrypted';

  @override
  String get startGroupNameLabel => 'GROUP NAME';

  @override
  String get startGroupRequired => 'Required';

  @override
  String get startGroupNameCaption =>
      'Visible to members. You can rename later.';

  @override
  String get startGroupNameInput => 'Name';

  @override
  String get startGroupDescriptionLabel => 'DESCRIPTION';

  @override
  String get startGroupDescriptionCaption =>
      'Optional. Purpose, charter, or context for members.';

  @override
  String get startGroupDescriptionInput => 'Description';

  @override
  String get startGroupDescriptionHint => 'What is this group for?';

  @override
  String get startGroupMembersLabel => 'INITIAL MEMBERS';

  @override
  String get startGroupNoneYet => 'None yet';

  @override
  String startGroupMembersCount(int count) {
    return '$count handle(s)';
  }

  @override
  String get startGroupMembersCaption =>
      'Comma or space separated handles. You can add more after creation.';

  @override
  String get startGroupMembersInput => 'Member handles';

  @override
  String get startGroupPublicTitle => 'Public directory';

  @override
  String get startGroupPublicSubtitle =>
      'Public groups are discoverable by handle. Keep off for invite-only groups.';

  @override
  String get startGroupErrorTitle => 'Unable to create group';

  @override
  String get startGroupCreating => 'Creating group';

  @override
  String get startGroupCreateButton => 'Create group';

  @override
  String get safetyNumbersTitle => 'Safety Number';

  @override
  String get safetyNumbersLoadingTitle => 'Deriving safety number';

  @override
  String get safetyNumbersLoadingBody => 'Hashing identity keys locally.';

  @override
  String get safetyNumbersMarkedVerified => 'Marked as verified';

  @override
  String get safetyNumbersRotateDialogTitle => 'Start a new session?';

  @override
  String get safetyNumbersRotateDialogBody =>
      'This runs a fresh key agreement with your contact\'s current keys, and your next message starts the new session. Messages already on their way still open. Use this if you suspect this device or your contact\'s device was briefly exposed: a stolen copy of the old session cannot read what the new one carries.';

  @override
  String get safetyNumbersCancel => 'Cancel';

  @override
  String get safetyNumbersRotate => 'Start';

  @override
  String get safetyNumbersSessionRotated =>
      'New session ready. Your next message starts it.';

  @override
  String get safetyNumbersNoSessionYet =>
      'No session yet — send a message first';

  @override
  String get safetyNumbersRotationFailed =>
      'Could not start a new session. Try again in a moment.';

  @override
  String get safetyNumbersErrorTitle => 'Could not load safety number';

  @override
  String get safetyNumbersErrorBody =>
      'This device could not work out the safety number. Try again in a moment.';

  @override
  String get safetyNumbersRetry => 'Retry';

  @override
  String get safetyNumbersNoMembersTitle => 'No other members';

  @override
  String get safetyNumbersNoMembersBody =>
      'This group has no other participants yet — invite someone to verify.';

  @override
  String get safetyNumbersGroupEyebrow => 'VERIFY GROUP MEMBERS';

  @override
  String get safetyNumbersGroupTitleGeneric =>
      'Verify each member of this group';

  @override
  String safetyNumbersGroupTitleNamed(String groupName) {
    return 'Verify each member of $groupName';
  }

  @override
  String get safetyNumbersGroupBody =>
      'Tap a member to see their 60-digit safety number. Compare it on a channel you trust — read it aloud over a call or scan the QR. A mismatch means that specific member\'s device may be compromised.';

  @override
  String get safetyNumbersUnverified => 'Unverified';

  @override
  String get safetyNumbersVerified => 'Verified';

  @override
  String get safetyNumbersDetailEyebrow => 'VERIFY IDENTITY';

  @override
  String safetyNumbersDetailTitle(String peer) {
    return 'Make sure you\'re talking to $peer';
  }

  @override
  String get safetyNumbersDetailBody =>
      'Both of you should see the same 60-digit number. Compare on a channel you trust — read it aloud over a call, or scan the QR. If the numbers don\'t match, someone is in the middle of your conversation.';

  @override
  String get safetyNumbersKeyChangedTitle => 'Peer identity key changed';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return 'The identity key for this peer is different from the one you verified on $date. This can happen after a reinstall — or if someone is impersonating them. Verify again before trusting.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return 'Verified on $date';
  }

  @override
  String get safetyNumbersVerifiedNote =>
      'If this peer reinstalls or switches devices, this verification is invalidated and you\'ll see a warning.';

  @override
  String get safetyNumbersReVerify => 'Re-verify with new key';

  @override
  String get safetyNumbersMarkVerified => 'Mark as verified';

  @override
  String get safetyNumbersRotateEyebrow => 'NEW SESSION';

  @override
  String get safetyNumbersRotateBody =>
      'Runs a fresh key agreement with your contact\'s current keys; your next message starts the new session, and messages already on their way still open. Use if this device or your contact\'s was briefly exposed.';

  @override
  String get safetyNumbersRotating => 'Starting…';

  @override
  String get safetyNumbersRotateButton => 'Start a new session';

  @override
  String get safetyNumbersCardLabel => 'SAFETY NUMBER';

  @override
  String get safetyNumbersCardLabelCurrent => 'CURRENT SAFETY NUMBER';

  @override
  String get safetyNumbersCardLabelNew => 'NEW SAFETY NUMBER';

  @override
  String get safetyNumbersScanLabel => 'SCAN TO COMPARE';

  @override
  String get safetyNumbersQrNote =>
      'This QR holds both public identity keys and user ids, nothing secret.';

  @override
  String get safetyNumbersNoPinTitle => 'No safety number yet';

  @override
  String get safetyNumbersNoPinBody =>
      'Exchange a message first. This device then pins the identity it talks to, and the number appears here.';

  @override
  String get safetyNumbersDirectoryMismatchTitle =>
      'The key server lists a different key';

  @override
  String get safetyNumbersDirectoryMismatchBody =>
      'The key server now serves another identity key for this device than the one pinned here. Nothing is sent to that key unless you compare and accept it.';

  @override
  String get safetyNumbersDirectoryOtherDeviceTitle =>
      'The key server lists another device';

  @override
  String get safetyNumbersDirectoryOtherDeviceBody =>
      'This conversation encrypts to a different device than the one the key server now lists for this contact. The number above belongs to the device it encrypts to: compare it with your contact before you trust it.';

  @override
  String get safetyNumbersPendingBody =>
      'This contact presents a new identity key. Compare the new safety number below before accepting it.';

  @override
  String get safetyNumbersAcceptNewKey => 'Accept the new key';

  @override
  String get safetyNumbersKeepCurrentKey => 'Keep the current key';

  @override
  String get safetyNumbersScanAction => 'Compare a scanned code';

  @override
  String get safetyNumbersScanFieldLabel => 'Scanned code';

  @override
  String get safetyNumbersScanVerify => 'Compare';

  @override
  String get safetyNumbersScanMismatchTitle => 'The codes do not match';

  @override
  String get safetyNumbersScanMismatchBody =>
      'Someone may be in the middle of this conversation. Do not mark it verified; compare again in person.';

  @override
  String get safetyNumbersScanInvalid => 'That is not a VEIL safety code.';

  @override
  String get safetyNumbersScanUnsupported =>
      'That code uses a safety-number version this app does not support.';

  @override
  String get safetyNumbersReverifyDialogTitle =>
      'Compare the new safety number';

  @override
  String safetyNumbersReverifyDialogBody(String peer) {
    return 'You had verified $peer. Accept the new key as verified only after comparing this number with $peer in person or on a call you trust.';
  }

  @override
  String safetyNumbersReverifyAffirm(String peer) {
    return 'I compared this number with $peer and it matches';
  }

  @override
  String get safetyNumbersReverifyAccept => 'Accept as verified';

  @override
  String get safetyNumbersChangeReplaced =>
      'The safety number changed again while you were reviewing it. Compare the new number before accepting it.';

  @override
  String get safetyNumbersChangedElsewhereTitle => 'Safety number changed';

  @override
  String safetyNumbersChangedElsewhereBody(String peer) {
    return '$peer presented a new identity key in another conversation. Until you review it there, $peer is not shown as verified. The number below is the one this device pinned before the change.';
  }

  @override
  String get safetyNumbersReviewChange => 'Review the new key';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileNicknameSaved => 'Nickname saved on this device';

  @override
  String get profileHandleLabel => 'HANDLE';

  @override
  String get profileHandleCaption => 'Your handle cannot be changed.';

  @override
  String get profileNicknameLabel => 'NICKNAME';

  @override
  String get profileNicknameCaption =>
      'Only this device knows it. Peers see your handle.';

  @override
  String get profileNicknameHint => 'How this device greets you';

  @override
  String get profileNicknameNotSet => 'Not set';

  @override
  String get profilePrivacyEyebrow => 'PRIVACY';

  @override
  String get profilePrivacyTitle => 'Nothing about you on the relay';

  @override
  String get profilePrivacyBody =>
      'The relay routes by handle and stores no name, bio or status. Your nickname stays on this device and is erased with it.';

  @override
  String get profileSaveNickname => 'Save nickname';

  @override
  String get profileEditNickname => 'Edit nickname';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get deviceTransferTitle => 'Device Transfer';

  @override
  String get deviceTransferChipOldDevice => 'Old device';

  @override
  String get deviceTransferChipNewDevice => 'New device';

  @override
  String get deviceTransferNoFallbackTitle => 'No fallback path';

  @override
  String get deviceTransferNoFallbackBody =>
      'If the old device is gone, transfer fails. VEIL does not offer recovery, reset, export, or admin restore.';

  @override
  String get deviceTransferWindowExpiredTitle => 'Transfer window expired';

  @override
  String get deviceTransferClaimExpiredMessage =>
      'This new-device claim expired. Register a fresh claim and request approval again.';

  @override
  String get deviceTransferPayloadCopied => 'Transfer code copied.';

  @override
  String get deviceTransferReturnToConversations => 'Return to conversations';

  @override
  String get deviceTransferPayloadInvalid =>
      'The transfer code\'s format is not valid.';

  @override
  String get deviceTransferImportFirst => 'Use a valid transfer code first.';

  @override
  String get deviceTransferClaimFailed => 'Claim failed.';

  @override
  String get deviceTransferRegisterBeforeComplete =>
      'Register this new-device claim before completion.';

  @override
  String get deviceTransferClaimExpiredRegisterFresh =>
      'This new-device claim has expired. Register a fresh claim first.';

  @override
  String get deviceTransferFinishStartedFirst =>
      'This device already started completing a transfer that the relay may have finished. Complete that transfer on this device before using another code.';

  @override
  String get deviceTransferComplete =>
      'Transfer complete. Your handle is now on this device and the old device has been signed out.';

  @override
  String get deviceTransferFailed => 'Transfer failed.';

  @override
  String get deviceTransferOldRequiredTitle => 'Old device session required';

  @override
  String get deviceTransferOldRequiredBody =>
      'Sign in on a currently trusted device to issue and approve a transfer.';

  @override
  String get deviceTransferOldIssueTitle => 'Issue a transfer code';

  @override
  String get deviceTransferOldIssueBody =>
      'Opens a short-lived transfer session for your new device.';

  @override
  String get deviceTransferOldIssueExpiredBody =>
      'The transfer session expired. Issue a new code.';

  @override
  String get deviceTransferOldHandTitle => 'Give the code to the new device';

  @override
  String get deviceTransferOldHandBody =>
      'The code appears here once it is issued.';

  @override
  String get deviceTransferOldApproveTitle => 'Approve the new device';

  @override
  String get deviceTransferOldApproveBody =>
      'After it registers, the new device shows a claim code. You approve that code here.';

  @override
  String get deviceTransferNewCodeTitle => 'Paste the transfer code';

  @override
  String get deviceTransferNewCodeBody =>
      'Issue the code on your old device, then paste it here.';

  @override
  String get deviceTransferNewCodeChange => 'Change';

  @override
  String get deviceTransferNewRegisterTitle => 'Register this device';

  @override
  String get deviceTransferNewCompleteTitle =>
      'Approve on the old device, then finish';

  @override
  String get deviceTransferNewCompleteBodyUpcoming =>
      'Once registered, this device shows a claim code for the old device to approve.';

  @override
  String get deviceTransferNewCompleteBody =>
      'Enter this claim code on the old device and approve it there.';

  @override
  String get deviceTransferNewCompleteNote =>
      'When you finish, the old device is signed out. Conversation history does not move to this device.';

  @override
  String deviceTransferStep1BodyExpires(String when) {
    return 'This transfer session expires $when.';
  }

  @override
  String get deviceTransferStatusExpired => 'Expired';

  @override
  String get deviceTransferIssuingToken => 'Issuing code';

  @override
  String get deviceTransferIssueToken => 'Issue transfer code';

  @override
  String get deviceTransferClaimFieldCaption =>
      'Approve only the exact claim code shown on the new device you trust.';

  @override
  String get deviceTransferClaimInputLabel => 'New-device claim code';

  @override
  String get deviceTransferClaimInputHint =>
      'Paste the claim code shown on the new device';

  @override
  String get deviceTransferApproveClaim => 'Approve this claim';

  @override
  String get deviceTransferCompleteOnNewNote =>
      'After you approve, finish on the new device. This device is then signed out and its local history is erased. Conversation history does not move to the new device.';

  @override
  String get deviceTransferCopyPayload => 'Copy code';

  @override
  String get deviceTransferClear => 'Clear';

  @override
  String get deviceTransferStatusTitle => 'Transfer status';

  @override
  String get deviceTransferStatusNeedsApi =>
      'This build is not connected to a relay, so it cannot transfer.';

  @override
  String get deviceTransferStatusTokenReady =>
      'Transfer session open. The code is ready.';

  @override
  String get deviceTransferStatusNotStarted => 'Start transfer first.';

  @override
  String get deviceTransferStatusClaimCodeMissing =>
      'Enter the new-device claim code first.';

  @override
  String deviceTransferStatusClaimNotWaiting(String claimId) {
    return 'No claim $claimId is waiting on this transfer.';
  }

  @override
  String deviceTransferStatusClaimApproved(String claimId, String fingerprint) {
    return 'Approved claim $claimId on old device. Key fingerprint: $fingerprint';
  }

  @override
  String get deviceTransferFailedTitle => 'Transfer failed';

  @override
  String get deviceTransferPayloadInputLabel => 'Transfer code';

  @override
  String get deviceTransferImportPayload => 'Use this code';

  @override
  String get deviceTransferNewDeviceCaption =>
      'This device creates its own keys and sends a claim that only the old device can approve. Register before the transfer code expires.';

  @override
  String get deviceTransferDeviceNameLabel => 'Device name';

  @override
  String get deviceTransferClaimExpiredPill => 'Claim expired';

  @override
  String deviceTransferClaimCode(String claimId) {
    return 'Claim code $claimId';
  }

  @override
  String deviceTransferClaimFingerprint(String fingerprint) {
    return 'Claim fingerprint $fingerprint';
  }

  @override
  String get deviceTransferFingerprintUnavailable => 'Unavailable';

  @override
  String deviceTransferExpires(String when) {
    return 'Expires $when';
  }

  @override
  String get deviceTransferRegisteringClaim => 'Registering claim';

  @override
  String get deviceTransferRegisterNewDevice => 'Register this new device';

  @override
  String get deviceTransferCompleting => 'Completing transfer';

  @override
  String get deviceTransferCompleteOnDevice => 'Complete on this device';

  @override
  String get deviceTransferExpiryNow => 'now';

  @override
  String deviceTransferExpiryInSeconds(int seconds) {
    return 'in ${seconds}s';
  }

  @override
  String deviceTransferExpiryInMinutes(int minutes) {
    return 'in ${minutes}m';
  }

  @override
  String deviceTransferExpiryAt(String time) {
    return 'at $time';
  }

  @override
  String get themeModeTitle => 'Theme';

  @override
  String get themeModeSubtitle => 'Choose how VEIL appears on this device.';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeSystem => 'System';

  @override
  String get aiDemoBannerTitle => 'Scripted demo';

  @override
  String get aiDemoBannerBody =>
      'Demo: replies are scripted on this device. Nothing is sent anywhere.';

  @override
  String get securityStatusTitle => 'Security Status';

  @override
  String get securityStatusHeroTitle => 'No backup. No recovery. No leaks.';

  @override
  String get securityStatusHeroBody =>
      'The identity and runtime rows are read from this device and this build. The product rules hold for every VEIL build.';

  @override
  String securityStatusAttentionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need a look',
      one: '1 item needs a look',
    );
    return '$_temp0';
  }

  @override
  String get securityStatusPillPrivateBeta => 'Private beta';

  @override
  String get securityStatusMetricRuntime => 'Runtime';

  @override
  String get securityStatusMetricRelay => 'Relay';

  @override
  String get securityStatusMetricRelayLinked => 'Linked';

  @override
  String get securityStatusMetricCache => 'Cache';

  @override
  String get securityStatusMetricCacheOff => 'Off';

  @override
  String get securityStatusSectionIdentity => 'Identity';

  @override
  String get securityStatusSectionRuntime => 'Runtime';

  @override
  String get securityStatusSectionProductRules => 'Product Rules';

  @override
  String get securityStatusChecking => 'Checking';

  @override
  String get securityStatusAvailable => 'Available';

  @override
  String get securityStatusUnavailable => 'Unavailable';

  @override
  String get securityStatusEnabled => 'Enabled';

  @override
  String get securityStatusDisabled => 'Disabled';

  @override
  String get securityStatusReady => 'Ready';

  @override
  String get securityStatusStarting => 'Starting';

  @override
  String get securityStatusBlocked => 'Blocked';

  @override
  String get securityStatusIdle => 'Idle';

  @override
  String get securityStatusBoundDevice => 'Bound device';

  @override
  String get securityStatusBoundDeviceUnbound => 'Unbound';

  @override
  String get securityStatusBoundDeviceNoneDetail =>
      'No active device session is present.';

  @override
  String get securityStatusBoundDeviceDetail =>
      'This device currently holds the active VEIL session.';

  @override
  String get securityStatusSecretRefs => 'Local secret refs';

  @override
  String get securityStatusSecretRefsPresent => 'Present';

  @override
  String get securityStatusSecretRefsMissing => 'Missing';

  @override
  String get securityStatusSecretRefsDetail =>
      'Private device material stays on the device. The server never receives it.';

  @override
  String get securityStatusPin => 'App lock PIN';

  @override
  String get securityStatusPinConfigured => 'Configured';

  @override
  String get securityStatusPinUnset => 'Unset';

  @override
  String get securityStatusPinDetail =>
      'Local barrier only. VEIL cannot unlock the app for you.';

  @override
  String get securityStatusBiometrics => 'Biometrics';

  @override
  String get securityStatusBiometricsDetail =>
      'Device-level biometric unlock only. No remote fallback exists.';

  @override
  String get securityStatusPrivacyShield => 'Privacy shield';

  @override
  String get securityStatusPrivacyShieldDetail =>
      'When VEIL leaves the foreground, the app obscures previews and re-arms the local barrier.';

  @override
  String get securityStatusAppPreview => 'Recent-app preview';

  @override
  String get securityStatusAppPreviewProtected => 'Protected';

  @override
  String get securityStatusAppPreviewPartial => 'Partial';

  @override
  String get securityStatusAppPreviewDetail =>
      'Native and Flutter privacy shields are used to hide app-switcher content while VEIL is backgrounded.';

  @override
  String get securityStatusScreenCapture => 'Screen capture';

  @override
  String get securityStatusScreenCapturePlatformLimited => 'Platform-limited';

  @override
  String get securityStatusScreenCaptureNotBlocked => 'Not blocked';

  @override
  String get securityStatusScreenCaptureSupportedDetail =>
      'Android blocks screenshots with secure-window flags when enabled.';

  @override
  String get securityStatusScreenCaptureUnsupportedDetail =>
      'This platform has no public API for full screenshot blocking, so VEIL relies on preview shielding and rapid relocking instead.';

  @override
  String get securityStatusScreenCaptureCheckingDetail =>
      'Checking native screen-capture policy.';

  @override
  String get securityStatusClipboard => 'Clipboard hygiene';

  @override
  String get securityStatusClipboardRestricted => 'Restricted';

  @override
  String get securityStatusClipboardDetail =>
      'Sensitive attachment tickets are summarized locally instead of exposing raw signed URLs for copy/share.';

  @override
  String get securityStatusTransport => 'Transport policy';

  @override
  String get securityStatusTransportCompliant => 'Compliant';

  @override
  String get securityStatusTransportDetail =>
      'Configured endpoints satisfy the current private-beta transport policy.';

  @override
  String get securityStatusTlsPins => 'TLS pinning';

  @override
  String get securityStatusTlsPinsPinned => 'Pinned';

  @override
  String get securityStatusTlsPinsUnpinned => 'Not pinned';

  @override
  String securityStatusTlsPinsPinnedDetail(int count) {
    return 'This build pins the relay\'s TLS keys ($count). A certificate whose key matches none of them is refused.';
  }

  @override
  String get securityStatusTlsPinsUnpinnedDetail =>
      'This build sets no TLS pins (VEIL_TLS_PINS), so the relay connection accepts any certificate the platform trusts. Release builds stop at a configuration error without them.';

  @override
  String get securityStatusApiMode => 'API mode';

  @override
  String get securityStatusApiAttached => 'Attached';

  @override
  String get securityStatusApiAttachedDetail =>
      'REST API is configured for this build.';

  @override
  String get securityStatusApiUnavailableDetail =>
      'No API endpoint is configured. Messaging is unavailable.';

  @override
  String get securityStatusRelayLink => 'Relay link';

  @override
  String get securityStatusRelayConnected => 'Connected';

  @override
  String get securityStatusRelayConnectedDetail =>
      'Realtime relay is connected with opaque event payloads.';

  @override
  String get securityStatusRelayIdleDetail =>
      'Realtime relay is disconnected or still syncing.';

  @override
  String get securityStatusLocalCache => 'Local cache';

  @override
  String get securityStatusLocalCacheDisabledDetail =>
      'Local message cache is disabled in this build.';

  @override
  String get securityStatusLocalCacheDetail =>
      'Conversations and envelopes are cached locally behind the current private-beta encrypted-at-rest layer, scrubbed from app-switcher previews, and wiped on destructive local lifecycle events.';

  @override
  String get securityStatusIntegrity => 'Device integrity';

  @override
  String get securityStatusIntegrityCompromised => 'Compromised';

  @override
  String get securityStatusIntegrityClean => 'Clean';

  @override
  String get securityStatusIntegrityCompromisedDetail =>
      'This device matched rooted or jailbroken heuristics. VEIL blocks local unlock in this state.';

  @override
  String securityStatusIntegrityCompromisedReasons(String reasons) {
    return 'This device matched rooted or jailbroken heuristics. $reasons';
  }

  @override
  String get securityStatusIntegrityCleanDetail =>
      'Native rooted and jailbroken heuristics did not trigger on this device.';

  @override
  String get securityStatusIntegrityCheckingDetail =>
      'Checking native integrity heuristics.';

  @override
  String get securityStatusCloudBackup => 'Cloud backup';

  @override
  String get securityStatusCloudBackupDetail =>
      'VEIL does not keep a recovery copy of your message history.';

  @override
  String get securityStatusAccountRecovery => 'Account recovery';

  @override
  String get securityStatusAccountRecoveryDetail =>
      'No recovery email, reset flow, or admin restore path exists.';

  @override
  String get securityStatusDeviceTransfer => 'Device transfer';

  @override
  String get securityStatusDeviceTransferValue => 'Old device required';

  @override
  String get securityStatusDeviceTransferDetail =>
      'Transfer succeeds only while the old device can approve it.';

  @override
  String get securityStatusLocalWipe => 'Local wipe';

  @override
  String get securityStatusLocalWipeDetail =>
      'This device can erase local session state, local secrets, encrypted cache, and the local barrier without creating a recovery path.';

  @override
  String get securityStatusCryptoAdapter => 'Crypto adapter';

  @override
  String get securityStatusCryptoVeilRatchet => 'Production (unaudited)';

  @override
  String securityStatusCryptoVeilRatchetDetail(String adapterId) {
    return 'VEIL\'s own X3DH and Double Ratchet (X25519, AES-256-GCM, Ed25519) is active ($adapterId). An external audit is still pending.';
  }

  @override
  String get securityStatusCryptoLibsignal => 'libsignal bridge (unaudited)';

  @override
  String securityStatusCryptoLibsignalDetail(String adapterId) {
    return 'Sessions and message encryption run in Signal\'s libsignal through VEIL\'s native bridge ($adapterId). The bridge has not been audited.';
  }

  @override
  String get securityStatusCryptoDevelopment => 'Development only';

  @override
  String securityStatusCryptoDevelopmentDetail(String adapterId) {
    return 'This build runs a development adapter ($adapterId), not production cryptography. Do not use it for real conversations.';
  }

  @override
  String get securityStatusPushPlaintext => 'Push plaintext';

  @override
  String get securityStatusPushPlaintextForbidden => 'Forbidden';

  @override
  String get securityStatusPushPlaintextDetail =>
      'Push payloads must never contain plaintext message content.';

  @override
  String get securityStatusPushProvider => 'Push provider';

  @override
  String get securityStatusPushProviderSeam => 'Seam only';

  @override
  String get securityStatusPushProviderSeamDetail =>
      'The metadata-only wake-up path is defined, but a real APNs/FCM provider is not wired in this build.';

  @override
  String get securityStatusPushProviderUnavailableDetail =>
      'No API endpoint is configured, so push delivery is unavailable in this build.';

  @override
  String get securityStatusPushPayloads => 'Push payloads';

  @override
  String get securityStatusPushPayloadsMetadata => 'Metadata only';

  @override
  String get securityStatusPushPayloadsMetadataDetail =>
      'If push is enabled later, wake-up hints must stay metadata-only. Message bodies remain out of push.';

  @override
  String get securityStatusPushPayloadsUnavailableDetail =>
      'No API endpoint is configured, so push payload generation is unavailable in this build.';
}
