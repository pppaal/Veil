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

  /// No description provided for @pillDeviceBound.
  ///
  /// In en, this message translates to:
  /// **'Device-bound'**
  String get pillDeviceBound;

  /// No description provided for @pillNoRecovery.
  ///
  /// In en, this message translates to:
  /// **'No recovery'**
  String get pillNoRecovery;

  /// No description provided for @pillNoPasswordReset.
  ///
  /// In en, this message translates to:
  /// **'No password reset'**
  String get pillNoPasswordReset;

  /// No description provided for @pillOldDeviceRequired.
  ///
  /// In en, this message translates to:
  /// **'Old device required'**
  String get pillOldDeviceRequired;

  /// No description provided for @pillPrivateBeta.
  ///
  /// In en, this message translates to:
  /// **'Private beta'**
  String get pillPrivateBeta;

  /// No description provided for @pillDeviceBoundMessenger.
  ///
  /// In en, this message translates to:
  /// **'Device-bound messenger'**
  String get pillDeviceBoundMessenger;

  /// No description provided for @pillNoContactSync.
  ///
  /// In en, this message translates to:
  /// **'No contact sync'**
  String get pillNoContactSync;

  /// No description provided for @pillHandleDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Handle discovery'**
  String get pillHandleDiscovery;

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
  /// **'Recent-app previews are obscured and the local barrier is re-armed when the app leaves the foreground.'**
  String get privacyShieldBody;

  /// No description provided for @splashEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRIVATE BETA'**
  String get splashEyebrow;

  /// No description provided for @splashBody.
  ///
  /// In en, this message translates to:
  /// **'No backup. No recovery. No leaks.'**
  String get splashBody;

  /// No description provided for @splashErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Runtime configuration blocked'**
  String get splashErrorTitle;

  /// No description provided for @splashPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing local state'**
  String get splashPreparingTitle;

  /// No description provided for @splashPreparingBody.
  ///
  /// In en, this message translates to:
  /// **'Checking onboarding, session binding, and local security state.'**
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
  /// **'VEIL is device-bound by design. Loss is final. Restore is unavailable. This is not a cloud inbox.'**
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
  /// **'Your private material stays on the device.'**
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
  /// **'Privacy Notice'**
  String get privacyConsentTitle;

  /// No description provided for @privacyConsentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read before using VEIL'**
  String get privacyConsentSubtitle;

  /// No description provided for @privacyConsentEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY PROTECTION'**
  String get privacyConsentEyebrow;

  /// No description provided for @privacyConsentHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy &\nData Protection'**
  String get privacyConsentHeroTitle;

  /// No description provided for @privacyConsentHeroBody.
  ///
  /// In en, this message translates to:
  /// **'VEIL complies with Korea\'s PIPA. Please review the notice below before using the service.'**
  String get privacyConsentHeroBody;

  /// No description provided for @privacyConsentAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree to the collection and use of personal information above. (Required)\nI agree to the collection and use of personal information as described above. (Required)'**
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
  /// **'User handle (unique identifier)'**
  String get privacyConsentCollectItem1;

  /// No description provided for @privacyConsentCollectItem2.
  ///
  /// In en, this message translates to:
  /// **'Device info (platform, device name)'**
  String get privacyConsentCollectItem2;

  /// No description provided for @privacyConsentCollectItem3.
  ///
  /// In en, this message translates to:
  /// **'Public key (for encrypted communication)'**
  String get privacyConsentCollectItem3;

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
  /// **'Device data removed when device is unpaired'**
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
  /// **'Contacts, call logs, or other device personal data'**
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
  /// **'Create Account'**
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

  /// No description provided for @authCreateHeroBody.
  ///
  /// In en, this message translates to:
  /// **'VEIL binds access to the hardware in your hand. If the device is lost, the account is lost with it.'**
  String get authCreateHeroBody;

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

  /// No description provided for @authCreateMetricIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get authCreateMetricIdentity;

  /// No description provided for @authCreateMetricIdentityValue.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get authCreateMetricIdentityValue;

  /// No description provided for @authCreateMetricRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get authCreateMetricRecovery;

  /// No description provided for @authCreateMetricRecoveryValue.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get authCreateMetricRecoveryValue;

  /// No description provided for @authCreateMetricTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get authCreateMetricTransfer;

  /// No description provided for @authCreateMetricTransferValue.
  ///
  /// In en, this message translates to:
  /// **'Old device'**
  String get authCreateMetricTransferValue;

  /// No description provided for @authCreateFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'PROFILE LABEL'**
  String get authCreateFieldLabel;

  /// No description provided for @authCreateFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Handles are the discovery layer. This label is presentation only.'**
  String get authCreateFieldCaption;

  /// No description provided for @authCreateDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get authCreateDisplayName;

  /// No description provided for @authCreateDisplayHint.
  ///
  /// In en, this message translates to:
  /// **'Optional label for this account'**
  String get authCreateDisplayHint;

  /// No description provided for @authCreateTransferLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer from old device'**
  String get authCreateTransferLabel;

  /// No description provided for @authHandleTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Handle'**
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
  /// **'Pick a direct handle for discovery. VEIL binds the handle to this device after local identity material is generated.'**
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

  /// No description provided for @authHandleChoosePrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a handle'**
  String get authHandleChoosePrompt;

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
  /// **'Challenge device'**
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

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsEyebrow.
  ///
  /// In en, this message translates to:
  /// **'LOCAL DEVICE'**
  String get settingsEyebrow;

  /// No description provided for @settingsNoDeviceBound.
  ///
  /// In en, this message translates to:
  /// **'No active device session is bound.'**
  String get settingsNoDeviceBound;

  /// No description provided for @settingsCurrentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current device session: {deviceId}'**
  String settingsCurrentDevice(String deviceId);

  /// No description provided for @settingsPillPrivateByDesign.
  ///
  /// In en, this message translates to:
  /// **'Private by design'**
  String get settingsPillPrivateByDesign;

  /// No description provided for @settingsSectionDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'TRUSTED DEVICE GRAPH'**
  String get settingsSectionDeviceGraph;

  /// No description provided for @settingsLoadingDeviceGraph.
  ///
  /// In en, this message translates to:
  /// **'Loading device graph'**
  String get settingsLoadingDeviceGraph;

  /// No description provided for @settingsLoadingDeviceGraphBody.
  ///
  /// In en, this message translates to:
  /// **'Reviewing the bound devices known to this account.'**
  String get settingsLoadingDeviceGraphBody;

  /// No description provided for @settingsDeviceGraphUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device graph unavailable'**
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
  /// **'Biometric and PIN barrier on this device only'**
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
  /// **'Review local guardrails and runtime state'**
  String get settingsSecurityStatusSubtitle;

  /// No description provided for @settingsNoRecoveryPath.
  ///
  /// In en, this message translates to:
  /// **'No recovery path'**
  String get settingsNoRecoveryPath;

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

  /// No description provided for @settingsIrreversible.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone'**
  String get settingsIrreversible;

  /// No description provided for @settingsDeleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccountTitle;

  /// No description provided for @settingsDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently removes your account, messages, and contacts. This cannot be undone.'**
  String get settingsDeleteAccountBody;

  /// No description provided for @settingsDeleteAccountConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get settingsDeleteAccountConfirmLabel;

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

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Send the first message — it\'s encrypted end-to-end.'**
  String get chatEmptyBody;

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
  /// **'Opening session'**
  String get chatLoadingTitle;

  /// No description provided for @chatLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Preparing encrypted channel…'**
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

  /// No description provided for @chatHeroEyebrow.
  ///
  /// In en, this message translates to:
  /// **'SECURE CONVERSATION'**
  String get chatHeroEyebrow;

  /// No description provided for @chatHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Direct 1:1 exchange only. Message bodies remain opaque to the server and expire locally when configured.'**
  String get chatHeroBody;

  /// No description provided for @chatSubtitleOnline.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get chatSubtitleOnline;

  /// No description provided for @chatSubtitleEmbedded.
  ///
  /// In en, this message translates to:
  /// **'Local search stays on this device. Message bodies remain opaque to the relay.'**
  String get chatSubtitleEmbedded;

  /// No description provided for @chatSubtitleStandalone.
  ///
  /// In en, this message translates to:
  /// **'Direct 1:1 exchange only. Message bodies remain opaque to the server.'**
  String get chatSubtitleStandalone;

  /// No description provided for @chatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search cached messages on this device'**
  String get chatSearchHint;

  /// No description provided for @chatSearchClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get chatSearchClearTooltip;

  /// No description provided for @chatPillAttachmentsEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Attachments encrypted'**
  String get chatPillAttachmentsEncrypted;

  /// No description provided for @chatPillLocalSearchOnly.
  ///
  /// In en, this message translates to:
  /// **'Local search only'**
  String get chatPillLocalSearchOnly;

  /// No description provided for @chatMetricRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get chatMetricRelay;

  /// No description provided for @chatMetricRelayLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get chatMetricRelayLinked;

  /// No description provided for @chatMetricRelayRecovering.
  ///
  /// In en, this message translates to:
  /// **'Recovering'**
  String get chatMetricRelayRecovering;

  /// No description provided for @chatMetricLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded'**
  String get chatMetricLoaded;

  /// No description provided for @chatMetricHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get chatMetricHistory;

  /// No description provided for @chatMetricHistoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading older'**
  String get chatMetricHistoryLoading;

  /// No description provided for @chatMetricHistoryPaged.
  ///
  /// In en, this message translates to:
  /// **'Paged'**
  String get chatMetricHistoryPaged;

  /// No description provided for @chatMetricHistoryComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get chatMetricHistoryComplete;

  /// No description provided for @chatMetricSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get chatMetricSearch;

  /// No description provided for @chatMetricSearchIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get chatMetricSearchIdle;

  /// No description provided for @chatMetricSearchHits.
  ///
  /// In en, this message translates to:
  /// **'{count} hits'**
  String chatMetricSearchHits(int count);

  /// No description provided for @chatBannerHistoryLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Syncing older history'**
  String get chatBannerHistoryLoadingTitle;

  /// No description provided for @chatBannerHistoryLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Pulling older encrypted history from the relay for this trusted device.'**
  String get chatBannerHistoryLoadingBody;

  /// No description provided for @chatBannerHistoryCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation window complete'**
  String get chatBannerHistoryCompleteTitle;

  /// No description provided for @chatBannerHistoryCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'The currently trusted device-local window is fully loaded. Older history is not pending right now.'**
  String get chatBannerHistoryCompleteBody;

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
  /// **'Queued locally'**
  String get chatBannerQueuedLocally;

  /// No description provided for @chatBannerFailedSends.
  ///
  /// In en, this message translates to:
  /// **'{count} message(s) failed to send. Retry when the relay is reachable.'**
  String chatBannerFailedSends(int count);

  /// No description provided for @chatBannerUploadingAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count} attachment message(s) are uploading opaque blobs before send.'**
  String chatBannerUploadingAttachments(int count);

  /// No description provided for @chatBannerQueuedMessages.
  ///
  /// In en, this message translates to:
  /// **'{count} message(s) are staged locally and will retry after reconnect.'**
  String chatBannerQueuedMessages(int count);

  /// No description provided for @chatRetryFailedSendsAction.
  ///
  /// In en, this message translates to:
  /// **'Retry failed sends'**
  String get chatRetryFailedSendsAction;

  /// No description provided for @chatSearchBannerSearchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Searching locally'**
  String get chatSearchBannerSearchingTitle;

  /// No description provided for @chatSearchBannerIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Local message search'**
  String get chatSearchBannerIdleTitle;

  /// No description provided for @chatSearchBannerSearchingBody.
  ///
  /// In en, this message translates to:
  /// **'Scanning cached message text on this device. Relay state does not change.'**
  String get chatSearchBannerSearchingBody;

  /// No description provided for @chatSearchBannerEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No cached message text matched this query in the current conversation.'**
  String get chatSearchBannerEmptyBody;

  /// No description provided for @chatSearchBannerResultBody.
  ///
  /// In en, this message translates to:
  /// **'Showing {count} cached match(es). Clear search to return to full conversation context.'**
  String chatSearchBannerResultBody(int count);

  /// No description provided for @chatComposerExpiryOff.
  ///
  /// In en, this message translates to:
  /// **'This send does not expire unless you change the rule.'**
  String get chatComposerExpiryOff;

  /// No description provided for @chatComposerExpiryOn.
  ///
  /// In en, this message translates to:
  /// **'This send expires in {duration} on every device that sees it.'**
  String chatComposerExpiryOn(String duration);

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
  /// **'No local matches'**
  String get chatSearchEmptyTitle;

  /// No description provided for @chatSearchEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'This device did not find a matching cached message in the current conversation.'**
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
  /// **'Messages remain until manually deleted.'**
  String get chatTtlOffCaption;

  /// No description provided for @chatTtl10s.
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get chatTtl10s;

  /// No description provided for @chatTtl10sCaption.
  ///
  /// In en, this message translates to:
  /// **'Strongest ephemerality. Expect the recipient to be looking.'**
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
  /// **'Default for casual private conversations.'**
  String get chatTtl1dCaption;

  /// No description provided for @chatTtlCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom TTL'**
  String get chatTtlCustom;

  /// No description provided for @chatTtlDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disappear off'**
  String get chatTtlDisabledLabel;

  /// No description provided for @chatAttachmentTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachment ticket ready'**
  String get chatAttachmentTicketTitle;

  /// No description provided for @chatAttachmentTicketBody.
  ///
  /// In en, this message translates to:
  /// **'A short-lived local download ticket was resolved for this device.\n\nSummary: {summary}\n\nCopying and sharing the raw ticket is intentionally disabled.'**
  String chatAttachmentTicketBody(String summary);

  /// No description provided for @chatAttachmentTicketFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment ticket failed'**
  String get chatAttachmentTicketFailed;

  /// No description provided for @chatAttachmentResolveAction.
  ///
  /// In en, this message translates to:
  /// **'Resolve download ticket'**
  String get chatAttachmentResolveAction;

  /// No description provided for @chatAttachmentResolvingAction.
  ///
  /// In en, this message translates to:
  /// **'Resolving ticket'**
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

  /// No description provided for @chatReplyLocally.
  ///
  /// In en, this message translates to:
  /// **'Reply locally'**
  String get chatReplyLocally;

  /// No description provided for @chatReplyPrimed.
  ///
  /// In en, this message translates to:
  /// **'Composer primed for a quick response in this conversation.'**
  String get chatReplyPrimed;

  /// No description provided for @chatScreenshotToast.
  ///
  /// In en, this message translates to:
  /// **'Screenshot detected in this conversation. Veil cannot prevent it on this device — the other side has been notified.'**
  String get chatScreenshotToast;

  /// No description provided for @chatScreenshotSystemNotice.
  ///
  /// In en, this message translates to:
  /// **'Peer took a screenshot of this conversation on their device.'**
  String get chatScreenshotSystemNotice;

  /// No description provided for @chatDecryptingEnvelope.
  ///
  /// In en, this message translates to:
  /// **'Decrypting envelope...'**
  String get chatDecryptingEnvelope;

  /// No description provided for @chatDecryptingSystemNotice.
  ///
  /// In en, this message translates to:
  /// **'Decrypting system notice...'**
  String get chatDecryptingSystemNotice;

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
  /// **'Opaque blob staged locally.{sizeLabel} Upload begins when the relay is reachable.'**
  String chatPhaseDescStaged(String sizeLabel);

  /// No description provided for @chatPhaseDescPreparing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing upload authorization and validating encrypted metadata.'**
  String get chatPhaseDescPreparing;

  /// No description provided for @chatPhaseDescUploading.
  ///
  /// In en, this message translates to:
  /// **'Sending ciphertext-like bytes to object storage. The relay never sees plaintext.'**
  String get chatPhaseDescUploading;

  /// No description provided for @chatPhaseDescFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Binding the uploaded blob into an encrypted message envelope.'**
  String get chatPhaseDescFinalizing;

  /// No description provided for @chatPhaseDescFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Retry will reuse the local encrypted temp blob.'**
  String get chatPhaseDescFailed;

  /// No description provided for @chatPhaseDescCanceled.
  ///
  /// In en, this message translates to:
  /// **'Upload stopped on this device. Retry will request a fresh ticket and reuse the local blob.'**
  String get chatPhaseDescCanceled;

  /// No description provided for @chatAttachmentSizeBytes.
  ///
  /// In en, this message translates to:
  /// **' {count} bytes.'**
  String chatAttachmentSizeBytes(int count);

  /// No description provided for @chatTypingSuffix.
  ///
  /// In en, this message translates to:
  /// **'@{handle} is typing'**
  String chatTypingSuffix(String handle);

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
  /// **'{count} message(s) are waiting on relay recovery. {retryLabel}'**
  String chatNetworkRecoveryFailed(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryUploading.
  ///
  /// In en, this message translates to:
  /// **'{count} attachment message(s) are paused while the relay reconnects. {retryLabel}'**
  String chatNetworkRecoveryUploading(int count, String retryLabel);

  /// No description provided for @chatNetworkRecoveryQueued.
  ///
  /// In en, this message translates to:
  /// **'{count} message(s) remain queued on this device. {retryLabel}'**
  String chatNetworkRecoveryQueued(int count, String retryLabel);

  /// No description provided for @chatRetryResumes.
  ///
  /// In en, this message translates to:
  /// **'Retry resumes when the relay reconnects.'**
  String get chatRetryResumes;

  /// No description provided for @chatRetryNextIn.
  ///
  /// In en, this message translates to:
  /// **'Next retry in {countdown}.'**
  String chatRetryNextIn(String countdown);

  /// No description provided for @chatDurationDays.
  ///
  /// In en, this message translates to:
  /// **'{count} day(s)'**
  String chatDurationDays(int count);

  /// No description provided for @chatDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{count} hour(s)'**
  String chatDurationHours(int count);

  /// No description provided for @chatDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minute(s)'**
  String chatDurationMinutes(int count);

  /// No description provided for @chatDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} second(s)'**
  String chatDurationSeconds(int count);

  /// No description provided for @conversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsTitle;

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

  /// No description provided for @conversationsQueuedOne.
  ///
  /// In en, this message translates to:
  /// **'1 message queued locally'**
  String get conversationsQueuedOne;

  /// No description provided for @conversationsQueuedMany.
  ///
  /// In en, this message translates to:
  /// **'{count} messages queued locally'**
  String conversationsQueuedMany(int count);

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
