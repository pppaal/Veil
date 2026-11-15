// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Veil';

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
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonNone => 'None';

  @override
  String get pillNoRecovery => 'No recovery';

  @override
  String get pillSessionLocked => 'Locked';

  @override
  String get pillPreviewObscured => 'Preview hidden';

  @override
  String get privacyShieldEyebrow => '';

  @override
  String get privacyShieldTitle => 'Veil';

  @override
  String get privacyShieldBody => '';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockLoadingTitle => 'Checking the app lock';

  @override
  String get appLockLoadingBody => '';

  @override
  String get appLockHeroEyebrow => '';

  @override
  String get appLockHeroTitle => 'Veil is locked';

  @override
  String get appLockHeroBody =>
      'Your PIN and biometrics are checked on this phone only.';

  @override
  String get appLockPillLocalOnly => 'This phone only';

  @override
  String get appLockPillNoRemoteReset => 'No remote reset';

  @override
  String get appLockNoRecoveryBody =>
      'If you forget your PIN, wipe this device and start over.';

  @override
  String get appLockCompromisedTitle => 'Can\'t unlock on this device';

  @override
  String get appLockCompromisedBody =>
      'This device appears to be rooted or jailbroken, so the app won\'t unlock here.';

  @override
  String appLockCompromisedReasons(String reasons) {
    return 'This device appears to be rooted or jailbroken. $reasons';
  }

  @override
  String get appLockLockoutTitle => 'Too many wrong PINs';

  @override
  String appLockLockoutBody(String retry) {
    return 'PIN entry is paused. $retry';
  }

  @override
  String get appLockRetryNow => 'Try again now.';

  @override
  String appLockRetrySeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Try again in $seconds seconds.',
      one: 'Try again in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String appLockRetryMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Try again in $minutes minutes.',
      one: 'Try again in 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String get appLockPinLabel => 'PIN';

  @override
  String get appLockMetricConfigured => 'Set';

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
  String get appLockMetricProtected => 'Hidden';

  @override
  String get appLockMetricShielded => 'Hidden';

  @override
  String get appLockPillPinConfigured => 'PIN set';

  @override
  String get appLockPillPinRequired => 'PIN required';

  @override
  String get appLockPillBiometricsAvailable => 'Biometrics available';

  @override
  String get appLockPillBiometricsUnavailable => 'Biometrics unavailable';

  @override
  String get appLockPillCaptureBlocked => 'Screenshots blocked';

  @override
  String get appLockPillPreviewShield => 'Preview hidden';

  @override
  String get appLockCaptionSet =>
      'Your PIN is checked on this phone only. If you forget it, wipe this device and start over.';

  @override
  String get appLockCaptionUnlock => 'Your PIN is checked on this phone only.';

  @override
  String get appLockFieldSetPin => 'New PIN';

  @override
  String get appLockFieldPinHint => '6 to 12 digits';

  @override
  String get appLockFieldPinError => 'Use 6 to 12 digits.';

  @override
  String get appLockFieldConfirm => 'Confirm PIN';

  @override
  String get appLockFieldConfirmHint => 'Enter it again';

  @override
  String get appLockConfirmMismatch => 'The PINs don\'t match.';

  @override
  String get appLockStatusTitle => 'Lock status';

  @override
  String get appLockStatusUnlockedTitle => 'Unlocked';

  @override
  String get appLockStatusUnlocked => 'Unlocked.';

  @override
  String get appLockStatusBiometricFailed =>
      'Biometrics didn\'t work. Enter your PIN.';

  @override
  String get appLockStatusEnterPin => 'Enter your PIN first.';

  @override
  String get appLockStatusPinFormat => 'The PIN must be 6 to 12 digits.';

  @override
  String get appLockStatusPinMismatch => 'Wrong PIN.';

  @override
  String appLockStatusPinMismatchAttempts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wrong PIN. $count attempts left.',
      one: 'Wrong PIN. 1 attempt left.',
    );
    return '$_temp0';
  }

  @override
  String get appLockStatusLocked => 'Too many attempts. Try again later.';

  @override
  String get appLockStatusCompromised => 'This device can\'t be unlocked.';

  @override
  String get appLockUseBiometrics => 'Use biometrics';

  @override
  String get appLockSetAndUnlock => 'Turn on';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockLockedTitle => 'Veil is locked';

  @override
  String get appLockSetupFooter =>
      'Your PIN is checked on this phone only. If you forget it, wipe this device and start over.';

  @override
  String get appLockTurnOn => 'Turn on';

  @override
  String get splashEyebrow => '';

  @override
  String get splashBody => '';

  @override
  String get splashErrorTitle => 'Couldn\'t start';

  @override
  String get splashPreparingTitle => 'Starting…';

  @override
  String get splashPreparingBody => '';

  @override
  String get onboardingWarnEyebrow => '';

  @override
  String get onboardingWarnTitle => 'Before you start';

  @override
  String get onboardingWarnBody => '';

  @override
  String get onboardingWarnDestructiveTitle => 'No backup';

  @override
  String get onboardingWarnDestructiveBody =>
      'If you lose this phone, you lose this account and its messages. There is no backup and no way to recover it.';

  @override
  String get onboardingWarnIdentityTitle => 'Your account';

  @override
  String get onboardingWarnIdentityLine1 => 'Your account lives on this phone.';

  @override
  String get onboardingWarnIdentityLine2 =>
      'Your private keys stay on this phone.';

  @override
  String get onboardingWarnIdentityLine3 =>
      'There is no password, so there is nothing to reset.';

  @override
  String get onboardingWarnTransferTitle => 'Moving to a new phone';

  @override
  String get onboardingWarnTransferLine1 =>
      'To move to a new phone you need the old one.';

  @override
  String get onboardingWarnTransferLine2 => 'The old phone approves the move.';

  @override
  String get onboardingWarnTransferLine3 =>
      'Your message history stays on the old phone.';

  @override
  String get onboardingWarnAgreeCheckbox =>
      'I understand there is no way to recover a lost account';

  @override
  String get onboardingWarnLine1 => 'Your account lives on this phone.';

  @override
  String get onboardingWarnLine2 =>
      'If you lose this phone, you lose this account and its messages. There is no backup and no way to recover it.';

  @override
  String get onboardingWarnLine3 =>
      'To move to a new phone you need the old one.';

  @override
  String get privacyConsentTitle => 'Privacy notice';

  @override
  String get privacyConsentSubtitle => 'Read this before you continue';

  @override
  String get privacyConsentHeroBody =>
      'What the service stores, why, and for how long, as Korea\'s PIPA requires.';

  @override
  String get privacyConsentAgree =>
      'I agree to the collection and use of personal information as described above. (Required)';

  @override
  String get privacyConsentAccept => 'Agree and continue';

  @override
  String get privacyConsentCollectTitle => 'What we store';

  @override
  String get privacyConsentCollectItem1 =>
      'Your handle, and the random account and device IDs linked to it';

  @override
  String get privacyConsentCollectItem2 =>
      'Device type, device name and push token (notifications carry no message content)';

  @override
  String get privacyConsentCollectItem3 =>
      'Your public keys, used to encrypt messages to you';

  @override
  String get privacyConsentCollectItem4 =>
      'Your in-app contact list: which accounts you added (the names you give them stay on this phone)';

  @override
  String get privacyConsentCollectItem5 =>
      'Chat membership and delivery metadata: when messages arrived, delivery and read-receipt times, the day a device was last seen';

  @override
  String get privacyConsentCollectItem6 =>
      'Call records: which chat, who started the call, call type, start and end time, duration (kept 30 days)';

  @override
  String get privacyConsentCollectItem7 =>
      'Group and channel names and descriptions (stored readable), and the blocks, mutes and abuse reports you make (reports kept 90 days)';

  @override
  String get privacyConsentPurposeTitle => 'Why';

  @override
  String get privacyConsentPurposeItem1 =>
      'Delivering end-to-end encrypted messages';

  @override
  String get privacyConsentPurposeItem2 =>
      'Signing in your device and keeping your session';

  @override
  String get privacyConsentPurposeItem3 =>
      'Finding people by handle and delivering messages to their devices';

  @override
  String get privacyConsentRetentionTitle => 'How long';

  @override
  String get privacyConsentRetentionItem1 =>
      'Deleted as soon as you delete your account';

  @override
  String get privacyConsentRetentionItem2 =>
      'Device data is removed when a device is signed out, and its device record within about 30 days';

  @override
  String get privacyConsentRetentionItem3 =>
      'Expired messages are deleted automatically';

  @override
  String get privacyConsentRightsTitle => 'Your rights';

  @override
  String get privacyConsentRightsItem1 =>
      'You can access, correct and delete your information';

  @override
  String get privacyConsentRightsItem2 =>
      'You can delete everything in Settings with Delete account';

  @override
  String get privacyConsentRightsItem3 =>
      'Withdrawing consent ends your access to the service';

  @override
  String get privacyConsentNotCollectedTitle => 'What we never collect';

  @override
  String get privacyConsentNotCollectedItem1 =>
      'Message contents: they are end-to-end encrypted and the server can\'t read them';

  @override
  String get privacyConsentNotCollectedItem2 => 'Location';

  @override
  String get privacyConsentNotCollectedItem3 =>
      'Your phone\'s address book, its call log or other personal data on your device';

  @override
  String get privacyConsentThirdPartyTitle => 'Third parties';

  @override
  String get privacyConsentThirdPartyBody =>
      'Veil does not share your information with third parties, except where the law requires it.';

  @override
  String get authCreateTitle => 'Create account';

  @override
  String get authCreateEyebrow => '';

  @override
  String get authCreateHeroTitle => '';

  @override
  String get authCreateRestoreTitle => 'Already have an account?';

  @override
  String get authCreateRestoreBody =>
      'You can move it here from your old phone. The old phone approves the move.';

  @override
  String get authCreateFieldLabel => 'Name';

  @override
  String get authCreateFieldCaption =>
      'Shown only on this phone. Others see your handle.';

  @override
  String get authCreateDisplayName => 'Name';

  @override
  String get authCreateDisplayHint => 'Optional';

  @override
  String get authCreateTransferLabel => 'Move from another phone';

  @override
  String get authHandleTitle => 'Choose a handle';

  @override
  String get authHandleEyebrow => '';

  @override
  String get authHandleHeroTitle => '';

  @override
  String get authHandleHeroBody =>
      'People find you by this handle. Veil has no phone number, email or contact upload.';

  @override
  String get authHandleFieldLabel => 'Handle';

  @override
  String get authHandleFieldCaption =>
      'Lowercase letters, digits and underscores. It can\'t be changed later.';

  @override
  String get authHandleFindCaption =>
      'People find you by this handle. Veil has no phone number, email or contact upload.';

  @override
  String get authHandleInputLabel => 'Handle';

  @override
  String get authHandleInputHint => 'alex';

  @override
  String get authHandleBindingSection => 'Creating your account';

  @override
  String get authHandleStep1Title => 'Create your keys';

  @override
  String get authHandleStep1Body =>
      'Keys are created on this phone and stay here.';

  @override
  String get authHandleStep2Title => 'Register the handle';

  @override
  String get authHandleStep2Body =>
      'Only your public keys and handle go to the server.';

  @override
  String get authHandleStep3Title => 'Check this phone';

  @override
  String get authHandleStep3Body =>
      'The server sends a one-time challenge to this phone.';

  @override
  String get authHandleStep4Title => 'Sign in';

  @override
  String get authHandleStep4Body =>
      'This phone answers it and your session starts.';

  @override
  String get authHandleFailedTitle => 'Couldn\'t create the account';

  @override
  String get authHandleBindCta => 'Create account';

  @override
  String get authStageGeneratingKeys => 'Creating keys…';

  @override
  String get authStageRegistering => 'Registering handle…';

  @override
  String get authStageRequestingChallenge => 'Checking this phone…';

  @override
  String get authStageVerifying => 'Signing in…';

  @override
  String get authStageComplete => 'Done';

  @override
  String get authDefaultDeviceName => 'My phone';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsProfileTitle => 'Profile';

  @override
  String get settingsLoadingDeviceGraph => 'Loading devices…';

  @override
  String get settingsLoadingDeviceGraphBody => '';

  @override
  String get settingsDeviceGraphUnavailable => 'Couldn\'t load devices';

  @override
  String get settingsNoTrustedDevices => 'No devices listed';

  @override
  String get settingsAppLockTitle => 'App lock';

  @override
  String get settingsAppLockSubtitle => 'PIN and biometrics';

  @override
  String get settingsDeviceTransferTitle => 'Move to a new phone';

  @override
  String get settingsDeviceTransferSubtitle => 'You need both phones';

  @override
  String get settingsSecurityStatusTitle => 'Security';

  @override
  String get settingsSecurityStatusSubtitle =>
      'Encryption, app lock and connection';

  @override
  String get settingsNoRecoveryPath => 'No recovery';

  @override
  String get settingsSectionPrivacy => 'Privacy';

  @override
  String get settingsReadReceiptsTitle => 'Send read receipts';

  @override
  String get settingsReadReceiptsSubtitle =>
      'When off, people don\'t see when you\'ve read their messages, and you don\'t see when they\'ve read yours.';

  @override
  String get settingsTypingIndicatorsTitle => 'Send typing indicators';

  @override
  String get settingsTypingIndicatorsSubtitle =>
      'Lets people see when you\'re typing. It\'s off until you turn it on.';

  @override
  String get settingsLockNow => 'Lock now';

  @override
  String get settingsWipeLocal => 'Wipe this device';

  @override
  String get settingsWipeConfirmTitle => 'Wipe this device?';

  @override
  String get settingsRevokeTitle => 'Revoke this device';

  @override
  String get settingsRevokeConfirmTitle => 'Revoke this device?';

  @override
  String get settingsLogout => 'Sign out';

  @override
  String get settingsDeleteAccountBody =>
      'This deletes your account, messages and contacts from this phone and the server. There is no backup, so this can\'t be undone.';

  @override
  String get settingsDeleteAccountAction => 'Delete account';

  @override
  String get settingsDeleteAccountConfirmHeadline => 'Delete your account?';

  @override
  String get settingsDeviceGraphLoadFailedBody =>
      'Couldn\'t load your devices. Check your connection and try again.';

  @override
  String get settingsNoTrustedDevicesBody =>
      'The server lists no devices for this account yet.';

  @override
  String get settingsRefreshDeviceGraph => 'Refresh';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsSectionDevices => 'Devices';

  @override
  String get settingsSectionTools => 'Tools';

  @override
  String get settingsSectionIrreversible => 'Account';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsDevicesTitle => 'Devices';

  @override
  String settingsDevicesRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices',
      one: '1 device',
    );
    return '$_temp0';
  }

  @override
  String settingsDevicesTrustedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices',
      one: '1 device',
    );
    return '$_temp0';
  }

  @override
  String settingsDevicesTrustedWithStale(int count, int stale) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices',
      one: '1 device',
    );
    return '$_temp0 ($stale stale)';
  }

  @override
  String get settingsDestructiveNoticeBody =>
      'There is no backup, no password reset and no way for anyone, including us, to recover an account.';

  @override
  String get settingsLockNowSubtitle => 'Lock the app right away';

  @override
  String get settingsWipeLocalSubtitle =>
      'Deletes your messages, keys, PIN and settings from this phone. The server is not told.';

  @override
  String get settingsWipeConfirmBody =>
      'This deletes your messages, keys, PIN and settings from this phone. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.';

  @override
  String get settingsWipeConfirmAction => 'Wipe';

  @override
  String get settingsRevokeSubtitle =>
      'Signs this device out on the server and wipes it.';

  @override
  String get settingsRevokeConfirmBody =>
      'This signs this device out on the server and wipes it. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.';

  @override
  String get settingsRevokeConfirmAction => 'Revoke';

  @override
  String get settingsLogoutSubtitle =>
      'Erases your keys and messages on this phone. To use the account here again, move it from another phone.';

  @override
  String get settingsLogoutConfirmTitle => 'Sign out of this phone?';

  @override
  String get settingsLogoutConfirmBody =>
      'This erases your keys and messages on this phone. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.';

  @override
  String get settingsLogoutConfirmPhrase => 'Sign out';

  @override
  String get settingsWipeConfirmPhrase => 'Wipe';

  @override
  String get settingsRevokeConfirmPhrase => 'Revoke';

  @override
  String get settingsDeleteAccountConfirmPhrase => 'Delete';

  @override
  String settingsTypePhraseToContinue(String phrase) {
    return 'Type \"$phrase\" to continue.';
  }

  @override
  String settingsRevokeListedTitle(String deviceName) {
    return 'Revoke $deviceName?';
  }

  @override
  String settingsRevokeListedBody(String deviceName) {
    return '$deviceName will be signed out and can no longer use this account.';
  }

  @override
  String settingsRevokeListedDone(String deviceName) {
    return '$deviceName was revoked.';
  }

  @override
  String get settingsRevokeListedFailed =>
      'Couldn\'t revoke the device. Try again.';

  @override
  String get settingsDeviceStateCurrent => 'This device';

  @override
  String get settingsDeviceStatePreferred => 'Preferred';

  @override
  String get settingsDeviceStateTrusted => 'Active';

  @override
  String get settingsDeviceStateStale => 'Stale';

  @override
  String get settingsDeviceStateRevoked => 'Revoked';

  @override
  String get settingsDeviceRevokeAction => 'Revoke';

  @override
  String settingsDeviceCreated(String when) {
    return 'Added $when';
  }

  @override
  String settingsDeviceSeen(String when) {
    return 'Last seen $when';
  }

  @override
  String settingsDeviceSynced(String when) {
    return 'Last synced $when';
  }

  @override
  String settingsDeviceActivity(String when) {
    return 'Last active $when';
  }

  @override
  String settingsDeviceTrustedAt(String when) {
    return 'Approved $when';
  }

  @override
  String settingsDeviceJoinedFrom(String device) {
    return 'Approved by $device';
  }

  @override
  String settingsDeviceRevokedAt(String when) {
    return 'Revoked $when';
  }

  @override
  String get settingsDeviceNoteCurrent => 'This is the phone you\'re using.';

  @override
  String get settingsDeviceNotePreferred => 'Messages go to this device first.';

  @override
  String get settingsDeviceNoteTrusted =>
      'This device can still use the account.';

  @override
  String get settingsDeviceNoteStale =>
      'Not seen for 30 days. Revoke it if you no longer use it.';

  @override
  String get settingsDeviceNoteRevoked =>
      'This device was signed out and can\'t use the account.';

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
    return 'Last activity $when';
  }

  @override
  String get settingsGraphPreferredDiffersTitle =>
      'Another device is preferred';

  @override
  String settingsGraphPreferredDiffersBody(String preferred, String current) {
    return 'Messages go to $preferred first. $current can still use the account.';
  }

  @override
  String get settingsGraphStaleTitle =>
      'A device hasn\'t been seen for 30 days';

  @override
  String get settingsGraphStaleBody =>
      'Stale devices can still use this account. Revoke the ones you no longer use.';

  @override
  String get chatEmptyTitle => 'No messages yet';

  @override
  String get chatEmptyBody => 'Messages are end-to-end encrypted.';

  @override
  String get chatEmptyEncrypted => 'Messages are end-to-end encrypted.';

  @override
  String get chatEmptyVerifyAction => 'Compare safety numbers';

  @override
  String get chatLoadFailedTitle => 'Couldn\'t load messages';

  @override
  String get chatLoadFailedBody => 'Try again in a moment.';

  @override
  String get chatComposeHint => 'Message';

  @override
  String get chatSendAction => 'Send';

  @override
  String get chatAttachAction => 'Attach';

  @override
  String get chatLoadingTitle => 'Loading messages…';

  @override
  String get chatLoadingBody => '';

  @override
  String get chatConversationNotFound => 'Chat not found';

  @override
  String get chatRelockTitle => 'Locked';

  @override
  String get chatRelockBody => 'Unlock the app to continue.';

  @override
  String get chatTitleFallback => 'Chat';

  @override
  String get chatSubtitleOnline => 'Online';

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
    return 'Disappearing: $value';
  }

  @override
  String get chatSearchHint => 'Search this chat';

  @override
  String get chatSearchClearTooltip => 'Clear search';

  @override
  String get chatSearchTooltip => 'Search';

  @override
  String chatSearchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
      zero: 'No matches',
    );
    return '$_temp0';
  }

  @override
  String get chatSearchSearching => 'Searching…';

  @override
  String get chatBannerConversationIssue => 'Something went wrong';

  @override
  String get chatBannerRelayReconnecting => 'Connecting…';

  @override
  String get chatBannerDeliveryStalled => 'Couldn\'t send';

  @override
  String get chatBannerQueuedLocally => 'Sending…';

  @override
  String chatBannerFailedSends(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages weren\'t sent.',
      one: '1 message wasn\'t sent.',
    );
    return '$_temp0';
  }

  @override
  String chatBannerUploadingAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments are',
      one: '1 attachment is',
    );
    return '$_temp0 being encrypted and uploaded.';
  }

  @override
  String chatBannerQueuedMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages are',
      one: '1 message is',
    );
    return '$_temp0 waiting to be sent.';
  }

  @override
  String get chatRetryFailedSendsAction => 'Retry now';

  @override
  String get chatLoadOlder => 'Load older messages';

  @override
  String get chatLoadingOlder => 'Loading older messages…';

  @override
  String get chatSearchEmptyTitle => 'No messages found';

  @override
  String get chatSearchEmptyBody => 'Only messages on this phone are searched.';

  @override
  String get chatTtlSheetTitle => 'Disappearing messages';

  @override
  String get chatTtlOff => 'Off';

  @override
  String get chatTtlOffCaption => 'Messages don\'t disappear.';

  @override
  String get chatTtl10s => '10 seconds';

  @override
  String get chatTtl10sCaption => 'Gone 10 seconds after it\'s sent.';

  @override
  String get chatTtl1m => '1 minute';

  @override
  String get chatTtl5m => '5 minutes';

  @override
  String get chatTtl1h => '1 hour';

  @override
  String get chatTtl1d => '1 day';

  @override
  String get chatTtl1dCaption => 'Gone a day after it\'s sent.';

  @override
  String get chatTtlCustom => 'Custom';

  @override
  String get chatTtlDisabledLabel => 'Off';

  @override
  String get chatAttachmentTicketTitle => 'File not downloaded';

  @override
  String chatAttachmentTicketBody(String summary) {
    return 'The server would send this file, but this version can\'t download or open it yet.\n\n$summary';
  }

  @override
  String get chatAttachmentTicketFailed => 'Couldn\'t request the download';

  @override
  String get chatAttachmentResolveAction => 'Request download';

  @override
  String get chatAttachmentResolvingAction => 'Requesting…';

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
  String get chatAttachmentStateBanner => 'Attachment';

  @override
  String get chatAttachmentCannotOpen =>
      'This version can\'t open attachments.';

  @override
  String get reactionsMoreTooltip => 'More reactions';

  @override
  String get chatScreenshotToast =>
      'You took a screenshot. Screenshots can\'t be blocked on this phone, so a notice is being sent to the other person.';

  @override
  String get chatScreenshotSystemNotice =>
      'Someone in this chat took a screenshot.';

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
      'Held back: the sender\'s safety number changed';

  @override
  String get chatLegacyUnverifiedBadge =>
      'Sent from an older version; not verified';

  @override
  String get chatLegacySenderLine => 'Sent from an older version; not verified';

  @override
  String get chatNotSentTapToRetry => 'Not sent. Tap to retry.';

  @override
  String get chatNoticeIdentityChanged =>
      'A contact\'s safety number changed. Review it before trusting it again.';

  @override
  String get chatNoticeIdentityNewDevice =>
      'This contact started using a new device.';

  @override
  String get chatNoticeSenderKeysKept =>
      'The server listed this group without its keys. This phone keeps using the ones it has.';

  @override
  String get chatNoticeGroupMemberAdded =>
      'Someone was added to this group. They can read messages sent from now on. Check the members in Safety number.';

  @override
  String get chatNoticeGroupMemberRemoved =>
      'Someone left this group or was removed from it.';

  @override
  String get chatIdentityChangedTitle => 'Safety number changed';

  @override
  String get chatIdentityChangedBody => 'Nothing is sent until you review it.';

  @override
  String get chatIdentityChangedReview => 'Review';

  @override
  String get chatIdentityChangedElsewhereTitle =>
      'Safety number changed in another chat';

  @override
  String get chatIdentityChangedElsewhereBody =>
      'Their safety number changed in a group you share. Until you review it there, they aren\'t shown as verified.';

  @override
  String get chatAccountHoldOtherTitle => 'A different account';

  @override
  String chatAccountHoldOtherBody(String handle) {
    return 'This chat is listed as @$handle, but it isn\'t the account you talked to as @$handle before. Nothing is sent or opened here until you confirm you want to talk to this account.';
  }

  @override
  String get chatAccountHoldUnissuedTitle =>
      'A name the server never gives out';

  @override
  String get chatAccountHoldUnissuedBody =>
      'This chat is listed under a name no server issues, so it may only look like someone you know. Nothing is sent or opened here until you confirm you want to talk to this account.';

  @override
  String get chatAccountHoldOwnTitle => 'Another account under your name';

  @override
  String chatAccountHoldOwnBody(String handle) {
    return 'This chat is listed under your own name, @$handle, but with another account. No one else can have your name, so the list this phone received was altered, perhaps to pass someone off as you. Nothing is sent or opened here until you confirm you want to talk to this account.';
  }

  @override
  String chatAccountHoldOwnConfirmTitle(String handle) {
    return 'Talk to this other @$handle?';
  }

  @override
  String get chatAccountHoldOwnConfirmBody =>
      'No other account can have your name, yet the server showed this one under it. Continue only if you confirmed another way, in person or on a call, whose account this is.';

  @override
  String get chatAccountHoldAcknowledge => 'Talk to this account';

  @override
  String get chatPeerVerified => 'Verified';

  @override
  String get chatRetrySend => 'Retry';

  @override
  String get chatRetryUpload => 'Retry upload';

  @override
  String get chatCancelAction => 'Cancel';

  @override
  String get chatDeliveryQueued => 'Waiting';

  @override
  String get chatDeliveryUploading => 'Uploading';

  @override
  String get chatDeliveryFailed => 'Not sent';

  @override
  String get chatDeliverySent => 'Sent';

  @override
  String get chatDeliveryDelivered => 'Delivered';

  @override
  String get chatDeliveryRead => 'Read';

  @override
  String get chatPhaseStaged => 'Ready';

  @override
  String get chatPhasePreparing => 'Preparing';

  @override
  String get chatPhaseUploading => 'Uploading';

  @override
  String get chatPhaseFinalizing => 'Finishing';

  @override
  String get chatPhaseFailed => 'Not sent';

  @override
  String get chatPhaseCanceled => 'Canceled';

  @override
  String chatPhaseDescStaged(String sizeLabel) {
    return 'Encrypted and ready.$sizeLabel It uploads when you\'re online.';
  }

  @override
  String get chatPhaseDescPreparing => 'Preparing the upload.';

  @override
  String get chatPhaseDescUploading => 'Uploading the encrypted file.';

  @override
  String get chatPhaseDescFinalizing => 'Attaching the file to the message.';

  @override
  String get chatPhaseDescFailed => 'The upload failed.';

  @override
  String get chatPhaseDescCanceled => 'The upload was canceled.';

  @override
  String chatAttachmentSizeBytes(int count) {
    return ' $count bytes.';
  }

  @override
  String chatTypingSuffix(String handle) {
    return '@$handle is typing…';
  }

  @override
  String get chatTypingUnnamed => 'Typing…';

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
      other: '$count messages weren\'t sent.',
      one: '1 message wasn\'t sent.',
    );
    return '$_temp0 $retryLabel';
  }

  @override
  String chatNetworkRecoveryUploading(int count, String retryLabel) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments are waiting.',
      one: '1 attachment is waiting.',
    );
    return '$_temp0 $retryLabel';
  }

  @override
  String chatNetworkRecoveryQueued(int count, String retryLabel) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages are waiting.',
      one: '1 message is waiting.',
    );
    return '$_temp0 $retryLabel';
  }

  @override
  String get chatRetryResumes => 'They\'ll be sent when you\'re back online.';

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
  String get errorSessionRequired => 'This phone is signed out.';

  @override
  String get errorTransferNeedsApi =>
      'Moving to a new phone needs a server connection.';

  @override
  String get errorClaimBeforeCompletion =>
      'Register this phone first, then approve it on the old one.';

  @override
  String get errorUnexpectedResponse =>
      'The server sent an unexpected response. Try again.';

  @override
  String get errorUploadFailed =>
      'The upload failed. Check your connection and try again.';

  @override
  String get errorSessionInvalid =>
      'This session is no longer valid on this phone.';

  @override
  String get errorNotAllowed => 'This isn\'t allowed on this phone.';

  @override
  String get errorNotFound => 'The server couldn\'t find that.';

  @override
  String get errorConflict =>
      'This conflicts with the current state. Refresh and try again.';

  @override
  String get errorRejected =>
      'The server didn\'t accept this. Check what you entered and try again.';

  @override
  String get errorRelayFailed =>
      'The server could not complete the request. Try again shortly.';

  @override
  String get errorApiNeedsTls =>
      'The server address must use TLS outside local development.';

  @override
  String get errorRealtimeNeedsTls =>
      'The realtime address must use TLS outside local development.';

  @override
  String get conversationsEmptyTitle => 'No chats yet';

  @override
  String get conversationsEmptyBody => 'Start a chat with someone\'s handle.';

  @override
  String get conversationsSearchHint => 'Search';

  @override
  String get conversationsNewChat => 'New chat';

  @override
  String get conversationsNewGroup => 'New group';

  @override
  String get conversationsArchiveSection => 'Older messages';

  @override
  String get conversationsLoadingArchive => 'Searching…';

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
  String get conversationsPreviewImage => 'Photo';

  @override
  String get conversationsPreviewAttachment => 'File';

  @override
  String get conversationsPreviewSystem => 'Security notice';

  @override
  String get conversationsPreviewVoice => 'Voice message';

  @override
  String get conversationsPreviewSticker => 'Sticker';

  @override
  String get conversationsPreviewReaction => 'Reaction';

  @override
  String get conversationsPreviewCall => 'Call';

  @override
  String get conversationsRelayLinked => 'Connected';

  @override
  String get conversationsRelayIdle => 'Not connected';

  @override
  String conversationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats',
      one: '1 chat',
    );
    return '$_temp0';
  }

  @override
  String get conversationsNoBackup => 'No backup';

  @override
  String get conversationsBarConnecting => 'Connecting…';

  @override
  String get conversationsBarOffline => 'Offline';

  @override
  String get conversationsSyncIssueTitle => 'Couldn\'t refresh';

  @override
  String get conversationsRelayInterruptedBody =>
      'Messages waiting to be sent go out once you\'re back online.';

  @override
  String get conversationsSearchHintCompact => 'Search';

  @override
  String get conversationsSearchLocalNote =>
      'Only messages on this phone are searched.';

  @override
  String get conversationsFilterAllSenders => 'All senders';

  @override
  String get conversationsFilterMine => 'From me';

  @override
  String get conversationsFilterTheirs => 'From them';

  @override
  String get conversationsFilterAllTypes => 'All types';

  @override
  String get conversationsFilterText => 'Text';

  @override
  String get conversationsFilterMedia => 'Media';

  @override
  String get conversationsFilterAnyDate => 'Any date';

  @override
  String get conversationsFilterLast7Days => 'Last 7 days';

  @override
  String get conversationsFilterLast30Days => 'Last 30 days';

  @override
  String get conversationsSectionLabel => 'Chats';

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
  String get conversationsNoMatchTitle => 'No matching chats';

  @override
  String get conversationsNoneYetTitle => 'No chats yet';

  @override
  String get conversationsNoMatchBody => 'No name or handle matches.';

  @override
  String get conversationsNoneYetBody => 'Start a chat with someone\'s handle.';

  @override
  String get conversationsStartDirect => 'New chat';

  @override
  String get conversationsMessagesSection => 'Messages';

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
      'No message matches these filters.';

  @override
  String get conversationsResultFromYou => 'You';

  @override
  String get conversationsResultFromPeer => 'Them';

  @override
  String get conversationsKindImage => 'Photo';

  @override
  String get conversationsKindAttachment => 'File';

  @override
  String get conversationsKindSystem => 'Notice';

  @override
  String get conversationsKindVoice => 'Voice message';

  @override
  String get conversationsKindSticker => 'Sticker';

  @override
  String get conversationsKindReaction => 'Reaction';

  @override
  String get conversationsKindCall => 'Call';

  @override
  String get conversationsLoadingMore => 'Loading more…';

  @override
  String get conversationsLoadMore => 'Load more';

  @override
  String get conversationsChoosePaneTitle => 'Select a chat';

  @override
  String get conversationsChoosePaneBody =>
      'Pick one from the list or start a new one.';

  @override
  String get conversationsNewTooltip => 'New chat';

  @override
  String conversationsRowSemantics(String name) {
    return 'Chat with $name';
  }

  @override
  String conversationsGroupRowSemantics(String names) {
    return 'Group chat with $names';
  }

  @override
  String get conversationsGroupMark => 'Group';

  @override
  String get navChats => 'Chats';

  @override
  String get navContacts => 'Contacts';

  @override
  String get navSettings => 'Settings';

  @override
  String get oneTimeLinkTitle => 'One-time link';

  @override
  String get oneTimeLinkSettingsSubtitle =>
      'Send a secret that can be opened once. The other person doesn\'t need the app.';

  @override
  String get oneTimeLinkSecretLabel => 'Secret';

  @override
  String get oneTimeLinkSecretHint => 'A password, an account number, a note';

  @override
  String get oneTimeLinkUsePassphrase => 'Protect with a passphrase';

  @override
  String get oneTimeLinkUsePassphraseBody =>
      'The key stays out of the link. Send the passphrase another way.';

  @override
  String get oneTimeLinkPassphraseLabel => 'Passphrase';

  @override
  String get oneTimeLinkCreate => 'Create link';

  @override
  String get oneTimeLinkCreating => 'Creating…';

  @override
  String get oneTimeLinkFailed =>
      'Couldn\'t create the link. Try again in a moment.';

  @override
  String get oneTimeLinkCopy => 'Copy link';

  @override
  String get oneTimeLinkCopied => 'Link copied';

  @override
  String oneTimeLinkExpires(String when) {
    return 'If it isn\'t opened, it\'s deleted on $when.';
  }

  @override
  String get oneTimeLinkSendPassphraseApart =>
      'Send the passphrase separately from the link.';

  @override
  String get oneTimeLinkProtectsLabel => 'What it protects';

  @override
  String get oneTimeLinkProtectsEncrypted =>
      'The secret is encrypted on this phone. The server stores only the encrypted text and never gets the key.';

  @override
  String get oneTimeLinkProtectsBurn =>
      'The server deletes it the first time it\'s opened, or when it expires unopened.';

  @override
  String get oneTimeLinkLimitsLabel => 'What it doesn\'t protect';

  @override
  String get oneTimeLinkLimitHolder =>
      'Whoever opens the whole link first can read it. If the channel isn\'t safe, add a passphrase.';

  @override
  String get oneTimeLinkLimitReader =>
      'The person who opens it can copy it or take a screenshot. One-time means it opens once, not that it can\'t be copied.';

  @override
  String get oneTimeLinkLimitRelay =>
      'The server sees when a link is made and opened, its size and the network addresses. It also serves the page that opens the link, so a link is only as trustworthy as the server.';

  @override
  String get oneTimeLinkFooter =>
      'The link opens once, then it\'s gone. The server can\'t read it.';

  @override
  String get contactsNotice =>
      'The server knows which accounts you added. The nicknames you give them stay on this phone.';

  @override
  String get contactsSearchHint => 'Search';

  @override
  String get contactsSearchClear => 'Clear search';

  @override
  String get contactsAdd => 'Add contact';

  @override
  String get contactsWorking => 'Saving…';

  @override
  String get contactsErrorTitle => 'Couldn\'t load contacts';

  @override
  String get contactsErrorBody => 'Showing the last list that loaded.';

  @override
  String get contactsEmptyTitle => 'No contacts yet';

  @override
  String get contactsEmptySearchTitle => 'No matches';

  @override
  String get contactsEmptySearchBody => 'No name or handle matches.';

  @override
  String get contactsEmptyBody => 'Add someone by their handle.';

  @override
  String get contactsAddSheetBody =>
      'Enter their handle exactly as they gave it to you.';

  @override
  String get contactsHandleLabel => 'Handle';

  @override
  String get contactsNicknameLabel => 'Nickname (optional)';

  @override
  String get contactsNicknameHint => 'Only you see this';

  @override
  String get contactsSave => 'Add';

  @override
  String get contactsAddFailed =>
      'Couldn\'t add that handle. Check the spelling and your connection.';

  @override
  String contactsAdded(String handle) {
    return '@$handle added';
  }

  @override
  String get contactsStartChat => 'Start chat';

  @override
  String get contactsStartChatFailed => 'Couldn\'t start the chat';

  @override
  String get contactsEditNickname => 'Edit nickname';

  @override
  String get contactsSaveNickname => 'Save';

  @override
  String get contactsNicknameCaption =>
      'Only you see the nickname. Leave it empty to show the handle.';

  @override
  String get contactsRemove => 'Remove contact';

  @override
  String contactsRemoved(String name) {
    return '$name removed';
  }

  @override
  String get contactsRemoveFailed => 'Couldn\'t remove the contact';

  @override
  String contactsRowSemantics(String name) {
    return 'Contact $name';
  }

  @override
  String get contactsVerifiedStatus => 'Verified';

  @override
  String get notificationNewMessageTitle => 'Veil';

  @override
  String get notificationNewMessageBody => 'New message';

  @override
  String get startDirectTitle => 'New chat';

  @override
  String get startDirectInputLabel => 'Handle';

  @override
  String get startDirectErrorTitle => 'Couldn\'t start the chat';

  @override
  String get startDirectErrorBody =>
      'Check the handle and your connection, then try again.';

  @override
  String get startDirectOpening => 'Opening…';

  @override
  String get startDirectOpenButton => 'Start chat';

  @override
  String get startDirectNoteTitle => '';

  @override
  String get startDirectNote =>
      'Enter their handle exactly as they gave it to you.';

  @override
  String get startDirectFieldCaption =>
      'Enter their handle exactly as they gave it to you.';

  @override
  String get startGroupTitle => 'New group';

  @override
  String get startGroupNameInput => 'Group name';

  @override
  String get startGroupNameHint => 'Weekend plans';

  @override
  String get startGroupDescriptionInput => 'Description (optional)';

  @override
  String get startGroupDescriptionHint => 'What it\'s for';

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
      'Handles, separated by commas. Members can\'t be added later, so list everyone now.';

  @override
  String get startGroupMembersInput => 'Members';

  @override
  String get startGroupErrorTitle => 'Couldn\'t create the group';

  @override
  String get startGroupErrorBody =>
      'Check the handles and your connection, then try again.';

  @override
  String get startGroupCreating => 'Creating…';

  @override
  String get startGroupCreateButton => 'Create group';

  @override
  String get startGroupNote =>
      'The server can read the group name, description and member list.';

  @override
  String get safetyNumbersTitle => 'Safety number';

  @override
  String get safetyNumbersLoadingTitle => 'Working out the safety number…';

  @override
  String get safetyNumbersLoadingBody => '';

  @override
  String get safetyNumbersMarkedVerified => 'Marked as verified';

  @override
  String get safetyNumbersRotateDialogTitle => 'Start a new session?';

  @override
  String get safetyNumbersRotateDialogBody =>
      'This sets up new keys with your contact. Your next message uses them, and messages already on their way still open. Do this if you think your phone or theirs was briefly in someone else\'s hands: anyone who copied the old keys can\'t read new messages.';

  @override
  String get safetyNumbersCancel => 'Cancel';

  @override
  String get safetyNumbersRotate => 'Start';

  @override
  String get safetyNumbersSessionRotated =>
      'New session ready. Your next message starts it.';

  @override
  String get safetyNumbersNoSessionYet =>
      'No session yet. Send a message first.';

  @override
  String get safetyNumbersRotationFailed =>
      'Couldn\'t start a new session. Try again in a moment.';

  @override
  String get safetyNumbersErrorTitle => 'Couldn\'t load the safety number';

  @override
  String get safetyNumbersErrorBody => 'Try again in a moment.';

  @override
  String get safetyNumbersRetry => 'Retry';

  @override
  String get safetyNumbersNoMembersTitle => 'No other members';

  @override
  String get safetyNumbersNoMembersBody => 'Nobody else is in this group yet.';

  @override
  String get safetyNumbersGroupEyebrow => '';

  @override
  String get safetyNumbersGroupTitleGeneric => 'Verify each member';

  @override
  String safetyNumbersGroupTitleNamed(String groupName) {
    return 'Verify each member of $groupName';
  }

  @override
  String get safetyNumbersGroupBody =>
      'Tap a member to see their 60-digit safety number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you and that member.';

  @override
  String get safetyNumbersUnverified => 'Not verified';

  @override
  String get safetyNumbersVerified => 'Verified';

  @override
  String get safetyNumbersDetailEyebrow => '';

  @override
  String safetyNumbersDetailTitle(String peer) {
    return 'Make sure you\'re talking to $peer';
  }

  @override
  String get safetyNumbersDetailBody =>
      'Both of you should see the same 60-digit number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you.';

  @override
  String get safetyNumbersKeyChangedTitle => 'Safety number changed';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return 'It\'s different from the one you verified on $date. This happens after a reinstall or a new phone, or if someone is pretending to be them. Compare the new number before trusting it.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return 'Verified on $date';
  }

  @override
  String get safetyNumbersVerifiedNote =>
      'If they reinstall or change phones, you\'ll be asked to verify again.';

  @override
  String get safetyNumbersReVerify => 'Verify the new number';

  @override
  String get safetyNumbersMarkVerified => 'Mark as verified';

  @override
  String get safetyNumbersRotateEyebrow => '';

  @override
  String get safetyNumbersRotateBody =>
      'Sets up new keys with your contact. Your next message uses them, and messages already on their way still open. Do this if your phone or theirs was briefly in someone else\'s hands.';

  @override
  String get safetyNumbersRotating => 'Starting…';

  @override
  String get safetyNumbersRotateButton => 'Start a new session';

  @override
  String get safetyNumbersCardLabel => 'Safety number';

  @override
  String get safetyNumbersCardLabelCurrent => 'Current safety number';

  @override
  String get safetyNumbersCardLabelNew => 'New safety number';

  @override
  String get safetyNumbersNewNumberHeader => 'New safety number';

  @override
  String get safetyNumbersScanLabel => 'Scan to compare';

  @override
  String get safetyNumbersQrNote =>
      'The code holds both public keys and account IDs, nothing secret.';

  @override
  String get safetyNumbersNoPinTitle => 'No safety number yet';

  @override
  String get safetyNumbersNoPinBody =>
      'Exchange a message first. The number appears here once this phone knows which keys it\'s talking to.';

  @override
  String get safetyNumbersDirectoryMismatchTitle =>
      'The server lists a different key';

  @override
  String get safetyNumbersDirectoryMismatchBody =>
      'The server now gives a different key for this contact than the one this phone knows. Nothing is sent to that key unless you compare and accept it.';

  @override
  String get safetyNumbersDirectoryOtherDeviceTitle =>
      'The server lists another device';

  @override
  String get safetyNumbersDirectoryOtherDeviceBody =>
      'This chat encrypts to a different device than the one the server now lists for this contact. The safety number here belongs to the device it encrypts to. If your contact changed phones, compare numbers with them again.';

  @override
  String get safetyNumbersPendingBody =>
      'Your contact\'s keys changed. Compare the new safety number below before accepting it.';

  @override
  String get safetyNumbersAcceptNewKey => 'Accept new number';

  @override
  String get safetyNumbersKeepCurrentKey => 'Keep the old one';

  @override
  String get safetyNumbersScanAction => 'Compare a scanned code';

  @override
  String get safetyNumbersScanTheirCode => 'Scan their code';

  @override
  String get safetyNumbersScanFieldLabel => 'Their code';

  @override
  String get safetyNumbersScanVerify => 'Compare';

  @override
  String get safetyNumbersScanMismatchTitle => 'The codes don\'t match';

  @override
  String get safetyNumbersScanMismatchBody =>
      'Someone may be between you. Don\'t mark it verified until you have compared again in person.';

  @override
  String get safetyNumbersScanInvalid => 'That isn\'t a safety code.';

  @override
  String get safetyNumbersScanUnsupported =>
      'That code is from a version this app doesn\'t support.';

  @override
  String get safetyNumbersReverifyDialogTitle =>
      'Compare the new safety number';

  @override
  String safetyNumbersReverifyDialogBody(String peer) {
    return 'You had verified $peer. Accept the new number only after comparing it with $peer in person or on a call you trust.';
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
    return '$peer\'s safety number changed in another chat. Until you review it there, $peer isn\'t shown as verified. The number below is the one this phone knew before the change.';
  }

  @override
  String get safetyNumbersReviewChange => 'Review the new number';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileNicknameSaved => 'Nickname saved';

  @override
  String get profileHandleLabel => 'Handle';

  @override
  String get profileHandleCaption => 'Your handle can\'t be changed.';

  @override
  String get profileNicknameLabel => 'Nickname';

  @override
  String get profileNicknameCaption => 'Only you see it.';

  @override
  String get profileNicknameHint => 'Optional';

  @override
  String get profileNicknameNotSet => 'Not set';

  @override
  String get profilePrivacyTitle => 'No profile on the server';

  @override
  String get profilePrivacyBody =>
      'The server stores no name or profile. Your nickname stays on this phone and is erased with it.';

  @override
  String get profileSaveNickname => 'Save';

  @override
  String get profileEditNickname => 'Edit nickname';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get profileNicknameFooter =>
      'Only you see nicknames. Your handle can\'t be changed.';

  @override
  String get deviceTransferTitle => 'Move to a new phone';

  @override
  String get deviceTransferChipOldDevice => 'Old phone';

  @override
  String get deviceTransferChipNewDevice => 'New phone';

  @override
  String get deviceTransferNoFallbackTitle => 'Both phones are needed';

  @override
  String get deviceTransferNoFallbackBody =>
      'You need the old phone. If it is gone, the account is gone.';

  @override
  String get deviceTransferOldPhoneNeeded =>
      'You need the old phone. If it is gone, the account is gone.';

  @override
  String get deviceTransferPayloadCopied => 'Transfer code copied.';

  @override
  String get deviceTransferReturnToConversations => 'Back to chats';

  @override
  String get deviceTransferPayloadInvalid =>
      'That isn\'t a valid transfer code.';

  @override
  String get deviceTransferImportFirst => 'Enter a valid transfer code first.';

  @override
  String get deviceTransferClaimFailed => 'Couldn\'t register this phone.';

  @override
  String get deviceTransferRegisterBeforeComplete =>
      'Register this phone before finishing.';

  @override
  String get deviceTransferCodeExpired =>
      'This transfer code has expired. Get a new one from the old phone.';

  @override
  String get deviceTransferFinishStartedFirst =>
      'This phone already started finishing a transfer that the server may have completed. Finish that one before using another code.';

  @override
  String get deviceTransferComplete =>
      'Done. Your account is now on this phone and the old phone is signed out.';

  @override
  String get deviceTransferFailed => 'Transfer failed.';

  @override
  String get deviceTransferOldRequiredTitle => 'Sign in on the old phone';

  @override
  String get deviceTransferOldRequiredBody =>
      'Only a phone that has the account can start and approve a move.';

  @override
  String get deviceTransferOldIssueTitle => 'Get a transfer code';

  @override
  String get deviceTransferOldIssueBody => 'The code works for a short time.';

  @override
  String get deviceTransferOldIssueExpiredBody =>
      'The code expired. Get a new one.';

  @override
  String get deviceTransferOldHandTitle => 'Enter the code on the new phone';

  @override
  String get deviceTransferOldHandBody =>
      'The code shows here once you get it.';

  @override
  String get deviceTransferOldApproveTitle => 'Approve the new phone';

  @override
  String get deviceTransferOldApproveBody =>
      'The new phone shows a code once it registers. Enter it here to approve.';

  @override
  String get deviceTransferNewCodeTitle => 'Enter the transfer code';

  @override
  String get deviceTransferNewCodeBody => 'Get it from your old phone.';

  @override
  String get deviceTransferNewCodeExpiredBody =>
      'The transfer code expired before the move finished. Get a new one from the old phone.';

  @override
  String get deviceTransferNewCodeChange => 'Change';

  @override
  String get deviceTransferNewRegisterTitle => 'Register this phone';

  @override
  String get deviceTransferNewCompleteTitle =>
      'Approve on the old phone, then finish';

  @override
  String get deviceTransferNewCompleteBodyUpcoming =>
      'Once registered, this phone shows a code for the old phone to approve.';

  @override
  String get deviceTransferNewCompleteBody =>
      'Enter this code on the old phone and approve it there.';

  @override
  String get deviceTransferNewCompleteNote =>
      'When you finish, the old phone is signed out. Your message history does not move.';

  @override
  String deviceTransferStep1BodyExpires(String when) {
    return 'This code expires $when.';
  }

  @override
  String get deviceTransferStatusExpired => 'Expired';

  @override
  String get deviceTransferIssuingToken => 'Getting a code…';

  @override
  String get deviceTransferIssueToken => 'Get code';

  @override
  String get deviceTransferClaimFieldCaption =>
      'Approve only the code shown on the new phone you trust.';

  @override
  String get deviceTransferClaimInputLabel => 'Code from the new phone';

  @override
  String get deviceTransferClaimInputHint => 'Shown on the new phone';

  @override
  String get deviceTransferApproveClaim => 'Approve';

  @override
  String get deviceTransferCompleteOnNewNote =>
      'After you approve, finish on the new phone. This phone is then signed out and its history is erased. Your message history does not move to the new phone.';

  @override
  String get deviceTransferCopyPayload => 'Copy';

  @override
  String get deviceTransferClear => 'Clear';

  @override
  String get deviceTransferStatusTitle => 'Status';

  @override
  String get deviceTransferStatusNeedsApi =>
      'No server is configured, so nothing can be moved.';

  @override
  String get deviceTransferStatusTokenReady => 'The code is ready.';

  @override
  String get deviceTransferStatusNotStarted => 'Get a transfer code first.';

  @override
  String get deviceTransferStatusClaimCodeMissing =>
      'Enter the code from the new phone first.';

  @override
  String deviceTransferStatusClaimNotWaiting(String claimId) {
    return 'No phone with code $claimId is waiting.';
  }

  @override
  String deviceTransferStatusClaimApproved(String claimId, String fingerprint) {
    return 'Approved code $claimId. Key fingerprint: $fingerprint';
  }

  @override
  String get deviceTransferFailedTitle => 'Couldn\'t move the account';

  @override
  String get deviceTransferPayloadInputLabel => 'Transfer code';

  @override
  String get deviceTransferImportPayload => 'Use this code';

  @override
  String get deviceTransferNewDeviceCaption =>
      'This phone creates its own keys and asks the old phone to approve them. Register before the code expires.';

  @override
  String get deviceTransferDeviceNameLabel => 'Device name';

  @override
  String deviceTransferClaimCode(String claimId) {
    return 'Code $claimId';
  }

  @override
  String deviceTransferClaimFingerprint(String fingerprint) {
    return 'Key fingerprint $fingerprint';
  }

  @override
  String get deviceTransferFingerprintUnavailable => 'Unavailable';

  @override
  String deviceTransferExpires(String when) {
    return 'Expires $when';
  }

  @override
  String get deviceTransferRegisteringClaim => 'Registering…';

  @override
  String get deviceTransferRegisterNewDevice => 'Register';

  @override
  String get deviceTransferCompleting => 'Finishing…';

  @override
  String get deviceTransferCompleteOnDevice => 'Finish';

  @override
  String get deviceTransferExpiryNow => 'now';

  @override
  String deviceTransferExpiryInSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'in $seconds seconds',
      one: 'in 1 second',
    );
    return '$_temp0';
  }

  @override
  String deviceTransferExpiryInMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'in $minutes minutes',
      one: 'in 1 minute',
    );
    return '$_temp0';
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
  String get securityStatusTitle => 'Security';

  @override
  String get securityStatusHeroTitle => 'How this phone is protected';

  @override
  String get securityStatusHeroBody =>
      'These rows are read from this phone and this version of the app.';

  @override
  String securityStatusAttentionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need attention',
      one: '1 item needs attention',
    );
    return '$_temp0';
  }

  @override
  String get securityStatusPillPrivateBeta => '';

  @override
  String get securityStatusMetricRuntime => 'Runtime';

  @override
  String get securityStatusMetricRelay => 'Server';

  @override
  String get securityStatusMetricRelayLinked => 'Connected';

  @override
  String get securityStatusMetricCache => 'Cache';

  @override
  String get securityStatusMetricCacheOff => 'Off';

  @override
  String get securityStatusSectionIdentity => 'This phone';

  @override
  String get securityStatusSectionRuntime => 'Connection';

  @override
  String get securityStatusSectionProductRules => 'Rules';

  @override
  String get securityGroupThisPhone => 'This phone';

  @override
  String get securityGroupConnection => 'Connection';

  @override
  String get securityGroupEncryption => 'Encryption';

  @override
  String get securityGroupRules => 'Rules';

  @override
  String get securityFooterEncryption =>
      'Messages are end-to-end encrypted. Keys exist only on your devices.';

  @override
  String get securityFooterNoRecovery =>
      'There is no backup, no password reset and no way for anyone, including us, to recover an account.';

  @override
  String get securityStatusChecking => 'Checking…';

  @override
  String get securityStatusAvailable => 'Available';

  @override
  String get securityStatusUnavailable => 'Unavailable';

  @override
  String get securityStatusEnabled => 'On';

  @override
  String get securityStatusDisabled => 'Off';

  @override
  String get securityStatusReady => 'Ready';

  @override
  String get securityStatusStarting => 'Starting…';

  @override
  String get securityStatusBlocked => 'Blocked';

  @override
  String get securityStatusIdle => 'Not connected';

  @override
  String get securityStatusBoundDevice => 'Account';

  @override
  String get securityStatusBoundDeviceUnbound => 'Signed out';

  @override
  String get securityStatusBoundDeviceNoneDetail =>
      'This phone is not signed in.';

  @override
  String get securityStatusBoundDeviceDetail => 'Signed in on this phone.';

  @override
  String get securityStatusSecretRefs => 'Keys';

  @override
  String get securityStatusSecretRefsPresent => 'On this phone';

  @override
  String get securityStatusSecretRefsMissing => 'Missing';

  @override
  String get securityStatusSecretRefsDetail => 'Stored on this phone only.';

  @override
  String get securityStatusPin => 'App lock';

  @override
  String get securityStatusPinConfigured => 'On';

  @override
  String get securityStatusPinUnset => 'Off';

  @override
  String get securityStatusPinDetail => 'Checked on this phone only.';

  @override
  String get securityStatusBiometrics => 'Biometrics';

  @override
  String get securityStatusBiometricsDetail =>
      'Uses the phone\'s own biometrics.';

  @override
  String get securityStatusPrivacyShield => 'Lock when leaving the app';

  @override
  String get securityStatusPrivacyShieldDetail =>
      'The app locks again and hides its preview when you switch away.';

  @override
  String get securityStatusAppPreview => 'App switcher preview';

  @override
  String get securityStatusAppPreviewProtected => 'Hidden';

  @override
  String get securityStatusAppPreviewPartial => 'Partial';

  @override
  String get securityStatusAppPreviewDetail =>
      'What the app switcher shows while the app is in the background.';

  @override
  String get securityStatusScreenCapture => 'Screenshots';

  @override
  String get securityStatusScreenCapturePlatformLimited => 'Limited';

  @override
  String get securityStatusScreenCaptureNotBlocked => 'Not blocked';

  @override
  String get securityStatusScreenCaptureSupportedDetail =>
      'Android blocks screenshots of the app.';

  @override
  String get securityStatusScreenCaptureUnsupportedDetail =>
      'This platform has no way to block screenshots, so the app hides its preview and locks quickly instead.';

  @override
  String get securityStatusScreenCaptureCheckingDetail => 'Checking…';

  @override
  String get securityStatusClipboard => 'Clipboard';

  @override
  String get securityStatusClipboardRestricted => 'Restricted';

  @override
  String get securityStatusClipboardDetail =>
      'Download links for attachments are never shown, so they can\'t be copied.';

  @override
  String get securityStatusTransport => 'Connection policy';

  @override
  String get securityStatusTransportCompliant => 'OK';

  @override
  String get securityStatusTransportDetail =>
      'The configured addresses use TLS.';

  @override
  String get securityStatusTlsPins => 'TLS pinning';

  @override
  String get securityStatusTlsPinsPinned => 'Pinned';

  @override
  String get securityStatusTlsPinsUnpinned => 'Not pinned';

  @override
  String securityStatusTlsPinsPinnedDetail(int count) {
    return 'This build pins the server\'s TLS keys ($count). A certificate that matches none of them is refused.';
  }

  @override
  String get securityStatusTlsPinsUnpinnedDetail =>
      'This build sets no TLS pins (VEIL_TLS_PINS), so the connection accepts any certificate the phone trusts. Release builds stop with a configuration error without them.';

  @override
  String get securityStatusApiMode => 'Server';

  @override
  String get securityStatusApiAttached => 'Configured';

  @override
  String get securityStatusApiAttachedDetail =>
      'A server address is configured.';

  @override
  String get securityStatusApiUnavailableDetail =>
      'No server address is configured. Messaging is unavailable.';

  @override
  String get securityStatusRelayLink => 'Connection';

  @override
  String get securityStatusRelayConnected => 'Connected';

  @override
  String get securityStatusRelayConnectedDetail =>
      'Messages arrive as they\'re sent.';

  @override
  String get securityStatusRelayIdleDetail => 'Not connected or still syncing.';

  @override
  String get securityStatusLocalCache => 'Messages on this phone';

  @override
  String get securityStatusLocalCacheDisabledDetail =>
      'No messages are stored on this phone in this build.';

  @override
  String get securityStatusLocalCacheDetail =>
      'Stored encrypted on this phone, hidden from the app switcher, and deleted when you wipe this device.';

  @override
  String get securityStatusIntegrity => 'Device integrity';

  @override
  String get securityStatusIntegrityCompromised => 'Compromised';

  @override
  String get securityStatusIntegrityClean => 'OK';

  @override
  String get securityStatusIntegrityCompromisedDetail =>
      'This device looks rooted or jailbroken, so the app won\'t unlock here.';

  @override
  String securityStatusIntegrityCompromisedReasons(String reasons) {
    return 'This device looks rooted or jailbroken. $reasons';
  }

  @override
  String get securityStatusIntegrityCleanDetail =>
      'No signs of rooting or jailbreaking.';

  @override
  String get securityStatusIntegrityCheckingDetail => 'Checking…';

  @override
  String get securityStatusCloudBackup => 'Backup';

  @override
  String get securityStatusCloudBackupDetail => 'None';

  @override
  String get securityStatusAccountRecovery => 'Account recovery';

  @override
  String get securityStatusAccountRecoveryDetail => 'None';

  @override
  String get securityStatusDeviceTransfer => 'Transfer';

  @override
  String get securityStatusDeviceTransferValue => 'Old phone required';

  @override
  String get securityStatusDeviceTransferDetail =>
      'The old phone has to approve it.';

  @override
  String get securityStatusLocalWipe => 'Wipe';

  @override
  String get securityStatusLocalWipeDetail =>
      'Erases the messages, keys and app lock on this phone.';

  @override
  String get securityStatusCryptoAdapter => 'Encryption';

  @override
  String get securityStatusCryptoVeilRatchet => 'Production (unaudited)';

  @override
  String securityStatusCryptoVeilRatchetDetail(String adapterId) {
    return 'X3DH and Double Ratchet over X25519, AES-256-GCM and Ed25519 ($adapterId). Not yet externally audited.';
  }

  @override
  String get securityStatusCryptoLibsignal => 'libsignal bridge (unaudited)';

  @override
  String securityStatusCryptoLibsignalDetail(String adapterId) {
    return 'Sessions and messages are encrypted by Signal\'s libsignal through a native bridge ($adapterId). The bridge has not been audited.';
  }

  @override
  String get securityStatusCryptoDevelopment => 'Development only';

  @override
  String securityStatusCryptoDevelopmentDetail(String adapterId) {
    return 'This build runs a development adapter ($adapterId), not production cryptography. Don\'t use it for real chats.';
  }

  @override
  String get securityStatusPushPlaintext => 'Message text in notifications';

  @override
  String get securityStatusPushPlaintextForbidden => 'None';

  @override
  String get securityStatusPushPlaintextDetail =>
      'Notifications never carry message text.';

  @override
  String get securityStatusPushProvider => 'Push notifications';

  @override
  String get securityStatusPushProviderSeam => 'Not connected';

  @override
  String get securityStatusPushProviderSeamDetail =>
      'Not connected to a push service in this build.';

  @override
  String get securityStatusPushProviderUnavailableDetail =>
      'No server address is configured, so there are no push notifications.';

  @override
  String get securityStatusPushPayloads => 'Notification content';

  @override
  String get securityStatusPushPayloadsMetadata => 'Metadata only';

  @override
  String get securityStatusPushPayloadsMetadataDetail =>
      'A notification only says that something arrived.';

  @override
  String get securityStatusPushPayloadsUnavailableDetail =>
      'No server address is configured, so there are no push notifications.';
}
