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
  String get pillNoRecovery => 'No recovery';

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
      'Recent-app previews are obscured and the app lock is re-armed when the app leaves the foreground.';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockLoadingTitle => 'Checking the app lock';

  @override
  String get appLockLoadingBody =>
      'Looking for a stored PIN and biometric availability.';

  @override
  String get appLockHeroEyebrow => 'THIS DEVICE ONLY';

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
      'If you forget the PIN and lose the active device, VEIL cannot restore access.';

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
      'Set a numeric PIN for this device before continuing. VEIL cannot reset it for you.';

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
  String get privacyConsentTitle => 'Privacy notice';

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
  String get authCreateTitle => 'Create account';

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
      'Only this device knows it. Others find you and see you by your handle.';

  @override
  String get authCreateDisplayName => 'Nickname';

  @override
  String get authCreateDisplayHint => 'Optional';

  @override
  String get authCreateTransferLabel => 'Transfer from old device';

  @override
  String get authHandleTitle => 'Choose handle';

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
  String get authHandleStep3Title => 'Check the device';

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
  String get settingsSectionAppearance => 'APPEARANCE';

  @override
  String get settingsProfileTitle => 'Profile';

  @override
  String get settingsLoadingDeviceGraph => 'Loading devices';

  @override
  String get settingsLoadingDeviceGraphBody =>
      'Reviewing the bound devices known to this account.';

  @override
  String get settingsDeviceGraphUnavailable => 'Device list unavailable';

  @override
  String get settingsNoTrustedDevices => 'No trusted devices visible';

  @override
  String get settingsAppLockTitle => 'App lock';

  @override
  String get settingsAppLockSubtitle =>
      'Biometric and PIN lock on this device only';

  @override
  String get settingsDeviceTransferTitle => 'Device transfer';

  @override
  String get settingsDeviceTransferSubtitle =>
      'Old device must initiate and approve';

  @override
  String get settingsSecurityStatusTitle => 'Security status';

  @override
  String get settingsSecurityStatusSubtitle =>
      'Keys, lock and relay connection on this device';

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
  String get settingsDeleteAccountBody =>
      'Permanently removes your account, messages, and contacts. This cannot be undone.';

  @override
  String get settingsDeleteAccountAction => 'Delete my account';

  @override
  String get settingsDeleteAccountConfirmHeadline => 'Delete your account?';

  @override
  String get settingsDeviceGraphLoadFailedBody =>
      'The list of trusted devices could not be loaded. The security controls of this device still work.';

  @override
  String get settingsNoTrustedDevicesBody =>
      'The relay lists no device for this account yet. What is bound to this device stays on it and cannot be recovered.';

  @override
  String get settingsRefreshDeviceGraph => 'Refresh device list';

  @override
  String get settingsSectionSecurity => 'SECURITY';

  @override
  String get settingsSectionDevices => 'DEVICES';

  @override
  String get settingsSectionTools => 'TOOLS';

  @override
  String get settingsSectionIrreversible => 'CANNOT BE UNDONE';

  @override
  String get settingsDevicesTitle => 'Trusted devices';

  @override
  String settingsDevicesRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices hold this account',
      one: '1 device holds this account',
    );
    return '$_temp0';
  }

  @override
  String settingsDevicesTrustedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trusted devices',
      one: '1 trusted device',
    );
    return '$_temp0';
  }

  @override
  String settingsDevicesTrustedWithStale(int count, int stale) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trusted devices',
      one: '1 trusted device',
    );
    return '$_temp0 ($stale stale)';
  }

  @override
  String get settingsDestructiveNoticeBody =>
      'What you erase here stays erased. VEIL keeps no backup and has no way to restore a device or an account.';

  @override
  String get settingsLockNowSubtitle =>
      'Hide the current session behind the app lock immediately';

  @override
  String get settingsWipeLocalSubtitle =>
      'Deletes the session, keys, encrypted cache, PIN and onboarding state from this device only. The relay is not told.';

  @override
  String get settingsWipeConfirmBody =>
      'This erases local VEIL state on this device. It does not create a recovery path. If this is your only active device, access is gone.';

  @override
  String get settingsWipeConfirmAction => 'Wipe local state';

  @override
  String get settingsRevokeSubtitle =>
      'Revokes this device on the relay and wipes its local state. No recovery exists.';

  @override
  String get settingsRevokeConfirmBody =>
      'This removes the active device binding for this account on this device and wipes local state here. VEIL cannot restore it.';

  @override
  String get settingsRevokeConfirmAction => 'Revoke device';

  @override
  String get settingsLogoutSubtitle =>
      'Erases this device\'s keys, session and messages. You cannot sign back in: the account returns here only by transfer from another trusted device.';

  @override
  String get settingsLogoutConfirmTitle => 'Log out of this device?';

  @override
  String get settingsLogoutConfirmBody =>
      'This erases the keys that make this device yours. VEIL cannot sign you back in. If this is your only trusted device, the account is gone.';

  @override
  String get settingsLogoutConfirmPhrase => 'LOG OUT';

  @override
  String get settingsWipeConfirmPhrase => 'WIPE';

  @override
  String get settingsRevokeConfirmPhrase => 'REVOKE';

  @override
  String get settingsDeleteAccountConfirmPhrase => 'DELETE';

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
    return 'This removes $deviceName from your trusted devices. VEIL will not create a recovery path for that device.';
  }

  @override
  String settingsRevokeListedDone(String deviceName) {
    return '$deviceName is no longer a trusted device.';
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
      'What you send here is encrypted on this device, for the people in this chat only.';

  @override
  String get chatEmptyVerifyAction => 'Compare safety numbers';

  @override
  String get chatLoadFailedTitle => 'Could not load messages';

  @override
  String get chatLoadFailedBody => 'Try again in a moment.';

  @override
  String get chatComposeHint => 'Type a message';

  @override
  String get chatSendAction => 'Send';

  @override
  String get chatAttachAction => 'Attach';

  @override
  String get chatLoadingTitle => 'Loading messages';

  @override
  String get chatLoadingBody =>
      'Fetching the messages sent to this device and decrypting them.';

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
  String get chatGroupUnknownSender => 'Unknown sender';

  @override
  String chatGroupMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String chatTimerTooltip(String value) {
    return 'Disappearing messages: $value';
  }

  @override
  String get chatSearchHint => 'Search this chat';

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
  String get chatSearchSearching => 'Searching this device…';

  @override
  String get chatBannerConversationIssue => 'Conversation issue';

  @override
  String get chatBannerRelayReconnecting => 'Relay reconnecting';

  @override
  String get chatBannerDeliveryStalled => 'Delivery stalled';

  @override
  String get chatBannerQueuedLocally => 'Waiting to be sent';

  @override
  String chatBannerFailedSends(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages were not sent.',
      one: '1 message was not sent.',
    );
    return '$_temp0 Retry once the relay is reachable.';
  }

  @override
  String chatBannerUploadingAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments are',
      one: '1 attachment is',
    );
    return '$_temp0 being uploaded, encrypted, before sending.';
  }

  @override
  String chatBannerQueuedMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages are',
      one: '1 message is',
    );
    return '$_temp0 waiting on this device and will be sent after reconnecting.';
  }

  @override
  String get chatRetryFailedSendsAction => 'Retry failed sends';

  @override
  String get chatLoadOlder => 'Load older';

  @override
  String get chatLoadingOlder => 'Loading older';

  @override
  String get chatSearchEmptyTitle => 'No matches';

  @override
  String get chatSearchEmptyBody =>
      'Nothing in this chat on this device matches. Only messages loaded here are searched.';

  @override
  String get chatTtlSheetTitle => 'Disappearing messages';

  @override
  String get chatTtlOff => 'Off';

  @override
  String get chatTtlOffCaption => 'Messages do not disappear.';

  @override
  String get chatTtl10s => '10 seconds';

  @override
  String get chatTtl10sCaption =>
      'Gone almost at once. For when the other person is looking.';

  @override
  String get chatTtl1m => '1 minute';

  @override
  String get chatTtl5m => '5 minutes';

  @override
  String get chatTtl1h => '1 hour';

  @override
  String get chatTtl1d => '1 day';

  @override
  String get chatTtl1dCaption => 'A good default for everyday chats.';

  @override
  String get chatTtlCustom => 'Custom timer';

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
  String get attachmentPlaceholderNotice =>
      'This version has no file picker. It sends a placeholder file instead: 2 KB of random bytes, encrypted and uploaded the way a chosen file will be.';

  @override
  String attachmentNameCaption(String contentType) {
    return 'The name stays on this device. Its extension sets the type the recipient is shown: $contentType';
  }

  @override
  String get attachmentNameInputLabel => 'File name';

  @override
  String get attachmentSendFailedTitle => 'Attachment send failed';

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
  String get chatDecryptingEnvelope => 'Decrypting…';

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
  String get chatLegacyUnverifiedBadge => 'Sender not verified (old format)';

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
  String get chatIdentityChangedElsewhereTitle =>
      'Safety number changed in another chat';

  @override
  String get chatIdentityChangedElsewhereBody =>
      'They showed a new key in a group you share. Until you review it there, they are not marked as verified.';

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
    return 'Encrypted on this device and ready.$sizeLabel The upload starts once the relay is reachable.';
  }

  @override
  String get chatPhaseDescPreparing =>
      'Getting permission to upload and checking the encrypted file.';

  @override
  String get chatPhaseDescUploading =>
      'Uploading the encrypted file. The relay never sees its contents.';

  @override
  String get chatPhaseDescFinalizing =>
      'Attaching the uploaded file to an encrypted message.';

  @override
  String get chatPhaseDescFailed =>
      'Upload failed. A retry uses the encrypted copy kept on this device.';

  @override
  String get chatPhaseDescCanceled =>
      'Upload stopped on this device. A retry starts over with the encrypted copy kept here.';

  @override
  String chatAttachmentSizeBytes(int count) {
    return ' $count bytes.';
  }

  @override
  String chatTypingSuffix(String handle) {
    return '@$handle is typing…';
  }

  @override
  String get chatTypingUnnamed => 'typing…';

  @override
  String chatReactionSemantics(String emoji, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reactions',
      one: '1 reaction',
    );
    return '$emoji, $_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages are',
      one: '1 message is',
    );
    return '$_temp0 waiting for the relay to come back. $retryLabel';
  }

  @override
  String chatNetworkRecoveryUploading(int count, String retryLabel) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments are',
      one: '1 attachment is',
    );
    return '$_temp0 paused while the relay reconnects. $retryLabel';
  }

  @override
  String chatNetworkRecoveryQueued(int count, String retryLabel) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages stay',
      one: '1 message stays',
    );
    return '$_temp0 queued on this device. $retryLabel';
  }

  @override
  String get chatRetryResumes => 'Sending resumes when the relay reconnects.';

  @override
  String chatRetryNextIn(String countdown) {
    return 'Next try in $countdown.';
  }

  @override
  String chatCountdownSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String chatCountdownMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String chatCountdownMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String chatDurationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String chatDurationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String chatDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String chatDurationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
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
  String get errorSessionRequired =>
      'This device no longer has a trusted VEIL session.';

  @override
  String get errorTransferNeedsApi =>
      'Device transfer is available only while connected to the VEIL API.';

  @override
  String get errorClaimBeforeCompletion =>
      'Register this new device first, then wait for approval from the old device.';

  @override
  String get errorUnexpectedResponse =>
      'The relay returned an unexpected response. Try again.';

  @override
  String get errorUploadFailed =>
      'The encrypted upload failed. Check the connection and try again.';

  @override
  String get errorSessionInvalid =>
      'This session is no longer valid on this device.';

  @override
  String get errorNotAllowed =>
      'This action is not allowed on the current device.';

  @override
  String get errorNotFound => 'The relay could not find what was asked for.';

  @override
  String get errorConflict =>
      'This request conflicts with the current state. Refresh and try again.';

  @override
  String get errorRejected =>
      'The submitted values were rejected. Review them and try again.';

  @override
  String get errorRelayFailed =>
      'The VEIL relay could not complete the request. Try again shortly.';

  @override
  String get errorApiNeedsTls =>
      'The VEIL API endpoint must use TLS outside local development.';

  @override
  String get errorRealtimeNeedsTls =>
      'The VEIL realtime endpoint must use TLS outside local development.';

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
  String get conversationsPreviewEmpty => 'No messages yet';

  @override
  String conversationsQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages waiting to be sent',
      one: '1 message waiting to be sent',
    );
    return '$_temp0';
  }

  @override
  String get conversationsPreviewExpired => 'Message expired';

  @override
  String get conversationsPreviewMessage => 'Encrypted message';

  @override
  String get conversationsPreviewImage => 'Encrypted image';

  @override
  String get conversationsPreviewAttachment => 'Encrypted attachment';

  @override
  String get conversationsPreviewSystem => 'Security notice';

  @override
  String get conversationsPreviewVoice => 'Encrypted voice note';

  @override
  String get conversationsPreviewSticker => 'Encrypted sticker';

  @override
  String get conversationsPreviewReaction => 'Encrypted reaction';

  @override
  String get conversationsPreviewCall => 'Encrypted call event';

  @override
  String get conversationsRelayLinked => 'Relay linked';

  @override
  String get conversationsRelayIdle => 'Relay not connected';

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
  String get conversationsSyncIssueTitle => 'Sync issue';

  @override
  String get conversationsRelayInterruptedBody =>
      'The connection to the relay dropped. Messages waiting to be sent go out once it is back.';

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
  String get conversationsNoneYetTitle => 'No conversations yet';

  @override
  String get conversationsNoMatchBody =>
      'No name or handle on this device matches.';

  @override
  String get conversationsNoneYetBody =>
      'Start one with someone\'s handle. VEIL does not look through your contacts: you find people by the handle they give you.';

  @override
  String get conversationsStartDirect => 'Start direct chat';

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
  String get conversationsNoMessageMatchBody =>
      'No message on this device matches with these filters.';

  @override
  String get conversationsResultFromYou => 'You';

  @override
  String get conversationsResultFromPeer => 'Them';

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
  String get conversationsChoosePaneTitle => 'Select a conversation';

  @override
  String get conversationsChoosePaneBody =>
      'Pick one from the list, or start a new one from the bar above it.';

  @override
  String get conversationsNewTooltip => 'New conversation';

  @override
  String conversationsRowSemantics(String name) {
    return 'Conversation with $name';
  }

  @override
  String conversationsGroupRowSemantics(String names) {
    return 'Group conversation with $names';
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
      'An encrypted message that is gone once opened. The recipient needs no app.';

  @override
  String get oneTimeLinkSecretLabel => 'Secret';

  @override
  String get oneTimeLinkSecretHint =>
      'A password, an account number, a sensitive note…';

  @override
  String get oneTimeLinkUsePassphrase => 'Lock with a passphrase';

  @override
  String get oneTimeLinkUsePassphraseBody =>
      'Keeps the key out of the link. Send the passphrase another way.';

  @override
  String get oneTimeLinkPassphraseLabel => 'Passphrase';

  @override
  String get oneTimeLinkCreate => 'Create link';

  @override
  String get oneTimeLinkCreating => 'Creating…';

  @override
  String get oneTimeLinkFailed =>
      'The link could not be created. Try again in a moment.';

  @override
  String get oneTimeLinkCopy => 'Copy link';

  @override
  String get oneTimeLinkCopied => 'Link copied';

  @override
  String oneTimeLinkExpires(String when) {
    return 'Unopened, the relay deletes it on $when.';
  }

  @override
  String get oneTimeLinkSendPassphraseApart =>
      'Send the passphrase separately from the link.';

  @override
  String get oneTimeLinkProtectsLabel => 'WHAT IT PROTECTS';

  @override
  String get oneTimeLinkProtectsEncrypted =>
      'The secret is encrypted on this device. The relay stores only ciphertext and is never sent the key.';

  @override
  String get oneTimeLinkProtectsBurn =>
      'The relay deletes it the first time it is opened, and when it expires unopened.';

  @override
  String get oneTimeLinkLimitsLabel => 'WHAT IT DOES NOT PROTECT';

  @override
  String get oneTimeLinkLimitHolder =>
      'Whoever gets the whole link first can read it. If the channel is not safe, lock it with a passphrase.';

  @override
  String get oneTimeLinkLimitReader =>
      'The reader can copy or screenshot it. One-time means one opening, not copy protection.';

  @override
  String get oneTimeLinkLimitRelay =>
      'The relay sees when a link is made and opened, its size and the network addresses. It also serves the page that opens the link in the recipient\'s browser, so a link is only as trustworthy as the relay.';

  @override
  String get contactsNotice =>
      'The relay keeps which accounts you added. The names you give them stay on this device.';

  @override
  String get contactsSearchHint => 'Search contacts';

  @override
  String get contactsSearchClear => 'Clear search';

  @override
  String get contactsAdd => 'Add contact';

  @override
  String get contactsWorking => 'Working…';

  @override
  String get contactsErrorTitle => 'Contacts could not be loaded';

  @override
  String get contactsErrorBody => 'The list below is as it was last loaded.';

  @override
  String get contactsEmptyTitle => 'No contacts yet';

  @override
  String get contactsEmptySearchTitle => 'No matches';

  @override
  String get contactsEmptySearchBody =>
      'No name or handle matches your search.';

  @override
  String get contactsEmptyBody =>
      'Add someone by their handle to keep them at hand.';

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
  String get contactsAddFailed =>
      'That handle could not be added. Check the spelling and your connection.';

  @override
  String contactsAdded(String handle) {
    return 'Contact @$handle added';
  }

  @override
  String get contactsStartChat => 'Start chat';

  @override
  String get contactsStartChatFailed => 'Could not start conversation';

  @override
  String get contactsEditNickname => 'Edit nickname';

  @override
  String get contactsSaveNickname => 'Save nickname';

  @override
  String get contactsNicknameCaption =>
      'Only this device knows the nickname. Leave it empty to show the handle.';

  @override
  String get contactsRemove => 'Remove contact';

  @override
  String contactsRemoved(String name) {
    return '$name removed from contacts';
  }

  @override
  String get contactsRemoveFailed => 'Could not remove contact';

  @override
  String contactsRowSemantics(String name) {
    return 'Contact $name';
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
  String get callsUnavailableBody => 'Pull down to try again.';

  @override
  String get callsEmptyTitle => 'No call history';

  @override
  String get callsEmptyBody =>
      'This version cannot place or receive calls, so there is nothing to list yet.';

  @override
  String get callsNotice =>
      'This version cannot place or receive calls. Tap a call to open its chat.';

  @override
  String get callsUnknownCounterparty => 'Unknown';

  @override
  String get callScreenTitle => 'Call';

  @override
  String get callScreenUnavailableTitle =>
      'Calls are not available in this version';

  @override
  String get callScreenUnavailableBody =>
      'Voice and video calls are not built yet. No call was placed, and the other person was not notified.';

  @override
  String get mediaPickerTitle => 'Photos and videos';

  @override
  String get mediaPickerUnavailableTitle =>
      'Photos and videos cannot be sent in this version';

  @override
  String get mediaPickerUnavailableBody =>
      'This version does not read the photo library or use the camera. Nothing was chosen or sent.';

  @override
  String get voiceRecorderTitle => 'Voice message';

  @override
  String get voiceRecorderUnavailableTitle =>
      'Voice messages cannot be recorded in this version';

  @override
  String get voiceRecorderUnavailableBody =>
      'This version does not use the microphone. Nothing was recorded or sent.';

  @override
  String get stickerPickerTitle => 'Emoji';

  @override
  String get stickerPickerTabSmileys => 'Smileys';

  @override
  String get stickerPickerTabGestures => 'Gestures';

  @override
  String get stickerPickerTabSymbols => 'Symbols';

  @override
  String get storiesNotice =>
      'Stories are encrypted, and this version cannot open or post them yet. Nothing is marked as viewed.';

  @override
  String get storiesUnavailableTitle => 'Stories could not be loaded';

  @override
  String get storiesUnavailableBody => 'Pull down to try again.';

  @override
  String get storiesEmptyTitle => 'No stories';

  @override
  String get storiesEmptyBody =>
      'Nobody has shared a story with you in the last 24 hours.';

  @override
  String get storiesUnknownAuthor => 'Unknown';

  @override
  String storiesRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stories',
      one: '1 story',
    );
    return '$_temp0';
  }

  @override
  String get storiesAgeJustNow => 'Just now';

  @override
  String storiesAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String storiesAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get storyViewerUnavailableTitle => 'This story cannot be opened';

  @override
  String get storyViewerUnavailableBody =>
      'Stories are encrypted, and this version cannot open them yet. The story was not marked as viewed.';

  @override
  String get notificationNewMessageTitle => 'VEIL';

  @override
  String get notificationNewMessageBody => 'New encrypted message';

  @override
  String get startDirectTitle => 'New direct chat';

  @override
  String get startDirectInputLabel => 'Handle';

  @override
  String get startDirectErrorTitle => 'Unable to open conversation';

  @override
  String get startDirectErrorBody =>
      'Check the handle and your connection, then try again.';

  @override
  String get startDirectOpening => 'Opening…';

  @override
  String get startDirectOpenButton => 'Open conversation';

  @override
  String get startDirectNoteTitle => 'No contact sync';

  @override
  String get startDirectNote =>
      'VEIL does not read your contacts or phone book, and suggests no one. A conversation opens only when you know the exact handle.';

  @override
  String get startGroupTitle => 'New group';

  @override
  String get startGroupNameInput => 'Group name';

  @override
  String get startGroupNameHint => 'Weekend hiking';

  @override
  String get startGroupDescriptionInput => 'Description (optional)';

  @override
  String get startGroupDescriptionHint => 'What is this group for?';

  @override
  String startGroupMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count handles',
      one: '1 handle',
    );
    return '$_temp0';
  }

  @override
  String get startGroupMembersCaption =>
      'Separate handles with commas or spaces. This version cannot add members later, so list everyone now.';

  @override
  String get startGroupMembersInput => 'Member handles';

  @override
  String get startGroupErrorTitle => 'Unable to create group';

  @override
  String get startGroupErrorBody =>
      'Check the handles and your connection, then try again.';

  @override
  String get startGroupCreating => 'Creating…';

  @override
  String get startGroupCreateButton => 'Create group';

  @override
  String get startGroupNote =>
      'Messages in a group are end-to-end encrypted. Its name, description and member list are not: the relay stores them as you type them here.';

  @override
  String get safetyNumbersTitle => 'Safety number';

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
  String get safetyNumbersKeyChangedTitle =>
      'This contact\'s identity key changed';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return 'This contact\'s identity key is different from the one you verified on $date. This can happen after a reinstall — or if someone is impersonating them. Verify again before trusting.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return 'Verified on $date';
  }

  @override
  String get safetyNumbersVerifiedNote =>
      'If this contact reinstalls or switches devices, this verification is invalidated and you\'ll see a warning.';

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
      'This conversation encrypts to a different device than the one the key server now lists for this contact. The safety number on this page belongs to the device it encrypts to. If your contact changed devices, compare numbers with them again.';

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
  String get profileHandleCaption =>
      'Others find and message you by this handle. It cannot be changed.';

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
  String get profilePrivacyTitle => 'No profile on the relay';

  @override
  String get profilePrivacyBody =>
      'The relay routes by handle and stores no name, bio or status. Your nickname stays on this device and is erased with it.';

  @override
  String get profileSaveNickname => 'Save';

  @override
  String get profileEditNickname => 'Edit nickname';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get deviceTransferTitle => 'Device transfer';

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
  String get deviceTransferCodeExpired =>
      'This transfer code has expired. Issue a new one on the old device.';

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
  String get deviceTransferNewCodeExpiredBody =>
      'The transfer code expired before the transfer was finished. Issue a new code on the old device and paste it here.';

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
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeSystem => 'System';

  @override
  String get aiDemoBannerTitle => 'Prepared answers';

  @override
  String get aiDemoBannerBody =>
      'Demo: replies are scripted on this device. Nothing is sent anywhere.';

  @override
  String get aiTitle => 'VEIL Assistant';

  @override
  String get aiClearTooltip => 'Clear conversation';

  @override
  String get aiIntro =>
      'There is no AI model behind this preview. Pick a question below to see the answer prepared for it.';

  @override
  String get aiQuestionBackup => 'Is there a backup?';

  @override
  String get aiAnswerBackup =>
      'No. VEIL has no backup and no account recovery. Messages are encrypted on this device before they reach the relay.';

  @override
  String get aiQuestionNewDevice => 'How do I move to a new device?';

  @override
  String get aiAnswerNewDevice =>
      'Your old device has to approve the new one. There is no cloud recovery path, by design.';

  @override
  String get aiQuestionGroups => 'Are group messages encrypted?';

  @override
  String get aiAnswerGroups =>
      'Yes. Group messages are encrypted on the sending device before they reach the relay.';

  @override
  String get aiQuestionCalls => 'Can I make calls?';

  @override
  String get aiAnswerCalls =>
      'Not in this version. Voice and video calls are not built yet.';

  @override
  String get securityStatusTitle => 'Security status';

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
  String get securityStatusSectionProductRules => 'Product rules';

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
  String get securityStatusSecretRefs => 'Device secret keys';

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
      'A lock on this device only. VEIL cannot unlock the app for you.';

  @override
  String get securityStatusBiometrics => 'Biometrics';

  @override
  String get securityStatusBiometricsDetail =>
      'Device-level biometric unlock only. No remote fallback exists.';

  @override
  String get securityStatusPrivacyShield => 'Privacy shield';

  @override
  String get securityStatusPrivacyShieldDetail =>
      'When VEIL leaves the foreground, the app obscures previews and re-arms the app lock.';

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
  String get securityStatusApiMode => 'Relay address';

  @override
  String get securityStatusApiAttached => 'Configured';

  @override
  String get securityStatusApiAttachedDetail =>
      'A relay address is configured for this build.';

  @override
  String get securityStatusApiUnavailableDetail =>
      'No relay address is configured. Messaging is unavailable.';

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
      'This device can erase local session state, local secrets, encrypted cache, and the app lock without creating a recovery path.';

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
  String get securityStatusPushProviderSeam => 'Not connected';

  @override
  String get securityStatusPushProviderSeamDetail =>
      'The metadata-only wake-up path is defined, but a real APNs/FCM provider is not wired in this build.';

  @override
  String get securityStatusPushProviderUnavailableDetail =>
      'No relay address is configured, so push delivery is unavailable in this build.';

  @override
  String get securityStatusPushPayloads => 'Push payloads';

  @override
  String get securityStatusPushPayloadsMetadata => 'Metadata only';

  @override
  String get securityStatusPushPayloadsMetadataDetail =>
      'If push is enabled later, wake-up hints must stay metadata-only. Message bodies remain out of push.';

  @override
  String get securityStatusPushPayloadsUnavailableDetail =>
      'No relay address is configured, so push payload generation is unavailable in this build.';
}
