import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Veil'**
  String get appTitle;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// No description provided for @commonOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @appLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// No description provided for @appLockCompromisedBody.
  ///
  /// In en, this message translates to:
  /// **'This phone looks rooted or jailbroken, so the app won\'t unlock here.'**
  String get appLockCompromisedBody;

  /// No description provided for @appLockCompromisedReasons.
  ///
  /// In en, this message translates to:
  /// **'This phone looks rooted or jailbroken. {reasons}'**
  String appLockCompromisedReasons(String reasons);

  /// No description provided for @appLockLockoutBody.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. {retry}'**
  String appLockLockoutBody(String retry);

  /// No description provided for @appLockRetryNow.
  ///
  /// In en, this message translates to:
  /// **'Try again now.'**
  String get appLockRetryNow;

  /// No description provided for @appLockRetrySeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Try again in 1 second.} other{Try again in {seconds} seconds.}}'**
  String appLockRetrySeconds(int seconds);

  /// No description provided for @appLockRetryMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Try again in 1 minute.} other{Try again in {minutes} minutes.}}'**
  String appLockRetryMinutes(int minutes);

  /// No description provided for @appLockPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get appLockPinLabel;

  /// No description provided for @appLockFieldPinHint.
  ///
  /// In en, this message translates to:
  /// **'6 to 12 digits'**
  String get appLockFieldPinHint;

  /// No description provided for @appLockFieldPinError.
  ///
  /// In en, this message translates to:
  /// **'Use 6 to 12 digits.'**
  String get appLockFieldPinError;

  /// No description provided for @appLockFieldConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get appLockFieldConfirm;

  /// No description provided for @appLockFieldConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Enter it again'**
  String get appLockFieldConfirmHint;

  /// No description provided for @appLockConfirmMismatch.
  ///
  /// In en, this message translates to:
  /// **'The PINs don\'t match.'**
  String get appLockConfirmMismatch;

  /// No description provided for @appLockStatusUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked.'**
  String get appLockStatusUnlocked;

  /// No description provided for @appLockStatusBiometricFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometrics didn\'t work. Enter your PIN.'**
  String get appLockStatusBiometricFailed;

  /// No description provided for @appLockStatusEnterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN first.'**
  String get appLockStatusEnterPin;

  /// No description provided for @appLockStatusPinFormat.
  ///
  /// In en, this message translates to:
  /// **'The PIN must be 6 to 12 digits.'**
  String get appLockStatusPinFormat;

  /// No description provided for @appLockStatusPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN.'**
  String get appLockStatusPinMismatch;

  /// No description provided for @appLockStatusPinMismatchAttempts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Wrong PIN. 1 try left.} other{Wrong PIN. {count} tries left.}}'**
  String appLockStatusPinMismatchAttempts(int count);

  /// No description provided for @appLockStatusLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Try again later.'**
  String get appLockStatusLocked;

  /// No description provided for @appLockStatusCompromised.
  ///
  /// In en, this message translates to:
  /// **'This phone can\'t be unlocked.'**
  String get appLockStatusCompromised;

  /// No description provided for @appLockUseBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get appLockUseBiometrics;

  /// No description provided for @appLockUseFaceId.
  ///
  /// In en, this message translates to:
  /// **'Use Face ID'**
  String get appLockUseFaceId;

  /// No description provided for @appLockUseTouchId.
  ///
  /// In en, this message translates to:
  /// **'Use Touch ID'**
  String get appLockUseTouchId;

  /// No description provided for @appLockUseFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint'**
  String get appLockUseFingerprint;

  /// No description provided for @appLockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get appLockUnlock;

  /// No description provided for @appLockLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Veil is locked'**
  String get appLockLockedTitle;

  /// No description provided for @appLockSetupFooter.
  ///
  /// In en, this message translates to:
  /// **'If you forget your PIN, there\'s no way to reset it.'**
  String get appLockSetupFooter;

  /// No description provided for @appLockTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get appLockTurnOn;

  /// No description provided for @splashErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start'**
  String get splashErrorTitle;

  /// No description provided for @onboardingWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get onboardingWarnTitle;

  /// No description provided for @onboardingWarnAgreeCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I understand a lost account can\'t be recovered'**
  String get onboardingWarnAgreeCheckbox;

  /// No description provided for @onboardingWarnLine1.
  ///
  /// In en, this message translates to:
  /// **'Your account lives on this phone.'**
  String get onboardingWarnLine1;

  /// No description provided for @onboardingWarnLine2.
  ///
  /// In en, this message translates to:
  /// **'If you lose the phone, your account and messages are gone for good.'**
  String get onboardingWarnLine2;

  /// No description provided for @onboardingWarnLine3.
  ///
  /// In en, this message translates to:
  /// **'To move to a new phone later, you\'ll need this one.'**
  String get onboardingWarnLine3;

  /// No description provided for @privacyConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get privacyConsentTitle;

  /// No description provided for @privacyConsentAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree to the collection and use of my personal information as described above (required)'**
  String get privacyConsentAgree;

  /// No description provided for @privacyConsentAccept.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get privacyConsentAccept;

  /// No description provided for @privacyConsentCollectTitle.
  ///
  /// In en, this message translates to:
  /// **'What we store'**
  String get privacyConsentCollectTitle;

  /// No description provided for @privacyConsentCollectItem1.
  ///
  /// In en, this message translates to:
  /// **'Your handle, and the random account and device IDs linked to it'**
  String get privacyConsentCollectItem1;

  /// No description provided for @privacyConsentCollectItem2.
  ///
  /// In en, this message translates to:
  /// **'Device type, device name and push token (notifications carry no message content)'**
  String get privacyConsentCollectItem2;

  /// No description provided for @privacyConsentCollectItem3.
  ///
  /// In en, this message translates to:
  /// **'Your public keys, used to encrypt messages to you'**
  String get privacyConsentCollectItem3;

  /// No description provided for @privacyConsentCollectItem4.
  ///
  /// In en, this message translates to:
  /// **'Your in-app contact list: which accounts you added (the names you give them stay on this phone)'**
  String get privacyConsentCollectItem4;

  /// No description provided for @privacyConsentCollectItem5.
  ///
  /// In en, this message translates to:
  /// **'Chat membership and delivery metadata: when messages arrived, delivery and read-receipt times, the day a device was last seen'**
  String get privacyConsentCollectItem5;

  /// No description provided for @privacyConsentCollectItem6.
  ///
  /// In en, this message translates to:
  /// **'Call records: which chat, who started the call, call type, start and end time, duration (kept 30 days)'**
  String get privacyConsentCollectItem6;

  /// No description provided for @privacyConsentCollectItem7.
  ///
  /// In en, this message translates to:
  /// **'Group and channel names and descriptions (stored readable), and the blocks, mutes and abuse reports you make (reports kept 90 days)'**
  String get privacyConsentCollectItem7;

  /// No description provided for @privacyConsentPurposeTitle.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get privacyConsentPurposeTitle;

  /// No description provided for @privacyConsentPurposeItem1.
  ///
  /// In en, this message translates to:
  /// **'Delivering end-to-end encrypted messages'**
  String get privacyConsentPurposeItem1;

  /// No description provided for @privacyConsentPurposeItem2.
  ///
  /// In en, this message translates to:
  /// **'Signing in your device and keeping your session'**
  String get privacyConsentPurposeItem2;

  /// No description provided for @privacyConsentPurposeItem3.
  ///
  /// In en, this message translates to:
  /// **'Finding people by handle and delivering messages to their devices'**
  String get privacyConsentPurposeItem3;

  /// No description provided for @privacyConsentRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'How long'**
  String get privacyConsentRetentionTitle;

  /// No description provided for @privacyConsentRetentionItem1.
  ///
  /// In en, this message translates to:
  /// **'Deleted as soon as you delete your account'**
  String get privacyConsentRetentionItem1;

  /// No description provided for @privacyConsentRetentionItem2.
  ///
  /// In en, this message translates to:
  /// **'Device data is removed when a device is signed out, and its device record within about 30 days'**
  String get privacyConsentRetentionItem2;

  /// No description provided for @privacyConsentRetentionItem3.
  ///
  /// In en, this message translates to:
  /// **'Expired messages are deleted automatically'**
  String get privacyConsentRetentionItem3;

  /// No description provided for @privacyConsentRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyConsentRightsTitle;

  /// No description provided for @privacyConsentRightsItem1.
  ///
  /// In en, this message translates to:
  /// **'You can access, correct and delete your information'**
  String get privacyConsentRightsItem1;

  /// No description provided for @privacyConsentRightsItem2.
  ///
  /// In en, this message translates to:
  /// **'You can delete everything in Settings with Delete account'**
  String get privacyConsentRightsItem2;

  /// No description provided for @privacyConsentRightsItem3.
  ///
  /// In en, this message translates to:
  /// **'Withdrawing consent ends your access to the service'**
  String get privacyConsentRightsItem3;

  /// No description provided for @privacyConsentNotCollectedTitle.
  ///
  /// In en, this message translates to:
  /// **'What we never collect'**
  String get privacyConsentNotCollectedTitle;

  /// No description provided for @privacyConsentNotCollectedItem1.
  ///
  /// In en, this message translates to:
  /// **'Message contents: they are end-to-end encrypted and the server can\'t read them'**
  String get privacyConsentNotCollectedItem1;

  /// No description provided for @privacyConsentNotCollectedItem2.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get privacyConsentNotCollectedItem2;

  /// No description provided for @privacyConsentNotCollectedItem3.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s address book, its call log or other personal data on your device'**
  String get privacyConsentNotCollectedItem3;

  /// No description provided for @privacyConsentThirdPartyTitle.
  ///
  /// In en, this message translates to:
  /// **'Third parties'**
  String get privacyConsentThirdPartyTitle;

  /// No description provided for @privacyConsentThirdPartyBody.
  ///
  /// In en, this message translates to:
  /// **'Veil does not share your information with third parties, except where the law requires it.'**
  String get privacyConsentThirdPartyBody;

  /// No description provided for @authCreateTransferLabel.
  ///
  /// In en, this message translates to:
  /// **'Move from another phone'**
  String get authCreateTransferLabel;

  /// No description provided for @authHandleTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a handle'**
  String get authHandleTitle;

  /// No description provided for @authHandleFindCaption.
  ///
  /// In en, this message translates to:
  /// **'You can\'t change it later.'**
  String get authHandleFindCaption;

  /// No description provided for @authHandleInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get authHandleInputLabel;

  /// No description provided for @authHandleInputHint.
  ///
  /// In en, this message translates to:
  /// **'alex'**
  String get authHandleInputHint;

  /// No description provided for @authHandleBindCta.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authHandleBindCta;

  /// No description provided for @authHandleInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use 3 to 32 lowercase letters, numbers, dots or underscores.'**
  String get authHandleInvalid;

  /// No description provided for @authHandleEdges.
  ///
  /// In en, this message translates to:
  /// **'Start and end with a letter or number.'**
  String get authHandleEdges;

  /// No description provided for @authHandleRun.
  ///
  /// In en, this message translates to:
  /// **'Don\'t put 2 dots or underscores in a row.'**
  String get authHandleRun;

  /// No description provided for @authCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating account…'**
  String get authCreating;

  /// No description provided for @authDefaultDeviceName.
  ///
  /// In en, this message translates to:
  /// **'My phone'**
  String get authDefaultDeviceName;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsAppLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLockTitle;

  /// No description provided for @settingsDeviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to a new phone'**
  String get settingsDeviceTransferTitle;

  /// No description provided for @settingsSectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsSectionPrivacy;

  /// No description provided for @settingsReadReceiptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send read receipts'**
  String get settingsReadReceiptsTitle;

  /// No description provided for @settingsTypingIndicatorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send typing indicators'**
  String get settingsTypingIndicatorsTitle;

  /// No description provided for @settingsLockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get settingsLockNow;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsLogout;

  /// No description provided for @settingsDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes your account, messages and contacts from this phone and the server, and the groups you created, for everyone in them. It can\'t be undone.'**
  String get settingsDeleteAccountBody;

  /// No description provided for @settingsDeleteAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccountAction;

  /// No description provided for @settingsDeleteAccountConfirmHeadline.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get settingsDeleteAccountConfirmHeadline;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsLogoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this phone?'**
  String get settingsLogoutConfirmTitle;

  /// No description provided for @settingsLogoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your chats on this phone are deleted, and you can\'t sign in as @{handle} again.'**
  String settingsLogoutConfirmBody(String handle);

  /// No description provided for @settingsLogoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign out. Check your connection and try again.'**
  String get settingsLogoutFailed;

  /// No description provided for @settingsTypePhraseToContinue.
  ///
  /// In en, this message translates to:
  /// **'Type {phrase} to confirm.'**
  String settingsTypePhraseToContinue(String phrase);

  /// No description provided for @settingsReadReceiptsCaption.
  ///
  /// In en, this message translates to:
  /// **'When off, you won\'t see theirs either.'**
  String get settingsReadReceiptsCaption;

  /// No description provided for @securityFooterUnaudited.
  ///
  /// In en, this message translates to:
  /// **'The encryption hasn\'t been independently audited yet.'**
  String get securityFooterUnaudited;

  /// No description provided for @securityFooterTestBuild.
  ///
  /// In en, this message translates to:
  /// **'This build uses test encryption. Don\'t use it for real chats.'**
  String get securityFooterTestBuild;

  /// No description provided for @securityScreenshotsNotice.
  ///
  /// In en, this message translates to:
  /// **'In a chat, the others are told when you take one.'**
  String get securityScreenshotsNotice;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// No description provided for @chatLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load messages'**
  String get chatLoadFailedTitle;

  /// No description provided for @chatComposeHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chatComposeHint;

  /// No description provided for @chatSendAction.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSendAction;

  /// No description provided for @chatAttachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get chatAttachAction;

  /// No description provided for @chatLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading messages…'**
  String get chatLoadingTitle;

  /// No description provided for @chatTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitleFallback;

  /// No description provided for @chatGroupUnknownSender.
  ///
  /// In en, this message translates to:
  /// **'Unknown sender'**
  String get chatGroupUnknownSender;

  /// No description provided for @chatGroupMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String chatGroupMemberCount(int count);

  /// No description provided for @chatTimerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Disappearing: {value}'**
  String chatTimerTooltip(String value);

  /// No description provided for @chatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search this chat'**
  String get chatSearchHint;

  /// No description provided for @chatSearchClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get chatSearchClearTooltip;

  /// No description provided for @chatSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get chatSearchTooltip;

  /// No description provided for @chatSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get chatSearchSearching;

  /// No description provided for @chatLoadOlder.
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get chatLoadOlder;

  /// No description provided for @chatLoadingOlder.
  ///
  /// In en, this message translates to:
  /// **'Loading older messages…'**
  String get chatLoadingOlder;

  /// No description provided for @chatSearchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get chatSearchEmptyTitle;

  /// No description provided for @chatSearchPosition.
  ///
  /// In en, this message translates to:
  /// **'{index} of {count}'**
  String chatSearchPosition(int index, int count);

  /// No description provided for @chatSearchOlderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Previous result'**
  String get chatSearchOlderTooltip;

  /// No description provided for @chatSearchNewerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Next result'**
  String get chatSearchNewerTooltip;

  /// No description provided for @chatTtlSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get chatTtlSheetTitle;

  /// No description provided for @chatTtlSheetFooter.
  ///
  /// In en, this message translates to:
  /// **'New messages disappear this long after they\'re sent.'**
  String get chatTtlSheetFooter;

  /// No description provided for @chatTtlOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get chatTtlOff;

  /// No description provided for @chatTtl10s.
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get chatTtl10s;

  /// No description provided for @chatTtl1m.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get chatTtl1m;

  /// No description provided for @chatTtl5m.
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get chatTtl5m;

  /// No description provided for @chatTtl1h.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get chatTtl1h;

  /// No description provided for @chatTtl1d.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get chatTtl1d;

  /// No description provided for @chatTtl1w.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get chatTtl1w;

  /// No description provided for @chatTtlDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get chatTtlDisabledLabel;

  /// No description provided for @chatAttachmentTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t open this file'**
  String get chatAttachmentTicketTitle;

  /// No description provided for @chatAttachmentTicketBody.
  ///
  /// In en, this message translates to:
  /// **'This version can\'t download files yet.\n\n{summary}'**
  String chatAttachmentTicketBody(String summary);

  /// No description provided for @chatAttachmentTicketFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t request the download'**
  String get chatAttachmentTicketFailed;

  /// No description provided for @chatAttachmentResolveAction.
  ///
  /// In en, this message translates to:
  /// **'Request download'**
  String get chatAttachmentResolveAction;

  /// No description provided for @chatAttachmentResolvingAction.
  ///
  /// In en, this message translates to:
  /// **'Requesting…'**
  String get chatAttachmentResolvingAction;

  /// No description provided for @chatAttachmentStateBanner.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get chatAttachmentStateBanner;

  /// No description provided for @chatAttachmentCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'Can\'t open in this version'**
  String get chatAttachmentCannotOpen;

  /// No description provided for @chatAttachmentTypeSize.
  ///
  /// In en, this message translates to:
  /// **'{type} · {size}'**
  String chatAttachmentTypeSize(String type, String size);

  /// No description provided for @chatAttachmentKindPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get chatAttachmentKindPhoto;

  /// No description provided for @chatAttachmentKindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get chatAttachmentKindVideo;

  /// No description provided for @chatAttachmentKindAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get chatAttachmentKindAudio;

  /// No description provided for @chatAttachmentKindFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get chatAttachmentKindFile;

  /// No description provided for @reactionsMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More reactions'**
  String get reactionsMoreTooltip;

  /// No description provided for @chatScreenshotSystemNotice.
  ///
  /// In en, this message translates to:
  /// **'@{handle} took a screenshot'**
  String chatScreenshotSystemNotice(String handle);

  /// No description provided for @chatScreenshotSelfNotice.
  ///
  /// In en, this message translates to:
  /// **'You took a screenshot'**
  String get chatScreenshotSelfNotice;

  /// No description provided for @chatDecryptingEnvelope.
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get chatDecryptingEnvelope;

  /// No description provided for @chatDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t decrypt this message'**
  String get chatDecryptFailed;

  /// No description provided for @chatDecryptReplayed.
  ///
  /// In en, this message translates to:
  /// **'Repeated or expired message'**
  String get chatDecryptReplayed;

  /// No description provided for @chatDecryptAwaitingKey.
  ///
  /// In en, this message translates to:
  /// **'Waiting for this message'**
  String get chatDecryptAwaitingKey;

  /// No description provided for @chatDecryptSessionMissing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for this message'**
  String get chatDecryptSessionMissing;

  /// No description provided for @chatDecryptIdentityRejected.
  ///
  /// In en, this message translates to:
  /// **'Locked until you review the new safety number'**
  String get chatDecryptIdentityRejected;

  /// No description provided for @chatDecryptHeldAccount.
  ///
  /// In en, this message translates to:
  /// **'Locked until you confirm this account'**
  String get chatDecryptHeldAccount;

  /// No description provided for @notificationNewMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get notificationNewMessage;

  /// No description provided for @chatLegacySenderLine.
  ///
  /// In en, this message translates to:
  /// **'Sent from an older app, not verified'**
  String get chatLegacySenderLine;

  /// No description provided for @chatNotSentTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Not sent. Tap to retry.'**
  String get chatNotSentTapToRetry;

  /// No description provided for @chatDayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chatDayToday;

  /// No description provided for @chatDayYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatDayYesterday;

  /// No description provided for @chatDayTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get chatDayTomorrow;

  /// No description provided for @dayAtTime.
  ///
  /// In en, this message translates to:
  /// **'{day} at {time}'**
  String dayAtTime(String day, String time);

  /// No description provided for @dateAtTime.
  ///
  /// In en, this message translates to:
  /// **'on {date} at {time}'**
  String dateAtTime(String date, String time);

  /// No description provided for @chatNoticeIdentityChanged.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get chatNoticeIdentityChanged;

  /// No description provided for @chatNoticeIdentityNewDevice.
  ///
  /// In en, this message translates to:
  /// **'A new device was added'**
  String get chatNoticeIdentityNewDevice;

  /// No description provided for @chatNoticeSenderKeysKept.
  ///
  /// In en, this message translates to:
  /// **'Group keys didn\'t update. This phone kept the ones it has'**
  String get chatNoticeSenderKeysKept;

  /// No description provided for @chatNoticeGroupMemberAdded.
  ///
  /// In en, this message translates to:
  /// **'A member was added and can read new messages'**
  String get chatNoticeGroupMemberAdded;

  /// No description provided for @chatNoticeGroupMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'A member left or was removed'**
  String get chatNoticeGroupMemberRemoved;

  /// No description provided for @chatNoticeTimerSetByYou.
  ///
  /// In en, this message translates to:
  /// **'You set disappearing messages to {duration}'**
  String chatNoticeTimerSetByYou(String duration);

  /// No description provided for @chatNoticeTimerOffByYou.
  ///
  /// In en, this message translates to:
  /// **'You turned off disappearing messages'**
  String get chatNoticeTimerOffByYou;

  /// No description provided for @chatNoticeTimerSet.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages set to {duration}'**
  String chatNoticeTimerSet(String duration);

  /// No description provided for @chatNoticeTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages turned off'**
  String get chatNoticeTimerOff;

  /// No description provided for @chatIdentityChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get chatIdentityChangedTitle;

  /// No description provided for @chatIdentityChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent until you review it.'**
  String get chatIdentityChangedBody;

  /// No description provided for @chatIdentityChangedReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get chatIdentityChangedReview;

  /// No description provided for @chatIdentityChangedElsewhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed in a group you share'**
  String get chatIdentityChangedElsewhereTitle;

  /// No description provided for @chatAccountHoldOtherTitle.
  ///
  /// In en, this message translates to:
  /// **'A different account'**
  String get chatAccountHoldOtherTitle;

  /// No description provided for @chatAccountHoldOtherBody.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t the @{handle} you talked to before. New messages stay locked and nothing is sent until you confirm.'**
  String chatAccountHoldOtherBody(String handle);

  /// No description provided for @chatAccountHoldUnissuedTitle.
  ///
  /// In en, this message translates to:
  /// **'A handle no account can have'**
  String get chatAccountHoldUnissuedTitle;

  /// No description provided for @chatAccountHoldUnissuedBody.
  ///
  /// In en, this message translates to:
  /// **'It may only look like someone you know. New messages stay locked and nothing is sent until you confirm.'**
  String get chatAccountHoldUnissuedBody;

  /// No description provided for @chatAccountHoldOwnTitle.
  ///
  /// In en, this message translates to:
  /// **'Another account under your handle'**
  String get chatAccountHoldOwnTitle;

  /// No description provided for @chatAccountHoldOwnBody.
  ///
  /// In en, this message translates to:
  /// **'No one else can have @{handle}, so the list this phone got was changed. New messages stay locked and nothing is sent until you confirm.'**
  String chatAccountHoldOwnBody(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk to this other @{handle}?'**
  String chatAccountHoldOwnConfirmTitle(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Continue only if you\'ve checked in person or on a call whose account this is.'**
  String get chatAccountHoldOwnConfirmBody;

  /// No description provided for @chatAccountHoldAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'Talk to this account'**
  String get chatAccountHoldAcknowledge;

  /// No description provided for @chatPeerVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get chatPeerVerified;

  /// No description provided for @chatRetrySend.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get chatRetrySend;

  /// No description provided for @chatRetryUpload.
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get chatRetryUpload;

  /// No description provided for @chatCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get chatCancelAction;

  /// No description provided for @chatDeliveryQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get chatDeliveryQueued;

  /// No description provided for @chatDeliveryUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get chatDeliveryUploading;

  /// No description provided for @chatDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get chatDeliveryFailed;

  /// No description provided for @chatDeliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get chatDeliverySent;

  /// No description provided for @chatDeliveryDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get chatDeliveryDelivered;

  /// No description provided for @chatDeliveryRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get chatDeliveryRead;

  /// No description provided for @chatPhaseStaged.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get chatPhaseStaged;

  /// No description provided for @chatPhasePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get chatPhasePreparing;

  /// No description provided for @chatPhaseUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get chatPhaseUploading;

  /// No description provided for @chatPhaseFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finishing'**
  String get chatPhaseFinalizing;

  /// No description provided for @chatPhaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get chatPhaseFailed;

  /// No description provided for @chatPhaseCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get chatPhaseCanceled;

  /// No description provided for @chatPhaseDescStaged.
  ///
  /// In en, this message translates to:
  /// **'Encrypted and ready.{sizeLabel} It uploads when you\'re online.'**
  String chatPhaseDescStaged(String sizeLabel);

  /// No description provided for @chatPhaseDescPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing the upload.'**
  String get chatPhaseDescPreparing;

  /// No description provided for @chatPhaseDescUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading the encrypted file.'**
  String get chatPhaseDescUploading;

  /// No description provided for @chatPhaseDescFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Attaching the file to the message.'**
  String get chatPhaseDescFinalizing;

  /// No description provided for @chatPhaseDescFailed.
  ///
  /// In en, this message translates to:
  /// **'The upload failed.'**
  String get chatPhaseDescFailed;

  /// No description provided for @chatPhaseDescCanceled.
  ///
  /// In en, this message translates to:
  /// **'The upload was canceled.'**
  String get chatPhaseDescCanceled;

  /// No description provided for @chatAttachmentSizeBytes.
  ///
  /// In en, this message translates to:
  /// **' {count} bytes.'**
  String chatAttachmentSizeBytes(int count);

  /// No description provided for @chatTypingSuffix.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing…'**
  String chatTypingSuffix(String name);

  /// No description provided for @chatTypingUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Typing…'**
  String get chatTypingUnnamed;

  /// No description provided for @chatReactionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{emoji}, {count, plural, =1{1 reaction} other{{count} reactions}}'**
  String chatReactionSemantics(String emoji, int count);

  /// No description provided for @chatSemanticsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get chatSemanticsSent;

  /// No description provided for @chatSemanticsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get chatSemanticsReceived;

  /// No description provided for @chatSemanticsBubble.
  ///
  /// In en, this message translates to:
  /// **'{direction} message bubble.{stateSegment}'**
  String chatSemanticsBubble(String direction, String stateSegment);

  /// No description provided for @chatSemanticsStateSegment.
  ///
  /// In en, this message translates to:
  /// **' {state}.'**
  String chatSemanticsStateSegment(String state);

  /// No description provided for @chatDurationDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String chatDurationDays(int count);

  /// No description provided for @chatDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String chatDurationHours(int count);

  /// No description provided for @chatDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String chatDurationMinutes(int count);

  /// No description provided for @chatDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String chatDurationSeconds(int count);

  /// No description provided for @chatExpiryExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get chatExpiryExpired;

  /// No description provided for @chatExpirySeconds.
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}s'**
  String chatExpirySeconds(int count);

  /// No description provided for @chatExpiryMinutes.
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}m'**
  String chatExpiryMinutes(int count);

  /// No description provided for @chatExpiryHours.
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}h'**
  String chatExpiryHours(int count);

  /// No description provided for @chatExpiryDays.
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}d'**
  String chatExpiryDays(int count);

  /// No description provided for @errorSessionRequired.
  ///
  /// In en, this message translates to:
  /// **'This phone is signed out.'**
  String get errorSessionRequired;

  /// No description provided for @errorTransferNeedsApi.
  ///
  /// In en, this message translates to:
  /// **'Moving to a new phone needs a server connection.'**
  String get errorTransferNeedsApi;

  /// No description provided for @errorClaimBeforeCompletion.
  ///
  /// In en, this message translates to:
  /// **'Enter the transfer code first.'**
  String get errorClaimBeforeCompletion;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorUnexpectedResponse;

  /// No description provided for @errorUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'The upload failed. Check your connection and try again.'**
  String get errorUploadFailed;

  /// No description provided for @errorSessionInvalid.
  ///
  /// In en, this message translates to:
  /// **'This session is no longer valid on this phone.'**
  String get errorSessionInvalid;

  /// No description provided for @errorNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t allowed on this phone.'**
  String get errorNotAllowed;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find that.'**
  String get errorNotFound;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'Something changed. Refresh and try again.'**
  String get errorConflict;

  /// No description provided for @errorRejected.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work. Check what you entered and try again.'**
  String get errorRejected;

  /// No description provided for @errorRelayFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorRelayFailed;

  /// No description provided for @errorApiNeedsTls.
  ///
  /// In en, this message translates to:
  /// **'The server address must use TLS outside local development.'**
  String get errorApiNeedsTls;

  /// No description provided for @errorRealtimeNeedsTls.
  ///
  /// In en, this message translates to:
  /// **'The realtime address must use TLS outside local development.'**
  String get errorRealtimeNeedsTls;

  /// No description provided for @errorNetworkTimeout.
  ///
  /// In en, this message translates to:
  /// **'No answer. Check your connection and try again.'**
  String get errorNetworkTimeout;

  /// No description provided for @errorNetworkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection.'**
  String get errorNetworkUnavailable;

  /// No description provided for @errorTlsPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate isn\'t the one this app trusts.'**
  String get errorTlsPinMismatch;

  /// No description provided for @errorChallengeInvalid.
  ///
  /// In en, this message translates to:
  /// **'The sign-in request expired. Try again.'**
  String get errorChallengeInvalid;

  /// No description provided for @errorDeviceNotActive.
  ///
  /// In en, this message translates to:
  /// **'This phone was removed from this account.'**
  String get errorDeviceNotActive;

  /// No description provided for @errorDeviceSignatureInvalid.
  ///
  /// In en, this message translates to:
  /// **'The server couldn\'t verify this phone.'**
  String get errorDeviceSignatureInvalid;

  /// No description provided for @errorHandleTaken.
  ///
  /// In en, this message translates to:
  /// **'That handle is taken. Try another.'**
  String get errorHandleTaken;

  /// No description provided for @errorTransferInactive.
  ///
  /// In en, this message translates to:
  /// **'This move has ended. Start again on your old phone.'**
  String get errorTransferInactive;

  /// No description provided for @errorTransferCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t valid.'**
  String get errorTransferCodeInvalid;

  /// No description provided for @errorTransferClaimRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the code on your new phone first.'**
  String get errorTransferClaimRequired;

  /// No description provided for @errorTransferApprovalRequired.
  ///
  /// In en, this message translates to:
  /// **'The old phone hasn\'t approved this phone yet.'**
  String get errorTransferApprovalRequired;

  /// No description provided for @errorTransferCompletionInvalid.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish the move. Start again on your old phone.'**
  String get errorTransferCompletionInvalid;

  /// No description provided for @errorAttachmentCanceled.
  ///
  /// In en, this message translates to:
  /// **'The upload was canceled.'**
  String get errorAttachmentCanceled;

  /// No description provided for @errorAttachmentRejected.
  ///
  /// In en, this message translates to:
  /// **'This file couldn\'t be sent. Attach it again.'**
  String get errorAttachmentRejected;

  /// No description provided for @errorPeerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Messages can\'t be sent to this account.'**
  String get errorPeerUnreachable;

  /// No description provided for @conversationsNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get conversationsNewGroup;

  /// No description provided for @conversationsPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get conversationsPreviewEmpty;

  /// No description provided for @conversationsQueued.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message waiting to be sent} other{{count} messages waiting to be sent}}'**
  String conversationsQueued(int count);

  /// No description provided for @conversationsNotSent.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message wasn\'t sent} other{{count} messages weren\'t sent}}'**
  String conversationsNotSent(int count);

  /// No description provided for @conversationsPreviewExpired.
  ///
  /// In en, this message translates to:
  /// **'Message expired'**
  String get conversationsPreviewExpired;

  /// No description provided for @conversationsPreviewMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get conversationsPreviewMessage;

  /// No description provided for @conversationsPreviewImage.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get conversationsPreviewImage;

  /// No description provided for @conversationsPreviewAttachment.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get conversationsPreviewAttachment;

  /// No description provided for @conversationsPreviewVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get conversationsPreviewVoice;

  /// No description provided for @conversationsPreviewSticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get conversationsPreviewSticker;

  /// No description provided for @conversationsPreviewReaction.
  ///
  /// In en, this message translates to:
  /// **'Reacted to a message'**
  String get conversationsPreviewReaction;

  /// No description provided for @conversationsPreviewSender.
  ///
  /// In en, this message translates to:
  /// **'{name}: {text}'**
  String conversationsPreviewSender(String name, String text);

  /// No description provided for @conversationsPreviewYou.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String conversationsPreviewYou(String text);

  /// No description provided for @conversationsBarConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get conversationsBarConnecting;

  /// No description provided for @conversationsBarOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get conversationsBarOffline;

  /// No description provided for @conversationsUnreadSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread message} other{{count} unread messages}}'**
  String conversationsUnreadSemantics(int count);

  /// No description provided for @conversationsSyncIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh chats'**
  String get conversationsSyncIssueTitle;

  /// No description provided for @conversationsSearchHintCompact.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get conversationsSearchHintCompact;

  /// No description provided for @conversationsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get conversationsSectionLabel;

  /// No description provided for @conversationsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String conversationsNoMatchTitle(String query);

  /// No description provided for @conversationsNoneYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get conversationsNoneYetTitle;

  /// No description provided for @conversationsStartDirect.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get conversationsStartDirect;

  /// No description provided for @conversationsMessagesSection.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get conversationsMessagesSection;

  /// No description provided for @conversationsLoadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more…'**
  String get conversationsLoadingMore;

  /// No description provided for @conversationsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get conversationsLoadMore;

  /// No description provided for @conversationsChoosePaneTitle.
  ///
  /// In en, this message translates to:
  /// **'Select a chat'**
  String get conversationsChoosePaneTitle;

  /// No description provided for @conversationsNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get conversationsNewTooltip;

  /// No description provided for @conversationsRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Chat with {name}'**
  String conversationsRowSemantics(String name);

  /// No description provided for @conversationsGroupRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, group chat'**
  String conversationsGroupRowSemantics(String name);

  /// No description provided for @conversationsGroupMark.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get conversationsGroupMark;

  /// No description provided for @navChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// No description provided for @navContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get navContacts;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @oneTimeLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'One-time link'**
  String get oneTimeLinkTitle;

  /// No description provided for @oneTimeLinkSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret'**
  String get oneTimeLinkSecretLabel;

  /// No description provided for @oneTimeLinkSecretHint.
  ///
  /// In en, this message translates to:
  /// **'A password, an account number, a note'**
  String get oneTimeLinkSecretHint;

  /// No description provided for @oneTimeLinkUsePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Add a passphrase'**
  String get oneTimeLinkUsePassphrase;

  /// No description provided for @oneTimeLinkPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get oneTimeLinkPassphraseLabel;

  /// No description provided for @oneTimeLinkCreate.
  ///
  /// In en, this message translates to:
  /// **'Create link'**
  String get oneTimeLinkCreate;

  /// No description provided for @oneTimeLinkCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get oneTimeLinkCreating;

  /// No description provided for @oneTimeLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the link. Try again.'**
  String get oneTimeLinkFailed;

  /// No description provided for @oneTimeLinkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get oneTimeLinkCopy;

  /// No description provided for @oneTimeLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get oneTimeLinkCopied;

  /// No description provided for @oneTimeLinkExpires.
  ///
  /// In en, this message translates to:
  /// **'If it isn\'t opened, it\'s deleted {when}.'**
  String oneTimeLinkExpires(String when);

  /// No description provided for @oneTimeLinkSendPassphraseApart.
  ///
  /// In en, this message translates to:
  /// **'Send the passphrase separately.'**
  String get oneTimeLinkSendPassphraseApart;

  /// No description provided for @oneTimeLinkFooter.
  ///
  /// In en, this message translates to:
  /// **'It opens once, for whoever opens it first.'**
  String get oneTimeLinkFooter;

  /// No description provided for @contactsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get contactsSearchHint;

  /// No description provided for @contactsSearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get contactsSearchClear;

  /// No description provided for @contactsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get contactsAdd;

  /// No description provided for @contactsWorking.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get contactsWorking;

  /// No description provided for @contactsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh contacts'**
  String get contactsErrorTitle;

  /// No description provided for @contactsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get contactsEmptyTitle;

  /// No description provided for @contactsEmptySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get contactsEmptySearchTitle;

  /// No description provided for @contactsHandleLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get contactsHandleLabel;

  /// No description provided for @contactsNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname (optional)'**
  String get contactsNicknameLabel;

  /// No description provided for @contactsSave.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get contactsSave;

  /// No description provided for @contactsAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the contact. Check your connection.'**
  String get contactsAddFailed;

  /// No description provided for @contactsAdded.
  ///
  /// In en, this message translates to:
  /// **'@{handle} added'**
  String contactsAdded(String handle);

  /// No description provided for @contactsStartChat.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get contactsStartChat;

  /// No description provided for @contactsStartChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the chat'**
  String get contactsStartChatFailed;

  /// No description provided for @contactsEditNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get contactsEditNickname;

  /// No description provided for @contactsSaveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get contactsSaveNickname;

  /// No description provided for @contactsNicknameCaption.
  ///
  /// In en, this message translates to:
  /// **'Only you see this.'**
  String get contactsNicknameCaption;

  /// No description provided for @contactsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get contactsRemove;

  /// No description provided for @contactsRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed'**
  String contactsRemoved(String name);

  /// No description provided for @contactsRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the contact'**
  String get contactsRemoveFailed;

  /// No description provided for @contactsRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Contact {name}'**
  String contactsRowSemantics(String name);

  /// An example handle in the field's hint: lower-case Latin, as every handle.
  ///
  /// In en, this message translates to:
  /// **'alex'**
  String get contactsHandleHint;

  /// No description provided for @startDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get startDirectTitle;

  /// No description provided for @startDirectOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get startDirectOpening;

  /// An example handle in the field's hint: lower-case Latin, as every handle.
  ///
  /// In en, this message translates to:
  /// **'Name or handle'**
  String get startDirectHandleHint;

  /// No description provided for @startDirectHandleError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the chat. Check your connection.'**
  String get startDirectHandleError;

  /// No description provided for @startDirectChatWith.
  ///
  /// In en, this message translates to:
  /// **'Chat with @{handle}'**
  String startDirectChatWith(String handle);

  /// No description provided for @startDirectContactsHeader.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get startDirectContactsHeader;

  /// No description provided for @startGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get startGroupTitle;

  /// No description provided for @startGroupNameInput.
  ///
  /// In en, this message translates to:
  /// **'Group name (required)'**
  String get startGroupNameInput;

  /// No description provided for @startGroupDescriptionInput.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get startGroupDescriptionInput;

  /// No description provided for @startGroupMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String startGroupMembersCount(int count);

  /// No description provided for @startGroupMembersCaption.
  ///
  /// In en, this message translates to:
  /// **'You can\'t add members later.'**
  String get startGroupMembersCaption;

  /// No description provided for @startGroupMembersInput.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get startGroupMembersInput;

  /// No description provided for @startGroupCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get startGroupCreating;

  /// No description provided for @startGroupCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get startGroupCreateButton;

  /// No description provided for @startGroupNote.
  ///
  /// In en, this message translates to:
  /// **'The server can read the group name, description and member list.'**
  String get startGroupNote;

  /// Example handles in the field's hint, separated as the field expects.
  ///
  /// In en, this message translates to:
  /// **'Add a handle'**
  String get startGroupMembersHint;

  /// No description provided for @startGroupMembersError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the group. Check your connection and try again.'**
  String get startGroupMembersError;

  /// No description provided for @safetyNumbersTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumbersTitle;

  /// No description provided for @safetyNumbersLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get safetyNumbersLoadingTitle;

  /// No description provided for @safetyNumbersMarkedVerified.
  ///
  /// In en, this message translates to:
  /// **'Marked as verified'**
  String get safetyNumbersMarkedVerified;

  /// No description provided for @safetyNumbersRotateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Renew the keys?'**
  String get safetyNumbersRotateDialogTitle;

  /// No description provided for @safetyNumbersRotateDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Your next message starts new keys. Do this if someone may have had your phone or theirs.'**
  String get safetyNumbersRotateDialogBody;

  /// No description provided for @safetyNumbersCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get safetyNumbersCancel;

  /// No description provided for @safetyNumbersRotate.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get safetyNumbersRotate;

  /// No description provided for @safetyNumbersSessionRotated.
  ///
  /// In en, this message translates to:
  /// **'Keys renewed'**
  String get safetyNumbersSessionRotated;

  /// No description provided for @safetyNumbersNoSessionYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to renew yet. Send a message first.'**
  String get safetyNumbersNoSessionYet;

  /// No description provided for @safetyNumbersRotationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t renew the keys. Try again.'**
  String get safetyNumbersRotationFailed;

  /// No description provided for @safetyNumbersErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the safety number'**
  String get safetyNumbersErrorTitle;

  /// No description provided for @safetyNumbersRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get safetyNumbersRetry;

  /// No description provided for @safetyNumbersNoMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'No other members'**
  String get safetyNumbersNoMembersTitle;

  /// No description provided for @safetyNumbersUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get safetyNumbersUnverified;

  /// No description provided for @safetyNumbersVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get safetyNumbersVerified;

  /// No description provided for @safetyNumbersDetailBody.
  ///
  /// In en, this message translates to:
  /// **'Check these numbers match {name}\'s phone, in person or on a call.'**
  String safetyNumbersDetailBody(String name);

  /// No description provided for @safetyNumbersKeyChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get safetyNumbersKeyChangedTitle;

  /// No description provided for @safetyNumbersKeyChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'It changed since you verified it on {date}. Usually that means a new phone, but it can mean someone is posing as them.'**
  String safetyNumbersKeyChangedMessage(String date);

  /// No description provided for @safetyNumbersVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified {date}'**
  String safetyNumbersVerifiedOn(String date);

  /// No description provided for @safetyNumbersReVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify the new number'**
  String get safetyNumbersReVerify;

  /// No description provided for @safetyNumbersMarkVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark as verified'**
  String get safetyNumbersMarkVerified;

  /// No description provided for @safetyNumbersRotating.
  ///
  /// In en, this message translates to:
  /// **'Renewing…'**
  String get safetyNumbersRotating;

  /// No description provided for @safetyNumbersRotateButton.
  ///
  /// In en, this message translates to:
  /// **'Renew keys'**
  String get safetyNumbersRotateButton;

  /// No description provided for @safetyNumbersNewNumberHeader.
  ///
  /// In en, this message translates to:
  /// **'New safety number'**
  String get safetyNumbersNewNumberHeader;

  /// No description provided for @safetyNumbersCurrentNumberHeader.
  ///
  /// In en, this message translates to:
  /// **'Number before the change'**
  String get safetyNumbersCurrentNumberHeader;

  /// No description provided for @safetyNumbersNoPinTitle.
  ///
  /// In en, this message translates to:
  /// **'No safety number yet'**
  String get safetyNumbersNoPinTitle;

  /// No description provided for @safetyNumbersNoPinBody.
  ///
  /// In en, this message translates to:
  /// **'It appears after you exchange a message.'**
  String get safetyNumbersNoPinBody;

  /// No description provided for @safetyNumbersDirectoryMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The server lists a different key'**
  String get safetyNumbersDirectoryMismatchTitle;

  /// No description provided for @safetyNumbersDirectoryMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent to it unless you compare and accept it.'**
  String get safetyNumbersDirectoryMismatchBody;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'The server lists another device'**
  String get safetyNumbersDirectoryOtherDeviceTitle;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'This chat still sends to the device it knows. If your contact changed phones, compare numbers again.'**
  String get safetyNumbersDirectoryOtherDeviceBody;

  /// No description provided for @safetyNumbersPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Their safety number changed. Compare it before you accept it.'**
  String get safetyNumbersPendingBody;

  /// No description provided for @safetyNumbersAcceptNewKey.
  ///
  /// In en, this message translates to:
  /// **'Accept new number'**
  String get safetyNumbersAcceptNewKey;

  /// No description provided for @safetyNumbersKeepCurrentKey.
  ///
  /// In en, this message translates to:
  /// **'Keep the old one'**
  String get safetyNumbersKeepCurrentKey;

  /// No description provided for @safetyNumbersScanAction.
  ///
  /// In en, this message translates to:
  /// **'Paste their code'**
  String get safetyNumbersScanAction;

  /// No description provided for @safetyNumbersCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy my code'**
  String get safetyNumbersCopyCode;

  /// No description provided for @safetyNumbersCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get safetyNumbersCodeCopied;

  /// No description provided for @safetyNumbersScanFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Their code'**
  String get safetyNumbersScanFieldLabel;

  /// No description provided for @safetyNumbersScanVerify.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get safetyNumbersScanVerify;

  /// No description provided for @safetyNumbersScanMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'These don\'t match'**
  String get safetyNumbersScanMismatchTitle;

  /// No description provided for @safetyNumbersScanMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'Someone may be in between. Compare again in person before you verify.'**
  String get safetyNumbersScanMismatchBody;

  /// No description provided for @safetyNumbersScanInvalid.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a safety code.'**
  String get safetyNumbersScanInvalid;

  /// No description provided for @safetyNumbersScanUnsupported.
  ///
  /// In en, this message translates to:
  /// **'That code is from a version this app doesn\'t support.'**
  String get safetyNumbersScanUnsupported;

  /// No description provided for @safetyNumbersReverifyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify the new number?'**
  String get safetyNumbersReverifyDialogTitle;

  /// No description provided for @safetyNumbersReverifyDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Do this only after comparing it with {peer} in person or on a call.'**
  String safetyNumbersReverifyDialogBody(String peer);

  /// No description provided for @safetyNumbersReverifyAffirm.
  ///
  /// In en, this message translates to:
  /// **'It matches {peer}\'s phone'**
  String safetyNumbersReverifyAffirm(String peer);

  /// No description provided for @safetyNumbersReverifyAccept.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get safetyNumbersReverifyAccept;

  /// No description provided for @safetyNumbersChangeReplaced.
  ///
  /// In en, this message translates to:
  /// **'It changed again while you were looking. Compare the newer number.'**
  String get safetyNumbersChangeReplaced;

  /// No description provided for @safetyNumbersChangedElsewhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Changed in a group you share'**
  String get safetyNumbersChangedElsewhereTitle;

  /// No description provided for @safetyNumbersChangedElsewhereBody.
  ///
  /// In en, this message translates to:
  /// **'Review it there first.'**
  String get safetyNumbersChangedElsewhereBody;

  /// No description provided for @safetyNumbersReviewChange.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get safetyNumbersReviewChange;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileNicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Name saved'**
  String get profileNicknameSaved;

  /// No description provided for @profileHandleCopied.
  ///
  /// In en, this message translates to:
  /// **'Handle copied'**
  String get profileHandleCopied;

  /// No description provided for @profileNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get profileNicknameHint;

  /// No description provided for @profileSaveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileSaveNickname;

  /// No description provided for @profileNicknameFooter.
  ///
  /// In en, this message translates to:
  /// **'Only you see your name.'**
  String get profileNicknameFooter;

  /// No description provided for @profileNicknameHeader.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileNicknameHeader;

  /// No description provided for @deviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to a new phone'**
  String get deviceTransferTitle;

  /// No description provided for @deviceTransferNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Move from another phone'**
  String get deviceTransferNewTitle;

  /// No description provided for @deviceTransferPayloadHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the code from your old phone'**
  String get deviceTransferPayloadHint;

  /// No description provided for @deviceTransferPayloadCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get deviceTransferPayloadCopied;

  /// No description provided for @deviceTransferReturnToConversations.
  ///
  /// In en, this message translates to:
  /// **'Back to chats'**
  String get deviceTransferReturnToConversations;

  /// No description provided for @deviceTransferPayloadInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t valid.'**
  String get deviceTransferPayloadInvalid;

  /// No description provided for @deviceTransferImportFirst.
  ///
  /// In en, this message translates to:
  /// **'Paste the code first.'**
  String get deviceTransferImportFirst;

  /// No description provided for @deviceTransferClaimFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t set up this phone. Try again.'**
  String get deviceTransferClaimFailed;

  /// No description provided for @deviceTransferCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'This code expired. Get a new one on your old phone.'**
  String get deviceTransferCodeExpired;

  /// No description provided for @deviceTransferFinishStartedFirst.
  ///
  /// In en, this message translates to:
  /// **'Finish the move you already started before using a new code.'**
  String get deviceTransferFinishStartedFirst;

  /// No description provided for @deviceTransferComplete.
  ///
  /// In en, this message translates to:
  /// **'Your account is on this phone now.'**
  String get deviceTransferComplete;

  /// No description provided for @deviceTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t move the account. Try again.'**
  String get deviceTransferFailed;

  /// No description provided for @deviceTransferOldIssueExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'This code expired. Get a new one.'**
  String get deviceTransferOldIssueExpiredBody;

  /// No description provided for @deviceTransferOldHandTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on your new phone'**
  String get deviceTransferOldHandTitle;

  /// No description provided for @deviceTransferOldStep1.
  ///
  /// In en, this message translates to:
  /// **'1. On your new phone, install Veil and tap Move from another phone.'**
  String get deviceTransferOldStep1;

  /// No description provided for @deviceTransferOldStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Enter the code this phone shows.'**
  String get deviceTransferOldStep2;

  /// No description provided for @deviceTransferOldStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Approve the new phone here.'**
  String get deviceTransferOldStep3;

  /// No description provided for @deviceTransferNewCodeExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'This code expired. Get a new one on your old phone.'**
  String get deviceTransferNewCodeExpiredBody;

  /// No description provided for @deviceTransferNewCodeChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get deviceTransferNewCodeChange;

  /// No description provided for @deviceTransferNewCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve on your old phone'**
  String get deviceTransferNewCompleteTitle;

  /// No description provided for @deviceTransferNewCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on your old phone.'**
  String get deviceTransferNewCompleteBody;

  /// No description provided for @deviceTransferIssuingToken.
  ///
  /// In en, this message translates to:
  /// **'Getting a code…'**
  String get deviceTransferIssuingToken;

  /// No description provided for @deviceTransferIssueToken.
  ///
  /// In en, this message translates to:
  /// **'Get code'**
  String get deviceTransferIssueToken;

  /// No description provided for @deviceTransferClaimInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Code from your new phone'**
  String get deviceTransferClaimInputLabel;

  /// No description provided for @deviceTransferApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move your account to the new phone?'**
  String get deviceTransferApproveTitle;

  /// No description provided for @deviceTransferApproveBody.
  ///
  /// In en, this message translates to:
  /// **'Check that your new phone shows {fingerprint}. This phone will then be signed out, and your messages won\'t move.'**
  String deviceTransferApproveBody(String fingerprint);

  /// No description provided for @deviceTransferApproveAction.
  ///
  /// In en, this message translates to:
  /// **'Move account'**
  String get deviceTransferApproveAction;

  /// No description provided for @deviceTransferApproveClaim.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get deviceTransferApproveClaim;

  /// No description provided for @deviceTransferCopyPayload.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get deviceTransferCopyPayload;

  /// No description provided for @deviceTransferStatusNeedsApi.
  ///
  /// In en, this message translates to:
  /// **'No server is configured, so nothing can be moved.'**
  String get deviceTransferStatusNeedsApi;

  /// No description provided for @deviceTransferStatusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Get a code first.'**
  String get deviceTransferStatusNotStarted;

  /// No description provided for @deviceTransferStatusClaimCodeMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from your new phone first.'**
  String get deviceTransferStatusClaimCodeMissing;

  /// No description provided for @deviceTransferStatusClaimNotWaiting.
  ///
  /// In en, this message translates to:
  /// **'No phone with code {claimId} is waiting.'**
  String deviceTransferStatusClaimNotWaiting(String claimId);

  /// No description provided for @deviceTransferStatusClaimApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved. Finish on your new phone.'**
  String get deviceTransferStatusClaimApproved;

  /// No description provided for @deviceTransferPayloadInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer code'**
  String get deviceTransferPayloadInputLabel;

  /// No description provided for @deviceTransferDeviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceTransferDeviceNameLabel;

  /// No description provided for @deviceTransferClaimFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Key fingerprint {fingerprint}'**
  String deviceTransferClaimFingerprint(String fingerprint);

  /// No description provided for @deviceTransferFingerprintUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get deviceTransferFingerprintUnavailable;

  /// No description provided for @deviceTransferExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {when}'**
  String deviceTransferExpires(String when);

  /// No description provided for @deviceTransferRegisteringClaim.
  ///
  /// In en, this message translates to:
  /// **'Setting up…'**
  String get deviceTransferRegisteringClaim;

  /// No description provided for @deviceTransferCompleting.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get deviceTransferCompleting;

  /// No description provided for @deviceTransferCompleteOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get deviceTransferCompleteOnDevice;

  /// No description provided for @deviceTransferExpiryNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get deviceTransferExpiryNow;

  /// No description provided for @deviceTransferExpiryInSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{in 1 second} other{in {seconds} seconds}}'**
  String deviceTransferExpiryInSeconds(int seconds);

  /// No description provided for @deviceTransferExpiryInMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{in 1 minute} other{in {minutes} minutes}}'**
  String deviceTransferExpiryInMinutes(int minutes);

  /// No description provided for @themeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeModeTitle;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeModeSystem;

  /// No description provided for @securityStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get securityStatusBlocked;

  /// No description provided for @securityStatusAppPreview.
  ///
  /// In en, this message translates to:
  /// **'App switcher preview'**
  String get securityStatusAppPreview;

  /// No description provided for @securityStatusAppPreviewProtected.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get securityStatusAppPreviewProtected;

  /// No description provided for @securityStatusAppPreviewPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get securityStatusAppPreviewPartial;

  /// No description provided for @securityStatusScreenCapture.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get securityStatusScreenCapture;

  /// No description provided for @securityStatusScreenCaptureNotBlocked.
  ///
  /// In en, this message translates to:
  /// **'Not blocked'**
  String get securityStatusScreenCaptureNotBlocked;

  /// No description provided for @securityStatusPushDelivery.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get securityStatusPushDelivery;

  /// No description provided for @securityStatusPushDeliveryOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get securityStatusPushDeliveryOn;

  /// No description provided for @securityNotificationsWhileOpen.
  ///
  /// In en, this message translates to:
  /// **'Only while Veil is open'**
  String get securityNotificationsWhileOpen;

  /// No description provided for @chatMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get chatMenuTooltip;

  /// No description provided for @muteTitle.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteTitle;

  /// No description provided for @muteUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get muteUnmute;

  /// No description provided for @muteOneHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get muteOneHour;

  /// No description provided for @muteEightHours.
  ///
  /// In en, this message translates to:
  /// **'8 hours'**
  String get muteEightHours;

  /// No description provided for @muteOneWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get muteOneWeek;

  /// No description provided for @muteAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get muteAlways;

  /// No description provided for @muteDoneFor.
  ///
  /// In en, this message translates to:
  /// **'Muted for {duration}'**
  String muteDoneFor(String duration);

  /// No description provided for @muteDoneAlways.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muteDoneAlways;

  /// No description provided for @muteUndone.
  ///
  /// In en, this message translates to:
  /// **'Unmuted'**
  String get muteUndone;

  /// No description provided for @muteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change notifications'**
  String get muteFailed;

  /// No description provided for @conversationsMutedSemantics.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get conversationsMutedSemantics;

  /// No description provided for @reportAction.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportAction;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report @{handle}'**
  String reportTitle(String handle);

  /// No description provided for @reportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Report @{handle}?'**
  String reportConfirmTitle(String handle);

  /// No description provided for @reportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonImpersonation.
  ///
  /// In en, this message translates to:
  /// **'Pretending to be someone'**
  String get reportReasonImpersonation;

  /// No description provided for @reportReasonCsam.
  ///
  /// In en, this message translates to:
  /// **'Child sexual abuse'**
  String get reportReasonCsam;

  /// No description provided for @reportReasonViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence or threats'**
  String get reportReasonViolence;

  /// No description provided for @reportReasonScam.
  ///
  /// In en, this message translates to:
  /// **'Scam or fraud'**
  String get reportReasonScam;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get reportReasonOther;

  /// No description provided for @reportAlsoBlock.
  ///
  /// In en, this message translates to:
  /// **'Also block @{handle}'**
  String reportAlsoBlock(String handle);

  /// No description provided for @reportFooterMessage.
  ///
  /// In en, this message translates to:
  /// **'We get both accounts, the reason and which message, but not what it says. They won\'t be told.'**
  String get reportFooterMessage;

  /// No description provided for @reportFooterChat.
  ///
  /// In en, this message translates to:
  /// **'We get both accounts, the reason and which chat, but no messages. They won\'t be told.'**
  String get reportFooterChat;

  /// No description provided for @reportFooterAccount.
  ///
  /// In en, this message translates to:
  /// **'We get both accounts and the reason, but no messages. They won\'t be told.'**
  String get reportFooterAccount;

  /// No description provided for @reportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get reportSent;

  /// No description provided for @reportSentAndBlocked.
  ///
  /// In en, this message translates to:
  /// **'Report sent and @{handle} blocked'**
  String reportSentAndBlocked(String handle);

  /// No description provided for @reportSentBlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Report sent, but @{handle} couldn\'t be blocked'**
  String reportSentBlockFailed(String handle);

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the report'**
  String get reportFailed;

  /// No description provided for @blockAction.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockAction;

  /// No description provided for @unblockAction.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockAction;

  /// No description provided for @blockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block @{handle}?'**
  String blockConfirmTitle(String handle);

  /// No description provided for @blockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Their messages to you will show as not sent, and they can\'t add you to groups. They won\'t be told, and in groups you share, you\'ll still see each other\'s messages.'**
  String get blockConfirmBody;

  /// No description provided for @blockDone.
  ///
  /// In en, this message translates to:
  /// **'@{handle} blocked'**
  String blockDone(String handle);

  /// No description provided for @blockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t block @{handle}'**
  String blockFailed(String handle);

  /// No description provided for @unblockDone.
  ///
  /// In en, this message translates to:
  /// **'@{handle} unblocked'**
  String unblockDone(String handle);

  /// No description provided for @unblockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unblock @{handle}'**
  String unblockFailed(String handle);

  /// No description provided for @blockedComposerLine.
  ///
  /// In en, this message translates to:
  /// **'You blocked @{handle}.'**
  String blockedComposerLine(String handle);

  /// No description provided for @blockedAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked accounts'**
  String get blockedAccountsTitle;

  /// No description provided for @blockedAccountsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No blocked accounts'**
  String get blockedAccountsEmptyTitle;

  /// No description provided for @blockedAccountsLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load blocked accounts'**
  String get blockedAccountsLoadFailedTitle;

  /// No description provided for @safetyAccountNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find @{handle}'**
  String safetyAccountNotFound(String handle);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
