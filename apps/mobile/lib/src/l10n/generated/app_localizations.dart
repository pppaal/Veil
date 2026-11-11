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
  /// **'Unverified sender (legacy)'**
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

  /// No description provided for @chatIdentityChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get chatIdentityChangedTitle;

  /// No description provided for @chatIdentityChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Sending is paused until you review the new safety number.'**
  String get chatIdentityChangedBody;

  /// No description provided for @chatIdentityChangedReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get chatIdentityChangedReview;

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

  /// No description provided for @startDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'Find by Handle'**
  String get startDirectTitle;

  /// No description provided for @startDirectEyebrow.
  ///
  /// In en, this message translates to:
  /// **'DIRECT DISCOVERY'**
  String get startDirectEyebrow;

  /// No description provided for @startDirectHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'No contact sync.'**
  String get startDirectHeroTitle;

  /// No description provided for @startDirectHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the handle directly. VEIL does not scan contacts, phone books, or social graphs.'**
  String get startDirectHeroBody;

  /// No description provided for @startDirectPillManual.
  ///
  /// In en, this message translates to:
  /// **'Manual discovery'**
  String get startDirectPillManual;

  /// No description provided for @startDirectPillNoGraph.
  ///
  /// In en, this message translates to:
  /// **'No social graph'**
  String get startDirectPillNoGraph;

  /// No description provided for @startDirectPillDirectOnly.
  ///
  /// In en, this message translates to:
  /// **'Direct only'**
  String get startDirectPillDirectOnly;

  /// No description provided for @startDirectBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Deliberate discovery'**
  String get startDirectBannerTitle;

  /// No description provided for @startDirectBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Conversations open only when you know the exact handle. There is no graph expansion layer here.'**
  String get startDirectBannerBody;

  /// No description provided for @startDirectMetricDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get startDirectMetricDiscovery;

  /// No description provided for @startDirectMetricDiscoveryValue.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get startDirectMetricDiscoveryValue;

  /// No description provided for @startDirectMetricGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get startDirectMetricGraph;

  /// No description provided for @startDirectMetricGraphValue.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get startDirectMetricGraphValue;

  /// No description provided for @startDirectMetricMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get startDirectMetricMode;

  /// No description provided for @startDirectMetricModeValue.
  ///
  /// In en, this message translates to:
  /// **'Direct 1:1'**
  String get startDirectMetricModeValue;

  /// No description provided for @startDirectFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'TARGET HANDLE'**
  String get startDirectFieldLabel;

  /// No description provided for @startDirectAwaitingInput.
  ///
  /// In en, this message translates to:
  /// **'Awaiting input'**
  String get startDirectAwaitingInput;

  /// No description provided for @startDirectFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Discovery stays manual. Direct conversations only.'**
  String get startDirectFieldCaption;

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

  /// No description provided for @startDirectOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening conversation'**
  String get startDirectOpening;

  /// No description provided for @startDirectOpenButton.
  ///
  /// In en, this message translates to:
  /// **'Open direct conversation'**
  String get startDirectOpenButton;

  /// No description provided for @startGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Start Group Chat'**
  String get startGroupTitle;

  /// No description provided for @startGroupEyebrow.
  ///
  /// In en, this message translates to:
  /// **'GROUP CREATION'**
  String get startGroupEyebrow;

  /// No description provided for @startGroupHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Private by invitation.'**
  String get startGroupHeroTitle;

  /// No description provided for @startGroupHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Groups are explicit. Add members by handle — VEIL never expands invites through contact graphs.'**
  String get startGroupHeroBody;

  /// No description provided for @startGroupPillInviteOnly.
  ///
  /// In en, this message translates to:
  /// **'Invite-only'**
  String get startGroupPillInviteOnly;

  /// No description provided for @startGroupPillManualRoster.
  ///
  /// In en, this message translates to:
  /// **'Manual roster'**
  String get startGroupPillManualRoster;

  /// No description provided for @startGroupPillE2E.
  ///
  /// In en, this message translates to:
  /// **'E2E encrypted'**
  String get startGroupPillE2E;

  /// No description provided for @startGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'GROUP NAME'**
  String get startGroupNameLabel;

  /// No description provided for @startGroupRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get startGroupRequired;

  /// No description provided for @startGroupNameCaption.
  ///
  /// In en, this message translates to:
  /// **'Visible to members. You can rename later.'**
  String get startGroupNameCaption;

  /// No description provided for @startGroupNameInput.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get startGroupNameInput;

  /// No description provided for @startGroupDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION'**
  String get startGroupDescriptionLabel;

  /// No description provided for @startGroupDescriptionCaption.
  ///
  /// In en, this message translates to:
  /// **'Optional. Purpose, charter, or context for members.'**
  String get startGroupDescriptionCaption;

  /// No description provided for @startGroupDescriptionInput.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get startGroupDescriptionInput;

  /// No description provided for @startGroupDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What is this group for?'**
  String get startGroupDescriptionHint;

  /// No description provided for @startGroupMembersLabel.
  ///
  /// In en, this message translates to:
  /// **'INITIAL MEMBERS'**
  String get startGroupMembersLabel;

  /// No description provided for @startGroupNoneYet.
  ///
  /// In en, this message translates to:
  /// **'None yet'**
  String get startGroupNoneYet;

  /// No description provided for @startGroupMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} handle(s)'**
  String startGroupMembersCount(int count);

  /// No description provided for @startGroupMembersCaption.
  ///
  /// In en, this message translates to:
  /// **'Comma or space separated handles. You can add more after creation.'**
  String get startGroupMembersCaption;

  /// No description provided for @startGroupMembersInput.
  ///
  /// In en, this message translates to:
  /// **'Member handles'**
  String get startGroupMembersInput;

  /// No description provided for @startGroupPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'Public directory'**
  String get startGroupPublicTitle;

  /// No description provided for @startGroupPublicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Public groups are discoverable by handle. Keep off for invite-only groups.'**
  String get startGroupPublicSubtitle;

  /// No description provided for @startGroupErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to create group'**
  String get startGroupErrorTitle;

  /// No description provided for @startGroupCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating group'**
  String get startGroupCreating;

  /// No description provided for @startGroupCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get startGroupCreateButton;

  /// No description provided for @safetyNumbersTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety Number'**
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
  /// **'Rotate session keys?'**
  String get safetyNumbersRotateDialogTitle;

  /// No description provided for @safetyNumbersRotateDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This forces a fresh Diffie-Hellman ratchet step on your next message. Old skipped message keys for this chat are dropped immediately. Use this if you suspect this device or your peer\'s device was briefly exposed — past messages stay readable, but any stolen session state stops being useful.'**
  String get safetyNumbersRotateDialogBody;

  /// No description provided for @safetyNumbersCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get safetyNumbersCancel;

  /// No description provided for @safetyNumbersRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get safetyNumbersRotate;

  /// No description provided for @safetyNumbersSessionRotated.
  ///
  /// In en, this message translates to:
  /// **'Session keys rotated'**
  String get safetyNumbersSessionRotated;

  /// No description provided for @safetyNumbersNoSessionYet.
  ///
  /// In en, this message translates to:
  /// **'No session yet — send a message first'**
  String get safetyNumbersNoSessionYet;

  /// No description provided for @safetyNumbersRotationFailed.
  ///
  /// In en, this message translates to:
  /// **'Rotation failed: {error}'**
  String safetyNumbersRotationFailed(String error);

  /// No description provided for @safetyNumbersErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load safety number'**
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

  /// No description provided for @safetyNumbersGroupRotateEyebrow.
  ///
  /// In en, this message translates to:
  /// **'ROTATE GROUP SESSION KEYS'**
  String get safetyNumbersGroupRotateEyebrow;

  /// No description provided for @safetyNumbersGroupRotateBody.
  ///
  /// In en, this message translates to:
  /// **'Forces a fresh DH ratchet step on the next group message and drops stashed skipped keys for this group. Affects every member — use if any participant\'s device was briefly exposed.'**
  String get safetyNumbersGroupRotateBody;

  /// No description provided for @safetyNumbersRotatingGroup.
  ///
  /// In en, this message translates to:
  /// **'Rotating…'**
  String get safetyNumbersRotatingGroup;

  /// No description provided for @safetyNumbersRotateGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Rotate group session keys'**
  String get safetyNumbersRotateGroupButton;

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
  /// **'Peer identity key changed'**
  String get safetyNumbersKeyChangedTitle;

  /// No description provided for @safetyNumbersKeyChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'The identity key for this peer is different from the one you verified on {date}. This can happen after a reinstall — or if someone is impersonating them. Verify again before trusting.'**
  String safetyNumbersKeyChangedMessage(String date);

  /// No description provided for @safetyNumbersVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified on {date}'**
  String safetyNumbersVerifiedOn(String date);

  /// No description provided for @safetyNumbersVerifiedNote.
  ///
  /// In en, this message translates to:
  /// **'If this peer reinstalls or switches devices, this verification is invalidated and you\'ll see a warning.'**
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
  /// **'ROTATE SESSION KEYS'**
  String get safetyNumbersRotateEyebrow;

  /// No description provided for @safetyNumbersRotateBody.
  ///
  /// In en, this message translates to:
  /// **'Forces a fresh DH ratchet step on your next message and drops any stashed skipped keys. Use if this device or your peer\'s was briefly exposed.'**
  String get safetyNumbersRotateBody;

  /// No description provided for @safetyNumbersRotating.
  ///
  /// In en, this message translates to:
  /// **'Rotating…'**
  String get safetyNumbersRotating;

  /// No description provided for @safetyNumbersRotateButton.
  ///
  /// In en, this message translates to:
  /// **'Rotate session keys'**
  String get safetyNumbersRotateButton;

  /// No description provided for @safetyNumbersCardLabel.
  ///
  /// In en, this message translates to:
  /// **'SAFETY NUMBER'**
  String get safetyNumbersCardLabel;

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
  /// **'No identity pinned yet'**
  String get safetyNumbersNoPinTitle;

  /// No description provided for @safetyNumbersNoPinBody.
  ///
  /// In en, this message translates to:
  /// **'Exchange a message first: this device pins the identity it talks to.'**
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
  /// **'Your handle cannot be changed.'**
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

  /// No description provided for @profilePrivacyEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY'**
  String get profilePrivacyEyebrow;

  /// No description provided for @profilePrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing about you on the relay'**
  String get profilePrivacyTitle;

  /// No description provided for @profilePrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'The relay routes by handle and stores no name, bio or status. Your nickname stays on this device and is erased with it.'**
  String get profilePrivacyBody;

  /// No description provided for @profileSaveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save nickname'**
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
  /// **'Device Transfer'**
  String get deviceTransferTitle;

  /// No description provided for @deviceTransferHeroEyebrow.
  ///
  /// In en, this message translates to:
  /// **'TRANSFER'**
  String get deviceTransferHeroEyebrow;

  /// No description provided for @deviceTransferHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Old device required.'**
  String get deviceTransferHeroTitle;

  /// No description provided for @deviceTransferHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Transfer is a live trusted-device join. The old device issues the session and approves the exact new-device claim. VEIL does not create recovery.'**
  String get deviceTransferHeroBody;

  /// No description provided for @deviceTransferPillTrustedJoin.
  ///
  /// In en, this message translates to:
  /// **'Trusted-device join'**
  String get deviceTransferPillTrustedJoin;

  /// No description provided for @deviceTransferPillNoFallback.
  ///
  /// In en, this message translates to:
  /// **'No fallback'**
  String get deviceTransferPillNoFallback;

  /// No description provided for @deviceTransferPillNoCloud.
  ///
  /// In en, this message translates to:
  /// **'No cloud recovery'**
  String get deviceTransferPillNoCloud;

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

  /// No description provided for @deviceTransferWindowExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer window expired'**
  String get deviceTransferWindowExpiredTitle;

  /// No description provided for @deviceTransferSessionExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'The old-device transfer session expired. Issue a fresh session from the old device.'**
  String get deviceTransferSessionExpiredMessage;

  /// No description provided for @deviceTransferClaimExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'This new-device claim expired. Register a fresh claim and request approval again.'**
  String get deviceTransferClaimExpiredMessage;

  /// No description provided for @deviceTransferMetricMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get deviceTransferMetricMode;

  /// No description provided for @deviceTransferMetricModeOld.
  ///
  /// In en, this message translates to:
  /// **'Old device'**
  String get deviceTransferMetricModeOld;

  /// No description provided for @deviceTransferMetricModeNew.
  ///
  /// In en, this message translates to:
  /// **'New device'**
  String get deviceTransferMetricModeNew;

  /// No description provided for @deviceTransferMetricSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get deviceTransferMetricSession;

  /// No description provided for @deviceTransferSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get deviceTransferSessionExpired;

  /// No description provided for @deviceTransferSessionIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get deviceTransferSessionIdle;

  /// No description provided for @deviceTransferSessionLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get deviceTransferSessionLive;

  /// No description provided for @deviceTransferMetricClaim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get deviceTransferMetricClaim;

  /// No description provided for @deviceTransferClaimMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get deviceTransferClaimMissing;

  /// No description provided for @deviceTransferClaimExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get deviceTransferClaimExpired;

  /// No description provided for @deviceTransferClaimIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get deviceTransferClaimIssued;

  /// No description provided for @deviceTransferPayloadCopied.
  ///
  /// In en, this message translates to:
  /// **'Transfer payload copied.'**
  String get deviceTransferPayloadCopied;

  /// No description provided for @deviceTransferReturnToConversations.
  ///
  /// In en, this message translates to:
  /// **'Return to conversations'**
  String get deviceTransferReturnToConversations;

  /// No description provided for @deviceTransferPayloadInvalid.
  ///
  /// In en, this message translates to:
  /// **'Transfer payload format is invalid.'**
  String get deviceTransferPayloadInvalid;

  /// No description provided for @deviceTransferPayloadImported.
  ///
  /// In en, this message translates to:
  /// **'Transfer payload imported. Register this new device before the transfer window closes.'**
  String get deviceTransferPayloadImported;

  /// No description provided for @deviceTransferImportFirst.
  ///
  /// In en, this message translates to:
  /// **'Import a valid transfer payload first.'**
  String get deviceTransferImportFirst;

  /// No description provided for @deviceTransferClaimRegistered.
  ///
  /// In en, this message translates to:
  /// **'Claim registered. Give this claim code to the old device and request approval before it expires.'**
  String get deviceTransferClaimRegistered;

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

  /// No description provided for @deviceTransferClaimExpiredRegisterFresh.
  ///
  /// In en, this message translates to:
  /// **'This new-device claim has expired. Register a fresh claim first.'**
  String get deviceTransferClaimExpiredRegisterFresh;

  /// No description provided for @deviceTransferComplete.
  ///
  /// In en, this message translates to:
  /// **'Transfer complete. This device joined the trusted graph.'**
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

  /// No description provided for @deviceTransferStep1Title.
  ///
  /// In en, this message translates to:
  /// **'1. Initiate on old device'**
  String get deviceTransferStep1Title;

  /// No description provided for @deviceTransferStep1BodyReady.
  ///
  /// In en, this message translates to:
  /// **'Generate a short-lived session and token for the next device.'**
  String get deviceTransferStep1BodyReady;

  /// No description provided for @deviceTransferStep1BodyExpires.
  ///
  /// In en, this message translates to:
  /// **'This transfer session expires {when}.'**
  String deviceTransferStep1BodyExpires(String when);

  /// No description provided for @deviceTransferStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get deviceTransferStatusReady;

  /// No description provided for @deviceTransferStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get deviceTransferStatusExpired;

  /// No description provided for @deviceTransferStatusIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get deviceTransferStatusIssued;

  /// No description provided for @deviceTransferIssuingToken.
  ///
  /// In en, this message translates to:
  /// **'Issuing token'**
  String get deviceTransferIssuingToken;

  /// No description provided for @deviceTransferIssueToken.
  ///
  /// In en, this message translates to:
  /// **'Issue transfer token'**
  String get deviceTransferIssueToken;

  /// No description provided for @deviceTransferStep2Title.
  ///
  /// In en, this message translates to:
  /// **'2. Approve on old device'**
  String get deviceTransferStep2Title;

  /// No description provided for @deviceTransferStep2BodyWaiting.
  ///
  /// In en, this message translates to:
  /// **'No transfer session exists yet.'**
  String get deviceTransferStep2BodyWaiting;

  /// No description provided for @deviceTransferStep2BodyExpired.
  ///
  /// In en, this message translates to:
  /// **'This transfer session expired. Clear it and issue a fresh one.'**
  String get deviceTransferStep2BodyExpired;

  /// No description provided for @deviceTransferStep2BodyAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Wait for the new device to register its claim, then approve that specific claim code here.'**
  String get deviceTransferStep2BodyAwaiting;

  /// No description provided for @deviceTransferStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get deviceTransferStatusWaiting;

  /// No description provided for @deviceTransferStatusAwaitingClaim.
  ///
  /// In en, this message translates to:
  /// **'Awaiting claim'**
  String get deviceTransferStatusAwaitingClaim;

  /// No description provided for @deviceTransferClaimFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'NEW-DEVICE CLAIM'**
  String get deviceTransferClaimFieldLabel;

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

  /// No description provided for @deviceTransferStep3Title.
  ///
  /// In en, this message translates to:
  /// **'3. Hand payload to new device'**
  String get deviceTransferStep3Title;

  /// No description provided for @deviceTransferReadyToCopy.
  ///
  /// In en, this message translates to:
  /// **'Ready to copy'**
  String get deviceTransferReadyToCopy;

  /// No description provided for @deviceTransferIssueTokenFirst.
  ///
  /// In en, this message translates to:
  /// **'Issue a transfer token first.'**
  String get deviceTransferIssueTokenFirst;

  /// No description provided for @deviceTransferPayloadExpiredNote.
  ///
  /// In en, this message translates to:
  /// **'This payload is no longer valid. Clear it and issue a fresh transfer session.'**
  String get deviceTransferPayloadExpiredNote;

  /// No description provided for @deviceTransferCompleteOnNewNote.
  ///
  /// In en, this message translates to:
  /// **'Complete on the new device. The old device remains trusted until you revoke it explicitly.'**
  String get deviceTransferCompleteOnNewNote;

  /// No description provided for @deviceTransferCopyPayload.
  ///
  /// In en, this message translates to:
  /// **'Copy payload'**
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

  /// No description provided for @deviceTransferFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed'**
  String get deviceTransferFailedTitle;

  /// No description provided for @deviceTransferPayloadFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'TRANSFER PAYLOAD'**
  String get deviceTransferPayloadFieldLabel;

  /// No description provided for @deviceTransferPayloadFieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Import the short-lived session and token issued by the trusted old device.'**
  String get deviceTransferPayloadFieldCaption;

  /// No description provided for @deviceTransferPayloadInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Paste transfer payload'**
  String get deviceTransferPayloadInputLabel;

  /// No description provided for @deviceTransferImportPayload.
  ///
  /// In en, this message translates to:
  /// **'Import payload'**
  String get deviceTransferImportPayload;

  /// No description provided for @deviceTransferNewDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'NEW DEVICE'**
  String get deviceTransferNewDeviceLabel;

  /// No description provided for @deviceTransferNewDeviceCaption.
  ///
  /// In en, this message translates to:
  /// **'This device proves its own claim. The old device only approves that exact claim.'**
  String get deviceTransferNewDeviceCaption;

  /// No description provided for @deviceTransferDeviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceTransferDeviceNameLabel;

  /// No description provided for @deviceTransferSessionIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Session id'**
  String get deviceTransferSessionIdLabel;

  /// No description provided for @deviceTransferTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer token'**
  String get deviceTransferTokenLabel;

  /// No description provided for @deviceTransferClaimNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Claim not registered'**
  String get deviceTransferClaimNotRegistered;

  /// No description provided for @deviceTransferClaimExpiredPill.
  ///
  /// In en, this message translates to:
  /// **'Claim expired'**
  String get deviceTransferClaimExpiredPill;

  /// No description provided for @deviceTransferClaimRegisteredPill.
  ///
  /// In en, this message translates to:
  /// **'Claim registered'**
  String get deviceTransferClaimRegisteredPill;

  /// No description provided for @deviceTransferOldApprovesExact.
  ///
  /// In en, this message translates to:
  /// **'Old device approves exact claim'**
  String get deviceTransferOldApprovesExact;

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

  /// No description provided for @themeModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how VEIL appears on this device.'**
  String get themeModeSubtitle;

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
  /// **'Scripted demo'**
  String get aiDemoBannerTitle;

  /// No description provided for @aiDemoBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Demo: replies are scripted on this device. Nothing is sent anywhere.'**
  String get aiDemoBannerBody;
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
