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
  String get authHandleEdges => 'Start and end with a letter or number.';

  @override
  String get authHandleRun => 'Don\'t put 2 dots or underscores in a row.';

  @override
  String get authCreating => 'Creating account…';

  @override
  String get authDefaultDeviceName => 'My phone';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

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
  String get settingsLogout => 'Sign out';

  @override
  String get settingsDeleteAccountBody =>
      'This deletes your account, messages and contacts from this phone and the server, and the groups you created, for everyone in them. It can\'t be undone.';

  @override
  String get settingsDeleteAccountAction => 'Delete account';

  @override
  String get settingsDeleteAccountConfirmHeadline => 'Delete your account?';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsLogoutConfirmTitle => 'Sign out of this phone?';

  @override
  String settingsLogoutConfirmBody(String handle) {
    return 'This deletes your chats from this phone, and you can\'t sign in as @$handle again.';
  }

  @override
  String get settingsLogoutFailed =>
      'Couldn\'t sign out. Check your connection and try again.';

  @override
  String settingsTypePhraseToContinue(String phrase) {
    return 'Type $phrase to confirm.';
  }

  @override
  String get settingsReadReceiptsCaption =>
      'When off, you won\'t see theirs either.';

  @override
  String get securityFooterUnaudited =>
      'The encryption hasn\'t been independently audited yet.';

  @override
  String get securityFooterTestBuild =>
      'This build uses test encryption. Don\'t use it for real chats.';

  @override
  String get securityScreenshotsNotice =>
      'In a chat, the others are told when you take one.';

  @override
  String get chatEmptyTitle => 'No messages yet';

  @override
  String get chatLoadFailedTitle => 'Couldn\'t load messages';

  @override
  String get chatComposeHint => 'Message';

  @override
  String get chatSendAction => 'Send';

  @override
  String get chatAttachAction => 'Add attachment';

  @override
  String get chatAttachPhotos => 'Photos';

  @override
  String get chatAttachFile => 'File';

  @override
  String chatAttachTooBig(String size) {
    return 'Files can be up to $size';
  }

  @override
  String get chatAttachPhotoFailed => 'Couldn\'t attach the photo';

  @override
  String get chatAttachFileFailed => 'Couldn\'t attach the file';

  @override
  String chatSendFileTitle(String name, String chat) {
    return 'Send \"$name\" to $chat?';
  }

  @override
  String get chatSendFileKeepsMetadata =>
      'A photo or video sent as a file keeps any location saved in it.';

  @override
  String get chatLoadingTitle => 'Loading messages…';

  @override
  String get chatTitleFallback => 'Chat';

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
  String get chatSearchSearching => 'Searching…';

  @override
  String get chatLoadOlder => 'Load older messages';

  @override
  String get chatLoadingOlder => 'Loading older messages…';

  @override
  String get chatSearchEmptyTitle => 'No results';

  @override
  String chatSearchPosition(int index, int count) {
    return '$index of $count';
  }

  @override
  String get chatSearchOlderTooltip => 'Previous result';

  @override
  String get chatSearchNewerTooltip => 'Next result';

  @override
  String get chatTtlSheetTitle => 'Disappearing messages';

  @override
  String get chatTtlSheetFooter =>
      'New messages disappear this long after they\'re sent.';

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
  String get chatTtl1w => '1 week';

  @override
  String get chatTtlDisabledLabel => 'Off';

  @override
  String get chatAttachmentCannotOpen => 'Can\'t open in this version';

  @override
  String chatAttachmentTypeSize(String type, String size) {
    return '$type · $size';
  }

  @override
  String get chatAttachmentKindPhoto => 'Photo';

  @override
  String get chatAttachmentKindVideo => 'Video';

  @override
  String get chatAttachmentKindAudio => 'Audio';

  @override
  String get chatAttachmentKindFile => 'File';

  @override
  String get chatAttachmentKindVoice => 'Voice message';

  @override
  String get chatPhotoUnavailable => 'Photo not available';

  @override
  String get chatFileUnavailable => 'File not available';

  @override
  String get chatDownloadFailed => 'Couldn\'t download. Tap to retry.';

  @override
  String get chatDownloadAction => 'Download';

  @override
  String get chatDownloading => 'Downloading';

  @override
  String get chatCancelDownload => 'Cancel download';

  @override
  String get chatOpenAction => 'Open';

  @override
  String get chatOpenFileNoApp => 'No app found to open this file';

  @override
  String get chatOpenFileFailed => 'Couldn\'t open the file';

  @override
  String get chatSaveAction => 'Save';

  @override
  String get chatSaveTitle => 'Save to your phone?';

  @override
  String get chatSaveBody =>
      'Other apps, and any cloud you save it to, can open it.';

  @override
  String get chatSaved => 'Saved';

  @override
  String get chatSaveFailed => 'Couldn\'t save. Try again.';

  @override
  String get viewerSenderYou => 'You';

  @override
  String get reactionsMoreTooltip => 'More reactions';

  @override
  String chatScreenshotSystemNotice(String handle) {
    return '@$handle took a screenshot';
  }

  @override
  String get chatScreenshotSelfNotice => 'You took a screenshot';

  @override
  String get chatDecryptingEnvelope => 'Decrypting…';

  @override
  String get chatDecryptFailed => 'Couldn\'t decrypt this message';

  @override
  String get chatDecryptReplayed => 'Repeated or expired message';

  @override
  String get chatDecryptAwaitingKey => 'Waiting for this message';

  @override
  String get chatDecryptSessionMissing => 'Waiting for this message';

  @override
  String get chatDecryptIdentityRejected =>
      'Locked until you review the new safety number';

  @override
  String get chatDecryptHeldAccount => 'Locked until you confirm this account';

  @override
  String get notificationNewMessage => 'New message';

  @override
  String get chatLegacySenderLine => 'Sent from an older app, not verified';

  @override
  String get chatNotSentTapToRetry => 'Not sent. Tap to retry.';

  @override
  String get chatDayToday => 'Today';

  @override
  String get chatDayYesterday => 'Yesterday';

  @override
  String get chatDayTomorrow => 'Tomorrow';

  @override
  String dayAtTime(String day, String time) {
    return '$day at $time';
  }

  @override
  String dateAtTime(String date, String time) {
    return 'on $date at $time';
  }

  @override
  String get chatNoticeIdentityChanged => 'Safety number changed';

  @override
  String get chatNoticeIdentityNewDevice => 'A new device was added';

  @override
  String get chatNoticeSenderKeysKept =>
      'Group keys didn\'t update. This phone kept the ones it has';

  @override
  String get chatNoticeGroupMemberAdded =>
      'A member was added and can read new messages';

  @override
  String get chatNoticeGroupMemberRemoved => 'A member left or was removed';

  @override
  String chatNoticeTimerSetByYou(String duration) {
    return 'You set disappearing messages to $duration';
  }

  @override
  String get chatNoticeTimerOffByYou => 'You turned off disappearing messages';

  @override
  String chatNoticeTimerSet(String duration) {
    return 'Disappearing messages set to $duration';
  }

  @override
  String get chatNoticeTimerOff => 'Disappearing messages turned off';

  @override
  String get chatIdentityChangedTitle => 'Safety number changed';

  @override
  String get chatIdentityChangedBody => 'Nothing is sent until you review it.';

  @override
  String get chatIdentityChangedReview => 'Review';

  @override
  String get chatIdentityChangedElsewhereTitle =>
      'Safety number changed in a group you share';

  @override
  String get chatAccountHoldOtherTitle => 'A different account';

  @override
  String chatAccountHoldOtherBody(String handle) {
    return 'This isn\'t the @$handle you talked to before. New messages stay locked and nothing is sent until you confirm.';
  }

  @override
  String get chatAccountHoldUnissuedTitle => 'A handle no account can have';

  @override
  String get chatAccountHoldUnissuedBody =>
      'It may only look like someone you know. New messages stay locked and nothing is sent until you confirm.';

  @override
  String get chatAccountHoldOwnTitle => 'Another account under your handle';

  @override
  String chatAccountHoldOwnBody(String handle) {
    return 'No one else can have @$handle, so the list this phone got was changed. New messages stay locked and nothing is sent until you confirm.';
  }

  @override
  String chatAccountHoldOwnConfirmTitle(String handle) {
    return 'Talk to this other @$handle?';
  }

  @override
  String get chatAccountHoldOwnConfirmBody =>
      'Continue only if you\'ve checked in person or on a call whose account this is.';

  @override
  String get chatAccountHoldAcknowledge => 'Talk to this account';

  @override
  String get chatPeerVerified => 'Verified';

  @override
  String get chatRetrySend => 'Retry';

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
  String chatTypingSuffix(String name) {
    return '$name is typing…';
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
  String get errorClaimBeforeCompletion => 'Enter the transfer code first.';

  @override
  String get errorUnexpectedResponse => 'Something went wrong. Try again.';

  @override
  String get errorUploadFailed =>
      'The upload failed. Check your connection and try again.';

  @override
  String get errorSessionInvalid =>
      'This session is no longer valid on this phone.';

  @override
  String get errorNotAllowed => 'This isn\'t allowed on this phone.';

  @override
  String get errorNotFound => 'Couldn\'t find that.';

  @override
  String get errorConflict => 'Something changed. Refresh and try again.';

  @override
  String get errorRejected =>
      'That didn\'t work. Check what you entered and try again.';

  @override
  String get errorRelayFailed => 'Something went wrong. Try again.';

  @override
  String get errorApiNeedsTls =>
      'The server address must use TLS outside local development.';

  @override
  String get errorRealtimeNeedsTls =>
      'The realtime address must use TLS outside local development.';

  @override
  String get errorNetworkTimeout =>
      'No answer. Check your connection and try again.';

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
      'This move has ended. Start again on your old phone.';

  @override
  String get errorTransferCodeInvalid => 'That code isn\'t valid.';

  @override
  String get errorTransferClaimRequired =>
      'Enter the code on your new phone first.';

  @override
  String get errorTransferApprovalRequired =>
      'The old phone hasn\'t approved this phone yet.';

  @override
  String get errorTransferCompletionInvalid =>
      'Couldn\'t finish the move. Start again on your old phone.';

  @override
  String get errorAttachmentCanceled => 'The upload was canceled.';

  @override
  String get errorAttachmentRejected =>
      'This file couldn\'t be sent. Attach it again.';

  @override
  String get errorPeerUnreachable => 'Messages can\'t be sent to this account.';

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
  String get conversationsPreviewMessage => 'Message';

  @override
  String get conversationsPreviewImage => 'Photo';

  @override
  String get conversationsPreviewAttachment => 'File';

  @override
  String get conversationsPreviewVoice => 'Voice message';

  @override
  String get conversationsPreviewSticker => 'Sticker';

  @override
  String get conversationsPreviewReaction => 'Reacted to a message';

  @override
  String conversationsPreviewSender(String name, String text) {
    return '$name: $text';
  }

  @override
  String conversationsPreviewYou(String text) {
    return 'You: $text';
  }

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
  String get conversationsMarkRead => 'Mark as read';

  @override
  String get conversationsMarkUnread => 'Mark as unread';

  @override
  String get conversationsMarkedUnreadSemantics => 'Marked unread';

  @override
  String navChatsUnreadSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread chats',
      one: '1 unread chat',
    );
    return '$_temp0';
  }

  @override
  String chatUnreadDivider(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread messages',
      one: '1 unread message',
    );
    return '$_temp0';
  }

  @override
  String get chatUnreadDividerNoCount => 'Unread messages';

  @override
  String get chatScrollToBottom => 'Scroll to bottom';

  @override
  String chatNewBelowSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages',
      one: '1 new message',
    );
    return '$_temp0';
  }

  @override
  String get conversationsSyncIssueTitle => 'Couldn\'t refresh chats';

  @override
  String get conversationsSearchHintCompact => 'Search';

  @override
  String get conversationsSectionLabel => 'Chats';

  @override
  String conversationsNoMatchTitle(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get conversationsNoneYetTitle => 'No chats yet';

  @override
  String get conversationsStartDirect => 'New chat';

  @override
  String get conversationsMessagesSection => 'Messages';

  @override
  String get conversationsLoadingMore => 'Loading more…';

  @override
  String get conversationsLoadMore => 'Load more';

  @override
  String get conversationsChoosePaneTitle => 'Select a chat';

  @override
  String get conversationsNewTooltip => 'New chat';

  @override
  String conversationsRowSemantics(String name) {
    return 'Chat with $name';
  }

  @override
  String conversationsGroupRowSemantics(String name) {
    return '$name, group chat';
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
  String get oneTimeLinkUsePassphrase => 'Add a passphrase';

  @override
  String get oneTimeLinkPassphraseLabel => 'Passphrase';

  @override
  String get oneTimeLinkCreate => 'Create link';

  @override
  String get oneTimeLinkCreating => 'Creating…';

  @override
  String get oneTimeLinkFailed => 'Couldn\'t create the link. Try again.';

  @override
  String get oneTimeLinkCopy => 'Copy link';

  @override
  String get oneTimeLinkCopied => 'Link copied';

  @override
  String oneTimeLinkExpires(String when) {
    return 'If it isn\'t opened, it\'s deleted $when.';
  }

  @override
  String get oneTimeLinkSendPassphraseApart =>
      'Send the passphrase separately.';

  @override
  String get oneTimeLinkFooter => 'It opens once, for whoever opens it first.';

  @override
  String get contactsSearchHint => 'Search';

  @override
  String get contactsSearchClear => 'Clear search';

  @override
  String get contactsAdd => 'Add contact';

  @override
  String get contactsWorking => 'Saving…';

  @override
  String get contactsErrorTitle => 'Couldn\'t refresh contacts';

  @override
  String get contactsEmptyTitle => 'No contacts yet';

  @override
  String get contactsEmptySearchTitle => 'No results';

  @override
  String get contactsHandleLabel => 'Handle';

  @override
  String get contactsNicknameLabel => 'Nickname (optional)';

  @override
  String get contactsSave => 'Add';

  @override
  String get contactsAddFailed =>
      'Couldn\'t add the contact. Check your connection.';

  @override
  String contactsAdded(String name) {
    return '$name added';
  }

  @override
  String get contactsStartChat => 'Message';

  @override
  String get contactsStartChatFailed => 'Couldn\'t start the chat';

  @override
  String get contactsEditNickname => 'Edit nickname';

  @override
  String get contactsSaveNickname => 'Save';

  @override
  String get contactsNicknameCaption => 'Only you see this.';

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
  String get startDirectOpening => 'Opening…';

  @override
  String get startDirectHandleHint => 'Name or handle';

  @override
  String get startDirectHandleError =>
      'Couldn\'t start the chat. Check your connection.';

  @override
  String startDirectChatWith(String handle) {
    return 'Chat with @$handle';
  }

  @override
  String get startDirectContactsHeader => 'Contacts';

  @override
  String get startGroupTitle => 'New group';

  @override
  String get startGroupNameInput => 'Group name (required)';

  @override
  String get startGroupDescriptionInput => 'Description (optional)';

  @override
  String startGroupMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get startGroupMembersCaption => 'You can\'t add members later.';

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
  String get startGroupMembersHint => 'Add a handle';

  @override
  String get startGroupMembersError =>
      'Couldn\'t create the group. Check your connection and try again.';

  @override
  String get safetyNumbersTitle => 'Safety number';

  @override
  String get safetyNumbersLoadingTitle => 'Loading…';

  @override
  String get safetyNumbersMarkedVerified => 'Marked as verified';

  @override
  String get safetyNumbersRotateDialogTitle => 'Renew the keys?';

  @override
  String get safetyNumbersRotateDialogBody =>
      'Your next message starts new keys. Do this if someone may have had your phone or theirs.';

  @override
  String get safetyNumbersCancel => 'Cancel';

  @override
  String get safetyNumbersRotate => 'Renew';

  @override
  String get safetyNumbersSessionRotated => 'Keys renewed';

  @override
  String get safetyNumbersNoSessionYet =>
      'Nothing to renew yet. Send a message first.';

  @override
  String get safetyNumbersRotationFailed =>
      'Couldn\'t renew the keys. Try again.';

  @override
  String get safetyNumbersErrorTitle => 'Couldn\'t load the safety number';

  @override
  String get safetyNumbersRetry => 'Retry';

  @override
  String get safetyNumbersNoMembersTitle => 'No other members';

  @override
  String get safetyNumbersUnverified => 'Not verified';

  @override
  String get safetyNumbersVerified => 'Verified';

  @override
  String safetyNumbersDetailBody(String name) {
    return 'Check these numbers match $name\'s phone, in person or on a call. Once verified, you\'ll see a warning if an account with a similar handle writes to you.';
  }

  @override
  String get safetyNumbersKeyChangedTitle => 'Safety number changed';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return 'It changed since you verified it on $date. Usually that means a new phone, but it can mean someone is posing as them.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return 'Verified $date';
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
  String get safetyNumbersCurrentNumberHeader => 'Number before the change';

  @override
  String get safetyNumbersNoPinTitle => 'No safety number yet';

  @override
  String get safetyNumbersNoPinBody =>
      'It appears after you exchange a message.';

  @override
  String get safetyNumbersDirectoryMismatchTitle =>
      'The server lists a different key';

  @override
  String get safetyNumbersDirectoryMismatchBody =>
      'Nothing is sent to it unless you compare and accept it.';

  @override
  String get safetyNumbersDirectoryOtherDeviceTitle =>
      'The server lists another device';

  @override
  String get safetyNumbersDirectoryOtherDeviceBody =>
      'This chat still sends to the device it knows. If your contact changed phones, compare numbers again.';

  @override
  String get safetyNumbersPendingBody =>
      'Their safety number changed. Compare it before you accept it.';

  @override
  String get safetyNumbersAcceptNewKey => 'Accept new number';

  @override
  String get safetyNumbersKeepCurrentKey => 'Keep the old one';

  @override
  String get safetyNumbersScanAction => 'Paste their code';

  @override
  String get safetyNumbersCopyCode => 'Copy my code';

  @override
  String get safetyNumbersCodeCopied => 'Code copied';

  @override
  String get safetyNumbersScanFieldLabel => 'Their code';

  @override
  String get safetyNumbersScanVerify => 'Compare';

  @override
  String get safetyNumbersScanMismatchTitle => 'These don\'t match';

  @override
  String get safetyNumbersScanMismatchBody =>
      'Someone may be in between. Compare again in person before you verify.';

  @override
  String get safetyNumbersScanInvalid => 'That isn\'t a safety code.';

  @override
  String get safetyNumbersScanUnsupported =>
      'That code is from a version this app doesn\'t support.';

  @override
  String get safetyNumbersReverifyDialogTitle => 'Verify the new number?';

  @override
  String safetyNumbersReverifyDialogBody(String peer) {
    return 'Do this only after comparing it with $peer in person or on a call.';
  }

  @override
  String safetyNumbersReverifyAffirm(String peer) {
    return 'It matches $peer\'s phone';
  }

  @override
  String get safetyNumbersReverifyAccept => 'Verify';

  @override
  String get safetyNumbersChangeReplaced =>
      'It changed again while you were looking. Compare the newer number.';

  @override
  String get safetyNumbersChangedElsewhereTitle =>
      'Changed in a group you share';

  @override
  String get safetyNumbersChangedElsewhereBody => 'Review it there first.';

  @override
  String get safetyNumbersReviewChange => 'Review';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileNicknameSaved => 'Name saved';

  @override
  String get profileHandleCopied => 'Handle copied';

  @override
  String get profileNicknameHint => 'Optional';

  @override
  String get profileSaveNickname => 'Save';

  @override
  String get profileNicknameFooter => 'Only you see your name.';

  @override
  String get profileNicknameHeader => 'Name';

  @override
  String get deviceTransferTitle => 'Move to a new phone';

  @override
  String get deviceTransferNewTitle => 'Move from another phone';

  @override
  String get deviceTransferPayloadHint => 'Paste the code from your old phone';

  @override
  String get deviceTransferPayloadCopied => 'Code copied';

  @override
  String get deviceTransferReturnToConversations => 'Back to chats';

  @override
  String get deviceTransferPayloadInvalid => 'That code isn\'t valid.';

  @override
  String get deviceTransferImportFirst => 'Paste the code first.';

  @override
  String get deviceTransferClaimFailed =>
      'Couldn\'t set up this phone. Try again.';

  @override
  String get deviceTransferCodeExpired =>
      'This code expired. Get a new one on your old phone.';

  @override
  String get deviceTransferFinishStartedFirst =>
      'Finish the move you already started before using a new code.';

  @override
  String get deviceTransferComplete => 'Your account is on this phone now.';

  @override
  String get deviceTransferFailed => 'Couldn\'t move the account. Try again.';

  @override
  String get deviceTransferOldIssueExpiredBody =>
      'This code expired. Get a new one.';

  @override
  String get deviceTransferOldHandTitle => 'Enter this code on your new phone';

  @override
  String get deviceTransferOldStep1 =>
      '1. On your new phone, install Veil and tap Move from another phone.';

  @override
  String get deviceTransferOldStep2 => '2. Enter the code this phone shows.';

  @override
  String get deviceTransferOldStep3 => '3. Approve the new phone here.';

  @override
  String get deviceTransferNewCodeExpiredBody =>
      'This code expired. Get a new one on your old phone.';

  @override
  String get deviceTransferNewCodeChange => 'Change';

  @override
  String get deviceTransferNewCompleteTitle => 'Approve on your old phone';

  @override
  String get deviceTransferNewCompleteBody =>
      'Enter this code on your old phone.';

  @override
  String get deviceTransferIssuingToken => 'Getting a code…';

  @override
  String get deviceTransferIssueToken => 'Get code';

  @override
  String get deviceTransferClaimInputLabel => 'Code from your new phone';

  @override
  String get deviceTransferApproveTitle =>
      'Move your account to the new phone?';

  @override
  String deviceTransferApproveBody(String fingerprint) {
    return 'Check that your new phone shows $fingerprint. This phone will then be signed out, and your messages won\'t move.';
  }

  @override
  String get deviceTransferApproveAction => 'Move account';

  @override
  String get deviceTransferApproveClaim => 'Approve';

  @override
  String get deviceTransferCopyPayload => 'Copy code';

  @override
  String get deviceTransferStatusNeedsApi =>
      'No server is configured, so nothing can be moved.';

  @override
  String get deviceTransferStatusNotStarted => 'Get a code first.';

  @override
  String get deviceTransferStatusClaimCodeMissing =>
      'Enter the code from your new phone first.';

  @override
  String deviceTransferStatusClaimNotWaiting(String claimId) {
    return 'No phone with code $claimId is waiting.';
  }

  @override
  String get deviceTransferStatusClaimApproved =>
      'Approved. Finish on your new phone.';

  @override
  String get deviceTransferPayloadInputLabel => 'Transfer code';

  @override
  String get deviceTransferDeviceNameLabel => 'Device name';

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
  String get deviceTransferRegisteringClaim => 'Setting up…';

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
  String get themeModeTitle => 'Theme';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeSystem => 'System';

  @override
  String get securityStatusBlocked => 'Blocked';

  @override
  String get securityStatusAppPreview => 'App switcher preview';

  @override
  String get securityStatusAppPreviewProtected => 'Hidden';

  @override
  String get securityStatusAppPreviewPartial => 'Partial';

  @override
  String get securityStatusScreenCapture => 'Screenshots';

  @override
  String get securityStatusScreenCaptureNotBlocked => 'Not blocked';

  @override
  String get securityStatusPushDelivery => 'Notifications';

  @override
  String get securityStatusPushDeliveryOn => 'On';

  @override
  String get securityNotificationsWhileOpen => 'Only while Veil is open';

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
    return 'Muted for $duration';
  }

  @override
  String get muteDoneAlways => 'Muted';

  @override
  String get muteUndone => 'Unmuted';

  @override
  String get muteFailed => 'Couldn\'t change notifications';

  @override
  String get conversationsMutedSemantics => 'Muted';

  @override
  String get reportAction => 'Report';

  @override
  String reportTitle(String name) {
    return 'Report $name';
  }

  @override
  String reportConfirmTitle(String name) {
    return 'Report $name?';
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
  String reportAlsoBlock(String name) {
    return 'Also block $name';
  }

  @override
  String get reportFooterMessage =>
      'We get both accounts, the reason and which message, but not what it says. They won\'t be told.';

  @override
  String get reportFooterChat =>
      'We get both accounts, the reason and which chat, but no messages. They won\'t be told.';

  @override
  String get reportFooterAccount =>
      'We get both accounts and the reason, but no messages. They won\'t be told.';

  @override
  String get reportSent => 'Report sent';

  @override
  String reportSentAndBlocked(String name) {
    return 'Report sent and $name blocked';
  }

  @override
  String reportSentBlockFailed(String name) {
    return 'Report sent, but $name couldn\'t be blocked';
  }

  @override
  String get reportFailed => 'Couldn\'t send the report';

  @override
  String get blockAction => 'Block';

  @override
  String get unblockAction => 'Unblock';

  @override
  String blockConfirmTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockConfirmBody =>
      'Their messages to you will show as not sent, and they can\'t add you to groups. They won\'t be told, and in groups you share, you\'ll still see each other\'s messages.';

  @override
  String blockDone(String name) {
    return '$name blocked';
  }

  @override
  String blockFailed(String name) {
    return 'Couldn\'t block $name';
  }

  @override
  String unblockDone(String name) {
    return '$name unblocked';
  }

  @override
  String unblockFailed(String name) {
    return 'Couldn\'t unblock $name';
  }

  @override
  String blockedComposerLine(String name) {
    return 'You blocked $name.';
  }

  @override
  String get blockedAccountsTitle => 'Blocked accounts';

  @override
  String get blockedAccountsEmptyTitle => 'No blocked accounts';

  @override
  String get blockedAccountsLoadFailedTitle =>
      'Couldn\'t load blocked accounts';

  @override
  String safetyAccountNotFound(String handle) {
    return 'Couldn\'t find @$handle';
  }

  @override
  String get errorRequestRejected => 'The server didn\'t accept that.';

  @override
  String get chatRequestTitle => 'Message request';

  @override
  String chatRequestDirectBody(String name) {
    return '$name won\'t know you\'ve read their messages until you accept.';
  }

  @override
  String get chatRequestGroupBody =>
      'You were added to this group. No one will know you\'ve read it until you accept.';

  @override
  String get chatRequestAccept => 'Accept';

  @override
  String get chatRequestLeave => 'Leave';

  @override
  String chatLeaveGroupTitle(String name) {
    return 'Leave $name?';
  }

  @override
  String get chatLeaveGroupBody => 'You\'ll stop getting its messages.';

  @override
  String get chatLeaveGroupConfirm => 'Leave';

  @override
  String get chatLeaveGroupFailed => 'Couldn\'t leave the group. Try again.';

  @override
  String get conversationsRequestPreview => 'Message request';

  @override
  String get notificationMessageRequest => 'Message request';

  @override
  String chatLookalikeTitle(String name) {
    return 'Not the $name you know';
  }

  @override
  String chatLookalikeBody(String handle, String name) {
    return '@$handle is a different account. Check with $name another way, like a call.';
  }

  @override
  String get chatClaimTitle => 'Make sure it\'s really them';

  @override
  String get chatClaimBody =>
      'Call the number you already have before you reply or send anything.';

  @override
  String chatVerifyNudge(String name) {
    return 'Check $name\'s safety number';
  }

  @override
  String get chatVerifyAction => 'Verify';

  @override
  String get riskLineFamilyClaim =>
      'Says it\'s family. Call the number you already have.';

  @override
  String get riskLineNewPhoneClaim =>
      'Says it\'s a new phone or account. Call the number you already have.';

  @override
  String get riskLineMoney =>
      'Asks for money. Call them before you send anything.';

  @override
  String get riskLineGiftCard => 'Asks for gift card codes. Don\'t send them.';

  @override
  String get riskLineCode => 'Asks for a verification code. Don\'t share it.';

  @override
  String get riskLineId => 'Asks for ID or card details. Don\'t send them.';

  @override
  String get riskLineRemoteApp =>
      'Asks you to install a remote-control app. Don\'t install it.';

  @override
  String get riskLineAppFile =>
      'Links to an app file. Don\'t install apps from a chat.';

  @override
  String get riskLineAppFileAttached =>
      'This is an app file. Don\'t install apps from a chat.';

  @override
  String get riskLineLookalikeLink => 'The link only looks like a known site.';

  @override
  String get riskLineHiddenLink => 'The link hides where it goes.';

  @override
  String get riskLineDelivery =>
      'Delivery message with a link. Check in the courier\'s own app.';

  @override
  String get riskLineBank =>
      'Says it\'s a bank or card company. Call the number on your card.';

  @override
  String get riskLineAuthority =>
      'Police and prosecutors never ask for money or apps in a chat.';

  @override
  String get riskLineGovernment =>
      'Check refunds and fines on the agency\'s own site or app.';

  @override
  String get riskLineInvestment =>
      'Promises sure profit. That\'s a common scam.';

  @override
  String get linkConfirmTitle => 'Open this link?';

  @override
  String get linkConfirmOpen => 'Open';

  @override
  String get linkConfirmCopy => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get linkOpenFailed => 'Couldn\'t open the link';

  @override
  String get linkRiskAppTitle => 'This link downloads an app';

  @override
  String get linkRiskAppBody => 'An app from a chat can take over your phone.';

  @override
  String get linkRiskHiddenTitle => 'You can\'t see where this link goes';

  @override
  String get linkRiskHiddenBody =>
      'Short links and unusual addresses can hide a fake site.';

  @override
  String get linkRiskLookalikeTitle => 'This isn\'t the site it looks like';

  @override
  String get linkRiskLookalikeBody =>
      'The address is close to a known site\'s, but different.';

  @override
  String get linkRiskKeepClosed => 'Don\'t open';

  @override
  String get linkRiskOpenAnyway => 'Open anyway';

  @override
  String get fileRiskAppTitle => 'This file is an app';

  @override
  String get fileRiskDontSave => 'Don\'t save';

  @override
  String get fileRiskSaveAnyway => 'Save anyway';

  @override
  String linkSemanticsLabel(String domain) {
    return 'Link, $domain';
  }
}
