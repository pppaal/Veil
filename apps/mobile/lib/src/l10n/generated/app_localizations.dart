import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL'**
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

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
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

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonConfirm.
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

  /// No description provided for @pillNoRecovery.
  ///
  /// In en, this message translates to:
  /// **'No recovery'**
  String get pillNoRecovery;

  /// No description provided for @pillSessionLocked.
  ///
  /// In en, this message translates to:
  /// **'Session locked'**
  String get pillSessionLocked;

  /// No description provided for @pillPreviewObscured.
  ///
  /// In en, this message translates to:
  /// **'Preview obscured'**
  String get pillPreviewObscured;

  /// No description provided for @privacyShieldEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY SHIELD'**
  String get privacyShieldEyebrow;

  /// No description provided for @privacyShieldTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL is hidden while inactive.'**
  String get privacyShieldTitle;

  /// No description provided for @privacyShieldBody.
  ///
  /// In en, this message translates to:
  /// **'Recent-app previews are obscured and the app lock is re-armed when the app leaves the foreground.'**
  String get privacyShieldBody;

  /// No description provided for @appLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// No description provided for @appLockLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking the app lock'**
  String get appLockLoadingTitle;

  /// No description provided for @appLockLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Looking for a stored PIN and biometric availability.'**
  String get appLockLoadingBody;

  /// No description provided for @appLockHeroEyebrow.
  ///
  /// In en, this message translates to:
  /// **'THIS DEVICE ONLY'**
  String get appLockHeroEyebrow;

  /// No description provided for @appLockHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL never unlocks itself remotely.'**
  String get appLockHeroTitle;

  /// No description provided for @appLockHeroBody.
  ///
  /// In en, this message translates to:
  /// **'PIN and biometrics are checked on this device only. No server can reset or override them.'**
  String get appLockHeroBody;

  /// No description provided for @appLockPillLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get appLockPillLocalOnly;

  /// No description provided for @appLockPillNoRemoteReset.
  ///
  /// In en, this message translates to:
  /// **'No remote reset'**
  String get appLockPillNoRemoteReset;

  /// No description provided for @appLockNoRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'If you forget the PIN and lose the active device, VEIL cannot restore access.'**
  String get appLockNoRecoveryBody;

  /// No description provided for @appLockCompromisedTitle.
  ///
  /// In en, this message translates to:
  /// **'Compromised device blocked'**
  String get appLockCompromisedTitle;

  /// No description provided for @appLockCompromisedBody.
  ///
  /// In en, this message translates to:
  /// **'This device appears rooted or jailbroken. VEIL blocks local unlock on compromised devices.'**
  String get appLockCompromisedBody;

  /// No description provided for @appLockCompromisedReasons.
  ///
  /// In en, this message translates to:
  /// **'This device appears rooted or jailbroken. {reasons}'**
  String appLockCompromisedReasons(String reasons);

  /// No description provided for @appLockLockoutTitle.
  ///
  /// In en, this message translates to:
  /// **'PIN temporarily locked'**
  String get appLockLockoutTitle;

  /// No description provided for @appLockLockoutBody.
  ///
  /// In en, this message translates to:
  /// **'Too many failed PIN attempts on this device. {retry}'**
  String appLockLockoutBody(String retry);

  /// No description provided for @appLockRetryNow.
  ///
  /// In en, this message translates to:
  /// **'Try again now.'**
  String get appLockRetryNow;

  /// No description provided for @appLockRetrySeconds.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds}s.'**
  String appLockRetrySeconds(int seconds);

  /// No description provided for @appLockRetryMinutes.
  ///
  /// In en, this message translates to:
  /// **'Try again in {minutes}m.'**
  String appLockRetryMinutes(int minutes);

  /// No description provided for @appLockPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get appLockPinLabel;

  /// No description provided for @appLockMetricConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get appLockMetricConfigured;

  /// No description provided for @appLockMetricRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get appLockMetricRequired;

  /// No description provided for @appLockMetricBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get appLockMetricBiometrics;

  /// No description provided for @appLockMetricAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get appLockMetricAvailable;

  /// No description provided for @appLockMetricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get appLockMetricUnavailable;

  /// No description provided for @appLockMetricPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appLockMetricPreview;

  /// No description provided for @appLockMetricProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get appLockMetricProtected;

  /// No description provided for @appLockMetricShielded.
  ///
  /// In en, this message translates to:
  /// **'Shielded'**
  String get appLockMetricShielded;

  /// No description provided for @appLockPillPinConfigured.
  ///
  /// In en, this message translates to:
  /// **'PIN configured'**
  String get appLockPillPinConfigured;

  /// No description provided for @appLockPillPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN required'**
  String get appLockPillPinRequired;

  /// No description provided for @appLockPillBiometricsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics available'**
  String get appLockPillBiometricsAvailable;

  /// No description provided for @appLockPillBiometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics unavailable'**
  String get appLockPillBiometricsUnavailable;

  /// No description provided for @appLockPillCaptureBlocked.
  ///
  /// In en, this message translates to:
  /// **'Capture blocked'**
  String get appLockPillCaptureBlocked;

  /// No description provided for @appLockPillPreviewShield.
  ///
  /// In en, this message translates to:
  /// **'Preview shield only'**
  String get appLockPillPreviewShield;

  /// No description provided for @appLockCaptionSet.
  ///
  /// In en, this message translates to:
  /// **'Set a numeric PIN for this device before continuing. VEIL cannot reset it for you.'**
  String get appLockCaptionSet;

  /// No description provided for @appLockCaptionUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock with this device\'s PIN or biometrics.'**
  String get appLockCaptionUnlock;

  /// No description provided for @appLockFieldSetPin.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get appLockFieldSetPin;

  /// No description provided for @appLockFieldPinHint.
  ///
  /// In en, this message translates to:
  /// **'6 to 12 digits'**
  String get appLockFieldPinHint;

  /// No description provided for @appLockFieldPinError.
  ///
  /// In en, this message translates to:
  /// **'Use 6 to 12 digits only.'**
  String get appLockFieldPinError;

  /// No description provided for @appLockFieldConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get appLockFieldConfirm;

  /// No description provided for @appLockFieldConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Repeat the same PIN'**
  String get appLockFieldConfirmHint;

  /// No description provided for @appLockConfirmMismatch.
  ///
  /// In en, this message translates to:
  /// **'PIN confirmation does not match.'**
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
  /// **'Biometric unlock failed.'**
  String get appLockStatusBiometricFailed;

  /// No description provided for @appLockStatusEnterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter a PIN first.'**
  String get appLockStatusEnterPin;

  /// No description provided for @appLockStatusPinFormat.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 6 to 12 digits.'**
  String get appLockStatusPinFormat;

  /// No description provided for @appLockStatusPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PIN mismatch.'**
  String get appLockStatusPinMismatch;

  /// No description provided for @appLockStatusPinMismatchAttempts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{PIN mismatch. 1 attempt left before temporary lock.} other{PIN mismatch. {count} attempts left before temporary lock.}}'**
  String appLockStatusPinMismatchAttempts(int count);

  /// No description provided for @appLockStatusLocked.
  ///
  /// In en, this message translates to:
  /// **'PIN locked temporarily.'**
  String get appLockStatusLocked;

  /// No description provided for @appLockStatusCompromised.
  ///
  /// In en, this message translates to:
  /// **'Unlock blocked on compromised device.'**
  String get appLockStatusCompromised;

  /// No description provided for @appLockUseBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get appLockUseBiometrics;

  /// No description provided for @appLockSetAndUnlock.
  ///
  /// In en, this message translates to:
  /// **'Set PIN and unlock'**
  String get appLockSetAndUnlock;

  /// No description provided for @appLockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock VEIL'**
  String get appLockUnlock;

  /// No description provided for @splashEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRIVATE BETA'**
  String get splashEyebrow;

  /// No description provided for @splashBody.
  ///
  /// In en, this message translates to:
  /// **'No backup. No recovery. No leaks.'**
  String get splashBody;

  /// No description provided for @splashErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL cannot start'**
  String get splashErrorTitle;

  /// No description provided for @splashPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Opening VEIL'**
  String get splashPreparingTitle;

  /// No description provided for @splashPreparingBody.
  ///
  /// In en, this message translates to:
  /// **'Checking this device\'s session and security state.'**
  String get splashPreparingBody;

  /// No description provided for @onboardingWarnEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT RULES'**
  String get onboardingWarnEyebrow;

  /// No description provided for @onboardingWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'No backup.\nNo recovery.\nNo leaks.'**
  String get onboardingWarnTitle;

  /// No description provided for @onboardingWarnBody.
  ///
  /// In en, this message translates to:
  /// **'VEIL is bound to this device by design. It is not a cloud inbox.'**
  String get onboardingWarnBody;

  /// No description provided for @onboardingWarnDestructiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Unrecoverable by design'**
  String get onboardingWarnDestructiveTitle;

  /// No description provided for @onboardingWarnDestructiveBody.
  ///
  /// In en, this message translates to:
  /// **'If you lose your device, your account and messages are gone. VEIL cannot restore your access.'**
  String get onboardingWarnDestructiveBody;

  /// No description provided for @onboardingWarnIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get onboardingWarnIdentityTitle;

  /// No description provided for @onboardingWarnIdentityLine1.
  ///
  /// In en, this message translates to:
  /// **'This device becomes your identity.'**
  String get onboardingWarnIdentityLine1;

  /// No description provided for @onboardingWarnIdentityLine2.
  ///
  /// In en, this message translates to:
  /// **'Your private keys stay on this device.'**
  String get onboardingWarnIdentityLine2;

  /// No description provided for @onboardingWarnIdentityLine3.
  ///
  /// In en, this message translates to:
  /// **'There is no password reset path.'**
  String get onboardingWarnIdentityLine3;

  /// No description provided for @onboardingWarnTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get onboardingWarnTransferTitle;

  /// No description provided for @onboardingWarnTransferLine1.
  ///
  /// In en, this message translates to:
  /// **'Transfer works only while the old device still exists.'**
  String get onboardingWarnTransferLine1;

  /// No description provided for @onboardingWarnTransferLine2.
  ///
  /// In en, this message translates to:
  /// **'The old device must approve the move.'**
  String get onboardingWarnTransferLine2;

  /// No description provided for @onboardingWarnTransferLine3.
  ///
  /// In en, this message translates to:
  /// **'No old device means no transfer.'**
  String get onboardingWarnTransferLine3;

  /// No description provided for @privacyConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get privacyConsentTitle;

  /// No description provided for @privacyConsentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read before using VEIL'**
  String get privacyConsentSubtitle;

  /// No description provided for @privacyConsentHeroBody.
  ///
  /// In en, this message translates to:
  /// **'VEIL complies with Korea\'s PIPA. Please review the notice below before using the service.'**
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
  /// **'Information we collect'**
  String get privacyConsentCollectTitle;

  /// No description provided for @privacyConsentCollectItem1.
  ///
  /// In en, this message translates to:
  /// **'User handle, and the random account and device IDs linked to it'**
  String get privacyConsentCollectItem1;

  /// No description provided for @privacyConsentCollectItem2.
  ///
  /// In en, this message translates to:
  /// **'Device info (platform, device label) and push token; push wake-ups carry no message content'**
  String get privacyConsentCollectItem2;

  /// No description provided for @privacyConsentCollectItem3.
  ///
  /// In en, this message translates to:
  /// **'Public identity key and prekeys (for encrypted communication)'**
  String get privacyConsentCollectItem3;

  /// No description provided for @privacyConsentCollectItem4.
  ///
  /// In en, this message translates to:
  /// **'Your in-app contact list: which accounts you added (the names you give them stay on this device)'**
  String get privacyConsentCollectItem4;

  /// No description provided for @privacyConsentCollectItem5.
  ///
  /// In en, this message translates to:
  /// **'Conversation membership and delivery metadata: when messages arrived, delivery and read-receipt times, the day a device was last seen'**
  String get privacyConsentCollectItem5;

  /// No description provided for @privacyConsentCollectItem6.
  ///
  /// In en, this message translates to:
  /// **'Call records: conversation, who started the call, call type, start and end time, duration (kept 30 days)'**
  String get privacyConsentCollectItem6;

  /// No description provided for @privacyConsentCollectItem7.
  ///
  /// In en, this message translates to:
  /// **'Group and channel names and descriptions (stored readable), and the blocks, mutes and abuse reports you make (reports kept 90 days)'**
  String get privacyConsentCollectItem7;

  /// No description provided for @privacyConsentPurposeTitle.
  ///
  /// In en, this message translates to:
  /// **'Purpose of collection'**
  String get privacyConsentPurposeTitle;

  /// No description provided for @privacyConsentPurposeItem1.
  ///
  /// In en, this message translates to:
  /// **'Provide end-to-end encrypted messaging'**
  String get privacyConsentPurposeItem1;

  /// No description provided for @privacyConsentPurposeItem2.
  ///
  /// In en, this message translates to:
  /// **'Device authentication and session management'**
  String get privacyConsentPurposeItem2;

  /// No description provided for @privacyConsentPurposeItem3.
  ///
  /// In en, this message translates to:
  /// **'Contact discovery and conversation routing'**
  String get privacyConsentPurposeItem3;

  /// No description provided for @privacyConsentRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Retention period'**
  String get privacyConsentRetentionTitle;

  /// No description provided for @privacyConsentRetentionItem1.
  ///
  /// In en, this message translates to:
  /// **'Deleted immediately on account deletion request'**
  String get privacyConsentRetentionItem1;

  /// No description provided for @privacyConsentRetentionItem2.
  ///
  /// In en, this message translates to:
  /// **'Device data is removed when the device is unpaired, and its device record within about 30 days'**
  String get privacyConsentRetentionItem2;

  /// No description provided for @privacyConsentRetentionItem3.
  ///
  /// In en, this message translates to:
  /// **'Expired messages are auto-deleted'**
  String get privacyConsentRetentionItem3;

  /// No description provided for @privacyConsentRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyConsentRightsTitle;

  /// No description provided for @privacyConsentRightsItem1.
  ///
  /// In en, this message translates to:
  /// **'Right to access, correct, and delete your information'**
  String get privacyConsentRightsItem1;

  /// No description provided for @privacyConsentRightsItem2.
  ///
  /// In en, this message translates to:
  /// **'Full deletion available from Settings → Delete account'**
  String get privacyConsentRightsItem2;

  /// No description provided for @privacyConsentRightsItem3.
  ///
  /// In en, this message translates to:
  /// **'Withdrawing consent terminates service access'**
  String get privacyConsentRightsItem3;

  /// No description provided for @privacyConsentNotCollectedTitle.
  ///
  /// In en, this message translates to:
  /// **'What we do not collect'**
  String get privacyConsentNotCollectedTitle;

  /// No description provided for @privacyConsentNotCollectedItem1.
  ///
  /// In en, this message translates to:
  /// **'Message contents (end-to-end encrypted, unreadable by server)'**
  String get privacyConsentNotCollectedItem1;

  /// No description provided for @privacyConsentNotCollectedItem2.
  ///
  /// In en, this message translates to:
  /// **'Location data'**
  String get privacyConsentNotCollectedItem2;

  /// No description provided for @privacyConsentNotCollectedItem3.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s address book, its call log, or other personal data stored on your device'**
  String get privacyConsentNotCollectedItem3;

  /// No description provided for @privacyConsentThirdPartyTitle.
  ///
  /// In en, this message translates to:
  /// **'Third-party disclosure'**
  String get privacyConsentThirdPartyTitle;

  /// No description provided for @privacyConsentThirdPartyBody.
  ///
  /// In en, this message translates to:
  /// **'VEIL does not share collected personal information with third parties, except as required by applicable law.'**
  String get privacyConsentThirdPartyBody;

  /// No description provided for @authCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateTitle;

  /// No description provided for @authCreateEyebrow.
  ///
  /// In en, this message translates to:
  /// **'DEVICE BINDING'**
  String get authCreateEyebrow;

  /// No description provided for @authCreateHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'This device becomes your identity.'**
  String get authCreateHeroTitle;

  /// No description provided for @authCreateRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'No restore path'**
  String get authCreateRestoreTitle;

  /// No description provided for @authCreateRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'If you lose this device, your account and messages are gone. VEIL cannot restore access. This is intentional.'**
  String get authCreateRestoreBody;

  /// No description provided for @authCreateFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get authCreateFieldLabel;

  /// No description provided for @authCreateFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Only this device knows it. Others find you and see you by your handle.'**
  String get authCreateFieldCaption;

  /// No description provided for @authCreateDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get authCreateDisplayName;

  /// No description provided for @authCreateDisplayHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get authCreateDisplayHint;

  /// No description provided for @authCreateTransferLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer from old device'**
  String get authCreateTransferLabel;

  /// No description provided for @authHandleTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose handle'**
  String get authHandleTitle;

  /// No description provided for @authHandleEyebrow.
  ///
  /// In en, this message translates to:
  /// **'HANDLE REGISTRATION'**
  String get authHandleEyebrow;

  /// No description provided for @authHandleHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers stay out.'**
  String get authHandleHeroTitle;

  /// No description provided for @authHandleHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Pick the handle people will find you by. VEIL binds it to this device once the device\'s keys are generated.'**
  String get authHandleHeroBody;

  /// No description provided for @authHandleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'HANDLE'**
  String get authHandleFieldLabel;

  /// No description provided for @authHandleFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Lowercase. Minimal. Permanent enough to matter.'**
  String get authHandleFieldCaption;

  /// No description provided for @authHandleInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get authHandleInputLabel;

  /// No description provided for @authHandleInputHint.
  ///
  /// In en, this message translates to:
  /// **'cold.operator'**
  String get authHandleInputHint;

  /// No description provided for @authHandleBindingSection.
  ///
  /// In en, this message translates to:
  /// **'BINDING FLOW'**
  String get authHandleBindingSection;

  /// No description provided for @authHandleStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Generate local identity'**
  String get authHandleStep1Title;

  /// No description provided for @authHandleStep1Body.
  ///
  /// In en, this message translates to:
  /// **'Create device-bound material and keep the private side on this device.'**
  String get authHandleStep1Body;

  /// No description provided for @authHandleStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Register handle'**
  String get authHandleStep2Title;

  /// No description provided for @authHandleStep2Body.
  ///
  /// In en, this message translates to:
  /// **'Publish only public device material and handle metadata.'**
  String get authHandleStep2Body;

  /// No description provided for @authHandleStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Check the device'**
  String get authHandleStep3Title;

  /// No description provided for @authHandleStep3Body.
  ///
  /// In en, this message translates to:
  /// **'Request a short-lived server challenge for this registered device.'**
  String get authHandleStep3Body;

  /// No description provided for @authHandleStep4Title.
  ///
  /// In en, this message translates to:
  /// **'Verify and bind'**
  String get authHandleStep4Title;

  /// No description provided for @authHandleStep4Body.
  ///
  /// In en, this message translates to:
  /// **'Complete verification and activate the device session.'**
  String get authHandleStep4Body;

  /// No description provided for @authHandleFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Binding failed'**
  String get authHandleFailedTitle;

  /// No description provided for @authHandleBindCta.
  ///
  /// In en, this message translates to:
  /// **'Bind this device'**
  String get authHandleBindCta;

  /// No description provided for @authStageGeneratingKeys.
  ///
  /// In en, this message translates to:
  /// **'Generating local identity'**
  String get authStageGeneratingKeys;

  /// No description provided for @authStageRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering handle'**
  String get authStageRegistering;

  /// No description provided for @authStageRequestingChallenge.
  ///
  /// In en, this message translates to:
  /// **'Requesting challenge'**
  String get authStageRequestingChallenge;

  /// No description provided for @authStageVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying device'**
  String get authStageVerifying;

  /// No description provided for @authStageComplete.
  ///
  /// In en, this message translates to:
  /// **'Bound'**
  String get authStageComplete;

  /// No description provided for @authDefaultDeviceName.
  ///
  /// In en, this message translates to:
  /// **'VEIL Mobile'**
  String get authDefaultDeviceName;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfileTitle;

  /// No description provided for @settingsLoadingDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'Loading devices'**
  String get settingsLoadingDeviceGraph;

  /// No description provided for @settingsLoadingDeviceGraphBody.
  ///
  /// In en, this message translates to:
  /// **'Reviewing the bound devices known to this account.'**
  String get settingsLoadingDeviceGraphBody;

  /// No description provided for @settingsDeviceGraphUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device list unavailable'**
  String get settingsDeviceGraphUnavailable;

  /// No description provided for @settingsNoTrustedDevices.
  ///
  /// In en, this message translates to:
  /// **'No trusted devices visible'**
  String get settingsNoTrustedDevices;

  /// No description provided for @settingsAppLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLockTitle;

  /// No description provided for @settingsAppLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Biometric and PIN lock on this device only'**
  String get settingsAppLockSubtitle;

  /// No description provided for @settingsDeviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Device transfer'**
  String get settingsDeviceTransferTitle;

  /// No description provided for @settingsDeviceTransferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Old device must initiate and approve'**
  String get settingsDeviceTransferSubtitle;

  /// No description provided for @settingsSecurityStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Security status'**
  String get settingsSecurityStatusTitle;

  /// No description provided for @settingsSecurityStatusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keys, lock and relay connection on this device'**
  String get settingsSecurityStatusSubtitle;

  /// No description provided for @settingsNoRecoveryPath.
  ///
  /// In en, this message translates to:
  /// **'No recovery path'**
  String get settingsNoRecoveryPath;

  /// No description provided for @settingsSectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY'**
  String get settingsSectionPrivacy;

  /// No description provided for @settingsReadReceiptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send read receipts'**
  String get settingsReadReceiptsTitle;

  /// No description provided for @settingsReadReceiptsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, contacts don\'t learn what you read, and you see their reads only as delivered.'**
  String get settingsReadReceiptsSubtitle;

  /// No description provided for @settingsTypingIndicatorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send typing indicators'**
  String get settingsTypingIndicatorsTitle;

  /// No description provided for @settingsTypingIndicatorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lets contacts see while you type. Off unless you turn it on.'**
  String get settingsTypingIndicatorsSubtitle;

  /// No description provided for @settingsLockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get settingsLockNow;

  /// No description provided for @settingsWipeLocal.
  ///
  /// In en, this message translates to:
  /// **'Wipe local device state'**
  String get settingsWipeLocal;

  /// No description provided for @settingsWipeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Wipe this device locally?'**
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
  /// **'Log out'**
  String get settingsLogout;

  /// No description provided for @settingsDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently removes your account, messages, and contacts. This cannot be undone.'**
  String get settingsDeleteAccountBody;

  /// No description provided for @settingsDeleteAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get settingsDeleteAccountAction;

  /// No description provided for @settingsDeleteAccountConfirmHeadline.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get settingsDeleteAccountConfirmHeadline;

  /// No description provided for @settingsDeviceGraphLoadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The list of trusted devices could not be loaded. The security controls of this device still work.'**
  String get settingsDeviceGraphLoadFailedBody;

  /// No description provided for @settingsNoTrustedDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'The relay lists no device for this account yet. What is bound to this device stays on it and cannot be recovered.'**
  String get settingsNoTrustedDevicesBody;

  /// No description provided for @settingsRefreshDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'Refresh device list'**
  String get settingsRefreshDeviceGraph;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionDevices.
  ///
  /// In en, this message translates to:
  /// **'DEVICES'**
  String get settingsSectionDevices;

  /// No description provided for @settingsSectionTools.
  ///
  /// In en, this message translates to:
  /// **'TOOLS'**
  String get settingsSectionTools;

  /// No description provided for @settingsSectionIrreversible.
  ///
  /// In en, this message translates to:
  /// **'CANNOT BE UNDONE'**
  String get settingsSectionIrreversible;

  /// No description provided for @settingsDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Trusted devices'**
  String get settingsDevicesTitle;

  /// No description provided for @settingsDevicesRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device holds this account} other{{count} devices hold this account}}'**
  String settingsDevicesRowCount(int count);

  /// No description provided for @settingsDevicesTrustedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trusted device} other{{count} trusted devices}}'**
  String settingsDevicesTrustedCount(int count);

  /// No description provided for @settingsDevicesTrustedWithStale.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trusted device} other{{count} trusted devices}} ({stale} stale)'**
  String settingsDevicesTrustedWithStale(int count, int stale);

  /// No description provided for @settingsDestructiveNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'What you erase here stays erased. VEIL keeps no backup and has no way to restore a device or an account.'**
  String get settingsDestructiveNoticeBody;

  /// No description provided for @settingsLockNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide the current session behind the app lock immediately'**
  String get settingsLockNowSubtitle;

  /// No description provided for @settingsWipeLocalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes the session, keys, encrypted cache, PIN and onboarding state from this device only. The relay is not told.'**
  String get settingsWipeLocalSubtitle;

  /// No description provided for @settingsWipeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This erases local VEIL state on this device. It does not create a recovery path. If this is your only active device, access is gone.'**
  String get settingsWipeConfirmBody;

  /// No description provided for @settingsWipeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Wipe local state'**
  String get settingsWipeConfirmAction;

  /// No description provided for @settingsRevokeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Revokes this device on the relay and wipes its local state. No recovery exists.'**
  String get settingsRevokeSubtitle;

  /// No description provided for @settingsRevokeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the active device binding for this account on this device and wipes local state here. VEIL cannot restore it.'**
  String get settingsRevokeConfirmBody;

  /// No description provided for @settingsRevokeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke device'**
  String get settingsRevokeConfirmAction;

  /// No description provided for @settingsLogoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Erases this device\'s keys, session and messages. You cannot sign back in: the account returns here only by transfer from another trusted device.'**
  String get settingsLogoutSubtitle;

  /// No description provided for @settingsLogoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out of this device?'**
  String get settingsLogoutConfirmTitle;

  /// No description provided for @settingsLogoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This erases the keys that make this device yours. VEIL cannot sign you back in. If this is your only trusted device, the account is gone.'**
  String get settingsLogoutConfirmBody;

  /// No description provided for @settingsLogoutConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'LOG OUT'**
  String get settingsLogoutConfirmPhrase;

  /// No description provided for @settingsWipeConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'WIPE'**
  String get settingsWipeConfirmPhrase;

  /// No description provided for @settingsRevokeConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'REVOKE'**
  String get settingsRevokeConfirmPhrase;

  /// No description provided for @settingsDeleteAccountConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get settingsDeleteAccountConfirmPhrase;

  /// No description provided for @settingsTypePhraseToContinue.
  ///
  /// In en, this message translates to:
  /// **'Type {phrase} to continue.'**
  String settingsTypePhraseToContinue(String phrase);

  /// No description provided for @settingsRevokeListedTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke {deviceName}?'**
  String settingsRevokeListedTitle(String deviceName);

  /// No description provided for @settingsRevokeListedBody.
  ///
  /// In en, this message translates to:
  /// **'This removes {deviceName} from your trusted devices. VEIL will not create a recovery path for that device.'**
  String settingsRevokeListedBody(String deviceName);

  /// No description provided for @settingsRevokeListedDone.
  ///
  /// In en, this message translates to:
  /// **'{deviceName} is no longer a trusted device.'**
  String settingsRevokeListedDone(String deviceName);

  /// No description provided for @settingsRevokeListedFailed.
  ///
  /// In en, this message translates to:
  /// **'The device could not be revoked. Try again.'**
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
  /// **'Trusted'**
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
  /// **'Created {when}'**
  String settingsDeviceCreated(String when);

  /// No description provided for @settingsDeviceSeen.
  ///
  /// In en, this message translates to:
  /// **'Seen {when}'**
  String settingsDeviceSeen(String when);

  /// No description provided for @settingsDeviceSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced {when}'**
  String settingsDeviceSynced(String when);

  /// No description provided for @settingsDeviceActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity {when}'**
  String settingsDeviceActivity(String when);

  /// No description provided for @settingsDeviceTrustedAt.
  ///
  /// In en, this message translates to:
  /// **'Trusted {when}'**
  String settingsDeviceTrustedAt(String when);

  /// No description provided for @settingsDeviceJoinedFrom.
  ///
  /// In en, this message translates to:
  /// **'Joined from {device}'**
  String settingsDeviceJoinedFrom(String device);

  /// No description provided for @settingsDeviceRevokedAt.
  ///
  /// In en, this message translates to:
  /// **'Revoked {when}'**
  String settingsDeviceRevokedAt(String when);

  /// No description provided for @settingsDeviceNoteCurrent.
  ///
  /// In en, this message translates to:
  /// **'This is the current trusted device. If every trusted device is lost, VEIL cannot restore access.'**
  String get settingsDeviceNoteCurrent;

  /// No description provided for @settingsDeviceNotePreferred.
  ///
  /// In en, this message translates to:
  /// **'This trusted device is the current preferred routing device. It is not a cloud recovery anchor.'**
  String get settingsDeviceNotePreferred;

  /// No description provided for @settingsDeviceNoteTrusted.
  ///
  /// In en, this message translates to:
  /// **'This device remains trusted and can continue syncing while another trusted device exists.'**
  String get settingsDeviceNoteTrusted;

  /// No description provided for @settingsDeviceNoteStale.
  ///
  /// In en, this message translates to:
  /// **'This device is still trusted but recent trusted activity has gone quiet. Revoke it if it should no longer retain access.'**
  String get settingsDeviceNoteStale;

  /// No description provided for @settingsDeviceNoteRevoked.
  ///
  /// In en, this message translates to:
  /// **'This device is no longer trusted and cannot resume the session.'**
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
  /// **'Recent trusted activity {when}'**
  String settingsGraphRecentActivity(String when);

  /// No description provided for @settingsGraphPreferredDiffersTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferred device differs'**
  String get settingsGraphPreferredDiffersTitle;

  /// No description provided for @settingsGraphPreferredDiffersBody.
  ///
  /// In en, this message translates to:
  /// **'{preferred} is currently preferred for routing and directory compatibility. {current} remains trusted.'**
  String settingsGraphPreferredDiffersBody(String preferred, String current);

  /// No description provided for @settingsGraphStaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Stale trusted devices present'**
  String get settingsGraphStaleTitle;

  /// No description provided for @settingsGraphStaleBody.
  ///
  /// In en, this message translates to:
  /// **'Some trusted devices have no recent trusted activity. Stale does not mean revoked, but they should be reviewed deliberately.'**
  String get settingsGraphStaleBody;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'What you send here is encrypted on this device, for the people in this chat only.'**
  String get chatEmptyBody;

  /// No description provided for @chatEmptyVerifyAction.
  ///
  /// In en, this message translates to:
  /// **'Compare safety numbers'**
  String get chatEmptyVerifyAction;

  /// No description provided for @chatLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load messages'**
  String get chatLoadFailedTitle;

  /// No description provided for @chatLoadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get chatLoadFailedBody;

  /// No description provided for @chatComposeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
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
  /// **'Loading messages'**
  String get chatLoadingTitle;

  /// No description provided for @chatLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Fetching the messages sent to this device and decrypting them.'**
  String get chatLoadingBody;

  /// No description provided for @chatConversationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Conversation not found'**
  String get chatConversationNotFound;

  /// No description provided for @chatRelockTitle.
  ///
  /// In en, this message translates to:
  /// **'Session locked'**
  String get chatRelockTitle;

  /// No description provided for @chatRelockBody.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app to continue this conversation.'**
  String get chatRelockBody;

  /// No description provided for @chatTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Secure conversation'**
  String get chatTitleFallback;

  /// No description provided for @chatSubtitleOnline.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
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
  /// **'Disappearing messages: {value}'**
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
  /// **'Search messages'**
  String get chatSearchTooltip;

  /// No description provided for @chatSearchMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matches on this device} =1{1 match on this device} other{{count} matches on this device}}'**
  String chatSearchMatchCount(int count);

  /// No description provided for @chatSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching this device…'**
  String get chatSearchSearching;

  /// No description provided for @chatBannerConversationIssue.
  ///
  /// In en, this message translates to:
  /// **'Conversation issue'**
  String get chatBannerConversationIssue;

  /// No description provided for @chatBannerRelayReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Relay reconnecting'**
  String get chatBannerRelayReconnecting;

  /// No description provided for @chatBannerDeliveryStalled.
  ///
  /// In en, this message translates to:
  /// **'Delivery stalled'**
  String get chatBannerDeliveryStalled;

  /// No description provided for @chatBannerQueuedLocally.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be sent'**
  String get chatBannerQueuedLocally;

  /// No description provided for @chatBannerFailedSends.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message was not sent.} other{{count} messages were not sent.}} Retry once the relay is reachable.'**
  String chatBannerFailedSends(int count);

  /// No description provided for @chatBannerUploadingAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment is} other{{count} attachments are}} being uploaded, encrypted, before sending.'**
  String chatBannerUploadingAttachments(int count);

  /// No description provided for @chatBannerQueuedMessages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message is} other{{count} messages are}} waiting on this device and will be sent after reconnecting.'**
  String chatBannerQueuedMessages(int count);

  /// No description provided for @chatRetryFailedSendsAction.
  ///
  /// In en, this message translates to:
  /// **'Retry failed sends'**
  String get chatRetryFailedSendsAction;

  /// No description provided for @chatLoadOlder.
  ///
  /// In en, this message translates to:
  /// **'Load older'**
  String get chatLoadOlder;

  /// No description provided for @chatLoadingOlder.
  ///
  /// In en, this message translates to:
  /// **'Loading older'**
  String get chatLoadingOlder;

  /// No description provided for @chatSearchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get chatSearchEmptyTitle;

  /// No description provided for @chatSearchEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this chat on this device matches. Only messages loaded here are searched.'**
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
  /// **'Messages do not disappear.'**
  String get chatTtlOffCaption;

  /// No description provided for @chatTtl10s.
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get chatTtl10s;

  /// No description provided for @chatTtl10sCaption.
  ///
  /// In en, this message translates to:
  /// **'Gone almost at once. For when the other person is looking.'**
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
  /// **'A good default for everyday chats.'**
  String get chatTtl1dCaption;

  /// No description provided for @chatTtlCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom timer'**
  String get chatTtlCustom;

  /// No description provided for @chatTtlDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disappear off'**
  String get chatTtlDisabledLabel;

  /// No description provided for @chatAttachmentTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'Download ticket issued'**
  String get chatAttachmentTicketTitle;

  /// No description provided for @chatAttachmentTicketBody.
  ///
  /// In en, this message translates to:
  /// **'The relay issued a short-lived download ticket for this device.\n\nSummary: {summary}\n\nThis build stops here: it does not fetch or open the file yet. The ticket itself is not shown, so it cannot be copied or shared.'**
  String chatAttachmentTicketBody(String summary);

  /// No description provided for @chatAttachmentTicketFailed.
  ///
  /// In en, this message translates to:
  /// **'Download request failed'**
  String get chatAttachmentTicketFailed;

  /// No description provided for @chatAttachmentResolveAction.
  ///
  /// In en, this message translates to:
  /// **'Request download'**
  String get chatAttachmentResolveAction;

  /// No description provided for @chatAttachmentResolvingAction.
  ///
  /// In en, this message translates to:
  /// **'Requesting download'**
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
  /// **'Attachment state'**
  String get chatAttachmentStateBanner;

  /// No description provided for @chatAttachmentCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'This version cannot open attachments.'**
  String get chatAttachmentCannotOpen;

  /// No description provided for @reactionsMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More reactions'**
  String get reactionsMoreTooltip;

  /// No description provided for @attachmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachmentTitle;

  /// No description provided for @attachmentPlaceholderNotice.
  ///
  /// In en, this message translates to:
  /// **'This version has no file picker. It sends a placeholder file instead: 2 KB of random bytes, encrypted and uploaded the way a chosen file will be.'**
  String get attachmentPlaceholderNotice;

  /// No description provided for @attachmentNameCaption.
  ///
  /// In en, this message translates to:
  /// **'The name stays on this device. Its extension sets the type the recipient is shown: {contentType}'**
  String attachmentNameCaption(String contentType);

  /// No description provided for @attachmentNameInputLabel.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get attachmentNameInputLabel;

  /// No description provided for @attachmentSendFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachment send failed'**
  String get attachmentSendFailedTitle;

  /// No description provided for @attachmentSendAction.
  ///
  /// In en, this message translates to:
  /// **'Encrypt and send'**
  String get attachmentSendAction;

  /// No description provided for @attachmentSendingAction.
  ///
  /// In en, this message translates to:
  /// **'Encrypting and sending'**
  String get attachmentSendingAction;

  /// No description provided for @chatScreenshotToast.
  ///
  /// In en, this message translates to:
  /// **'Screenshot detected in this conversation. Veil cannot prevent it on this device — a notice is being sent to the other side.'**
  String get chatScreenshotToast;

  /// No description provided for @chatScreenshotSystemNotice.
  ///
  /// In en, this message translates to:
  /// **'Peer took a screenshot of this conversation on their device.'**
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
  /// **'Held back: the sender\'s identity changed'**
  String get chatDecryptIdentityRejected;

  /// No description provided for @chatLegacyUnverifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Sender not verified (old format)'**
  String get chatLegacyUnverifiedBadge;

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
  /// **'The server listed this group without its group encryption keys. This device keeps using them.'**
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
  /// **'Nothing is sent to the new key until you review it.'**
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
  /// **'They showed a new key in a group you share. Until you review it there, they are not marked as verified.'**
  String get chatIdentityChangedElsewhereBody;

  /// No description provided for @chatAccountHoldOtherTitle.
  ///
  /// In en, this message translates to:
  /// **'A different account'**
  String get chatAccountHoldOtherTitle;

  /// No description provided for @chatAccountHoldOtherBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed as @{handle}, but it is not the account you talked to as @{handle} before. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String chatAccountHoldOtherBody(String handle);

  /// No description provided for @chatAccountHoldUnissuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Name no VEIL server gives out'**
  String get chatAccountHoldUnissuedTitle;

  /// No description provided for @chatAccountHoldUnissuedBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed under a name no VEIL server issues, so it may only look like someone you know. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String get chatAccountHoldUnissuedBody;

  /// No description provided for @chatAccountHoldOwnTitle.
  ///
  /// In en, this message translates to:
  /// **'Another account under your name'**
  String get chatAccountHoldOwnTitle;

  /// No description provided for @chatAccountHoldOwnBody.
  ///
  /// In en, this message translates to:
  /// **'This chat is listed under your own name, @{handle}, but with another account. No one else can have your name: the list this device received was altered, perhaps to pass someone off as you. Nothing is sent or opened here until you confirm you want to talk to this account.'**
  String chatAccountHoldOwnBody(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk to this other @{handle}?'**
  String chatAccountHoldOwnConfirmTitle(String handle);

  /// No description provided for @chatAccountHoldOwnConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'No other VEIL account can have your name: the server showed this account under it. Continue only if you confirmed another way (in person, a call) whose account this is.'**
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
  /// **'Retry send'**
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
  /// **'Queued'**
  String get chatDeliveryQueued;

  /// No description provided for @chatDeliveryUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get chatDeliveryUploading;

  /// No description provided for @chatDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry required'**
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
  /// **'Staged'**
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
  /// **'Finalizing'**
  String get chatPhaseFinalizing;

  /// No description provided for @chatPhaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry required'**
  String get chatPhaseFailed;

  /// No description provided for @chatPhaseCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get chatPhaseCanceled;

  /// No description provided for @chatPhaseDescStaged.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on this device and ready.{sizeLabel} The upload starts once the relay is reachable.'**
  String chatPhaseDescStaged(String sizeLabel);

  /// No description provided for @chatPhaseDescPreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting permission to upload and checking the encrypted file.'**
  String get chatPhaseDescPreparing;

  /// No description provided for @chatPhaseDescUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading the encrypted file. The relay never sees its contents.'**
  String get chatPhaseDescUploading;

  /// No description provided for @chatPhaseDescFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Attaching the uploaded file to an encrypted message.'**
  String get chatPhaseDescFinalizing;

  /// No description provided for @chatPhaseDescFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed. A retry uses the encrypted copy kept on this device.'**
  String get chatPhaseDescFailed;

  /// No description provided for @chatPhaseDescCanceled.
  ///
  /// In en, this message translates to:
  /// **'Upload stopped on this device. A retry starts over with the encrypted copy kept here.'**
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
  /// **'typing…'**
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
  /// **'{count, plural, =1{1 message is} other{{count} messages are}} waiting for the relay to come back. {retryLabel}'**
  String chatNetworkRecoveryFailed(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryUploading.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment is} other{{count} attachments are}} paused while the relay reconnects. {retryLabel}'**
  String chatNetworkRecoveryUploading(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryQueued.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message stays} other{{count} messages stay}} queued on this device. {retryLabel}'**
  String chatNetworkRecoveryQueued(int count, String retryLabel);

  /// No description provided for @chatRetryResumes.
  ///
  /// In en, this message translates to:
  /// **'Sending resumes when the relay reconnects.'**
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
  /// **'This device no longer has a trusted VEIL session.'**
  String get errorSessionRequired;

  /// No description provided for @errorTransferNeedsApi.
  ///
  /// In en, this message translates to:
  /// **'Device transfer is available only while connected to the VEIL API.'**
  String get errorTransferNeedsApi;

  /// No description provided for @errorClaimBeforeCompletion.
  ///
  /// In en, this message translates to:
  /// **'Register this new device first, then wait for approval from the old device.'**
  String get errorClaimBeforeCompletion;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The relay returned an unexpected response. Try again.'**
  String get errorUnexpectedResponse;

  /// No description provided for @errorUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'The encrypted upload failed. Check the connection and try again.'**
  String get errorUploadFailed;

  /// No description provided for @errorSessionInvalid.
  ///
  /// In en, this message translates to:
  /// **'This session is no longer valid on this device.'**
  String get errorSessionInvalid;

  /// No description provided for @errorNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This action is not allowed on the current device.'**
  String get errorNotAllowed;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'The relay could not find what was asked for.'**
  String get errorNotFound;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'This request conflicts with the current state. Refresh and try again.'**
  String get errorConflict;

  /// No description provided for @errorRejected.
  ///
  /// In en, this message translates to:
  /// **'The submitted values were rejected. Review them and try again.'**
  String get errorRejected;

  /// No description provided for @errorRelayFailed.
  ///
  /// In en, this message translates to:
  /// **'The VEIL relay could not complete the request. Try again shortly.'**
  String get errorRelayFailed;

  /// No description provided for @errorApiNeedsTls.
  ///
  /// In en, this message translates to:
  /// **'The VEIL API endpoint must use TLS outside local development.'**
  String get errorApiNeedsTls;

  /// No description provided for @errorRealtimeNeedsTls.
  ///
  /// In en, this message translates to:
  /// **'The VEIL realtime endpoint must use TLS outside local development.'**
  String get errorRealtimeNeedsTls;

  /// No description provided for @conversationsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get conversationsEmptyTitle;

  /// No description provided for @conversationsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Find someone by handle and send the first encrypted message.'**
  String get conversationsEmptyBody;

  /// No description provided for @conversationsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversations and archive'**
  String get conversationsSearchHint;

  /// No description provided for @conversationsNewChat.
  ///
  /// In en, this message translates to:
  /// **'New direct chat'**
  String get conversationsNewChat;

  /// No description provided for @conversationsNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get conversationsNewGroup;

  /// No description provided for @conversationsArchiveSection.
  ///
  /// In en, this message translates to:
  /// **'Archive results'**
  String get conversationsArchiveSection;

  /// No description provided for @conversationsLoadingArchive.
  ///
  /// In en, this message translates to:
  /// **'Searching archive…'**
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
  /// **'Encrypted image'**
  String get conversationsPreviewImage;

  /// No description provided for @conversationsPreviewAttachment.
  ///
  /// In en, this message translates to:
  /// **'Encrypted attachment'**
  String get conversationsPreviewAttachment;

  /// No description provided for @conversationsPreviewSystem.
  ///
  /// In en, this message translates to:
  /// **'Security notice'**
  String get conversationsPreviewSystem;

  /// No description provided for @conversationsPreviewVoice.
  ///
  /// In en, this message translates to:
  /// **'Encrypted voice note'**
  String get conversationsPreviewVoice;

  /// No description provided for @conversationsPreviewSticker.
  ///
  /// In en, this message translates to:
  /// **'Encrypted sticker'**
  String get conversationsPreviewSticker;

  /// No description provided for @conversationsPreviewReaction.
  ///
  /// In en, this message translates to:
  /// **'Encrypted reaction'**
  String get conversationsPreviewReaction;

  /// No description provided for @conversationsPreviewCall.
  ///
  /// In en, this message translates to:
  /// **'Encrypted call event'**
  String get conversationsPreviewCall;

  /// No description provided for @conversationsRelayLinked.
  ///
  /// In en, this message translates to:
  /// **'Relay linked'**
  String get conversationsRelayLinked;

  /// No description provided for @conversationsRelayIdle.
  ///
  /// In en, this message translates to:
  /// **'Relay not connected'**
  String get conversationsRelayIdle;

  /// No description provided for @conversationsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conversation} other{{count} conversations}}'**
  String conversationsCount(int count);

  /// No description provided for @conversationsNoBackup.
  ///
  /// In en, this message translates to:
  /// **'No backup'**
  String get conversationsNoBackup;

  /// No description provided for @conversationsSyncIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync issue'**
  String get conversationsSyncIssueTitle;

  /// No description provided for @conversationsRelayInterruptedBody.
  ///
  /// In en, this message translates to:
  /// **'The connection to the relay dropped. Messages waiting to be sent go out once it is back.'**
  String get conversationsRelayInterruptedBody;

  /// No description provided for @conversationsSearchHintCompact.
  ///
  /// In en, this message translates to:
  /// **'Search chats and messages'**
  String get conversationsSearchHintCompact;

  /// No description provided for @conversationsSearchLocalNote.
  ///
  /// In en, this message translates to:
  /// **'Search stays on this device.'**
  String get conversationsSearchLocalNote;

  /// No description provided for @conversationsFilterAllSenders.
  ///
  /// In en, this message translates to:
  /// **'All senders'**
  String get conversationsFilterAllSenders;

  /// No description provided for @conversationsFilterMine.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get conversationsFilterMine;

  /// No description provided for @conversationsFilterTheirs.
  ///
  /// In en, this message translates to:
  /// **'Theirs'**
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
  /// **'Last 7d'**
  String get conversationsFilterLast7Days;

  /// No description provided for @conversationsFilterLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30d'**
  String get conversationsFilterLast30Days;

  /// No description provided for @conversationsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'CONVERSATIONS'**
  String get conversationsSectionLabel;

  /// No description provided for @conversationsMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String conversationsMatchCount(int count);

  /// No description provided for @conversationsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching conversations'**
  String get conversationsNoMatchTitle;

  /// No description provided for @conversationsNoneYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get conversationsNoneYetTitle;

  /// No description provided for @conversationsNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'No name or handle on this device matches.'**
  String get conversationsNoMatchBody;

  /// No description provided for @conversationsNoneYetBody.
  ///
  /// In en, this message translates to:
  /// **'Start one with someone\'s handle. VEIL does not look through your contacts: you find people by the handle they give you.'**
  String get conversationsNoneYetBody;

  /// No description provided for @conversationsStartDirect.
  ///
  /// In en, this message translates to:
  /// **'Start direct chat'**
  String get conversationsStartDirect;

  /// No description provided for @conversationsMessagesSection.
  ///
  /// In en, this message translates to:
  /// **'MESSAGES'**
  String get conversationsMessagesSection;

  /// No description provided for @conversationsResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String conversationsResultCount(int count);

  /// No description provided for @conversationsNoMessageMatchBody.
  ///
  /// In en, this message translates to:
  /// **'No message on this device matches with these filters.'**
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
  /// **'Image'**
  String get conversationsKindImage;

  /// No description provided for @conversationsKindAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get conversationsKindAttachment;

  /// No description provided for @conversationsKindSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get conversationsKindSystem;

  /// No description provided for @conversationsKindVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
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

  /// No description provided for @conversationsKindCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get conversationsKindCall;

  /// No description provided for @conversationsLoadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more'**
  String get conversationsLoadingMore;

  /// No description provided for @conversationsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more results'**
  String get conversationsLoadMore;

  /// No description provided for @conversationsChoosePaneTitle.
  ///
  /// In en, this message translates to:
  /// **'Select a conversation'**
  String get conversationsChoosePaneTitle;

  /// No description provided for @conversationsChoosePaneBody.
  ///
  /// In en, this message translates to:
  /// **'Pick one from the list, or start a new one from the bar above it.'**
  String get conversationsChoosePaneBody;

  /// No description provided for @conversationsNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get conversationsNewTooltip;

  /// No description provided for @conversationsRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Conversation with {name}'**
  String conversationsRowSemantics(String name);

  /// No description provided for @conversationsGroupRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Group conversation with {names}'**
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

  /// No description provided for @navStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get navStories;

  /// No description provided for @navCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get navCalls;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @oneTimeLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'One-time secret link'**
  String get oneTimeLinkTitle;

  /// No description provided for @oneTimeLinkSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An encrypted message that is gone once opened. The recipient needs no app.'**
  String get oneTimeLinkSettingsSubtitle;

  /// No description provided for @oneTimeLinkSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret'**
  String get oneTimeLinkSecretLabel;

  /// No description provided for @oneTimeLinkSecretHint.
  ///
  /// In en, this message translates to:
  /// **'A password, an account number, a sensitive note…'**
  String get oneTimeLinkSecretHint;

  /// No description provided for @oneTimeLinkUsePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Lock with a passphrase'**
  String get oneTimeLinkUsePassphrase;

  /// No description provided for @oneTimeLinkUsePassphraseBody.
  ///
  /// In en, this message translates to:
  /// **'Keeps the key out of the link. Send the passphrase another way.'**
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
  /// **'The link could not be created. Try again in a moment.'**
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
  /// **'Unopened, the relay deletes it on {when}.'**
  String oneTimeLinkExpires(String when);

  /// No description provided for @oneTimeLinkSendPassphraseApart.
  ///
  /// In en, this message translates to:
  /// **'Send the passphrase separately from the link.'**
  String get oneTimeLinkSendPassphraseApart;

  /// No description provided for @oneTimeLinkProtectsLabel.
  ///
  /// In en, this message translates to:
  /// **'WHAT IT PROTECTS'**
  String get oneTimeLinkProtectsLabel;

  /// No description provided for @oneTimeLinkProtectsEncrypted.
  ///
  /// In en, this message translates to:
  /// **'The secret is encrypted on this device. The relay stores only ciphertext and is never sent the key.'**
  String get oneTimeLinkProtectsEncrypted;

  /// No description provided for @oneTimeLinkProtectsBurn.
  ///
  /// In en, this message translates to:
  /// **'The relay deletes it the first time it is opened, and when it expires unopened.'**
  String get oneTimeLinkProtectsBurn;

  /// No description provided for @oneTimeLinkLimitsLabel.
  ///
  /// In en, this message translates to:
  /// **'WHAT IT DOES NOT PROTECT'**
  String get oneTimeLinkLimitsLabel;

  /// No description provided for @oneTimeLinkLimitHolder.
  ///
  /// In en, this message translates to:
  /// **'Whoever gets the whole link first can read it. If the channel is not safe, lock it with a passphrase.'**
  String get oneTimeLinkLimitHolder;

  /// No description provided for @oneTimeLinkLimitReader.
  ///
  /// In en, this message translates to:
  /// **'The reader can copy or screenshot it. One-time means one opening, not copy protection.'**
  String get oneTimeLinkLimitReader;

  /// No description provided for @oneTimeLinkLimitRelay.
  ///
  /// In en, this message translates to:
  /// **'The relay sees when a link is made and opened, its size and the network addresses. It also serves the page that opens the link in the recipient\'s browser, so a link is only as trustworthy as the relay.'**
  String get oneTimeLinkLimitRelay;

  /// No description provided for @contactsNotice.
  ///
  /// In en, this message translates to:
  /// **'The relay keeps which accounts you added. The names you give them stay on this device.'**
  String get contactsNotice;

  /// No description provided for @contactsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
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
  /// **'Working…'**
  String get contactsWorking;

  /// No description provided for @contactsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Contacts could not be loaded'**
  String get contactsErrorTitle;

  /// No description provided for @contactsErrorBody.
  ///
  /// In en, this message translates to:
  /// **'The list below is as it was last loaded.'**
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
  /// **'No name or handle matches your search.'**
  String get contactsEmptySearchBody;

  /// No description provided for @contactsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add someone by their handle to keep them at hand.'**
  String get contactsEmptyBody;

  /// No description provided for @contactsAddSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the exact handle. VEIL does not scan address books.'**
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
  /// **'Private label'**
  String get contactsNicknameHint;

  /// No description provided for @contactsSave.
  ///
  /// In en, this message translates to:
  /// **'Save contact'**
  String get contactsSave;

  /// No description provided for @contactsAddFailed.
  ///
  /// In en, this message translates to:
  /// **'That handle could not be added. Check the spelling and your connection.'**
  String get contactsAddFailed;

  /// No description provided for @contactsAdded.
  ///
  /// In en, this message translates to:
  /// **'Contact @{handle} added'**
  String contactsAdded(String handle);

  /// No description provided for @contactsStartChat.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get contactsStartChat;

  /// No description provided for @contactsStartChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start conversation'**
  String get contactsStartChatFailed;

  /// No description provided for @contactsEditNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get contactsEditNickname;

  /// No description provided for @contactsSaveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save nickname'**
  String get contactsSaveNickname;

  /// No description provided for @contactsNicknameCaption.
  ///
  /// In en, this message translates to:
  /// **'Only this device knows the nickname. Leave it empty to show the handle.'**
  String get contactsNicknameCaption;

  /// No description provided for @contactsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get contactsRemove;

  /// No description provided for @contactsRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed from contacts'**
  String contactsRemoved(String name);

  /// No description provided for @contactsRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove contact'**
  String get contactsRemoveFailed;

  /// No description provided for @contactsRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Contact {name}'**
  String contactsRowSemantics(String name);

  /// No description provided for @callsMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get callsMissed;

  /// No description provided for @callsDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get callsDeclined;

  /// No description provided for @callsRinging.
  ///
  /// In en, this message translates to:
  /// **'Ringing'**
  String get callsRinging;

  /// No description provided for @callsIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get callsIncoming;

  /// No description provided for @callsOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get callsOutgoing;

  /// No description provided for @callsToday.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String callsToday(String time);

  /// No description provided for @callsYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String callsYesterday(String time);

  /// No description provided for @callsUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Call history unavailable'**
  String get callsUnavailableTitle;

  /// No description provided for @callsUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again.'**
  String get callsUnavailableBody;

  /// No description provided for @callsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No call history'**
  String get callsEmptyTitle;

  /// No description provided for @callsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'This version cannot place or receive calls, so there is nothing to list yet.'**
  String get callsEmptyBody;

  /// No description provided for @callsNotice.
  ///
  /// In en, this message translates to:
  /// **'This version cannot place or receive calls. Tap a call to open its chat.'**
  String get callsNotice;

  /// No description provided for @callsUnknownCounterparty.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get callsUnknownCounterparty;

  /// No description provided for @callScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callScreenTitle;

  /// No description provided for @callScreenUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Calls are not available in this version'**
  String get callScreenUnavailableTitle;

  /// No description provided for @callScreenUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Voice and video calls are not built yet. No call was placed, and the other person was not notified.'**
  String get callScreenUnavailableBody;

  /// No description provided for @mediaPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos'**
  String get mediaPickerTitle;

  /// No description provided for @mediaPickerUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos cannot be sent in this version'**
  String get mediaPickerUnavailableTitle;

  /// No description provided for @mediaPickerUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'This version does not read the photo library or use the camera. Nothing was chosen or sent.'**
  String get mediaPickerUnavailableBody;

  /// No description provided for @voiceRecorderTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceRecorderTitle;

  /// No description provided for @voiceRecorderUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice messages cannot be recorded in this version'**
  String get voiceRecorderUnavailableTitle;

  /// No description provided for @voiceRecorderUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'This version does not use the microphone. Nothing was recorded or sent.'**
  String get voiceRecorderUnavailableBody;

  /// No description provided for @stickerPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get stickerPickerTitle;

  /// No description provided for @stickerPickerTabSmileys.
  ///
  /// In en, this message translates to:
  /// **'Smileys'**
  String get stickerPickerTabSmileys;

  /// No description provided for @stickerPickerTabGestures.
  ///
  /// In en, this message translates to:
  /// **'Gestures'**
  String get stickerPickerTabGestures;

  /// No description provided for @stickerPickerTabSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get stickerPickerTabSymbols;

  /// No description provided for @storiesNotice.
  ///
  /// In en, this message translates to:
  /// **'Stories are encrypted, and this version cannot open or post them yet. Nothing is marked as viewed.'**
  String get storiesNotice;

  /// No description provided for @storiesUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Stories could not be loaded'**
  String get storiesUnavailableTitle;

  /// No description provided for @storiesUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Pull down to try again.'**
  String get storiesUnavailableBody;

  /// No description provided for @storiesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No stories'**
  String get storiesEmptyTitle;

  /// No description provided for @storiesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody has shared a story with you in the last 24 hours.'**
  String get storiesEmptyBody;

  /// No description provided for @storiesUnknownAuthor.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get storiesUnknownAuthor;

  /// No description provided for @storiesRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 story} other{{count} stories}}'**
  String storiesRowCount(int count);

  /// No description provided for @storiesAgeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get storiesAgeJustNow;

  /// No description provided for @storiesAgeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String storiesAgeMinutes(int count);

  /// No description provided for @storiesAgeHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String storiesAgeHours(int count);

  /// No description provided for @storyViewerUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This story cannot be opened'**
  String get storyViewerUnavailableTitle;

  /// No description provided for @storyViewerUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Stories are encrypted, and this version cannot open them yet. The story was not marked as viewed.'**
  String get storyViewerUnavailableBody;

  /// No description provided for @notificationNewMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL'**
  String get notificationNewMessageTitle;

  /// No description provided for @notificationNewMessageBody.
  ///
  /// In en, this message translates to:
  /// **'New encrypted message'**
  String get notificationNewMessageBody;

  /// No description provided for @startDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'New direct chat'**
  String get startDirectTitle;

  /// No description provided for @startDirectInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get startDirectInputLabel;

  /// No description provided for @startDirectErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to open conversation'**
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
  /// **'Open conversation'**
  String get startDirectOpenButton;

  /// No description provided for @startDirectNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'No contact sync'**
  String get startDirectNoteTitle;

  /// No description provided for @startDirectNote.
  ///
  /// In en, this message translates to:
  /// **'VEIL does not read your contacts or phone book, and suggests no one. A conversation opens only when you know the exact handle.'**
  String get startDirectNote;

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
  /// **'Weekend hiking'**
  String get startGroupNameHint;

  /// No description provided for @startGroupDescriptionInput.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get startGroupDescriptionInput;

  /// No description provided for @startGroupDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What is this group for?'**
  String get startGroupDescriptionHint;

  /// No description provided for @startGroupMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 handle} other{{count} handles}}'**
  String startGroupMembersCount(int count);

  /// No description provided for @startGroupMembersCaption.
  ///
  /// In en, this message translates to:
  /// **'Separate handles with commas or spaces. This version cannot add members later, so list everyone now.'**
  String get startGroupMembersCaption;

  /// No description provided for @startGroupMembersInput.
  ///
  /// In en, this message translates to:
  /// **'Member handles'**
  String get startGroupMembersInput;

  /// No description provided for @startGroupErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to create group'**
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
  /// **'Messages in a group are end-to-end encrypted. Its name, description and member list are not: the relay stores them as you type them here.'**
  String get startGroupNote;

  /// No description provided for @safetyNumbersTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumbersTitle;

  /// No description provided for @safetyNumbersLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Deriving safety number'**
  String get safetyNumbersLoadingTitle;

  /// No description provided for @safetyNumbersLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Hashing identity keys locally.'**
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
  /// **'This runs a fresh key agreement with your contact\'s current keys, and your next message starts the new session. Messages already on their way still open. Use this if you suspect this device or your contact\'s device was briefly exposed: a stolen copy of the old session cannot read what the new one carries.'**
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
  /// **'No session yet — send a message first'**
  String get safetyNumbersNoSessionYet;

  /// No description provided for @safetyNumbersRotationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start a new session. Try again in a moment.'**
  String get safetyNumbersRotationFailed;

  /// No description provided for @safetyNumbersErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load safety number'**
  String get safetyNumbersErrorTitle;

  /// No description provided for @safetyNumbersErrorBody.
  ///
  /// In en, this message translates to:
  /// **'This device could not work out the safety number. Try again in a moment.'**
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
  /// **'This group has no other participants yet — invite someone to verify.'**
  String get safetyNumbersNoMembersBody;

  /// No description provided for @safetyNumbersGroupEyebrow.
  ///
  /// In en, this message translates to:
  /// **'VERIFY GROUP MEMBERS'**
  String get safetyNumbersGroupEyebrow;

  /// No description provided for @safetyNumbersGroupTitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Verify each member of this group'**
  String get safetyNumbersGroupTitleGeneric;

  /// No description provided for @safetyNumbersGroupTitleNamed.
  ///
  /// In en, this message translates to:
  /// **'Verify each member of {groupName}'**
  String safetyNumbersGroupTitleNamed(String groupName);

  /// No description provided for @safetyNumbersGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a member to see their 60-digit safety number. Compare it on a channel you trust — read it aloud over a call or scan the QR. A mismatch means that specific member\'s device may be compromised.'**
  String get safetyNumbersGroupBody;

  /// No description provided for @safetyNumbersUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get safetyNumbersUnverified;

  /// No description provided for @safetyNumbersVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get safetyNumbersVerified;

  /// No description provided for @safetyNumbersDetailEyebrow.
  ///
  /// In en, this message translates to:
  /// **'VERIFY IDENTITY'**
  String get safetyNumbersDetailEyebrow;

  /// No description provided for @safetyNumbersDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure you\'re talking to {peer}'**
  String safetyNumbersDetailTitle(String peer);

  /// No description provided for @safetyNumbersDetailBody.
  ///
  /// In en, this message translates to:
  /// **'Both of you should see the same 60-digit number. Compare on a channel you trust — read it aloud over a call, or scan the QR. If the numbers don\'t match, someone is in the middle of your conversation.'**
  String get safetyNumbersDetailBody;

  /// No description provided for @safetyNumbersKeyChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'This contact\'s identity key changed'**
  String get safetyNumbersKeyChangedTitle;

  /// No description provided for @safetyNumbersKeyChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'This contact\'s identity key is different from the one you verified on {date}. This can happen after a reinstall — or if someone is impersonating them. Verify again before trusting.'**
  String safetyNumbersKeyChangedMessage(String date);

  /// No description provided for @safetyNumbersVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified on {date}'**
  String safetyNumbersVerifiedOn(String date);

  /// No description provided for @safetyNumbersVerifiedNote.
  ///
  /// In en, this message translates to:
  /// **'If this contact reinstalls or switches devices, this verification is invalidated and you\'ll see a warning.'**
  String get safetyNumbersVerifiedNote;

  /// No description provided for @safetyNumbersReVerify.
  ///
  /// In en, this message translates to:
  /// **'Re-verify with new key'**
  String get safetyNumbersReVerify;

  /// No description provided for @safetyNumbersMarkVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark as verified'**
  String get safetyNumbersMarkVerified;

  /// No description provided for @safetyNumbersRotateEyebrow.
  ///
  /// In en, this message translates to:
  /// **'NEW SESSION'**
  String get safetyNumbersRotateEyebrow;

  /// No description provided for @safetyNumbersRotateBody.
  ///
  /// In en, this message translates to:
  /// **'Runs a fresh key agreement with your contact\'s current keys; your next message starts the new session, and messages already on their way still open. Use if this device or your contact\'s was briefly exposed.'**
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

  /// No description provided for @safetyNumbersCardLabel.
  ///
  /// In en, this message translates to:
  /// **'SAFETY NUMBER'**
  String get safetyNumbersCardLabel;

  /// No description provided for @safetyNumbersCardLabelCurrent.
  ///
  /// In en, this message translates to:
  /// **'CURRENT SAFETY NUMBER'**
  String get safetyNumbersCardLabelCurrent;

  /// No description provided for @safetyNumbersCardLabelNew.
  ///
  /// In en, this message translates to:
  /// **'NEW SAFETY NUMBER'**
  String get safetyNumbersCardLabelNew;

  /// No description provided for @safetyNumbersScanLabel.
  ///
  /// In en, this message translates to:
  /// **'SCAN TO COMPARE'**
  String get safetyNumbersScanLabel;

  /// No description provided for @safetyNumbersQrNote.
  ///
  /// In en, this message translates to:
  /// **'This QR holds both public identity keys and user ids, nothing secret.'**
  String get safetyNumbersQrNote;

  /// No description provided for @safetyNumbersNoPinTitle.
  ///
  /// In en, this message translates to:
  /// **'No safety number yet'**
  String get safetyNumbersNoPinTitle;

  /// No description provided for @safetyNumbersNoPinBody.
  ///
  /// In en, this message translates to:
  /// **'Exchange a message first. This device then pins the identity it talks to, and the number appears here.'**
  String get safetyNumbersNoPinBody;

  /// No description provided for @safetyNumbersDirectoryMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The key server lists a different key'**
  String get safetyNumbersDirectoryMismatchTitle;

  /// No description provided for @safetyNumbersDirectoryMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The key server now serves another identity key for this device than the one pinned here. Nothing is sent to that key unless you compare and accept it.'**
  String get safetyNumbersDirectoryMismatchBody;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'The key server lists another device'**
  String get safetyNumbersDirectoryOtherDeviceTitle;

  /// No description provided for @safetyNumbersDirectoryOtherDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'This conversation encrypts to a different device than the one the key server now lists for this contact. The safety number on this page belongs to the device it encrypts to. If your contact changed devices, compare numbers with them again.'**
  String get safetyNumbersDirectoryOtherDeviceBody;

  /// No description provided for @safetyNumbersPendingBody.
  ///
  /// In en, this message translates to:
  /// **'This contact presents a new identity key. Compare the new safety number below before accepting it.'**
  String get safetyNumbersPendingBody;

  /// No description provided for @safetyNumbersAcceptNewKey.
  ///
  /// In en, this message translates to:
  /// **'Accept the new key'**
  String get safetyNumbersAcceptNewKey;

  /// No description provided for @safetyNumbersKeepCurrentKey.
  ///
  /// In en, this message translates to:
  /// **'Keep the current key'**
  String get safetyNumbersKeepCurrentKey;

  /// No description provided for @safetyNumbersScanAction.
  ///
  /// In en, this message translates to:
  /// **'Compare a scanned code'**
  String get safetyNumbersScanAction;

  /// No description provided for @safetyNumbersScanFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Scanned code'**
  String get safetyNumbersScanFieldLabel;

  /// No description provided for @safetyNumbersScanVerify.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get safetyNumbersScanVerify;

  /// No description provided for @safetyNumbersScanMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The codes do not match'**
  String get safetyNumbersScanMismatchTitle;

  /// No description provided for @safetyNumbersScanMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'Someone may be in the middle of this conversation. Do not mark it verified; compare again in person.'**
  String get safetyNumbersScanMismatchBody;

  /// No description provided for @safetyNumbersScanInvalid.
  ///
  /// In en, this message translates to:
  /// **'That is not a VEIL safety code.'**
  String get safetyNumbersScanInvalid;

  /// No description provided for @safetyNumbersScanUnsupported.
  ///
  /// In en, this message translates to:
  /// **'That code uses a safety-number version this app does not support.'**
  String get safetyNumbersScanUnsupported;

  /// No description provided for @safetyNumbersReverifyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare the new safety number'**
  String get safetyNumbersReverifyDialogTitle;

  /// No description provided for @safetyNumbersReverifyDialogBody.
  ///
  /// In en, this message translates to:
  /// **'You had verified {peer}. Accept the new key as verified only after comparing this number with {peer} in person or on a call you trust.'**
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
  /// **'{peer} presented a new identity key in another conversation. Until you review it there, {peer} is not shown as verified. The number below is the one this device pinned before the change.'**
  String safetyNumbersChangedElsewhereBody(String peer);

  /// No description provided for @safetyNumbersReviewChange.
  ///
  /// In en, this message translates to:
  /// **'Review the new key'**
  String get safetyNumbersReviewChange;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileNicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Nickname saved on this device'**
  String get profileNicknameSaved;

  /// No description provided for @profileHandleLabel.
  ///
  /// In en, this message translates to:
  /// **'HANDLE'**
  String get profileHandleLabel;

  /// No description provided for @profileHandleCaption.
  ///
  /// In en, this message translates to:
  /// **'Others find and message you by this handle. It cannot be changed.'**
  String get profileHandleCaption;

  /// No description provided for @profileNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'NICKNAME'**
  String get profileNicknameLabel;

  /// No description provided for @profileNicknameCaption.
  ///
  /// In en, this message translates to:
  /// **'Only this device knows it. Peers see your handle.'**
  String get profileNicknameCaption;

  /// No description provided for @profileNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'How this device greets you'**
  String get profileNicknameHint;

  /// No description provided for @profileNicknameNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileNicknameNotSet;

  /// No description provided for @profilePrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'No profile on the relay'**
  String get profilePrivacyTitle;

  /// No description provided for @profilePrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'The relay routes by handle and stores no name, bio or status. Your nickname stays on this device and is erased with it.'**
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

  /// No description provided for @deviceTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Device transfer'**
  String get deviceTransferTitle;

  /// No description provided for @deviceTransferChipOldDevice.
  ///
  /// In en, this message translates to:
  /// **'Old device'**
  String get deviceTransferChipOldDevice;

  /// No description provided for @deviceTransferChipNewDevice.
  ///
  /// In en, this message translates to:
  /// **'New device'**
  String get deviceTransferChipNewDevice;

  /// No description provided for @deviceTransferNoFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'No fallback path'**
  String get deviceTransferNoFallbackTitle;

  /// No description provided for @deviceTransferNoFallbackBody.
  ///
  /// In en, this message translates to:
  /// **'If the old device is gone, transfer fails. VEIL does not offer recovery, reset, export, or admin restore.'**
  String get deviceTransferNoFallbackBody;

  /// No description provided for @deviceTransferPayloadCopied.
  ///
  /// In en, this message translates to:
  /// **'Transfer code copied.'**
  String get deviceTransferPayloadCopied;

  /// No description provided for @deviceTransferReturnToConversations.
  ///
  /// In en, this message translates to:
  /// **'Return to conversations'**
  String get deviceTransferReturnToConversations;

  /// No description provided for @deviceTransferPayloadInvalid.
  ///
  /// In en, this message translates to:
  /// **'The transfer code\'s format is not valid.'**
  String get deviceTransferPayloadInvalid;

  /// No description provided for @deviceTransferImportFirst.
  ///
  /// In en, this message translates to:
  /// **'Use a valid transfer code first.'**
  String get deviceTransferImportFirst;

  /// No description provided for @deviceTransferClaimFailed.
  ///
  /// In en, this message translates to:
  /// **'Claim failed.'**
  String get deviceTransferClaimFailed;

  /// No description provided for @deviceTransferRegisterBeforeComplete.
  ///
  /// In en, this message translates to:
  /// **'Register this new-device claim before completion.'**
  String get deviceTransferRegisterBeforeComplete;

  /// No description provided for @deviceTransferCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'This transfer code has expired. Issue a new one on the old device.'**
  String get deviceTransferCodeExpired;

  /// No description provided for @deviceTransferFinishStartedFirst.
  ///
  /// In en, this message translates to:
  /// **'This device already started completing a transfer that the relay may have finished. Complete that transfer on this device before using another code.'**
  String get deviceTransferFinishStartedFirst;

  /// No description provided for @deviceTransferComplete.
  ///
  /// In en, this message translates to:
  /// **'Transfer complete. Your handle is now on this device and the old device has been signed out.'**
  String get deviceTransferComplete;

  /// No description provided for @deviceTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed.'**
  String get deviceTransferFailed;

  /// No description provided for @deviceTransferOldRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Old device session required'**
  String get deviceTransferOldRequiredTitle;

  /// No description provided for @deviceTransferOldRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in on a currently trusted device to issue and approve a transfer.'**
  String get deviceTransferOldRequiredBody;

  /// No description provided for @deviceTransferOldIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue a transfer code'**
  String get deviceTransferOldIssueTitle;

  /// No description provided for @deviceTransferOldIssueBody.
  ///
  /// In en, this message translates to:
  /// **'Opens a short-lived transfer session for your new device.'**
  String get deviceTransferOldIssueBody;

  /// No description provided for @deviceTransferOldIssueExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'The transfer session expired. Issue a new code.'**
  String get deviceTransferOldIssueExpiredBody;

  /// No description provided for @deviceTransferOldHandTitle.
  ///
  /// In en, this message translates to:
  /// **'Give the code to the new device'**
  String get deviceTransferOldHandTitle;

  /// No description provided for @deviceTransferOldHandBody.
  ///
  /// In en, this message translates to:
  /// **'The code appears here once it is issued.'**
  String get deviceTransferOldHandBody;

  /// No description provided for @deviceTransferOldApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve the new device'**
  String get deviceTransferOldApproveTitle;

  /// No description provided for @deviceTransferOldApproveBody.
  ///
  /// In en, this message translates to:
  /// **'After it registers, the new device shows a claim code. You approve that code here.'**
  String get deviceTransferOldApproveBody;

  /// No description provided for @deviceTransferNewCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste the transfer code'**
  String get deviceTransferNewCodeTitle;

  /// No description provided for @deviceTransferNewCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Issue the code on your old device, then paste it here.'**
  String get deviceTransferNewCodeBody;

  /// No description provided for @deviceTransferNewCodeExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'The transfer code expired before the transfer was finished. Issue a new code on the old device and paste it here.'**
  String get deviceTransferNewCodeExpiredBody;

  /// No description provided for @deviceTransferNewCodeChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get deviceTransferNewCodeChange;

  /// No description provided for @deviceTransferNewRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register this device'**
  String get deviceTransferNewRegisterTitle;

  /// No description provided for @deviceTransferNewCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve on the old device, then finish'**
  String get deviceTransferNewCompleteTitle;

  /// No description provided for @deviceTransferNewCompleteBodyUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Once registered, this device shows a claim code for the old device to approve.'**
  String get deviceTransferNewCompleteBodyUpcoming;

  /// No description provided for @deviceTransferNewCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Enter this claim code on the old device and approve it there.'**
  String get deviceTransferNewCompleteBody;

  /// No description provided for @deviceTransferNewCompleteNote.
  ///
  /// In en, this message translates to:
  /// **'When you finish, the old device is signed out. Conversation history does not move to this device.'**
  String get deviceTransferNewCompleteNote;

  /// No description provided for @deviceTransferStep1BodyExpires.
  ///
  /// In en, this message translates to:
  /// **'This transfer session expires {when}.'**
  String deviceTransferStep1BodyExpires(String when);

  /// No description provided for @deviceTransferStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get deviceTransferStatusExpired;

  /// No description provided for @deviceTransferIssuingToken.
  ///
  /// In en, this message translates to:
  /// **'Issuing code'**
  String get deviceTransferIssuingToken;

  /// No description provided for @deviceTransferIssueToken.
  ///
  /// In en, this message translates to:
  /// **'Issue transfer code'**
  String get deviceTransferIssueToken;

  /// No description provided for @deviceTransferClaimFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Approve only the exact claim code shown on the new device you trust.'**
  String get deviceTransferClaimFieldCaption;

  /// No description provided for @deviceTransferClaimInputLabel.
  ///
  /// In en, this message translates to:
  /// **'New-device claim code'**
  String get deviceTransferClaimInputLabel;

  /// No description provided for @deviceTransferClaimInputHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the claim code shown on the new device'**
  String get deviceTransferClaimInputHint;

  /// No description provided for @deviceTransferApproveClaim.
  ///
  /// In en, this message translates to:
  /// **'Approve this claim'**
  String get deviceTransferApproveClaim;

  /// No description provided for @deviceTransferCompleteOnNewNote.
  ///
  /// In en, this message translates to:
  /// **'After you approve, finish on the new device. This device is then signed out and its local history is erased. Conversation history does not move to the new device.'**
  String get deviceTransferCompleteOnNewNote;

  /// No description provided for @deviceTransferCopyPayload.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get deviceTransferCopyPayload;

  /// No description provided for @deviceTransferClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get deviceTransferClear;

  /// No description provided for @deviceTransferStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer status'**
  String get deviceTransferStatusTitle;

  /// No description provided for @deviceTransferStatusNeedsApi.
  ///
  /// In en, this message translates to:
  /// **'This build is not connected to a relay, so it cannot transfer.'**
  String get deviceTransferStatusNeedsApi;

  /// No description provided for @deviceTransferStatusTokenReady.
  ///
  /// In en, this message translates to:
  /// **'Transfer session open. The code is ready.'**
  String get deviceTransferStatusTokenReady;

  /// No description provided for @deviceTransferStatusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Start transfer first.'**
  String get deviceTransferStatusNotStarted;

  /// No description provided for @deviceTransferStatusClaimCodeMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter the new-device claim code first.'**
  String get deviceTransferStatusClaimCodeMissing;

  /// No description provided for @deviceTransferStatusClaimNotWaiting.
  ///
  /// In en, this message translates to:
  /// **'No claim {claimId} is waiting on this transfer.'**
  String deviceTransferStatusClaimNotWaiting(String claimId);

  /// No description provided for @deviceTransferStatusClaimApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved claim {claimId} on old device. Key fingerprint: {fingerprint}'**
  String deviceTransferStatusClaimApproved(String claimId, String fingerprint);

  /// No description provided for @deviceTransferFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed'**
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
  /// **'This device creates its own keys and sends a claim that only the old device can approve. Register before the transfer code expires.'**
  String get deviceTransferNewDeviceCaption;

  /// No description provided for @deviceTransferDeviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceTransferDeviceNameLabel;

  /// No description provided for @deviceTransferClaimCode.
  ///
  /// In en, this message translates to:
  /// **'Claim code {claimId}'**
  String deviceTransferClaimCode(String claimId);

  /// No description provided for @deviceTransferClaimFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Claim fingerprint {fingerprint}'**
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
  /// **'Registering claim'**
  String get deviceTransferRegisteringClaim;

  /// No description provided for @deviceTransferRegisterNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Register this new device'**
  String get deviceTransferRegisterNewDevice;

  /// No description provided for @deviceTransferCompleting.
  ///
  /// In en, this message translates to:
  /// **'Completing transfer'**
  String get deviceTransferCompleting;

  /// No description provided for @deviceTransferCompleteOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Complete on this device'**
  String get deviceTransferCompleteOnDevice;

  /// No description provided for @deviceTransferExpiryNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get deviceTransferExpiryNow;

  /// No description provided for @deviceTransferExpiryInSeconds.
  ///
  /// In en, this message translates to:
  /// **'in {seconds}s'**
  String deviceTransferExpiryInSeconds(int seconds);

  /// No description provided for @deviceTransferExpiryInMinutes.
  ///
  /// In en, this message translates to:
  /// **'in {minutes}m'**
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

  /// No description provided for @aiDemoBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepared answers'**
  String get aiDemoBannerTitle;

  /// No description provided for @aiDemoBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Demo: replies are scripted on this device. Nothing is sent anywhere.'**
  String get aiDemoBannerBody;

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'VEIL Assistant'**
  String get aiTitle;

  /// No description provided for @aiClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get aiClearTooltip;

  /// No description provided for @aiIntro.
  ///
  /// In en, this message translates to:
  /// **'There is no AI model behind this preview. Pick a question below to see the answer prepared for it.'**
  String get aiIntro;

  /// No description provided for @aiQuestionBackup.
  ///
  /// In en, this message translates to:
  /// **'Is there a backup?'**
  String get aiQuestionBackup;

  /// No description provided for @aiAnswerBackup.
  ///
  /// In en, this message translates to:
  /// **'No. VEIL has no backup and no account recovery. Messages are encrypted on this device before they reach the relay.'**
  String get aiAnswerBackup;

  /// No description provided for @aiQuestionNewDevice.
  ///
  /// In en, this message translates to:
  /// **'How do I move to a new device?'**
  String get aiQuestionNewDevice;

  /// No description provided for @aiAnswerNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Your old device has to approve the new one. There is no cloud recovery path, by design.'**
  String get aiAnswerNewDevice;

  /// No description provided for @aiQuestionGroups.
  ///
  /// In en, this message translates to:
  /// **'Are group messages encrypted?'**
  String get aiQuestionGroups;

  /// No description provided for @aiAnswerGroups.
  ///
  /// In en, this message translates to:
  /// **'Yes. Group messages are encrypted on the sending device before they reach the relay.'**
  String get aiAnswerGroups;

  /// No description provided for @aiQuestionCalls.
  ///
  /// In en, this message translates to:
  /// **'Can I make calls?'**
  String get aiQuestionCalls;

  /// No description provided for @aiAnswerCalls.
  ///
  /// In en, this message translates to:
  /// **'Not in this version. Voice and video calls are not built yet.'**
  String get aiAnswerCalls;

  /// No description provided for @securityStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Security status'**
  String get securityStatusTitle;

  /// No description provided for @securityStatusHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'No backup. No recovery. No leaks.'**
  String get securityStatusHeroTitle;

  /// No description provided for @securityStatusHeroBody.
  ///
  /// In en, this message translates to:
  /// **'The identity and runtime rows are read from this device and this build. The product rules hold for every VEIL build.'**
  String get securityStatusHeroBody;

  /// No description provided for @securityStatusAttentionTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs a look} other{{count} items need a look}}'**
  String securityStatusAttentionTitle(int count);

  /// No description provided for @securityStatusPillPrivateBeta.
  ///
  /// In en, this message translates to:
  /// **'Private beta'**
  String get securityStatusPillPrivateBeta;

  /// No description provided for @securityStatusMetricRuntime.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get securityStatusMetricRuntime;

  /// No description provided for @securityStatusMetricRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get securityStatusMetricRelay;

  /// No description provided for @securityStatusMetricRelayLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get securityStatusMetricRelayLinked;

  /// No description provided for @securityStatusMetricCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get securityStatusMetricCache;

  /// No description provided for @securityStatusMetricCacheOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityStatusMetricCacheOff;

  /// No description provided for @securityStatusSectionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get securityStatusSectionIdentity;

  /// No description provided for @securityStatusSectionRuntime.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get securityStatusSectionRuntime;

  /// No description provided for @securityStatusSectionProductRules.
  ///
  /// In en, this message translates to:
  /// **'Product rules'**
  String get securityStatusSectionProductRules;

  /// No description provided for @securityStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
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
  /// **'Enabled'**
  String get securityStatusEnabled;

  /// No description provided for @securityStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get securityStatusDisabled;

  /// No description provided for @securityStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get securityStatusReady;

  /// No description provided for @securityStatusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get securityStatusStarting;

  /// No description provided for @securityStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get securityStatusBlocked;

  /// No description provided for @securityStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get securityStatusIdle;

  /// No description provided for @securityStatusBoundDevice.
  ///
  /// In en, this message translates to:
  /// **'Bound device'**
  String get securityStatusBoundDevice;

  /// No description provided for @securityStatusBoundDeviceUnbound.
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get securityStatusBoundDeviceUnbound;

  /// No description provided for @securityStatusBoundDeviceNoneDetail.
  ///
  /// In en, this message translates to:
  /// **'No active device session is present.'**
  String get securityStatusBoundDeviceNoneDetail;

  /// No description provided for @securityStatusBoundDeviceDetail.
  ///
  /// In en, this message translates to:
  /// **'This device currently holds the active VEIL session.'**
  String get securityStatusBoundDeviceDetail;

  /// No description provided for @securityStatusSecretRefs.
  ///
  /// In en, this message translates to:
  /// **'Device secret keys'**
  String get securityStatusSecretRefs;

  /// No description provided for @securityStatusSecretRefsPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get securityStatusSecretRefsPresent;

  /// No description provided for @securityStatusSecretRefsMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get securityStatusSecretRefsMissing;

  /// No description provided for @securityStatusSecretRefsDetail.
  ///
  /// In en, this message translates to:
  /// **'Private device material stays on the device. The server never receives it.'**
  String get securityStatusSecretRefsDetail;

  /// No description provided for @securityStatusPin.
  ///
  /// In en, this message translates to:
  /// **'App lock PIN'**
  String get securityStatusPin;

  /// No description provided for @securityStatusPinConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get securityStatusPinConfigured;

  /// No description provided for @securityStatusPinUnset.
  ///
  /// In en, this message translates to:
  /// **'Unset'**
  String get securityStatusPinUnset;

  /// No description provided for @securityStatusPinDetail.
  ///
  /// In en, this message translates to:
  /// **'A lock on this device only. VEIL cannot unlock the app for you.'**
  String get securityStatusPinDetail;

  /// No description provided for @securityStatusBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get securityStatusBiometrics;

  /// No description provided for @securityStatusBiometricsDetail.
  ///
  /// In en, this message translates to:
  /// **'Device-level biometric unlock only. No remote fallback exists.'**
  String get securityStatusBiometricsDetail;

  /// No description provided for @securityStatusPrivacyShield.
  ///
  /// In en, this message translates to:
  /// **'Privacy shield'**
  String get securityStatusPrivacyShield;

  /// No description provided for @securityStatusPrivacyShieldDetail.
  ///
  /// In en, this message translates to:
  /// **'When VEIL leaves the foreground, the app obscures previews and re-arms the app lock.'**
  String get securityStatusPrivacyShieldDetail;

  /// No description provided for @securityStatusAppPreview.
  ///
  /// In en, this message translates to:
  /// **'Recent-app preview'**
  String get securityStatusAppPreview;

  /// No description provided for @securityStatusAppPreviewProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get securityStatusAppPreviewProtected;

  /// No description provided for @securityStatusAppPreviewPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get securityStatusAppPreviewPartial;

  /// No description provided for @securityStatusAppPreviewDetail.
  ///
  /// In en, this message translates to:
  /// **'Native and Flutter privacy shields are used to hide app-switcher content while VEIL is backgrounded.'**
  String get securityStatusAppPreviewDetail;

  /// No description provided for @securityStatusScreenCapture.
  ///
  /// In en, this message translates to:
  /// **'Screen capture'**
  String get securityStatusScreenCapture;

  /// No description provided for @securityStatusScreenCapturePlatformLimited.
  ///
  /// In en, this message translates to:
  /// **'Platform-limited'**
  String get securityStatusScreenCapturePlatformLimited;

  /// No description provided for @securityStatusScreenCaptureNotBlocked.
  ///
  /// In en, this message translates to:
  /// **'Not blocked'**
  String get securityStatusScreenCaptureNotBlocked;

  /// No description provided for @securityStatusScreenCaptureSupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'Android blocks screenshots with secure-window flags when enabled.'**
  String get securityStatusScreenCaptureSupportedDetail;

  /// No description provided for @securityStatusScreenCaptureUnsupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'This platform has no public API for full screenshot blocking, so VEIL relies on preview shielding and rapid relocking instead.'**
  String get securityStatusScreenCaptureUnsupportedDetail;

  /// No description provided for @securityStatusScreenCaptureCheckingDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking native screen-capture policy.'**
  String get securityStatusScreenCaptureCheckingDetail;

  /// No description provided for @securityStatusClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard hygiene'**
  String get securityStatusClipboard;

  /// No description provided for @securityStatusClipboardRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get securityStatusClipboardRestricted;

  /// No description provided for @securityStatusClipboardDetail.
  ///
  /// In en, this message translates to:
  /// **'Sensitive attachment tickets are summarized locally instead of exposing raw signed URLs for copy/share.'**
  String get securityStatusClipboardDetail;

  /// No description provided for @securityStatusTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport policy'**
  String get securityStatusTransport;

  /// No description provided for @securityStatusTransportCompliant.
  ///
  /// In en, this message translates to:
  /// **'Compliant'**
  String get securityStatusTransportCompliant;

  /// No description provided for @securityStatusTransportDetail.
  ///
  /// In en, this message translates to:
  /// **'Configured endpoints satisfy the current private-beta transport policy.'**
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
  /// **'This build pins the relay\'s TLS keys ({count}). A certificate whose key matches none of them is refused.'**
  String securityStatusTlsPinsPinnedDetail(int count);

  /// No description provided for @securityStatusTlsPinsUnpinnedDetail.
  ///
  /// In en, this message translates to:
  /// **'This build sets no TLS pins (VEIL_TLS_PINS), so the relay connection accepts any certificate the platform trusts. Release builds stop at a configuration error without them.'**
  String get securityStatusTlsPinsUnpinnedDetail;

  /// No description provided for @securityStatusApiMode.
  ///
  /// In en, this message translates to:
  /// **'Relay address'**
  String get securityStatusApiMode;

  /// No description provided for @securityStatusApiAttached.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get securityStatusApiAttached;

  /// No description provided for @securityStatusApiAttachedDetail.
  ///
  /// In en, this message translates to:
  /// **'A relay address is configured for this build.'**
  String get securityStatusApiAttachedDetail;

  /// No description provided for @securityStatusApiUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No relay address is configured. Messaging is unavailable.'**
  String get securityStatusApiUnavailableDetail;

  /// No description provided for @securityStatusRelayLink.
  ///
  /// In en, this message translates to:
  /// **'Relay link'**
  String get securityStatusRelayLink;

  /// No description provided for @securityStatusRelayConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get securityStatusRelayConnected;

  /// No description provided for @securityStatusRelayConnectedDetail.
  ///
  /// In en, this message translates to:
  /// **'Realtime relay is connected with opaque event payloads.'**
  String get securityStatusRelayConnectedDetail;

  /// No description provided for @securityStatusRelayIdleDetail.
  ///
  /// In en, this message translates to:
  /// **'Realtime relay is disconnected or still syncing.'**
  String get securityStatusRelayIdleDetail;

  /// No description provided for @securityStatusLocalCache.
  ///
  /// In en, this message translates to:
  /// **'Local cache'**
  String get securityStatusLocalCache;

  /// No description provided for @securityStatusLocalCacheDisabledDetail.
  ///
  /// In en, this message translates to:
  /// **'Local message cache is disabled in this build.'**
  String get securityStatusLocalCacheDisabledDetail;

  /// No description provided for @securityStatusLocalCacheDetail.
  ///
  /// In en, this message translates to:
  /// **'Conversations and envelopes are cached locally behind the current private-beta encrypted-at-rest layer, scrubbed from app-switcher previews, and wiped on destructive local lifecycle events.'**
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
  /// **'Clean'**
  String get securityStatusIntegrityClean;

  /// No description provided for @securityStatusIntegrityCompromisedDetail.
  ///
  /// In en, this message translates to:
  /// **'This device matched rooted or jailbroken heuristics. VEIL blocks local unlock in this state.'**
  String get securityStatusIntegrityCompromisedDetail;

  /// No description provided for @securityStatusIntegrityCompromisedReasons.
  ///
  /// In en, this message translates to:
  /// **'This device matched rooted or jailbroken heuristics. {reasons}'**
  String securityStatusIntegrityCompromisedReasons(String reasons);

  /// No description provided for @securityStatusIntegrityCleanDetail.
  ///
  /// In en, this message translates to:
  /// **'Native rooted and jailbroken heuristics did not trigger on this device.'**
  String get securityStatusIntegrityCleanDetail;

  /// No description provided for @securityStatusIntegrityCheckingDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking native integrity heuristics.'**
  String get securityStatusIntegrityCheckingDetail;

  /// No description provided for @securityStatusCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup'**
  String get securityStatusCloudBackup;

  /// No description provided for @securityStatusCloudBackupDetail.
  ///
  /// In en, this message translates to:
  /// **'VEIL does not keep a recovery copy of your message history.'**
  String get securityStatusCloudBackupDetail;

  /// No description provided for @securityStatusAccountRecovery.
  ///
  /// In en, this message translates to:
  /// **'Account recovery'**
  String get securityStatusAccountRecovery;

  /// No description provided for @securityStatusAccountRecoveryDetail.
  ///
  /// In en, this message translates to:
  /// **'No recovery email, reset flow, or admin restore path exists.'**
  String get securityStatusAccountRecoveryDetail;

  /// No description provided for @securityStatusDeviceTransfer.
  ///
  /// In en, this message translates to:
  /// **'Device transfer'**
  String get securityStatusDeviceTransfer;

  /// No description provided for @securityStatusDeviceTransferValue.
  ///
  /// In en, this message translates to:
  /// **'Old device required'**
  String get securityStatusDeviceTransferValue;

  /// No description provided for @securityStatusDeviceTransferDetail.
  ///
  /// In en, this message translates to:
  /// **'Transfer succeeds only while the old device can approve it.'**
  String get securityStatusDeviceTransferDetail;

  /// No description provided for @securityStatusLocalWipe.
  ///
  /// In en, this message translates to:
  /// **'Local wipe'**
  String get securityStatusLocalWipe;

  /// No description provided for @securityStatusLocalWipeDetail.
  ///
  /// In en, this message translates to:
  /// **'This device can erase local session state, local secrets, encrypted cache, and the app lock without creating a recovery path.'**
  String get securityStatusLocalWipeDetail;

  /// No description provided for @securityStatusCryptoAdapter.
  ///
  /// In en, this message translates to:
  /// **'Crypto adapter'**
  String get securityStatusCryptoAdapter;

  /// No description provided for @securityStatusCryptoVeilRatchet.
  ///
  /// In en, this message translates to:
  /// **'Production (unaudited)'**
  String get securityStatusCryptoVeilRatchet;

  /// No description provided for @securityStatusCryptoVeilRatchetDetail.
  ///
  /// In en, this message translates to:
  /// **'VEIL\'s own X3DH and Double Ratchet (X25519, AES-256-GCM, Ed25519) is active ({adapterId}). An external audit is still pending.'**
  String securityStatusCryptoVeilRatchetDetail(String adapterId);

  /// No description provided for @securityStatusCryptoLibsignal.
  ///
  /// In en, this message translates to:
  /// **'libsignal bridge (unaudited)'**
  String get securityStatusCryptoLibsignal;

  /// No description provided for @securityStatusCryptoLibsignalDetail.
  ///
  /// In en, this message translates to:
  /// **'Sessions and message encryption run in Signal\'s libsignal through VEIL\'s native bridge ({adapterId}). The bridge has not been audited.'**
  String securityStatusCryptoLibsignalDetail(String adapterId);

  /// No description provided for @securityStatusCryptoDevelopment.
  ///
  /// In en, this message translates to:
  /// **'Development only'**
  String get securityStatusCryptoDevelopment;

  /// No description provided for @securityStatusCryptoDevelopmentDetail.
  ///
  /// In en, this message translates to:
  /// **'This build runs a development adapter ({adapterId}), not production cryptography. Do not use it for real conversations.'**
  String securityStatusCryptoDevelopmentDetail(String adapterId);

  /// No description provided for @securityStatusPushPlaintext.
  ///
  /// In en, this message translates to:
  /// **'Push plaintext'**
  String get securityStatusPushPlaintext;

  /// No description provided for @securityStatusPushPlaintextForbidden.
  ///
  /// In en, this message translates to:
  /// **'Forbidden'**
  String get securityStatusPushPlaintextForbidden;

  /// No description provided for @securityStatusPushPlaintextDetail.
  ///
  /// In en, this message translates to:
  /// **'Push payloads must never contain plaintext message content.'**
  String get securityStatusPushPlaintextDetail;

  /// No description provided for @securityStatusPushProvider.
  ///
  /// In en, this message translates to:
  /// **'Push provider'**
  String get securityStatusPushProvider;

  /// No description provided for @securityStatusPushProviderSeam.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get securityStatusPushProviderSeam;

  /// No description provided for @securityStatusPushProviderSeamDetail.
  ///
  /// In en, this message translates to:
  /// **'The metadata-only wake-up path is defined, but a real APNs/FCM provider is not wired in this build.'**
  String get securityStatusPushProviderSeamDetail;

  /// No description provided for @securityStatusPushProviderUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No relay address is configured, so push delivery is unavailable in this build.'**
  String get securityStatusPushProviderUnavailableDetail;

  /// No description provided for @securityStatusPushPayloads.
  ///
  /// In en, this message translates to:
  /// **'Push payloads'**
  String get securityStatusPushPayloads;

  /// No description provided for @securityStatusPushPayloadsMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata only'**
  String get securityStatusPushPayloadsMetadata;

  /// No description provided for @securityStatusPushPayloadsMetadataDetail.
  ///
  /// In en, this message translates to:
  /// **'If push is enabled later, wake-up hints must stay metadata-only. Message bodies remain out of push.'**
  String get securityStatusPushPayloadsMetadataDetail;

  /// No description provided for @securityStatusPushPayloadsUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'No relay address is configured, so push payload generation is unavailable in this build.'**
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
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
