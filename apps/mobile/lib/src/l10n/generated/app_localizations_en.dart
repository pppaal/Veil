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
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonNone => 'None';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockCompromisedBody =>
      'This phone looks rooted or jailbroken, so the app won\'t unlock here.';

  @override
  String appLockCompromisedReasons(String reasons) {
    return 'This phone looks rooted or jailbroken. $reasons';
  }

  @override
  String appLockLockoutBody(String retry) {
    return 'Too many tries. $retry';
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
      other: 'Wrong PIN. $count tries left.',
      one: 'Wrong PIN. 1 try left.',
    );
    return '$_temp0';
  }

  @override
  String get appLockStatusLocked => 'Too many tries. Try again later.';

  @override
  String get appLockStatusCompromised => 'This phone can\'t be unlocked.';

  @override
  String get appLockUseBiometrics => 'Use biometrics';

  @override
  String get appLockUseFaceId => 'Use Face ID';

  @override
  String get appLockUseTouchId => 'Use Touch ID';

  @override
  String get appLockUseFingerprint => 'Use fingerprint';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockLockedTitle => 'Veil is locked';

  @override
  String get appLockSetupFooter =>
      'If you forget your PIN, there\'s no way to reset it.';

  @override
  String get appLockTurnOn => 'Turn on';

  @override
  String get splashErrorTitle => 'Couldn\'t start';

  @override
  String get onboardingWarnTitle => 'Before you start';

  @override
  String get onboardingWarnAgreeCheckbox =>
      'I understand a lost account can\'t be recovered';

  @override
  String get onboardingWarnLine1 => 'Your account lives on this phone.';

  @override
  String get onboardingWarnLine2 =>
      'If you lose the phone, your account and messages are gone for good.';

  @override
  String get onboardingWarnLine3 =>
      'To move to a new phone later, you\'ll need this one.';

  @override
  String get privacyConsentTitle => 'Privacy notice';

  @override
  String get privacyConsentAgree =>
      'I agree to the collection and use of my personal information as described above (required)';

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
  String get authCreateTransferLabel => 'Move from another phone';

  @override
  String get authHandleTitle => 'Choose a handle';

  @override
  String get authHandleFindCaption => 'You can\'t change it later.';

  @override
  String get authHandleInputLabel => 'Handle';

  @override
  String get authHandleInputHint => 'alex';

  @override
  String get authHandleBindCta => 'Create account';

  @override
  String get authHandleInvalid =>
      'Use 3 to 32 lowercase letters, numbers, dots or underscores.';

  @override
  String get authCreating => 'Creating account…';

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
  String get settingsDeviceGraphUnavailable => 'Couldn\'t load devices';

  @override
  String get settingsNoTrustedDevices => 'No devices listed';

  @override
  String get settingsAppLockTitle => 'App lock';

  @override
  String get settingsDeviceTransferTitle => 'Move to a new phone';

  @override
  String get settingsSectionPrivacy => 'Privacy';

  @override
  String get settingsReadReceiptsTitle => 'Send read receipts';

  @override
  String get settingsTypingIndicatorsTitle => 'Send typing indicators';

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
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsDevicesTitle => 'Devices';

  @override
  String get settingsWipeConfirmBody =>
      'This deletes your messages, keys, PIN and settings from this phone. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.';

  @override
  String get settingsWipeConfirmAction => 'Wipe';

  @override
  String get settingsRevokeConfirmBody =>
      'This signs this device out on the server and wipes it. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.';

  @override
  String get settingsRevokeConfirmAction => 'Revoke';

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
  String settingsDeviceJoinedFrom(String device) {
    return 'Approved by $device';
  }

  @override
  String settingsDeviceRevokedAt(String when) {
    return 'Revoked $when';
  }

  @override
  String get settingsDeviceNotePreferred => 'Messages go to this device first.';

  @override
  String get settingsDeviceNoteStale =>
      'Not seen for 30 days. Revoke it if you no longer use it.';

  @override
  String get settingsSecurityDetailsTitle => 'Security details';

  @override
  String get settingsReadReceiptsCaption =>
      'When off, neither of you sees when messages are read.';

  @override
  String get settingsTypingIndicatorsCaption =>
      'Lets people see when you\'re typing.';

  @override
  String settingsDevicesStaleNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices haven\'t been seen for 30 days.',
      one: 'A device hasn\'t been seen for 30 days.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDevicesReview => 'Review';

  @override
  String get chatEmptyTitle => 'No messages yet';

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
  String get chatBannerRelayReconnecting => 'Connecting…';

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
  String get chatTtlSheetFooter => 'The timer starts when a message is sent.';

  @override
  String get chatTtlOff => 'Off';

  @override
  String get chatTtl10s => '10 seconds';

  @override
  String get chatTtl1m => '1 minute';

  @override
  String get chatTtl5m => '5 minutes';

  @override
  String get chatTtl1h => '1 hour';

  @override
  String get chatTtl1d => '1 day';

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
  String get chatAttachmentStateBanner => 'Attachment';

  @override
  String get chatAttachmentCannotOpen =>
      'This version can\'t open attachments.';

  @override
  String get chatAttachmentKindPhoto => 'Photo';

  @override
  String get chatAttachmentKindVideo => 'Video';

  @override
  String get chatAttachmentKindAudio => 'Audio';

  @override
  String get chatAttachmentKindDocument => 'Document';

  @override
  String get chatAttachmentKindFile => 'File';

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
  String get chatLegacySenderLine => 'Sent from an older version; not verified';

  @override
  String get chatNotSentTapToRetry => 'Not sent. Tap to retry.';

  @override
  String get chatDayToday => 'Today';

  @override
  String get chatDayYesterday => 'Yesterday';

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
  String get errorRelayFailed => 'The server couldn\'t complete the request.';

  @override
  String get errorApiNeedsTls =>
      'The server address must use TLS outside local development.';

  @override
  String get errorRealtimeNeedsTls =>
      'The realtime address must use TLS outside local development.';

  @override
  String get errorNetworkTimeout => 'The server took too long to answer.';

  @override
  String get errorNetworkUnavailable =>
      'Can\'t reach the server. Check your connection.';

  @override
  String get errorTlsPinMismatch =>
      'The server\'s certificate isn\'t the one this app trusts.';

  @override
  String get errorChallengeInvalid => 'The sign-in request expired. Try again.';

  @override
  String get errorDeviceNotActive =>
      'This phone was removed from this account.';

  @override
  String get errorDeviceSignatureInvalid =>
      'The server couldn\'t verify this phone.';

  @override
  String get errorHandleTaken => 'That handle is taken. Try another.';

  @override
  String get errorTransferInactive =>
      'This transfer has ended. Start a new one on the old phone.';

  @override
  String get errorTransferCodeInvalid => 'This transfer code isn\'t valid.';

  @override
  String get errorTransferClaimRequired =>
      'Enter the transfer code on the new phone first.';

  @override
  String get errorTransferApprovalRequired =>
      'The old phone hasn\'t approved this phone yet.';

  @override
  String get errorTransferCompletionInvalid =>
      'This phone couldn\'t finish the transfer. Start again on the old phone.';

  @override
  String get errorAttachmentCanceled => 'The upload was canceled.';

  @override
  String get errorAttachmentRejected =>
      'This file couldn\'t be sent. Attach it again.';

  @override
  String get errorPeerUnreachable => 'Messages can\'t be sent to this account.';

  @override
  String get conversationsNewChat => 'New chat';

  @override
  String get conversationsNewGroup => 'New group';

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
  String conversationsNotSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages weren\'t sent',
      one: '1 message wasn\'t sent',
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
  String get conversationsBarConnecting => 'Connecting…';

  @override
  String get conversationsBarOffline => 'Offline';

  @override
  String conversationsUnreadSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread messages',
      one: '1 unread message',
    );
    return '$_temp0';
  }

  @override
  String get conversationsSyncIssueTitle => 'Couldn\'t refresh';

  @override
  String get conversationsSearchHintCompact => 'Search';

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
  String get oneTimeLinkSecretLabel => 'Secret';

  @override
  String get oneTimeLinkSecretHint => 'A password, an account number, a note';

  @override
  String get oneTimeLinkUsePassphrase => 'Protect with a passphrase';

  @override
  String get oneTimeLinkUsePassphraseCaption =>
      'The secret can\'t be read without it.';

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
  String get contactsHandleHint => 'alex';

  @override
  String get startDirectTitle => 'New chat';

  @override
  String get startDirectInputLabel => 'Handle';

  @override
  String get startDirectOpening => 'Opening…';

  @override
  String get startDirectOpenButton => 'Start chat';

  @override
  String get startDirectFieldCaption =>
      'Enter their handle exactly as they gave it to you.';

  @override
  String get startDirectHandleHint => 'alex';

  @override
  String get startDirectHandleError =>
      'Couldn\'t start the chat. Check the handle and your connection.';

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
  String get startGroupCreating => 'Creating…';

  @override
  String get startGroupCreateButton => 'Create group';

  @override
  String get startGroupNote =>
      'The server can read the group name, description and member list.';

  @override
  String get startGroupNameRequired => 'Required';

  @override
  String get startGroupMembersHint => 'alex, sam, priya';

  @override
  String get startGroupMembersError =>
      'Couldn\'t create the group. Check the handles and your connection.';

  @override
  String get safetyNumbersTitle => 'Safety number';

  @override
  String get safetyNumbersLoadingTitle => 'Working out the safety number…';

  @override
  String get safetyNumbersMarkedVerified => 'Marked as verified';

  @override
  String get safetyNumbersRotateDialogTitle => 'Renew the keys?';

  @override
  String get safetyNumbersRotateDialogBody =>
      'Your next message uses new keys, and messages already on their way still open. Do this if you think your phone or theirs was briefly in someone else\'s hands: anyone who copied the old keys can\'t read new messages.';

  @override
  String get safetyNumbersCancel => 'Cancel';

  @override
  String get safetyNumbersRotate => 'Renew';

  @override
  String get safetyNumbersSessionRotated =>
      'New keys ready. Your next message uses them.';

  @override
  String get safetyNumbersNoSessionYet =>
      'There are no keys to renew yet. Send a message first.';

  @override
  String get safetyNumbersRotationFailed =>
      'Couldn\'t renew the keys. Try again in a moment.';

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
  String get safetyNumbersGroupBody =>
      'Tap a member to see their 60-digit safety number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you and that member.';

  @override
  String get safetyNumbersUnverified => 'Not verified';

  @override
  String get safetyNumbersVerified => 'Verified';

  @override
  String get safetyNumbersDetailBody =>
      'Both of you should see the same 60-digit number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you.';

  @override
  String get safetyNumbersKeyChangedTitle => 'Safety number changed';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return 'It changed since you verified it on $date, after a reinstall, a new phone, or someone pretending to be them. Compare the new number before you trust it.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return 'Verified on $date';
  }

  @override
  String get safetyNumbersReVerify => 'Verify the new number';

  @override
  String get safetyNumbersMarkVerified => 'Mark as verified';

  @override
  String get safetyNumbersRotating => 'Renewing…';

  @override
  String get safetyNumbersRotateButton => 'Renew keys';

  @override
  String get safetyNumbersNewNumberHeader => 'New safety number';

  @override
  String get safetyNumbersCurrentNumberHeader => 'Current safety number';

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
  String get safetyNumbersScanAction => 'Compare their code';

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
  String get profileNicknameHint => 'Optional';

  @override
  String get profileSaveNickname => 'Save';

  @override
  String get profileNicknameFooter =>
      'Only you see nicknames. Your handle can\'t be changed.';

  @override
  String get profileNicknameHeader => 'Nickname';

  @override
  String get deviceTransferTitle => 'Move to a new phone';

  @override
  String get deviceTransferChipOldDevice => 'Old phone';

  @override
  String get deviceTransferChipNewDevice => 'New phone';

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
  String get deviceTransferOldApproveTitle => 'Approve the new phone';

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
  String get deviceTransferClaimInputLabel => 'Code from the new phone';

  @override
  String get deviceTransferApproveClaim => 'Approve';

  @override
  String get deviceTransferApproveFooter =>
      'Approve only the code your new phone shows. When the move finishes, this phone is signed out and your message history does not move to the new phone.';

  @override
  String get deviceTransferCopyPayload => 'Copy';

  @override
  String get deviceTransferClear => 'Clear';

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
  String get securityFooterDevice => 'Your account lives on this phone.';

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
  String get securityStatusSecretRefs => 'Keys';

  @override
  String get securityStatusSecretRefsPresent => 'On this phone';

  @override
  String get securityStatusSecretRefsMissing => 'Missing';

  @override
  String get securityStatusPin => 'App lock';

  @override
  String get securityStatusPinConfigured => 'On';

  @override
  String get securityStatusPinUnset => 'Off';

  @override
  String get securityStatusBiometrics => 'Biometrics';

  @override
  String get securityStatusAppPreview => 'App switcher preview';

  @override
  String get securityStatusAppPreviewProtected => 'Hidden';

  @override
  String get securityStatusAppPreviewPartial => 'Partial';

  @override
  String get securityStatusScreenCapture => 'Screenshots';

  @override
  String get securityStatusScreenCapturePlatformLimited => 'Limited';

  @override
  String get securityStatusScreenCaptureNotBlocked => 'Not blocked';

  @override
  String get securityStatusScreenCaptureUnsupportedDetail =>
      'This platform has no way to block screenshots, so the app hides its preview and locks quickly instead.';

  @override
  String get securityStatusClipboard => 'Clipboard';

  @override
  String get securityStatusClipboardRestricted => 'Restricted';

  @override
  String get securityStatusClipboardDetail =>
      'Download links for attachments are never shown, so they can\'t be copied.';

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
      'Any certificate the phone trusts is accepted.';

  @override
  String get securityStatusApiMode => 'Server';

  @override
  String get securityStatusApiUnavailableDetail =>
      'No server address is configured. Messaging is unavailable.';

  @override
  String get securityStatusRelayConnected => 'Connected';

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
  String get securityStatusCloudBackup => 'Backup';

  @override
  String get securityStatusAccountRecovery => 'Account recovery';

  @override
  String get securityStatusDeviceTransfer => 'Transfer';

  @override
  String get securityStatusDeviceTransferValue => 'Old phone required';

  @override
  String get securityStatusLocalWipe => 'Wipe';

  @override
  String get securityStatusLocalWipeValue => 'This phone only';

  @override
  String get securityStatusCryptoImplementation => 'Implementation';

  @override
  String get securityStatusCryptoVeilRatchet => 'Production (unaudited)';

  @override
  String securityStatusCryptoVeilRatchetDetail(String adapterId) {
    return 'X3DH and Double Ratchet ($adapterId)';
  }

  @override
  String get securityStatusCryptoLibsignal => 'libsignal bridge (unaudited)';

  @override
  String securityStatusCryptoLibsignalDetail(String adapterId) {
    return 'Signal\'s libsignal through a native bridge ($adapterId)';
  }

  @override
  String get securityStatusCryptoDevelopment => 'Development only';

  @override
  String securityStatusCryptoDevelopmentDetail(String adapterId) {
    return 'This build runs a development adapter ($adapterId), not production cryptography. Don\'t use it for real chats.';
  }

  @override
  String get securityStatusPushDelivery => 'Push notifications';

  @override
  String get securityStatusPushDeliveryOn => 'Connected';

  @override
  String get securityStatusPushDeliveryOff => 'Not connected';

  @override
  String get securityStatusPushDeliveryOffDetail =>
      'Notifications arrive only while the app is open.';

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

  @override
  String get chatMenuTooltip => 'More options';

  @override
  String get muteTitle => 'Mute notifications';

  @override
  String get muteUnmute => 'Unmute';

  @override
  String get muteOneHour => '1 hour';

  @override
  String get muteEightHours => '8 hours';

  @override
  String get muteOneWeek => '1 week';

  @override
  String get muteAlways => 'Always';

  @override
  String muteDoneFor(String duration) {
    return 'Notifications off for $duration';
  }

  @override
  String get muteDoneAlways => 'Notifications off';

  @override
  String get muteUndone => 'Notifications on';

  @override
  String get muteFailed => 'Couldn\'t change notifications';

  @override
  String get conversationsMutedSemantics => 'Muted';

  @override
  String get reportAction => 'Report';

  @override
  String reportTitle(String handle) {
    return 'Report @$handle';
  }

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Harassment';

  @override
  String get reportReasonImpersonation => 'Pretending to be someone';

  @override
  String get reportReasonCsam => 'Child sexual abuse';

  @override
  String get reportReasonViolence => 'Violence or threats';

  @override
  String get reportReasonScam => 'Scam or fraud';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String reportAlsoBlock(String handle) {
    return 'Also block @$handle';
  }

  @override
  String get reportFooterMessage =>
      'The report includes your account, theirs, the reason and which chat and message, but not what it says.';

  @override
  String get reportFooterChat =>
      'The report includes your account, theirs, the reason and which chat, but no messages.';

  @override
  String get reportFooterAccount =>
      'The report includes your account, theirs and the reason, but no messages.';

  @override
  String get reportSent => 'Report sent';

  @override
  String reportSentAndBlocked(String handle) {
    return 'Report sent and @$handle blocked';
  }

  @override
  String reportSentBlockFailed(String handle) {
    return 'Report sent, but @$handle couldn\'t be blocked';
  }

  @override
  String get reportFailed => 'Couldn\'t send the report';

  @override
  String get blockAction => 'Block';

  @override
  String get unblockAction => 'Unblock';

  @override
  String blockConfirmTitle(String handle) {
    return 'Block @$handle?';
  }

  @override
  String get blockConfirmBody =>
      'They can\'t message you directly or add you to a group. They aren\'t told, but their direct messages to you will fail, and in groups you share you\'ll both still see each other\'s messages.';

  @override
  String blockDone(String handle) {
    return '@$handle blocked';
  }

  @override
  String blockFailed(String handle) {
    return 'Couldn\'t block @$handle';
  }

  @override
  String unblockDone(String handle) {
    return '@$handle unblocked';
  }

  @override
  String unblockFailed(String handle) {
    return 'Couldn\'t unblock @$handle';
  }

  @override
  String get blockedComposerLine => 'You blocked this account.';

  @override
  String get blockedAccountsTitle => 'Blocked accounts';

  @override
  String get blockedAccountsEmptyTitle => 'No blocked accounts';

  @override
  String get blockedAccountsEmptyBody =>
      'You can block someone from a chat or from Contacts.';

  @override
  String get blockedAccountsLoadFailedTitle =>
      'Couldn\'t load blocked accounts';

  @override
  String get blockedAccountsLoadFailedBody =>
      'Check your connection and try again.';

  @override
  String safetyAccountNotFound(String handle) {
    return 'Couldn\'t find @$handle';
  }
}
