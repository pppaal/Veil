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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// No description provided for @commonIUnderstand.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get commonIUnderstand;

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

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No recovery'**
  String get pillNoRecovery;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get pillSessionLocked;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Preview hidden'**
  String get pillPreviewObscured;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get privacyShieldEyebrow;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Veil'**
  String get privacyShieldTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get privacyShieldBody;

  /// No description provided for @appLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Checking the app lock'**
  String get appLockLoadingTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get appLockLoadingBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get appLockHeroEyebrow;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Veil is locked'**
  String get appLockHeroTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your PIN and biometrics are checked on this phone only.'**
  String get appLockHeroBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'This phone only'**
  String get appLockPillLocalOnly;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No remote reset'**
  String get appLockPillNoRemoteReset;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'If you forget your PIN, wipe this device and start over.'**
  String get appLockNoRecoveryBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Can\'t unlock on this device'**
  String get appLockCompromisedTitle;

  /// No description provided for @appLockCompromisedBody.
  ///
  /// In en, this message translates to:
  /// **'This device appears to be rooted or jailbroken, so the app won\'t unlock here.'**
  String get appLockCompromisedBody;

  /// No description provided for @appLockCompromisedReasons.
  ///
  /// In en, this message translates to:
  /// **'This device appears to be rooted or jailbroken. {reasons}'**
  String appLockCompromisedReasons(String reasons);

  /// No description provided for @appLockLockoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong PINs'**
  String get appLockLockoutTitle;

  /// No description provided for @appLockLockoutBody.
  ///
  /// In en, this message translates to:
  /// **'PIN entry is paused. {retry}'**
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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get appLockMetricConfigured;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get appLockMetricRequired;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get appLockMetricBiometrics;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get appLockMetricAvailable;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get appLockMetricUnavailable;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appLockMetricPreview;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get appLockMetricProtected;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get appLockMetricShielded;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'PIN set'**
  String get appLockPillPinConfigured;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'PIN required'**
  String get appLockPillPinRequired;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Biometrics available'**
  String get appLockPillBiometricsAvailable;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Biometrics unavailable'**
  String get appLockPillBiometricsUnavailable;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Screenshots blocked'**
  String get appLockPillCaptureBlocked;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Preview hidden'**
  String get appLockPillPreviewShield;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your PIN is checked on this phone only. If you forget it, wipe this device and start over.'**
  String get appLockCaptionSet;

  /// No description provided for @appLockCaptionUnlock.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is checked on this phone only.'**
  String get appLockCaptionUnlock;

  /// No description provided for @appLockFieldSetPin.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get appLockFieldSetPin;

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

  /// No description provided for @appLockStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock status'**
  String get appLockStatusTitle;

  /// No description provided for @appLockStatusUnlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get appLockStatusUnlockedTitle;

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
  /// **'{count, plural, =1{Wrong PIN. 1 attempt left.} other{Wrong PIN. {count} attempts left.}}'**
  String appLockStatusPinMismatchAttempts(int count);

  /// No description provided for @appLockStatusLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again later.'**
  String get appLockStatusLocked;

  /// No description provided for @appLockStatusCompromised.
  ///
  /// In en, this message translates to:
  /// **'This device can\'t be unlocked.'**
  String get appLockStatusCompromised;

  /// No description provided for @appLockUseBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get appLockUseBiometrics;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get appLockSetAndUnlock;

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
  /// **'Your PIN is checked on this phone only. If you forget it, wipe this device and start over.'**
  String get appLockSetupFooter;

  /// No description provided for @appLockTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get appLockTurnOn;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get splashEyebrow;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get splashBody;

  /// No description provided for @splashErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start'**
  String get splashErrorTitle;

  /// No description provided for @splashPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get splashPreparingTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get splashPreparingBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get onboardingWarnEyebrow;

  /// No description provided for @onboardingWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get onboardingWarnTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get onboardingWarnBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No backup'**
  String get onboardingWarnDestructiveTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'If you lose this phone, you lose this account and its messages. There is no backup and no way to recover it.'**
  String get onboardingWarnDestructiveBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get onboardingWarnIdentityTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your account lives on this phone.'**
  String get onboardingWarnIdentityLine1;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your private keys stay on this phone.'**
  String get onboardingWarnIdentityLine2;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'There is no password, so there is nothing to reset.'**
  String get onboardingWarnIdentityLine3;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Moving to a new phone'**
  String get onboardingWarnTransferTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'To move to a new phone you need the old one.'**
  String get onboardingWarnTransferLine1;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'The old phone approves the move.'**
  String get onboardingWarnTransferLine2;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Your message history stays on the old phone.'**
  String get onboardingWarnTransferLine3;

  /// No description provided for @onboardingWarnAgreeCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I understand there is no way to recover a lost account'**
  String get onboardingWarnAgreeCheckbox;

  /// No description provided for @onboardingWarnLine1.
  ///
  /// In en, this message translates to:
  /// **'Your account lives on this phone.'**
  String get onboardingWarnLine1;

  /// No description provided for @onboardingWarnLine2.
  ///
  /// In en, this message translates to:
  /// **'If you lose this phone, you lose this account and its messages. There is no backup and no way to recover it.'**
  String get onboardingWarnLine2;

  /// No description provided for @onboardingWarnLine3.
  ///
  /// In en, this message translates to:
  /// **'To move to a new phone you need the old one.'**
  String get onboardingWarnLine3;

  /// No description provided for @privacyConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get privacyConsentTitle;

  /// No description provided for @privacyConsentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read this before you continue'**
  String get privacyConsentSubtitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'What the service stores, why, and for how long, as Korea\'s PIPA requires.'**
  String get privacyConsentHeroBody;

  /// No description provided for @privacyConsentAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree to the collection and use of personal information as described above. (Required)'**
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

  /// No description provided for @authCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get authCreateEyebrow;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get authCreateHeroTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authCreateRestoreTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'You can move it here from your old phone. The old phone approves the move.'**
  String get authCreateRestoreBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authCreateFieldLabel;

  /// No description provided for @authCreateFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Shown only on this phone. Others see your handle.'**
  String get authCreateFieldCaption;

  /// No description provided for @authCreateDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authCreateDisplayName;

  /// No description provided for @authCreateDisplayHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get authCreateDisplayHint;

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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get authHandleEyebrow;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get authHandleHeroTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'People find you by this handle. Veil has no phone number, email or contact upload.'**
  String get authHandleHeroBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get authHandleFieldLabel;

  /// No description provided for @authHandleFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letters, digits and underscores. It can\'t be changed later.'**
  String get authHandleFieldCaption;

  /// No description provided for @authHandleFindCaption.
  ///
  /// In en, this message translates to:
  /// **'People find you by this handle. Veil has no phone number, email or contact upload.'**
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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Creating your account'**
  String get authHandleBindingSection;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Create your keys'**
  String get authHandleStep1Title;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Keys are created on this phone and stay here.'**
  String get authHandleStep1Body;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Register the handle'**
  String get authHandleStep2Title;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Only your public keys and handle go to the server.'**
  String get authHandleStep2Body;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Check this phone'**
  String get authHandleStep3Title;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'The server sends a one-time challenge to this phone.'**
  String get authHandleStep3Body;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authHandleStep4Title;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'This phone answers it and your session starts.'**
  String get authHandleStep4Body;

  /// No description provided for @authHandleFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the account'**
  String get authHandleFailedTitle;

  /// No description provided for @authHandleBindCta.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authHandleBindCta;

  /// No description provided for @authStageGeneratingKeys.
  ///
  /// In en, this message translates to:
  /// **'Creating keys…'**
  String get authStageGeneratingKeys;

  /// No description provided for @authStageRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering handle…'**
  String get authStageRegistering;

  /// No description provided for @authStageRequestingChallenge.
  ///
  /// In en, this message translates to:
  /// **'Checking this phone…'**
  String get authStageRequestingChallenge;

  /// No description provided for @authStageVerifying.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get authStageVerifying;

  /// No description provided for @authStageComplete.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get authStageComplete;

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

  /// No description provided for @settingsProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfileTitle;

  /// No description provided for @settingsLoadingDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'Loading devices…'**
  String get settingsLoadingDeviceGraph;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get settingsLoadingDeviceGraphBody;

  /// No description provided for @settingsDeviceGraphUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load devices'**
  String get settingsDeviceGraphUnavailable;

  /// No description provided for @settingsNoTrustedDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices listed'**
  String get settingsNoTrustedDevices;

  /// No description provided for @settingsAppLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLockTitle;

  /// No description provided for @settingsAppLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'PIN and biometrics'**
  String get settingsAppLockSubtitle;

  /// No description provided for @settingsDeviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to a new phone'**
  String get settingsDeviceTransferTitle;

  /// No description provided for @settingsDeviceTransferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You need both phones'**
  String get settingsDeviceTransferSubtitle;

  /// No description provided for @settingsSecurityStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurityStatusTitle;

  /// No description provided for @settingsSecurityStatusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encryption, app lock and connection'**
  String get settingsSecurityStatusSubtitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No recovery'**
  String get settingsNoRecoveryPath;

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

  /// No description provided for @settingsReadReceiptsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, people don\'t see when you\'ve read their messages, and you don\'t see when they\'ve read yours.'**
  String get settingsReadReceiptsSubtitle;

  /// No description provided for @settingsTypingIndicatorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send typing indicators'**
  String get settingsTypingIndicatorsTitle;

  /// No description provided for @settingsTypingIndicatorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lets people see when you\'re typing. It\'s off until you turn it on.'**
  String get settingsTypingIndicatorsSubtitle;

  /// No description provided for @settingsLockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get settingsLockNow;

  /// No description provided for @settingsWipeLocal.
  ///
  /// In en, this message translates to:
  /// **'Wipe this device'**
  String get settingsWipeLocal;

  /// No description provided for @settingsWipeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Wipe this device?'**
  String get settingsWipeConfirmTitle;

  /// No description provided for @settingsRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this device'**
  String get settingsRevokeTitle;

  /// No description provided for @settingsRevokeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this device?'**
  String get settingsRevokeConfirmTitle;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsLogout;

  /// No description provided for @settingsDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes your account, messages and contacts from this phone and the server. There is no backup, so this can\'t be undone.'**
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

  /// No description provided for @settingsDeviceGraphLoadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your devices. Check your connection and try again.'**
  String get settingsDeviceGraphLoadFailedBody;

  /// No description provided for @settingsNoTrustedDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'The server lists no devices for this account yet.'**
  String get settingsNoTrustedDevicesBody;

  /// No description provided for @settingsRefreshDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsRefreshDeviceGraph;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsSectionDevices;

  /// No description provided for @settingsSectionTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingsSectionTools;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionIrreversible;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevicesTitle;

  /// No description provided for @settingsDevicesRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device} other{{count} devices}}'**
  String settingsDevicesRowCount(int count);

  /// No description provided for @settingsDevicesTrustedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device} other{{count} devices}}'**
  String settingsDevicesTrustedCount(int count);

  /// No description provided for @settingsDevicesTrustedWithStale.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device} other{{count} devices}} ({stale} stale)'**
  String settingsDevicesTrustedWithStale(int count, int stale);

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'There is no backup, no password reset and no way for anyone, including us, to recover an account.'**
  String get settingsDestructiveNoticeBody;

  /// No description provided for @settingsLockNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lock the app right away'**
  String get settingsLockNowSubtitle;

  /// No description provided for @settingsWipeLocalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes your messages, keys, PIN and settings from this phone. The server is not told.'**
  String get settingsWipeLocalSubtitle;

  /// No description provided for @settingsWipeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes your messages, keys, PIN and settings from this phone. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.'**
  String get settingsWipeConfirmBody;

  /// No description provided for @settingsWipeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get settingsWipeConfirmAction;

  /// No description provided for @settingsRevokeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Signs this device out on the server and wipes it.'**
  String get settingsRevokeSubtitle;

  /// No description provided for @settingsRevokeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This signs this device out on the server and wipes it. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.'**
  String get settingsRevokeConfirmBody;

  /// No description provided for @settingsRevokeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get settingsRevokeConfirmAction;

  /// No description provided for @settingsLogoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Erases your keys and messages on this phone. To use the account here again, move it from another phone.'**
  String get settingsLogoutSubtitle;

  /// No description provided for @settingsLogoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this phone?'**
  String get settingsLogoutConfirmTitle;

  /// No description provided for @settingsLogoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This erases your keys and messages on this phone. If this is your only device, the account and its messages are gone. There is no backup and no way to recover them.'**
  String get settingsLogoutConfirmBody;

  /// No description provided for @settingsLogoutConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsLogoutConfirmPhrase;

  /// No description provided for @settingsWipeConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get settingsWipeConfirmPhrase;

  /// No description provided for @settingsRevokeConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get settingsRevokeConfirmPhrase;

  /// No description provided for @settingsDeleteAccountConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsDeleteAccountConfirmPhrase;

  /// No description provided for @settingsTypePhraseToContinue.
  ///
  /// In en, this message translates to:
  /// **'Type \"{phrase}\" to continue.'**
  String settingsTypePhraseToContinue(String phrase);

  /// No description provided for @settingsRevokeListedTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke {deviceName}?'**
  String settingsRevokeListedTitle(String deviceName);

  /// No description provided for @settingsRevokeListedBody.
  ///
  /// In en, this message translates to:
  /// **'{deviceName} will be signed out and can no longer use this account.'**
  String settingsRevokeListedBody(String deviceName);

  /// No description provided for @settingsRevokeListedDone.
  ///
  /// In en, this message translates to:
  /// **'{deviceName} was revoked.'**
  String settingsRevokeListedDone(String deviceName);

  /// No description provided for @settingsRevokeListedFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t revoke the device. Try again.'**
  String get settingsRevokeListedFailed;

  /// No description provided for @settingsDeviceStateCurrent.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get settingsDeviceStateCurrent;

  /// No description provided for @settingsDeviceStatePreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred'**
  String get settingsDeviceStatePreferred;

  /// No description provided for @settingsDeviceStateTrusted.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsDeviceStateTrusted;

  /// No description provided for @settingsDeviceStateStale.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get settingsDeviceStateStale;

  /// No description provided for @settingsDeviceStateRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get settingsDeviceStateRevoked;

  /// No description provided for @settingsDeviceRevokeAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get settingsDeviceRevokeAction;

  /// No description provided for @settingsDeviceCreated.
  ///
  /// In en, this message translates to:
  /// **'Added {when}'**
  String settingsDeviceCreated(String when);

  /// No description provided for @settingsDeviceSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {when}'**
  String settingsDeviceSeen(String when);

  /// No description provided for @settingsDeviceSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {when}'**
  String settingsDeviceSynced(String when);

  /// No description provided for @settingsDeviceActivity.
  ///
  /// In en, this message translates to:
  /// **'Last active {when}'**
  String settingsDeviceActivity(String when);

  /// No description provided for @settingsDeviceTrustedAt.
  ///
  /// In en, this message translates to:
  /// **'Approved {when}'**
  String settingsDeviceTrustedAt(String when);

  /// No description provided for @settingsDeviceJoinedFrom.
  ///
  /// In en, this message translates to:
  /// **'Approved by {device}'**
  String settingsDeviceJoinedFrom(String device);

  /// No description provided for @settingsDeviceRevokedAt.
  ///
  /// In en, this message translates to:
  /// **'Revoked {when}'**
  String settingsDeviceRevokedAt(String when);

  /// No description provided for @settingsDeviceNoteCurrent.
  ///
  /// In en, this message translates to:
  /// **'This is the phone you\'re using.'**
  String get settingsDeviceNoteCurrent;

  /// No description provided for @settingsDeviceNotePreferred.
  ///
  /// In en, this message translates to:
  /// **'Messages go to this device first.'**
  String get settingsDeviceNotePreferred;

  /// No description provided for @settingsDeviceNoteTrusted.
  ///
  /// In en, this message translates to:
  /// **'This device can still use the account.'**
  String get settingsDeviceNoteTrusted;

  /// No description provided for @settingsDeviceNoteStale.
  ///
  /// In en, this message translates to:
  /// **'Not seen for 30 days. Revoke it if you no longer use it.'**
  String get settingsDeviceNoteStale;

  /// No description provided for @settingsDeviceNoteRevoked.
  ///
  /// In en, this message translates to:
  /// **'This device was signed out and can\'t use the account.'**
  String get settingsDeviceNoteRevoked;

  /// No description provided for @settingsGraphStaleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} stale'**
  String settingsGraphStaleCount(int count);

  /// No description provided for @settingsGraphRevokedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} revoked'**
  String settingsGraphRevokedCount(int count);

  /// No description provided for @settingsGraphRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity {when}'**
  String settingsGraphRecentActivity(String when);

  /// No description provided for @settingsGraphPreferredDiffersTitle.
  ///
  /// In en, this message translates to:
  /// **'Another device is preferred'**
  String get settingsGraphPreferredDiffersTitle;

  /// No description provided for @settingsGraphPreferredDiffersBody.
  ///
  /// In en, this message translates to:
  /// **'Messages go to {preferred} first. {current} can still use the account.'**
  String settingsGraphPreferredDiffersBody(String preferred, String current);

  /// No description provided for @settingsGraphStaleTitle.
  ///
  /// In en, this message translates to:
  /// **'A device hasn\'t been seen for 30 days'**
  String get settingsGraphStaleTitle;

  /// No description provided for @settingsGraphStaleBody.
  ///
  /// In en, this message translates to:
  /// **'Stale devices can still use this account. Revoke the ones you no longer use.'**
  String get settingsGraphStaleBody;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Messages are end-to-end encrypted.'**
  String get chatEmptyBody;

  /// No description provided for @chatEmptyEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Messages are end-to-end encrypted.'**
  String get chatEmptyEncrypted;

  /// No description provided for @chatEmptyVerifyAction.
  ///
  /// In en, this message translates to:
  /// **'Compare safety numbers'**
  String get chatEmptyVerifyAction;

  /// No description provided for @chatLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load messages'**
  String get chatLoadFailedTitle;

  /// No description provided for @chatLoadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get chatLoadFailedBody;

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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get chatLoadingBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Chat not found'**
  String get chatConversationNotFound;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get chatRelockTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Unlock the app to continue.'**
  String get chatRelockBody;

  /// No description provided for @chatTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitleFallback;

  /// No description provided for @chatSubtitleOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get chatSubtitleOnline;

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

  /// No description provided for @chatSearchMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matches} =1{1 match} other{{count} matches}}'**
  String chatSearchMatchCount(int count);

  /// No description provided for @chatSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get chatSearchSearching;

  /// No description provided for @chatBannerConversationIssue.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get chatBannerConversationIssue;

  /// No description provided for @chatBannerRelayReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get chatBannerRelayReconnecting;

  /// No description provided for @chatBannerDeliveryStalled.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send'**
  String get chatBannerDeliveryStalled;

  /// No description provided for @chatBannerQueuedLocally.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get chatBannerQueuedLocally;

  /// No description provided for @chatBannerFailedSends.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message wasn\'t sent.} other{{count} messages weren\'t sent.}}'**
  String chatBannerFailedSends(int count);

  /// No description provided for @chatBannerUploadingAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment is} other{{count} attachments are}} being encrypted and uploaded.'**
  String chatBannerUploadingAttachments(int count);

  /// No description provided for @chatBannerQueuedMessages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message is} other{{count} messages are}} waiting to be sent.'**
  String chatBannerQueuedMessages(int count);

  /// No description provided for @chatRetryFailedSendsAction.
  ///
  /// In en, this message translates to:
  /// **'Retry now'**
  String get chatRetryFailedSendsAction;

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
  /// **'No messages found'**
  String get chatSearchEmptyTitle;

  /// No description provided for @chatSearchEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Only messages on this phone are searched.'**
  String get chatSearchEmptyBody;

  /// No description provided for @chatTtlSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get chatTtlSheetTitle;

  /// No description provided for @chatTtlOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get chatTtlOff;

  /// No description provided for @chatTtlOffCaption.
  ///
  /// In en, this message translates to:
  /// **'Messages don\'t disappear.'**
  String get chatTtlOffCaption;

  /// No description provided for @chatTtl10s.
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get chatTtl10s;

  /// No description provided for @chatTtl10sCaption.
  ///
  /// In en, this message translates to:
  /// **'Gone 10 seconds after it\'s sent.'**
  String get chatTtl10sCaption;

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

  /// No description provided for @chatTtl1dCaption.
  ///
  /// In en, this message translates to:
  /// **'Gone a day after it\'s sent.'**
  String get chatTtl1dCaption;

  /// No description provided for @chatTtlCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get chatTtlCustom;

  /// No description provided for @chatTtlDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get chatTtlDisabledLabel;

  /// No description provided for @chatAttachmentTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'File not downloaded'**
  String get chatAttachmentTicketTitle;

  /// No description provided for @chatAttachmentTicketBody.
  ///
  /// In en, this message translates to:
  /// **'The server would send this file, but this version can\'t download or open it yet.\n\n{summary}'**
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

  /// No description provided for @chatAttachmentEncryptedImage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted image'**
  String get chatAttachmentEncryptedImage;

  /// No description provided for @chatAttachmentEncryptedVideo.
  ///
  /// In en, this message translates to:
  /// **'Encrypted video'**
  String get chatAttachmentEncryptedVideo;

  /// No description provided for @chatAttachmentEncryptedAudio.
  ///
  /// In en, this message translates to:
  /// **'Encrypted audio'**
  String get chatAttachmentEncryptedAudio;

  /// No description provided for @chatAttachmentEncryptedDocument.
  ///
  /// In en, this message translates to:
  /// **'Encrypted document'**
  String get chatAttachmentEncryptedDocument;

  /// No description provided for @chatAttachmentEncryptedFile.
  ///
  /// In en, this message translates to:
  /// **'Encrypted file'**
  String get chatAttachmentEncryptedFile;

  /// No description provided for @chatAttachmentStateBanner.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get chatAttachmentStateBanner;

  /// No description provided for @chatAttachmentCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'This version can\'t open attachments.'**
  String get chatAttachmentCannotOpen;

  /// No description provided for @reactionsMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More reactions'**
  String get reactionsMoreTooltip;

  /// No description provided for @chatScreenshotToast.
  ///
  /// In en, this message translates to:
  /// **'You took a screenshot. Screenshots can\'t be blocked on this phone, so a notice is being sent to the other person.'**
  String get chatScreenshotToast;

  /// No description provided for @chatScreenshotSystemNotice.
  ///
  /// In en, this message translates to:
  /// **'Someone in this chat took a screenshot.'**
  String get chatScreenshotSystemNotice;

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
  /// **'Waiting for the sender\'s key'**
  String get chatDecryptAwaitingKey;

  /// No description provided for @chatDecryptSessionMissing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a secure session'**
  String get chatDecryptSessionMissing;

  /// No description provided for @chatDecryptIdentityRejected.
  ///
  /// In en, this message translates to:
  /// **'Held back: the sender\'s safety number changed'**
  String get chatDecryptIdentityRejected;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Sent from an older version; not verified'**
  String get chatLegacyUnverifiedBadge;

  /// No description provided for @chatLegacySenderLine.
  ///
  /// In en, this message translates to:
  /// **'Sent from an older version; not verified'**
  String get chatLegacySenderLine;

  /// No description provided for @chatNotSentTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Not sent. Tap to retry.'**
  String get chatNotSentTapToRetry;

  /// No description provided for @chatNoticeIdentityChanged.
  ///
  /// In en, this message translates to:
  /// **'A contact\'s safety number changed. Review it before trusting it again.'**
  String get chatNoticeIdentityChanged;

  /// No description provided for @chatNoticeIdentityNewDevice.
  ///
  /// In en, this message translates to:
  /// **'This contact started using a new device.'**
  String get chatNoticeIdentityNewDevice;

  /// No description provided for @chatNoticeSenderKeysKept.
  ///
  /// In en, this message translates to:
  /// **'The server listed this group without its keys. This phone keeps using the ones it has.'**
  String get chatNoticeSenderKeysKept;

  /// No description provided for @chatNoticeGroupMemberAdded.
  ///
  /// In en, this message translates to:
  /// **'Someone was added to this group. They can read messages sent from now on. Check the members in Safety number.'**
  String get chatNoticeGroupMemberAdded;

  /// No description provided for @chatNoticeGroupMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'Someone left this group or was removed from it.'**
  String get chatNoticeGroupMemberRemoved;

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
  /// **'Safety number changed in another chat'**
  String get chatIdentityChangedElsewhereTitle;

  /// No description provided for @chatIdentityChangedElsewhereBody.
  ///
  /// In en, this message translates to:
  /// **'Their safety number changed in a group you share. Until you review it there, they aren\'t shown as verified.'**
  String get chatIdentityChangedElsewhereBody;

  /// No description provided for @chatAccountHoldOtherTitle.
  ///
  /// In en, this message translates to:
  /// **'A different account'**
  String get chatAccountHoldOtherTitle;

  /// No description provided for @chatAccountHoldOtherBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed as @{handle}, but it isn\'t the account you talked to as @{handle} before. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String chatAccountHoldOtherBody(String handle);

  /// No description provided for @chatAccountHoldUnissuedTitle.
  ///
  /// In en, this message translates to:
  /// **'A name the server never gives out'**
  String get chatAccountHoldUnissuedTitle;

  /// No description provided for @chatAccountHoldUnissuedBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed under a name no server issues, so it may only look like someone you know. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String get chatAccountHoldUnissuedBody;

  /// No description provided for @chatAccountHoldOwnTitle.
  ///
  /// In en, this message translates to:
  /// **'Another account under your name'**
  String get chatAccountHoldOwnTitle;

  /// No description provided for @chatAccountHoldOwnBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed under your own name, @{handle}, but with another account. No one else can have your name, so the list this phone received was altered, perhaps to pass someone off as you. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String chatAccountHoldOwnBody(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk to this other @{handle}?'**
  String chatAccountHoldOwnConfirmTitle(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'No other account can have your name, yet the server showed this one under it. Continue only if you confirmed another way, in person or on a call, whose account this is.'**
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
  /// **'@{handle} is typing…'**
  String chatTypingSuffix(String handle);

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

  /// No description provided for @chatNetworkRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message wasn\'t sent.} other{{count} messages weren\'t sent.}} {retryLabel}'**
  String chatNetworkRecoveryFailed(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryUploading.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment is waiting.} other{{count} attachments are waiting.}} {retryLabel}'**
  String chatNetworkRecoveryUploading(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryQueued.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message is waiting.} other{{count} messages are waiting.}} {retryLabel}'**
  String chatNetworkRecoveryQueued(int count, String retryLabel);

  /// No description provided for @chatRetryResumes.
  ///
  /// In en, this message translates to:
  /// **'They\'ll be sent when you\'re back online.'**
  String get chatRetryResumes;

  /// No description provided for @chatRetryNextIn.
  ///
  /// In en, this message translates to:
  /// **'Next try in {countdown}.'**
  String chatRetryNextIn(String countdown);

  /// No description provided for @chatCountdownSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String chatCountdownSeconds(int seconds);

  /// No description provided for @chatCountdownMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String chatCountdownMinutes(int minutes);

  /// No description provided for @chatCountdownMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String chatCountdownMinutesSeconds(int minutes, int seconds);

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
  /// **'Register this phone first, then approve it on the old one.'**
  String get errorClaimBeforeCompletion;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unexpected response. Try again.'**
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
  /// **'The server couldn\'t find that.'**
  String get errorNotFound;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'This conflicts with the current state. Refresh and try again.'**
  String get errorConflict;

  /// No description provided for @errorRejected.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t accept this. Check what you entered and try again.'**
  String get errorRejected;

  /// No description provided for @errorRelayFailed.
  ///
  /// In en, this message translates to:
  /// **'The server could not complete the request. Try again shortly.'**
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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get conversationsEmptyTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Start a chat with someone\'s handle.'**
  String get conversationsEmptyBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get conversationsSearchHint;

  /// No description provided for @conversationsNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get conversationsNewChat;

  /// No description provided for @conversationsNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get conversationsNewGroup;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Older messages'**
  String get conversationsArchiveSection;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get conversationsLoadingArchive;

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

  /// No description provided for @conversationsPreviewExpired.
  ///
  /// In en, this message translates to:
  /// **'Message expired'**
  String get conversationsPreviewExpired;

  /// No description provided for @conversationsPreviewMessage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message'**
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

  /// No description provided for @conversationsPreviewSystem.
  ///
  /// In en, this message translates to:
  /// **'Security notice'**
  String get conversationsPreviewSystem;

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
  /// **'Reaction'**
  String get conversationsPreviewReaction;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get conversationsPreviewCall;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get conversationsRelayLinked;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get conversationsRelayIdle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 chat} other{{count} chats}}'**
  String conversationsCount(int count);

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No backup'**
  String get conversationsNoBackup;

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

  /// No description provided for @conversationsSyncIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh'**
  String get conversationsSyncIssueTitle;

  /// No description provided for @conversationsRelayInterruptedBody.
  ///
  /// In en, this message translates to:
  /// **'Messages waiting to be sent go out once you\'re back online.'**
  String get conversationsRelayInterruptedBody;

  /// No description provided for @conversationsSearchHintCompact.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get conversationsSearchHintCompact;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Only messages on this phone are searched.'**
  String get conversationsSearchLocalNote;

  /// No description provided for @conversationsFilterAllSenders.
  ///
  /// In en, this message translates to:
  /// **'All senders'**
  String get conversationsFilterAllSenders;

  /// No description provided for @conversationsFilterMine.
  ///
  /// In en, this message translates to:
  /// **'From me'**
  String get conversationsFilterMine;

  /// No description provided for @conversationsFilterTheirs.
  ///
  /// In en, this message translates to:
  /// **'From them'**
  String get conversationsFilterTheirs;

  /// No description provided for @conversationsFilterAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get conversationsFilterAllTypes;

  /// No description provided for @conversationsFilterText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get conversationsFilterText;

  /// No description provided for @conversationsFilterMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get conversationsFilterMedia;

  /// No description provided for @conversationsFilterAnyDate.
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get conversationsFilterAnyDate;

  /// No description provided for @conversationsFilterLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get conversationsFilterLast7Days;

  /// No description provided for @conversationsFilterLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get conversationsFilterLast30Days;

  /// No description provided for @conversationsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get conversationsSectionLabel;

  /// No description provided for @conversationsMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String conversationsMatchCount(int count);

  /// No description provided for @conversationsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching chats'**
  String get conversationsNoMatchTitle;

  /// No description provided for @conversationsNoneYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get conversationsNoneYetTitle;

  /// No description provided for @conversationsNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'No name or handle matches.'**
  String get conversationsNoMatchBody;

  /// No description provided for @conversationsNoneYetBody.
  ///
  /// In en, this message translates to:
  /// **'Start a chat with someone\'s handle.'**
  String get conversationsNoneYetBody;

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

  /// No description provided for @conversationsResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String conversationsResultCount(int count);

  /// No description provided for @conversationsNoMessageMatchBody.
  ///
  /// In en, this message translates to:
  /// **'No message matches these filters.'**
  String get conversationsNoMessageMatchBody;

  /// No description provided for @conversationsResultFromYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get conversationsResultFromYou;

  /// No description provided for @conversationsResultFromPeer.
  ///
  /// In en, this message translates to:
  /// **'Them'**
  String get conversationsResultFromPeer;

  /// No description provided for @conversationsKindImage.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get conversationsKindImage;

  /// No description provided for @conversationsKindAttachment.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get conversationsKindAttachment;

  /// No description provided for @conversationsKindSystem.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get conversationsKindSystem;

  /// No description provided for @conversationsKindVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get conversationsKindVoice;

  /// No description provided for @conversationsKindSticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get conversationsKindSticker;

  /// No description provided for @conversationsKindReaction.
  ///
  /// In en, this message translates to:
  /// **'Reaction'**
  String get conversationsKindReaction;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get conversationsKindCall;

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

  /// No description provided for @conversationsChoosePaneBody.
  ///
  /// In en, this message translates to:
  /// **'Pick one from the list or start a new one.'**
  String get conversationsChoosePaneBody;

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
  /// **'Group chat with {names}'**
  String conversationsGroupRowSemantics(String names);

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

  /// No description provided for @oneTimeLinkSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send a secret that can be opened once. The other person doesn\'t need the app.'**
  String get oneTimeLinkSettingsSubtitle;

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
  /// **'Protect with a passphrase'**
  String get oneTimeLinkUsePassphrase;

  /// No description provided for @oneTimeLinkUsePassphraseBody.
  ///
  /// In en, this message translates to:
  /// **'The key stays out of the link. Send the passphrase another way.'**
  String get oneTimeLinkUsePassphraseBody;

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
  /// **'Couldn\'t create the link. Try again in a moment.'**
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
  /// **'If it isn\'t opened, it\'s deleted on {when}.'**
  String oneTimeLinkExpires(String when);

  /// No description provided for @oneTimeLinkSendPassphraseApart.
  ///
  /// In en, this message translates to:
  /// **'Send the passphrase separately from the link.'**
  String get oneTimeLinkSendPassphraseApart;

  /// No description provided for @oneTimeLinkProtectsLabel.
  ///
  /// In en, this message translates to:
  /// **'What it protects'**
  String get oneTimeLinkProtectsLabel;

  /// No description provided for @oneTimeLinkProtectsEncrypted.
  ///
  /// In en, this message translates to:
  /// **'The secret is encrypted on this phone. The server stores only the encrypted text and never gets the key.'**
  String get oneTimeLinkProtectsEncrypted;

  /// No description provided for @oneTimeLinkProtectsBurn.
  ///
  /// In en, this message translates to:
  /// **'The server deletes it the first time it\'s opened, or when it expires unopened.'**
  String get oneTimeLinkProtectsBurn;

  /// No description provided for @oneTimeLinkLimitsLabel.
  ///
  /// In en, this message translates to:
  /// **'What it doesn\'t protect'**
  String get oneTimeLinkLimitsLabel;

  /// No description provided for @oneTimeLinkLimitHolder.
  ///
  /// In en, this message translates to:
  /// **'Whoever opens the whole link first can read it. If the channel isn\'t safe, add a passphrase.'**
  String get oneTimeLinkLimitHolder;

  /// No description provided for @oneTimeLinkLimitReader.
  ///
  /// In en, this message translates to:
  /// **'The person who opens it can copy it or take a screenshot. One-time means it opens once, not that it can\'t be copied.'**
  String get oneTimeLinkLimitReader;

  /// No description provided for @oneTimeLinkLimitRelay.
  ///
  /// In en, this message translates to:
  /// **'The server sees when a link is made and opened, its size and the network addresses. It also serves the page that opens the link, so a link is only as trustworthy as the server.'**
  String get oneTimeLinkLimitRelay;

  /// No description provided for @oneTimeLinkFooter.
  ///
  /// In en, this message translates to:
  /// **'The link opens once, then it\'s gone. The server can\'t read it.'**
  String get oneTimeLinkFooter;

  /// No description provided for @contactsNotice.
  ///
  /// In en, this message translates to:
  /// **'The server knows which accounts you added. The nicknames you give them stay on this phone.'**
  String get contactsNotice;

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
  /// **'Couldn\'t load contacts'**
  String get contactsErrorTitle;

  /// No description provided for @contactsErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Showing the last list that loaded.'**
  String get contactsErrorBody;

  /// No description provided for @contactsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get contactsEmptyTitle;

  /// No description provided for @contactsEmptySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get contactsEmptySearchTitle;

  /// No description provided for @contactsEmptySearchBody.
  ///
  /// In en, this message translates to:
  /// **'No name or handle matches.'**
  String get contactsEmptySearchBody;

  /// No description provided for @contactsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add someone by their handle.'**
  String get contactsEmptyBody;

  /// No description provided for @contactsAddSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Enter their handle exactly as they gave it to you.'**
  String get contactsAddSheetBody;

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

  /// No description provided for @contactsNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Only you see this'**
  String get contactsNicknameHint;

  /// No description provided for @contactsSave.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get contactsSave;

  /// No description provided for @contactsAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that handle. Check the spelling and your connection.'**
  String get contactsAddFailed;

  /// No description provided for @contactsAdded.
  ///
  /// In en, this message translates to:
  /// **'@{handle} added'**
  String contactsAdded(String handle);

  /// No description provided for @contactsStartChat.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
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
  /// **'Only you see the nickname. Leave it empty to show the handle.'**
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

  /// No description provided for @contactsVerifiedStatus.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get contactsVerifiedStatus;

  /// No description provided for @notificationNewMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Veil'**
  String get notificationNewMessageTitle;

  /// No description provided for @notificationNewMessageBody.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get notificationNewMessageBody;

  /// No description provided for @startDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get startDirectTitle;

  /// No description provided for @startDirectInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get startDirectInputLabel;

  /// No description provided for @startDirectErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the chat'**
  String get startDirectErrorTitle;

  /// No description provided for @startDirectErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check the handle and your connection, then try again.'**
  String get startDirectErrorBody;

  /// No description provided for @startDirectOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get startDirectOpening;

  /// No description provided for @startDirectOpenButton.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get startDirectOpenButton;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get startDirectNoteTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Enter their handle exactly as they gave it to you.'**
  String get startDirectNote;

  /// No description provided for @startDirectFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Enter their handle exactly as they gave it to you.'**
  String get startDirectFieldCaption;

  /// No description provided for @startGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get startGroupTitle;

  /// No description provided for @startGroupNameInput.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get startGroupNameInput;

  /// No description provided for @startGroupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Weekend plans'**
  String get startGroupNameHint;

  /// No description provided for @startGroupDescriptionInput.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get startGroupDescriptionInput;

  /// No description provided for @startGroupDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What it\'s for'**
  String get startGroupDescriptionHint;

  /// No description provided for @startGroupMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 handle} other{{count} handles}}'**
  String startGroupMembersCount(int count);

  /// No description provided for @startGroupMembersCaption.
  ///
  /// In en, this message translates to:
  /// **'Handles, separated by commas. Members can\'t be added later, so list everyone now.'**
  String get startGroupMembersCaption;

  /// No description provided for @startGroupMembersInput.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get startGroupMembersInput;

  /// No description provided for @startGroupErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the group'**
  String get startGroupErrorTitle;

  /// No description provided for @startGroupErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check the handles and your connection, then try again.'**
  String get startGroupErrorBody;

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

  /// No description provided for @safetyNumbersTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumbersTitle;

  /// No description provided for @safetyNumbersLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Working out the safety number…'**
  String get safetyNumbersLoadingTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get safetyNumbersLoadingBody;

  /// No description provided for @safetyNumbersMarkedVerified.
  ///
  /// In en, this message translates to:
  /// **'Marked as verified'**
  String get safetyNumbersMarkedVerified;

  /// No description provided for @safetyNumbersRotateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new session?'**
  String get safetyNumbersRotateDialogTitle;

  /// No description provided for @safetyNumbersRotateDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This sets up new keys with your contact. Your next message uses them, and messages already on their way still open. Do this if you think your phone or theirs was briefly in someone else\'s hands: anyone who copied the old keys can\'t read new messages.'**
  String get safetyNumbersRotateDialogBody;

  /// No description provided for @safetyNumbersCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get safetyNumbersCancel;

  /// No description provided for @safetyNumbersRotate.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get safetyNumbersRotate;

  /// No description provided for @safetyNumbersSessionRotated.
  ///
  /// In en, this message translates to:
  /// **'New session ready. Your next message starts it.'**
  String get safetyNumbersSessionRotated;

  /// No description provided for @safetyNumbersNoSessionYet.
  ///
  /// In en, this message translates to:
  /// **'No session yet. Send a message first.'**
  String get safetyNumbersNoSessionYet;

  /// No description provided for @safetyNumbersRotationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start a new session. Try again in a moment.'**
  String get safetyNumbersRotationFailed;

  /// No description provided for @safetyNumbersErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the safety number'**
  String get safetyNumbersErrorTitle;

  /// No description provided for @safetyNumbersErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get safetyNumbersErrorBody;

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

  /// No description provided for @safetyNumbersNoMembersBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody else is in this group yet.'**
  String get safetyNumbersNoMembersBody;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get safetyNumbersGroupEyebrow;

  /// No description provided for @safetyNumbersGroupTitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Verify each member'**
  String get safetyNumbersGroupTitleGeneric;

  /// No description provided for @safetyNumbersGroupTitleNamed.
  ///
  /// In en, this message translates to:
  /// **'Verify each member of {groupName}'**
  String safetyNumbersGroupTitleNamed(String groupName);

  /// No description provided for @safetyNumbersGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a member to see their 60-digit safety number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you and that member.'**
  String get safetyNumbersGroupBody;

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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get safetyNumbersDetailEyebrow;

  /// No description provided for @safetyNumbersDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure you\'re talking to {peer}'**
  String safetyNumbersDetailTitle(String peer);

  /// No description provided for @safetyNumbersDetailBody.
  ///
  /// In en, this message translates to:
  /// **'Both of you should see the same 60-digit number. Compare it over a call or scan the QR code. If it doesn\'t match, someone may be between you.'**
  String get safetyNumbersDetailBody;

  /// No description provided for @safetyNumbersKeyChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get safetyNumbersKeyChangedTitle;

  /// No description provided for @safetyNumbersKeyChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'It\'s different from the one you verified on {date}. This happens after a reinstall or a new phone, or if someone is pretending to be them. Compare the new number before trusting it.'**
  String safetyNumbersKeyChangedMessage(String date);

  /// No description provided for @safetyNumbersVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified on {date}'**
  String safetyNumbersVerifiedOn(String date);

  /// No description provided for @safetyNumbersVerifiedNote.
  ///
  /// In en, this message translates to:
  /// **'If they reinstall or change phones, you\'ll be asked to verify again.'**
  String get safetyNumbersVerifiedNote;

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

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get safetyNumbersRotateEyebrow;

  /// No description provided for @safetyNumbersRotateBody.
  ///
  /// In en, this message translates to:
  /// **'Sets up new keys with your contact. Your next message uses them, and messages already on their way still open. Do this if your phone or theirs was briefly in someone else\'s hands.'**
  String get safetyNumbersRotateBody;

  /// No description provided for @safetyNumbersRotating.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get safetyNumbersRotating;

  /// No description provided for @safetyNumbersRotateButton.
  ///
  /// In en, this message translates to:
  /// **'Start a new session'**
  String get safetyNumbersRotateButton;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumbersCardLabel;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Current safety number'**
  String get safetyNumbersCardLabelCurrent;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'New safety number'**
  String get safetyNumbersCardLabelNew;

  /// No description provided for @safetyNumbersNewNumberHeader.
  ///
  /// In en, this message translates to:
  /// **'New safety number'**
  String get safetyNumbersNewNumberHeader;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Scan to compare'**
  String get safetyNumbersScanLabel;

  /// No description provided for @safetyNumbersQrNote.
  ///
  /// In en, this message translates to:
  /// **'The code holds both public keys and account IDs, nothing secret.'**
  String get safetyNumbersQrNote;

  /// No description provided for @safetyNumbersNoPinTitle.
  ///
  /// In en, this message translates to:
  /// **'No safety number yet'**
  String get safetyNumbersNoPinTitle;

  /// No description provided for @safetyNumbersNoPinBody.
  ///
  /// In en, this message translates to:
  /// **'Exchange a message first. The number appears here once this phone knows which keys it\'s talking to.'**
  String get safetyNumbersNoPinBody;

  /// No description provided for @safetyNumbersDirectoryMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The server lists a different key'**
  String get safetyNumbersDirectoryMismatchTitle;

  /// No description provided for @safetyNumbersDirectoryMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The server now gives a different key for this contact than the one this phone knows. Nothing is sent to that key unless you compare and accept it.'**
  String get safetyNumbersDirectoryMismatchBody;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'The server lists another device'**
  String get safetyNumbersDirectoryOtherDeviceTitle;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'This chat encrypts to a different device than the one the server now lists for this contact. The safety number here belongs to the device it encrypts to. If your contact changed phones, compare numbers with them again.'**
  String get safetyNumbersDirectoryOtherDeviceBody;

  /// No description provided for @safetyNumbersPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your contact\'s keys changed. Compare the new safety number below before accepting it.'**
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
  /// **'Compare a scanned code'**
  String get safetyNumbersScanAction;

  /// No description provided for @safetyNumbersScanTheirCode.
  ///
  /// In en, this message translates to:
  /// **'Scan their code'**
  String get safetyNumbersScanTheirCode;

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
  /// **'The codes don\'t match'**
  String get safetyNumbersScanMismatchTitle;

  /// No description provided for @safetyNumbersScanMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'Someone may be between you. Don\'t mark it verified until you have compared again in person.'**
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
  /// **'Compare the new safety number'**
  String get safetyNumbersReverifyDialogTitle;

  /// No description provided for @safetyNumbersReverifyDialogBody.
  ///
  /// In en, this message translates to:
  /// **'You had verified {peer}. Accept the new number only after comparing it with {peer} in person or on a call you trust.'**
  String safetyNumbersReverifyDialogBody(String peer);

  /// No description provided for @safetyNumbersReverifyAffirm.
  ///
  /// In en, this message translates to:
  /// **'I compared this number with {peer} and it matches'**
  String safetyNumbersReverifyAffirm(String peer);

  /// No description provided for @safetyNumbersReverifyAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept as verified'**
  String get safetyNumbersReverifyAccept;

  /// No description provided for @safetyNumbersChangeReplaced.
  ///
  /// In en, this message translates to:
  /// **'The safety number changed again while you were reviewing it. Compare the new number before accepting it.'**
  String get safetyNumbersChangeReplaced;

  /// No description provided for @safetyNumbersChangedElsewhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get safetyNumbersChangedElsewhereTitle;

  /// No description provided for @safetyNumbersChangedElsewhereBody.
  ///
  /// In en, this message translates to:
  /// **'{peer}\'s safety number changed in another chat. Until you review it there, {peer} isn\'t shown as verified. The number below is the one this phone knew before the change.'**
  String safetyNumbersChangedElsewhereBody(String peer);

  /// No description provided for @safetyNumbersReviewChange.
  ///
  /// In en, this message translates to:
  /// **'Review the new number'**
  String get safetyNumbersReviewChange;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileNicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Nickname saved'**
  String get profileNicknameSaved;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get profileHandleLabel;

  /// No description provided for @profileHandleCaption.
  ///
  /// In en, this message translates to:
  /// **'Your handle can\'t be changed.'**
  String get profileHandleCaption;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get profileNicknameLabel;

  /// No description provided for @profileNicknameCaption.
  ///
  /// In en, this message translates to:
  /// **'Only you see it.'**
  String get profileNicknameCaption;

  /// No description provided for @profileNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get profileNicknameHint;

  /// No description provided for @profileNicknameNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileNicknameNotSet;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'No profile on the server'**
  String get profilePrivacyTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'The server stores no name or profile. Your nickname stays on this phone and is erased with it.'**
  String get profilePrivacyBody;

  /// No description provided for @profileSaveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileSaveNickname;

  /// No description provided for @profileEditNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get profileEditNickname;

  /// No description provided for @profileCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileCancel;

  /// No description provided for @profileNicknameFooter.
  ///
  /// In en, this message translates to:
  /// **'Only you see nicknames. Your handle can\'t be changed.'**
  String get profileNicknameFooter;

  /// No description provided for @deviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to a new phone'**
  String get deviceTransferTitle;

  /// No description provided for @deviceTransferChipOldDevice.
  ///
  /// In en, this message translates to:
  /// **'Old phone'**
  String get deviceTransferChipOldDevice;

  /// No description provided for @deviceTransferChipNewDevice.
  ///
  /// In en, this message translates to:
  /// **'New phone'**
  String get deviceTransferChipNewDevice;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Both phones are needed'**
  String get deviceTransferNoFallbackTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'You need the old phone. If it is gone, the account is gone.'**
  String get deviceTransferNoFallbackBody;

  /// No description provided for @deviceTransferOldPhoneNeeded.
  ///
  /// In en, this message translates to:
  /// **'You need the old phone. If it is gone, the account is gone.'**
  String get deviceTransferOldPhoneNeeded;

  /// No description provided for @deviceTransferPayloadCopied.
  ///
  /// In en, this message translates to:
  /// **'Transfer code copied.'**
  String get deviceTransferPayloadCopied;

  /// No description provided for @deviceTransferReturnToConversations.
  ///
  /// In en, this message translates to:
  /// **'Back to chats'**
  String get deviceTransferReturnToConversations;

  /// No description provided for @deviceTransferPayloadInvalid.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a valid transfer code.'**
  String get deviceTransferPayloadInvalid;

  /// No description provided for @deviceTransferImportFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid transfer code first.'**
  String get deviceTransferImportFirst;

  /// No description provided for @deviceTransferClaimFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t register this phone.'**
  String get deviceTransferClaimFailed;

  /// No description provided for @deviceTransferRegisterBeforeComplete.
  ///
  /// In en, this message translates to:
  /// **'Register this phone before finishing.'**
  String get deviceTransferRegisterBeforeComplete;

  /// No description provided for @deviceTransferCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'This transfer code has expired. Get a new one from the old phone.'**
  String get deviceTransferCodeExpired;

  /// No description provided for @deviceTransferFinishStartedFirst.
  ///
  /// In en, this message translates to:
  /// **'This phone already started finishing a transfer that the server may have completed. Finish that one before using another code.'**
  String get deviceTransferFinishStartedFirst;

  /// No description provided for @deviceTransferComplete.
  ///
  /// In en, this message translates to:
  /// **'Done. Your account is now on this phone and the old phone is signed out.'**
  String get deviceTransferComplete;

  /// No description provided for @deviceTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed.'**
  String get deviceTransferFailed;

  /// No description provided for @deviceTransferOldRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in on the old phone'**
  String get deviceTransferOldRequiredTitle;

  /// No description provided for @deviceTransferOldRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Only a phone that has the account can start and approve a move.'**
  String get deviceTransferOldRequiredBody;

  /// No description provided for @deviceTransferOldIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Get a transfer code'**
  String get deviceTransferOldIssueTitle;

  /// No description provided for @deviceTransferOldIssueBody.
  ///
  /// In en, this message translates to:
  /// **'The code works for a short time.'**
  String get deviceTransferOldIssueBody;

  /// No description provided for @deviceTransferOldIssueExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'The code expired. Get a new one.'**
  String get deviceTransferOldIssueExpiredBody;

  /// No description provided for @deviceTransferOldHandTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code on the new phone'**
  String get deviceTransferOldHandTitle;

  /// No description provided for @deviceTransferOldHandBody.
  ///
  /// In en, this message translates to:
  /// **'The code shows here once you get it.'**
  String get deviceTransferOldHandBody;

  /// No description provided for @deviceTransferOldApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve the new phone'**
  String get deviceTransferOldApproveTitle;

  /// No description provided for @deviceTransferOldApproveBody.
  ///
  /// In en, this message translates to:
  /// **'The new phone shows a code once it registers. Enter it here to approve.'**
  String get deviceTransferOldApproveBody;

  /// No description provided for @deviceTransferNewCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the transfer code'**
  String get deviceTransferNewCodeTitle;

  /// No description provided for @deviceTransferNewCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Get it from your old phone.'**
  String get deviceTransferNewCodeBody;

  /// No description provided for @deviceTransferNewCodeExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'The transfer code expired before the move finished. Get a new one from the old phone.'**
  String get deviceTransferNewCodeExpiredBody;

  /// No description provided for @deviceTransferNewCodeChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get deviceTransferNewCodeChange;

  /// No description provided for @deviceTransferNewRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register this phone'**
  String get deviceTransferNewRegisterTitle;

  /// No description provided for @deviceTransferNewCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve on the old phone, then finish'**
  String get deviceTransferNewCompleteTitle;

  /// No description provided for @deviceTransferNewCompleteBodyUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Once registered, this phone shows a code for the old phone to approve.'**
  String get deviceTransferNewCompleteBodyUpcoming;

  /// No description provided for @deviceTransferNewCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on the old phone and approve it there.'**
  String get deviceTransferNewCompleteBody;

  /// No description provided for @deviceTransferNewCompleteNote.
  ///
  /// In en, this message translates to:
  /// **'When you finish, the old phone is signed out. Your message history does not move.'**
  String get deviceTransferNewCompleteNote;

  /// No description provided for @deviceTransferStep1BodyExpires.
  ///
  /// In en, this message translates to:
  /// **'This code expires {when}.'**
  String deviceTransferStep1BodyExpires(String when);

  /// No description provided for @deviceTransferStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get deviceTransferStatusExpired;

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

  /// No description provided for @deviceTransferClaimFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Approve only the code shown on the new phone you trust.'**
  String get deviceTransferClaimFieldCaption;

  /// No description provided for @deviceTransferClaimInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Code from the new phone'**
  String get deviceTransferClaimInputLabel;

  /// No description provided for @deviceTransferClaimInputHint.
  ///
  /// In en, this message translates to:
  /// **'Shown on the new phone'**
  String get deviceTransferClaimInputHint;

  /// No description provided for @deviceTransferApproveClaim.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get deviceTransferApproveClaim;

  /// No description provided for @deviceTransferCompleteOnNewNote.
  ///
  /// In en, this message translates to:
  /// **'After you approve, finish on the new phone. This phone is then signed out and its history is erased. Your message history does not move to the new phone.'**
  String get deviceTransferCompleteOnNewNote;

  /// No description provided for @deviceTransferCopyPayload.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get deviceTransferCopyPayload;

  /// No description provided for @deviceTransferClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get deviceTransferClear;

  /// No description provided for @deviceTransferStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get deviceTransferStatusTitle;

  /// No description provided for @deviceTransferStatusNeedsApi.
  ///
  /// In en, this message translates to:
  /// **'No server is configured, so nothing can be moved.'**
  String get deviceTransferStatusNeedsApi;

  /// No description provided for @deviceTransferStatusTokenReady.
  ///
  /// In en, this message translates to:
  /// **'The code is ready.'**
  String get deviceTransferStatusTokenReady;

  /// No description provided for @deviceTransferStatusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Get a transfer code first.'**
  String get deviceTransferStatusNotStarted;

  /// No description provided for @deviceTransferStatusClaimCodeMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the new phone first.'**
  String get deviceTransferStatusClaimCodeMissing;

  /// No description provided for @deviceTransferStatusClaimNotWaiting.
  ///
  /// In en, this message translates to:
  /// **'No phone with code {claimId} is waiting.'**
  String deviceTransferStatusClaimNotWaiting(String claimId);

  /// No description provided for @deviceTransferStatusClaimApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved code {claimId}. Key fingerprint: {fingerprint}'**
  String deviceTransferStatusClaimApproved(String claimId, String fingerprint);

  /// No description provided for @deviceTransferFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t move the account'**
  String get deviceTransferFailedTitle;

  /// No description provided for @deviceTransferPayloadInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer code'**
  String get deviceTransferPayloadInputLabel;

  /// No description provided for @deviceTransferImportPayload.
  ///
  /// In en, this message translates to:
  /// **'Use this code'**
  String get deviceTransferImportPayload;

  /// No description provided for @deviceTransferNewDeviceCaption.
  ///
  /// In en, this message translates to:
  /// **'This phone creates its own keys and asks the old phone to approve them. Register before the code expires.'**
  String get deviceTransferNewDeviceCaption;

  /// No description provided for @deviceTransferDeviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceTransferDeviceNameLabel;

  /// No description provided for @deviceTransferClaimCode.
  ///
  /// In en, this message translates to:
  /// **'Code {claimId}'**
  String deviceTransferClaimCode(String claimId);

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
  /// **'Registering…'**
  String get deviceTransferRegisteringClaim;

  /// No description provided for @deviceTransferRegisterNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get deviceTransferRegisterNewDevice;

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

  /// No description provided for @deviceTransferExpiryAt.
  ///
  /// In en, this message translates to:
  /// **'at {time}'**
  String deviceTransferExpiryAt(String time);

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

  /// No description provided for @securityStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityStatusTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'How this phone is protected'**
  String get securityStatusHeroTitle;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'These rows are read from this phone and this version of the app.'**
  String get securityStatusHeroBody;

  /// No description provided for @securityStatusAttentionTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs attention} other{{count} items need attention}}'**
  String securityStatusAttentionTitle(int count);

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **''**
  String get securityStatusPillPrivateBeta;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get securityStatusMetricRuntime;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get securityStatusMetricRelay;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get securityStatusMetricRelayLinked;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get securityStatusMetricCache;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityStatusMetricCacheOff;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get securityStatusSectionIdentity;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get securityStatusSectionRuntime;

  /// deprecated: deleted in W0-ARB phase 2
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get securityStatusSectionProductRules;

  /// No description provided for @securityGroupThisPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get securityGroupThisPhone;

  /// No description provided for @securityGroupConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get securityGroupConnection;

  /// No description provided for @securityGroupEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get securityGroupEncryption;

  /// No description provided for @securityGroupRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get securityGroupRules;

  /// No description provided for @securityFooterEncryption.
  ///
  /// In en, this message translates to:
  /// **'Messages are end-to-end encrypted. Keys exist only on your devices.'**
  String get securityFooterEncryption;

  /// No description provided for @securityFooterNoRecovery.
  ///
  /// In en, this message translates to:
  /// **'There is no backup, no password reset and no way for anyone, including us, to recover an account.'**
  String get securityFooterNoRecovery;

  /// No description provided for @securityStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get securityStatusChecking;

  /// No description provided for @securityStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get securityStatusAvailable;

  /// No description provided for @securityStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get securityStatusUnavailable;

  /// No description provided for @securityStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get securityStatusEnabled;

  /// No description provided for @securityStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityStatusDisabled;

  /// No description provided for @securityStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get securityStatusReady;

  /// No description provided for @securityStatusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get securityStatusStarting;

  /// No description provided for @securityStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get securityStatusBlocked;

  /// No description provided for @securityStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get securityStatusIdle;

  /// No description provided for @securityStatusBoundDevice.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get securityStatusBoundDevice;

  /// No description provided for @securityStatusBoundDeviceUnbound.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get securityStatusBoundDeviceUnbound;

  /// No description provided for @securityStatusBoundDeviceNoneDetail.
  ///
  /// In en, this message translates to:
  /// **'This phone is not signed in.'**
  String get securityStatusBoundDeviceNoneDetail;

  /// No description provided for @securityStatusBoundDeviceDetail.
  ///
  /// In en, this message translates to:
  /// **'Signed in on this phone.'**
  String get securityStatusBoundDeviceDetail;

  /// No description provided for @securityStatusSecretRefs.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get securityStatusSecretRefs;

  /// No description provided for @securityStatusSecretRefsPresent.
  ///
  /// In en, this message translates to:
  /// **'On this phone'**
  String get securityStatusSecretRefsPresent;

  /// No description provided for @securityStatusSecretRefsMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get securityStatusSecretRefsMissing;

  /// No description provided for @securityStatusSecretRefsDetail.
  ///
  /// In en, this message translates to:
  /// **'Stored on this phone only.'**
  String get securityStatusSecretRefsDetail;

  /// No description provided for @securityStatusPin.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get securityStatusPin;

  /// No description provided for @securityStatusPinConfigured.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get securityStatusPinConfigured;

  /// No description provided for @securityStatusPinUnset.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityStatusPinUnset;

  /// No description provided for @securityStatusPinDetail.
  ///
  /// In en, this message translates to:
  /// **'Checked on this phone only.'**
  String get securityStatusPinDetail;

  /// No description provided for @securityStatusBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get securityStatusBiometrics;

  /// No description provided for @securityStatusBiometricsDetail.
  ///
  /// In en, this message translates to:
  /// **'Uses the phone\'s own biometrics.'**
  String get securityStatusBiometricsDetail;

  /// No description provided for @securityStatusPrivacyShield.
  ///
  /// In en, this message translates to:
  /// **'Lock when leaving the app'**
  String get securityStatusPrivacyShield;

  /// No description provided for @securityStatusPrivacyShieldDetail.
  ///
  /// In en, this message translates to:
  /// **'The app locks again and hides its preview when you switch away.'**
  String get securityStatusPrivacyShieldDetail;

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

  /// No description provided for @securityStatusAppPreviewDetail.
  ///
  /// In en, this message translates to:
  /// **'What the app switcher shows while the app is in the background.'**
  String get securityStatusAppPreviewDetail;

  /// No description provided for @securityStatusScreenCapture.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get securityStatusScreenCapture;

  /// No description provided for @securityStatusScreenCapturePlatformLimited.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get securityStatusScreenCapturePlatformLimited;

  /// No description provided for @securityStatusScreenCaptureNotBlocked.
  ///
  /// In en, this message translates to:
  /// **'Not blocked'**
  String get securityStatusScreenCaptureNotBlocked;

  /// No description provided for @securityStatusScreenCaptureSupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'Android blocks screenshots of the app.'**
  String get securityStatusScreenCaptureSupportedDetail;

  /// No description provided for @securityStatusScreenCaptureUnsupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'This platform has no way to block screenshots, so the app hides its preview and locks quickly instead.'**
  String get securityStatusScreenCaptureUnsupportedDetail;

  /// No description provided for @securityStatusScreenCaptureCheckingDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get securityStatusScreenCaptureCheckingDetail;

  /// No description provided for @securityStatusClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get securityStatusClipboard;

  /// No description provided for @securityStatusClipboardRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get securityStatusClipboardRestricted;

  /// No description provided for @securityStatusClipboardDetail.
  ///
  /// In en, this message translates to:
  /// **'Download links for attachments are never shown, so they can\'t be copied.'**
  String get securityStatusClipboardDetail;

  /// No description provided for @securityStatusTransport.
  ///
  /// In en, this message translates to:
  /// **'Connection policy'**
  String get securityStatusTransport;

  /// No description provided for @securityStatusTransportCompliant.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get securityStatusTransportCompliant;

  /// No description provided for @securityStatusTransportDetail.
  ///
  /// In en, this message translates to:
  /// **'The configured addresses use TLS.'**
  String get securityStatusTransportDetail;

  /// No description provided for @securityStatusTlsPins.
  ///
  /// In en, this message translates to:
  /// **'TLS pinning'**
  String get securityStatusTlsPins;

  /// No description provided for @securityStatusTlsPinsPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get securityStatusTlsPinsPinned;

  /// No description provided for @securityStatusTlsPinsUnpinned.
  ///
  /// In en, this message translates to:
  /// **'Not pinned'**
  String get securityStatusTlsPinsUnpinned;

  /// No description provided for @securityStatusTlsPinsPinnedDetail.
  ///
  /// In en, this message translates to:
  /// **'This build pins the server\'s TLS keys ({count}). A certificate that matches none of them is refused.'**
  String securityStatusTlsPinsPinnedDetail(int count);

  /// No description provided for @securityStatusTlsPinsUnpinnedDetail.
  ///
  /// In en, this message translates to:
  /// **'This build sets no TLS pins (VEIL_TLS_PINS), so the connection accepts any certificate the phone trusts. Release builds stop with a configuration error without them.'**
  String get securityStatusTlsPinsUnpinnedDetail;

  /// No description provided for @securityStatusApiMode.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get securityStatusApiMode;

  /// No description provided for @securityStatusApiAttached.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get securityStatusApiAttached;

  /// No description provided for @securityStatusApiAttachedDetail.
  ///
  /// In en, this message translates to:
  /// **'A server address is configured.'**
  String get securityStatusApiAttachedDetail;

  /// No description provided for @securityStatusApiUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No server address is configured. Messaging is unavailable.'**
  String get securityStatusApiUnavailableDetail;

  /// No description provided for @securityStatusRelayLink.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get securityStatusRelayLink;

  /// No description provided for @securityStatusRelayConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get securityStatusRelayConnected;

  /// No description provided for @securityStatusRelayConnectedDetail.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive as they\'re sent.'**
  String get securityStatusRelayConnectedDetail;

  /// No description provided for @securityStatusRelayIdleDetail.
  ///
  /// In en, this message translates to:
  /// **'Not connected or still syncing.'**
  String get securityStatusRelayIdleDetail;

  /// No description provided for @securityStatusLocalCache.
  ///
  /// In en, this message translates to:
  /// **'Messages on this phone'**
  String get securityStatusLocalCache;

  /// No description provided for @securityStatusLocalCacheDisabledDetail.
  ///
  /// In en, this message translates to:
  /// **'No messages are stored on this phone in this build.'**
  String get securityStatusLocalCacheDisabledDetail;

  /// No description provided for @securityStatusLocalCacheDetail.
  ///
  /// In en, this message translates to:
  /// **'Stored encrypted on this phone, hidden from the app switcher, and deleted when you wipe this device.'**
  String get securityStatusLocalCacheDetail;

  /// No description provided for @securityStatusIntegrity.
  ///
  /// In en, this message translates to:
  /// **'Device integrity'**
  String get securityStatusIntegrity;

  /// No description provided for @securityStatusIntegrityCompromised.
  ///
  /// In en, this message translates to:
  /// **'Compromised'**
  String get securityStatusIntegrityCompromised;

  /// No description provided for @securityStatusIntegrityClean.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get securityStatusIntegrityClean;

  /// No description provided for @securityStatusIntegrityCompromisedDetail.
  ///
  /// In en, this message translates to:
  /// **'This device looks rooted or jailbroken, so the app won\'t unlock here.'**
  String get securityStatusIntegrityCompromisedDetail;

  /// No description provided for @securityStatusIntegrityCompromisedReasons.
  ///
  /// In en, this message translates to:
  /// **'This device looks rooted or jailbroken. {reasons}'**
  String securityStatusIntegrityCompromisedReasons(String reasons);

  /// No description provided for @securityStatusIntegrityCleanDetail.
  ///
  /// In en, this message translates to:
  /// **'No signs of rooting or jailbreaking.'**
  String get securityStatusIntegrityCleanDetail;

  /// No description provided for @securityStatusIntegrityCheckingDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get securityStatusIntegrityCheckingDetail;

  /// No description provided for @securityStatusCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get securityStatusCloudBackup;

  /// No description provided for @securityStatusCloudBackupDetail.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get securityStatusCloudBackupDetail;

  /// No description provided for @securityStatusAccountRecovery.
  ///
  /// In en, this message translates to:
  /// **'Account recovery'**
  String get securityStatusAccountRecovery;

  /// No description provided for @securityStatusAccountRecoveryDetail.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get securityStatusAccountRecoveryDetail;

  /// No description provided for @securityStatusDeviceTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get securityStatusDeviceTransfer;

  /// No description provided for @securityStatusDeviceTransferValue.
  ///
  /// In en, this message translates to:
  /// **'Old phone required'**
  String get securityStatusDeviceTransferValue;

  /// No description provided for @securityStatusDeviceTransferDetail.
  ///
  /// In en, this message translates to:
  /// **'The old phone has to approve it.'**
  String get securityStatusDeviceTransferDetail;

  /// No description provided for @securityStatusLocalWipe.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get securityStatusLocalWipe;

  /// No description provided for @securityStatusLocalWipeDetail.
  ///
  /// In en, this message translates to:
  /// **'Erases the messages, keys and app lock on this phone.'**
  String get securityStatusLocalWipeDetail;

  /// No description provided for @securityStatusCryptoAdapter.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get securityStatusCryptoAdapter;

  /// No description provided for @securityStatusCryptoVeilRatchet.
  ///
  /// In en, this message translates to:
  /// **'Production (unaudited)'**
  String get securityStatusCryptoVeilRatchet;

  /// No description provided for @securityStatusCryptoVeilRatchetDetail.
  ///
  /// In en, this message translates to:
  /// **'X3DH and Double Ratchet over X25519, AES-256-GCM and Ed25519 ({adapterId}). Not yet externally audited.'**
  String securityStatusCryptoVeilRatchetDetail(String adapterId);

  /// No description provided for @securityStatusCryptoLibsignal.
  ///
  /// In en, this message translates to:
  /// **'libsignal bridge (unaudited)'**
  String get securityStatusCryptoLibsignal;

  /// No description provided for @securityStatusCryptoLibsignalDetail.
  ///
  /// In en, this message translates to:
  /// **'Sessions and messages are encrypted by Signal\'s libsignal through a native bridge ({adapterId}). The bridge has not been audited.'**
  String securityStatusCryptoLibsignalDetail(String adapterId);

  /// No description provided for @securityStatusCryptoDevelopment.
  ///
  /// In en, this message translates to:
  /// **'Development only'**
  String get securityStatusCryptoDevelopment;

  /// No description provided for @securityStatusCryptoDevelopmentDetail.
  ///
  /// In en, this message translates to:
  /// **'This build runs a development adapter ({adapterId}), not production cryptography. Don\'t use it for real chats.'**
  String securityStatusCryptoDevelopmentDetail(String adapterId);

  /// No description provided for @securityStatusPushPlaintext.
  ///
  /// In en, this message translates to:
  /// **'Message text in notifications'**
  String get securityStatusPushPlaintext;

  /// No description provided for @securityStatusPushPlaintextForbidden.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get securityStatusPushPlaintextForbidden;

  /// No description provided for @securityStatusPushPlaintextDetail.
  ///
  /// In en, this message translates to:
  /// **'Notifications never carry message text.'**
  String get securityStatusPushPlaintextDetail;

  /// No description provided for @securityStatusPushProvider.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get securityStatusPushProvider;

  /// No description provided for @securityStatusPushProviderSeam.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get securityStatusPushProviderSeam;

  /// No description provided for @securityStatusPushProviderSeamDetail.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a push service in this build.'**
  String get securityStatusPushProviderSeamDetail;

  /// No description provided for @securityStatusPushProviderUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No server address is configured, so there are no push notifications.'**
  String get securityStatusPushProviderUnavailableDetail;

  /// No description provided for @securityStatusPushPayloads.
  ///
  /// In en, this message translates to:
  /// **'Notification content'**
  String get securityStatusPushPayloads;

  /// No description provided for @securityStatusPushPayloadsMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata only'**
  String get securityStatusPushPayloadsMetadata;

  /// No description provided for @securityStatusPushPayloadsMetadataDetail.
  ///
  /// In en, this message translates to:
  /// **'A notification only says that something arrived.'**
  String get securityStatusPushPayloadsMetadataDetail;

  /// No description provided for @securityStatusPushPayloadsUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No server address is configured, so there are no push notifications.'**
  String get securityStatusPushPayloadsUnavailableDetail;
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
