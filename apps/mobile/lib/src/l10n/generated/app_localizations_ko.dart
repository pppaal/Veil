// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'VEIL';

  @override
  String get commonContinue => '계속';

  @override
  String get commonCancel => '취소';

  @override
  String get commonSave => '저장';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonClose => '닫기';

  @override
  String get commonBack => '뒤로';

  @override
  String get commonDone => '완료';

  @override
  String get commonConfirm => '확인';

  @override
  String get commonLoading => '불러오는 중…';

  @override
  String get commonError => '문제가 발생했습니다';

  @override
  String get commonIUnderstand => '이해했습니다';

  @override
  String get pillDeviceBound => '기기 귀속';

  @override
  String get pillNoRecovery => '복구 불가';

  @override
  String get pillNoPasswordReset => '비밀번호 재설정 없음';

  @override
  String get pillOldDeviceRequired => '기존 기기 필요';

  @override
  String get pillPrivateBeta => '비공개 베타';

  @override
  String get pillDeviceBoundMessenger => '기기 귀속 메신저';

  @override
  String get pillNoContactSync => '연락처 동기화 없음';

  @override
  String get pillHandleDiscovery => '핸들 검색';

  @override
  String get pillSessionLocked => '세션 잠김';

  @override
  String get pillPreviewObscured => '미리보기 가려짐';

  @override
  String get privacyShieldEyebrow => '프라이버시 실드';

  @override
  String get privacyShieldTitle => '비활성 상태에서는 VEIL이 숨겨집니다.';

  @override
  String get privacyShieldBody =>
      '최근 앱 미리보기가 가려지고, 앱이 포그라운드를 떠나면 로컬 잠금이 다시 걸립니다.';

  @override
  String get appLockTitle => '앱 잠금';

  @override
  String get appLockLoadingTitle => '로컬 잠금 확인 중';

  @override
  String get appLockLoadingBody => '저장된 PIN과 생체 인식 사용 가능 여부를 확인합니다.';

  @override
  String get appLockHeroEyebrow => '로컬 잠금';

  @override
  String get appLockHeroTitle => 'VEIL은 원격으로 잠금을 풀지 않습니다.';

  @override
  String get appLockHeroBody =>
      'PIN과 생체 인식은 이 기기에서만 확인합니다. 원격 재설정도, 복구 수단도, 서버의 개입도 없습니다.';

  @override
  String get appLockPillLocalOnly => '이 기기 전용';

  @override
  String get appLockPillNoRemoteReset => '원격 재설정 없음';

  @override
  String get appLockNoRecoveryBody =>
      'PIN을 잊고 사용 중인 기기까지 잃으면 VEIL은 접근 권한을 되살릴 수 없습니다.';

  @override
  String get appLockCompromisedTitle => '변조된 기기에서는 차단됩니다';

  @override
  String get appLockCompromisedBody =>
      '이 기기는 루팅 또는 탈옥된 것으로 보입니다. VEIL은 변조된 기기에서 잠금 해제를 막습니다.';

  @override
  String appLockCompromisedReasons(String reasons) {
    return '이 기기는 루팅 또는 탈옥된 것으로 보입니다. $reasons';
  }

  @override
  String get appLockLockoutTitle => 'PIN이 잠시 잠겼습니다';

  @override
  String appLockLockoutBody(String retry) {
    return '이 기기에서 PIN을 너무 여러 번 틀렸습니다. $retry';
  }

  @override
  String get appLockRetryNow => '지금 다시 시도하세요.';

  @override
  String appLockRetrySeconds(int seconds) {
    return '$seconds초 후에 다시 시도하세요.';
  }

  @override
  String appLockRetryMinutes(int minutes) {
    return '$minutes분 후에 다시 시도하세요.';
  }

  @override
  String get appLockPinLabel => 'PIN';

  @override
  String get appLockMetricConfigured => '설정됨';

  @override
  String get appLockMetricRequired => '설정 필요';

  @override
  String get appLockMetricBiometrics => '생체 인식';

  @override
  String get appLockMetricAvailable => '사용 가능';

  @override
  String get appLockMetricUnavailable => '사용 불가';

  @override
  String get appLockMetricPreview => '미리보기';

  @override
  String get appLockMetricProtected => '보호됨';

  @override
  String get appLockMetricShielded => '가려짐';

  @override
  String get appLockPillPinConfigured => 'PIN 설정됨';

  @override
  String get appLockPillPinRequired => 'PIN 설정 필요';

  @override
  String get appLockPillBiometricsAvailable => '생체 인식 사용 가능';

  @override
  String get appLockPillBiometricsUnavailable => '생체 인식 사용 불가';

  @override
  String get appLockPillCaptureBlocked => '화면 캡처 차단됨';

  @override
  String get appLockPillPreviewShield => '미리보기만 가림';

  @override
  String get appLockCaptionSet =>
      '계속하려면 이 기기에서만 쓰는 숫자 PIN을 정하세요. VEIL은 이 PIN을 대신 재설정해 줄 수 없습니다.';

  @override
  String get appLockCaptionUnlock =>
      '이 기기의 PIN이나 생체 인식으로 잠금을 해제하세요. 서버와는 통신하지 않습니다.';

  @override
  String get appLockFieldSetPin => 'PIN 설정';

  @override
  String get appLockFieldPinHint => '숫자 6~12자리';

  @override
  String get appLockFieldPinError => '숫자 6~12자리만 사용하세요.';

  @override
  String get appLockFieldConfirm => 'PIN 확인';

  @override
  String get appLockFieldConfirmHint => '같은 PIN을 다시 입력하세요';

  @override
  String get appLockConfirmMismatch => '확인용 PIN이 일치하지 않습니다.';

  @override
  String get appLockStatusTitle => '잠금 상태';

  @override
  String get appLockStatusUnlockedTitle => '잠금 해제됨';

  @override
  String get appLockStatusUnlocked => '잠금이 해제되었습니다.';

  @override
  String get appLockStatusBiometricFailed => '생체 인식에 실패했습니다.';

  @override
  String get appLockStatusEnterPin => '먼저 PIN을 입력하세요.';

  @override
  String get appLockStatusPinFormat => 'PIN은 숫자 6~12자리여야 합니다.';

  @override
  String get appLockStatusPinMismatch => 'PIN이 일치하지 않습니다.';

  @override
  String appLockStatusPinMismatchAttempts(int count) {
    return 'PIN이 일치하지 않습니다. $count번 더 틀리면 잠시 잠깁니다.';
  }

  @override
  String get appLockStatusLocked => 'PIN이 잠시 잠겼습니다.';

  @override
  String get appLockStatusCompromised => '변조된 기기에서는 잠금을 해제할 수 없습니다.';

  @override
  String get appLockUseBiometrics => '생체 인식 사용';

  @override
  String get appLockSetAndUnlock => 'PIN 설정 후 잠금 해제';

  @override
  String get appLockUnlock => 'VEIL 잠금 해제';

  @override
  String get splashEyebrow => '비공개 베타';

  @override
  String get splashBody => '백업 없음. 복구 없음. 유출 없음.';

  @override
  String get splashErrorTitle => '런타임 구성이 차단됨';

  @override
  String get splashPreparingTitle => '로컬 상태 준비 중';

  @override
  String get splashPreparingBody => '온보딩, 세션 연결, 로컬 보안 상태를 확인하는 중입니다.';

  @override
  String get onboardingWarnEyebrow => '제품 원칙';

  @override
  String get onboardingWarnTitle => '백업 없음.\n복구 없음.\n유출 없음.';

  @override
  String get onboardingWarnBody =>
      'VEIL은 설계상 기기에 귀속됩니다. 기기 분실은 곧 계정 상실입니다. 복구는 불가능하며, 클라우드 수신함이 아닙니다.';

  @override
  String get onboardingWarnDestructiveTitle => '복구 불가한 설계';

  @override
  String get onboardingWarnDestructiveBody =>
      '기기를 분실하면 계정과 메시지가 모두 사라집니다. VEIL은 접근 권한을 복원해 드릴 수 없습니다.';

  @override
  String get onboardingWarnIdentityTitle => '신원';

  @override
  String get onboardingWarnIdentityLine1 => '이 기기가 당신의 신원이 됩니다.';

  @override
  String get onboardingWarnIdentityLine2 => '개인 정보는 기기 안에만 저장됩니다.';

  @override
  String get onboardingWarnIdentityLine3 => '비밀번호 재설정 경로가 존재하지 않습니다.';

  @override
  String get onboardingWarnTransferTitle => '이전';

  @override
  String get onboardingWarnTransferLine1 => '이전은 기존 기기가 남아 있을 때만 가능합니다.';

  @override
  String get onboardingWarnTransferLine2 => '기존 기기에서 이전 승인이 필요합니다.';

  @override
  String get onboardingWarnTransferLine3 => '기존 기기가 없다면 이전도 없습니다.';

  @override
  String get privacyConsentTitle => '개인정보 처리방침';

  @override
  String get privacyConsentSubtitle => 'VEIL을 사용하기 전에 꼭 읽어주세요';

  @override
  String get privacyConsentEyebrow => '개인정보 보호';

  @override
  String get privacyConsentHeroTitle => '개인정보 &\n데이터 보호';

  @override
  String get privacyConsentHeroBody =>
      'VEIL은 개인정보보호법(PIPA)을 준수합니다. 서비스 이용 전 아래 내용을 확인하고 동의해 주세요.';

  @override
  String get privacyConsentAgree => '위 개인정보 수집·이용에 동의합니다. (필수)';

  @override
  String get privacyConsentAccept => '동의하고 계속하기';

  @override
  String get privacyConsentCollectTitle => '수집하는 개인정보';

  @override
  String get privacyConsentCollectItem1 => '사용자 핸들과 이에 연결된 무작위 계정 ID 및 디바이스 ID';

  @override
  String get privacyConsentCollectItem2 =>
      '디바이스 정보 (플랫폼, 디바이스 이름)와 푸시 토큰 (푸시 알림에는 메시지 내용이 포함되지 않음)';

  @override
  String get privacyConsentCollectItem3 => '공개 신원 키와 프리키 (암호화 통신용)';

  @override
  String get privacyConsentCollectItem4 =>
      '앱 내 연락처 목록: 추가한 계정 (연락처에 붙인 이름은 이 기기에만 저장)';

  @override
  String get privacyConsentCollectItem5 =>
      '대화 참여 정보와 전송 메타데이터: 메시지 도착 시각, 전달·읽음 확인 시각, 디바이스의 마지막 접속일';

  @override
  String get privacyConsentCollectItem6 =>
      '통화 기록: 대화, 통화를 건 사람, 통화 유형, 시작·종료 시각, 통화 시간 (30일 보관)';

  @override
  String get privacyConsentCollectItem7 =>
      '그룹·채널 이름과 설명 (읽을 수 있는 형태로 저장), 직접 설정한 차단·알림 끔·신고 내역 (신고는 90일 보관)';

  @override
  String get privacyConsentPurposeTitle => '수집 목적';

  @override
  String get privacyConsentPurposeItem1 => '종단간 암호화 메시징 서비스 제공';

  @override
  String get privacyConsentPurposeItem2 => '디바이스 인증 및 세션 관리';

  @override
  String get privacyConsentPurposeItem3 => '연락처 검색 및 대화 연결';

  @override
  String get privacyConsentRetentionTitle => '보유 기간';

  @override
  String get privacyConsentRetentionItem1 => '계정 삭제 요청 시 즉시 파기';

  @override
  String get privacyConsentRetentionItem2 =>
      '디바이스 해제 시 해당 디바이스 정보 삭제, 디바이스 기록은 약 30일 이내 삭제';

  @override
  String get privacyConsentRetentionItem3 => '만료된 메시지는 자동 삭제';

  @override
  String get privacyConsentRightsTitle => '이용자의 권리';

  @override
  String get privacyConsentRightsItem1 => '개인정보 열람, 정정, 삭제 요구 가능';

  @override
  String get privacyConsentRightsItem2 => '설정 > 계정 삭제에서 전체 데이터 삭제 가능';

  @override
  String get privacyConsentRightsItem3 => '동의 철회 시 서비스 이용 중단';

  @override
  String get privacyConsentNotCollectedTitle => '수집하지 않는 정보';

  @override
  String get privacyConsentNotCollectedItem1 => '메시지 내용 (종단간 암호화, 서버 해독 불가)';

  @override
  String get privacyConsentNotCollectedItem2 => '위치 정보';

  @override
  String get privacyConsentNotCollectedItem3 => '휴대폰 주소록, 통화 기록 등 기기에 저장된 개인정보';

  @override
  String get privacyConsentThirdPartyTitle => '제3자 제공';

  @override
  String get privacyConsentThirdPartyBody =>
      'VEIL은 수집한 개인정보를 제3자에게 제공하지 않습니다. 다만 법령에 의한 요청이 있는 경우 관련 법령에 따라 처리합니다.';

  @override
  String get authCreateTitle => '계정 만들기';

  @override
  String get authCreateEyebrow => '기기 귀속';

  @override
  String get authCreateHeroTitle => '이 기기가 당신의 신원이 됩니다.';

  @override
  String get authCreateHeroBody =>
      'VEIL은 지금 손에 든 이 하드웨어에 접근 권한을 묶습니다. 기기를 잃어버리면 계정도 함께 사라집니다.';

  @override
  String get authCreateRestoreTitle => '복원 경로 없음';

  @override
  String get authCreateRestoreBody =>
      '이 기기를 분실하면 계정과 메시지가 모두 사라집니다. VEIL은 접근을 복원할 수 없으며, 이는 의도된 설계입니다.';

  @override
  String get authCreateMetricIdentity => '신원';

  @override
  String get authCreateMetricIdentityValue => '로컬';

  @override
  String get authCreateMetricRecovery => '복구';

  @override
  String get authCreateMetricRecoveryValue => '없음';

  @override
  String get authCreateMetricTransfer => '이전';

  @override
  String get authCreateMetricTransferValue => '기존 기기';

  @override
  String get authCreateFieldLabel => '프로필 레이블';

  @override
  String get authCreateFieldCaption =>
      '사람들은 핸들로 나를 찾습니다. 이 이름은 표시용일 뿐 검색에는 쓰이지 않습니다.';

  @override
  String get authCreateDisplayName => '표시 이름';

  @override
  String get authCreateDisplayHint => '이 계정의 선택 레이블';

  @override
  String get authCreateTransferLabel => '기존 기기에서 이전하기';

  @override
  String get authHandleTitle => '핸들 선택';

  @override
  String get authHandleEyebrow => '핸들 등록';

  @override
  String get authHandleHeroTitle => '전화번호는 받지 않습니다.';

  @override
  String get authHandleHeroBody =>
      '검색용 핸들을 정해 주세요. 로컬 신원 정보가 생성된 뒤, VEIL이 핸들을 이 기기에 묶습니다.';

  @override
  String get authHandleFieldLabel => '핸들';

  @override
  String get authHandleFieldCaption => '소문자로, 짧게. 오래 쓸 이름이니 신중하게 고르세요.';

  @override
  String get authHandleInputLabel => '핸들';

  @override
  String get authHandleInputHint => 'cold.operator';

  @override
  String get authHandleChoosePrompt => '핸들을 입력하세요';

  @override
  String get authHandleBindingSection => '등록 절차';

  @override
  String get authHandleStep1Title => '로컬 신원 생성';

  @override
  String get authHandleStep1Body => '기기에 귀속된 암호화 정보를 만들고, 개인 키는 이 기기에만 둡니다.';

  @override
  String get authHandleStep2Title => '핸들 등록';

  @override
  String get authHandleStep2Body => '공개 기기 정보와 핸들 메타데이터만 서버에 게시합니다.';

  @override
  String get authHandleStep3Title => '기기 챌린지';

  @override
  String get authHandleStep3Body => '등록된 기기에 대한 짧은 수명의 서버 챌린지를 요청합니다.';

  @override
  String get authHandleStep4Title => '검증 및 기기 연결';

  @override
  String get authHandleStep4Body => '검증을 완료하고 기기 세션을 활성화합니다.';

  @override
  String get authHandleFailedTitle => '기기 연결 실패';

  @override
  String get authHandleBindCta => '이 기기에 연결';

  @override
  String get authStageGeneratingKeys => '로컬 신원 생성 중';

  @override
  String get authStageRegistering => '핸들 등록 중';

  @override
  String get authStageRequestingChallenge => '챌린지 요청 중';

  @override
  String get authStageVerifying => '기기 확인 중';

  @override
  String get authStageComplete => '연결됨';

  @override
  String get authDefaultDeviceName => 'VEIL 모바일';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsProfileTitle => '프로필';

  @override
  String get settingsProfileSubtitle => '내 핸들과 이 기기에서 부르는 닉네임';

  @override
  String get settingsEyebrow => '로컬 기기';

  @override
  String get settingsNoDeviceBound => '연결된 기기 세션이 없습니다.';

  @override
  String settingsCurrentDevice(String deviceId) {
    return '현재 기기 세션: $deviceId';
  }

  @override
  String get settingsPillPrivateByDesign => '설계상 프라이빗';

  @override
  String get settingsSectionDeviceGraph => '신뢰 기기 그래프';

  @override
  String get settingsLoadingDeviceGraph => '기기 그래프 불러오는 중';

  @override
  String get settingsLoadingDeviceGraphBody => '이 계정에 등록된 기기들을 확인하고 있습니다.';

  @override
  String get settingsDeviceGraphUnavailable => '기기 그래프를 불러올 수 없습니다';

  @override
  String get settingsNoTrustedDevices => '표시할 신뢰 기기가 없습니다';

  @override
  String get settingsAppLockTitle => '앱 잠금';

  @override
  String get settingsAppLockSubtitle => '이 기기에만 적용되는 생체 인식 및 PIN 잠금';

  @override
  String get settingsDeviceTransferTitle => '기기 이전';

  @override
  String get settingsDeviceTransferSubtitle => '기존 기기가 이전을 시작하고 승인해야 합니다';

  @override
  String get settingsSecurityStatusTitle => '보안 상태';

  @override
  String get settingsSecurityStatusSubtitle => '로컬 가드레일과 런타임 상태 확인';

  @override
  String get settingsNoRecoveryPath => '복구 경로 없음';

  @override
  String get settingsSectionPrivacy => '개인정보';

  @override
  String get settingsReadReceiptsTitle => '읽음 확인 보내기';

  @override
  String get settingsReadReceiptsSubtitle =>
      '끄면 상대가 내가 읽은 것을 알 수 없고, 나도 상대의 읽음을 전달됨으로만 봅니다.';

  @override
  String get settingsTypingIndicatorsTitle => '입력 중 표시 보내기';

  @override
  String get settingsTypingIndicatorsSubtitle =>
      '상대가 내가 입력 중인지 볼 수 있습니다. 켜기 전에는 꺼져 있습니다.';

  @override
  String get settingsLockNow => '지금 잠그기';

  @override
  String get settingsWipeLocal => '이 기기에서 로컬 상태 삭제';

  @override
  String get settingsWipeConfirmTitle => '이 기기에서 로컬 상태를 삭제할까요?';

  @override
  String get settingsRevokeTitle => '이 기기 해지';

  @override
  String get settingsRevokeConfirmTitle => '이 기기를 해지할까요?';

  @override
  String get settingsLogout => '로그아웃';

  @override
  String get settingsIrreversible => '되돌릴 수 없습니다';

  @override
  String get settingsDeleteAccountTitle => '계정 삭제';

  @override
  String get settingsDeleteAccountBody =>
      '계정, 메시지, 연락처가 영구적으로 삭제됩니다. 되돌릴 수 없습니다.';

  @override
  String get settingsDeleteAccountConfirmLabel => '확인을 위해 DELETE를 입력하세요';

  @override
  String get settingsDeleteAccountAction => '계정 삭제';

  @override
  String get settingsDeleteAccountConfirmHeadline => '계정을 삭제하시겠습니까?';

  @override
  String get settingsDeviceGraphLoadFailedBody =>
      '이 기기에서 현재 신뢰 그래프를 불러오지 못했습니다. 로컬 보안 기능은 계속 사용할 수 있습니다.';

  @override
  String get settingsNoTrustedDevicesBody =>
      '이 계정에는 아직 읽을 수 있는 기기 그래프가 없습니다. 기기에 묶인 기능은 여전히 이 기기에만 있으며 복구할 수 없습니다.';

  @override
  String get settingsRefreshDeviceGraph => '기기 그래프 새로 고침';

  @override
  String get settingsSectionSecurity => '보안';

  @override
  String get settingsSectionSession => '세션';

  @override
  String get settingsDestructiveNoticeBody =>
      '이 기기에서 실행한 삭제 작업은 되돌릴 수 없습니다. VEIL은 백업도, 복원 권한도 보관하지 않습니다.';

  @override
  String get settingsLockNowSubtitle => '현재 세션을 지금 바로 앱 잠금 뒤로 숨깁니다';

  @override
  String get settingsWipeLocalSubtitle =>
      '이 기기에 있는 세션 상태, 비밀 키, 암호화된 캐시, PIN, 온보딩 상태만 삭제합니다.';

  @override
  String get settingsWipeConfirmBody =>
      '이 기기의 VEIL 로컬 상태를 지웁니다. 복구 경로는 생기지 않습니다. 이 기기가 유일한 활성 기기라면 다시는 접근할 수 없습니다.';

  @override
  String get settingsWipeConfirmAction => '로컬 상태 삭제';

  @override
  String get settingsRevokeSubtitle =>
      '이 기기에 묶인 세션을 없애고 이 기기의 로컬 상태를 삭제합니다. 복구할 수 없습니다.';

  @override
  String get settingsRevokeConfirmBody =>
      '이 계정과 이 기기의 연결을 끊고 이 기기의 로컬 상태를 삭제합니다. VEIL은 이를 복원할 수 없습니다.';

  @override
  String get settingsRevokeConfirmAction => '기기 해지';

  @override
  String get settingsLogoutSubtitle => '온보딩 동의와 앱 잠금은 그대로 두고 이 기기의 세션만 지웁니다.';

  @override
  String settingsTypePhraseToContinue(String phrase) {
    return '계속하려면 다음을 입력하세요: $phrase';
  }

  @override
  String settingsRevokeListedTitle(String deviceName) {
    return '$deviceName 기기를 해지할까요?';
  }

  @override
  String settingsRevokeListedBody(String deviceName) {
    return '신뢰 기기 그래프에서 $deviceName 기기를 제거합니다. VEIL은 그 기기를 위한 복구 경로를 만들지 않습니다.';
  }

  @override
  String settingsRevokeListedDone(String deviceName) {
    return '신뢰 그래프에서 $deviceName 기기를 제거했습니다.';
  }

  @override
  String get settingsRevokeListedFailed => '기기를 해지하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsDeviceStateCurrent => '이 기기';

  @override
  String get settingsDeviceStatePreferred => '우선 기기';

  @override
  String get settingsDeviceStateTrusted => '신뢰됨';

  @override
  String get settingsDeviceStateStale => '장기 미사용';

  @override
  String get settingsDeviceStateRevoked => '해지됨';

  @override
  String get settingsDeviceRevokeAction => '해지';

  @override
  String settingsDeviceCreated(String when) {
    return '생성 $when';
  }

  @override
  String settingsDeviceSeen(String when) {
    return '접속 $when';
  }

  @override
  String settingsDeviceSynced(String when) {
    return '동기화 $when';
  }

  @override
  String settingsDeviceActivity(String when) {
    return '활동 $when';
  }

  @override
  String settingsDeviceTrustedAt(String when) {
    return '신뢰 시작 $when';
  }

  @override
  String settingsDeviceJoinedFrom(String device) {
    return '$device에서 추가됨';
  }

  @override
  String settingsDeviceRevokedAt(String when) {
    return '해지 $when';
  }

  @override
  String get settingsDeviceNoteCurrent =>
      '지금 사용 중인 신뢰 기기입니다. 신뢰 기기를 모두 잃으면 VEIL은 접근을 복원할 수 없습니다.';

  @override
  String get settingsDeviceNotePreferred =>
      '이 신뢰 기기는 현재 메시지를 우선 전달받는 기기입니다. 클라우드 복구 수단이 아닙니다.';

  @override
  String get settingsDeviceNoteTrusted =>
      '이 기기는 계속 신뢰되며, 다른 신뢰 기기가 있는 동안 계속 동기화할 수 있습니다.';

  @override
  String get settingsDeviceNoteStale =>
      '이 기기는 아직 신뢰되지만 최근 활동이 없습니다. 더는 접근하면 안 되는 기기라면 해지하세요.';

  @override
  String get settingsDeviceNoteRevoked =>
      '이 기기는 더 이상 신뢰되지 않으며 세션을 다시 시작할 수 없습니다.';

  @override
  String get settingsGraphSummary => '그래프 요약';

  @override
  String settingsGraphTrustedCount(int count) {
    return '신뢰 $count대';
  }

  @override
  String settingsGraphStaleCount(int count) {
    return '장기 미사용 $count대';
  }

  @override
  String settingsGraphRevokedCount(int count) {
    return '해지 $count대';
  }

  @override
  String settingsGraphRecentActivity(String when) {
    return '최근 신뢰 기기 활동 $when';
  }

  @override
  String get settingsGraphPreferredDiffersTitle => '우선 기기가 다릅니다';

  @override
  String settingsGraphPreferredDiffersBody(String preferred, String current) {
    return '현재 메시지 전달과 디렉터리 호환의 우선 기기는 $preferred입니다. $current도 계속 신뢰됩니다.';
  }

  @override
  String get settingsGraphStaleTitle => '장기 미사용 신뢰 기기가 있습니다';

  @override
  String get settingsGraphStaleBody =>
      '일부 신뢰 기기에 최근 활동이 없습니다. 장기 미사용이 해지를 뜻하지는 않지만, 하나씩 확인해 보세요.';

  @override
  String get chatEmptyTitle => '아직 메시지가 없습니다';

  @override
  String get chatEmptyBody => '여기서 보내는 메시지는 이 기기에서 암호화되어 이 대화의 참여자만 읽을 수 있습니다.';

  @override
  String get chatEmptyVerifyAction => '안전 번호 비교하기';

  @override
  String get chatLoadFailedTitle => '메시지를 불러오지 못했습니다';

  @override
  String get chatLoadFailedBody => '잠시 후 다시 시도해 주세요.';

  @override
  String get chatComposeHint => '메시지를 입력하세요';

  @override
  String get chatSendAction => '보내기';

  @override
  String get chatAttachAction => '첨부';

  @override
  String get chatLoadingTitle => '메시지를 불러오는 중';

  @override
  String get chatLoadingBody => '이 기기로 온 메시지를 가져와 여는 중입니다.';

  @override
  String get chatConversationNotFound => '대화를 찾을 수 없습니다';

  @override
  String get chatRelockTitle => '세션 잠김';

  @override
  String get chatRelockBody => '이 대화를 이어가려면 앱 잠금을 해제하세요.';

  @override
  String get chatTitleFallback => '보안 대화';

  @override
  String get chatSubtitleOnline => '온라인';

  @override
  String get chatGroupUnknownSender => '알 수 없는 발신자';

  @override
  String chatGroupMemberCount(int count) {
    return '멤버 $count명';
  }

  @override
  String chatTimerTooltip(String value) {
    return '사라지는 메시지: $value';
  }

  @override
  String get chatSearchHint => '이 대화에서 검색';

  @override
  String get chatSearchClearTooltip => '검색 지우기';

  @override
  String get chatSearchTooltip => '메시지 검색';

  @override
  String chatSearchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이 기기에서 $count건 일치',
      zero: '이 기기에서 일치하는 메시지가 없습니다',
    );
    return '$_temp0';
  }

  @override
  String get chatSearchSearching => '이 기기에서 찾는 중…';

  @override
  String get chatBannerConversationIssue => '대화에 문제가 생겼습니다';

  @override
  String get chatBannerRelayReconnecting => '릴레이 재연결 중';

  @override
  String get chatBannerDeliveryStalled => '전송이 멈췄습니다';

  @override
  String get chatBannerQueuedLocally => '보내기 대기 중';

  @override
  String chatBannerFailedSends(int count) {
    return '메시지 $count개를 보내지 못했습니다. 릴레이에 연결되면 다시 시도하세요.';
  }

  @override
  String chatBannerUploadingAttachments(int count) {
    return '첨부 파일 $count개를 암호화된 상태로 올리는 중입니다. 다 올리면 보냅니다.';
  }

  @override
  String chatBannerQueuedMessages(int count) {
    return '메시지 $count개가 이 기기에서 대기 중이며, 다시 연결되면 보냅니다.';
  }

  @override
  String get chatRetryFailedSendsAction => '모두 다시 보내기';

  @override
  String get chatLoadOlder => '이전 메시지 불러오기';

  @override
  String get chatLoadingOlder => '이전 메시지를 불러오는 중';

  @override
  String get chatSearchEmptyTitle => '일치하는 메시지가 없습니다';

  @override
  String get chatSearchEmptyBody =>
      '이 대화에서 이 기기에 있는 메시지 중 일치하는 것이 없습니다. 이 기기에 불러온 메시지만 검색합니다.';

  @override
  String get chatTtlSheetTitle => '사라지는 메시지';

  @override
  String get chatTtlOff => '끔';

  @override
  String get chatTtlOffCaption => '메시지가 사라지지 않습니다.';

  @override
  String get chatTtl10s => '10초';

  @override
  String get chatTtl10sCaption => '가장 빨리 사라집니다. 상대가 보고 있을 때 쓰세요.';

  @override
  String get chatTtl1m => '1분';

  @override
  String get chatTtl5m => '5분';

  @override
  String get chatTtl1h => '1시간';

  @override
  String get chatTtl1d => '1일';

  @override
  String get chatTtl1dCaption => '일상 대화에 무난한 설정입니다.';

  @override
  String get chatTtlCustom => '사용자 지정';

  @override
  String get chatTtlDisabledLabel => '사라짐 꺼짐';

  @override
  String get chatAttachmentTicketTitle => '다운로드 티켓 발급됨';

  @override
  String chatAttachmentTicketBody(String summary) {
    return '릴레이가 이 기기에 단기 다운로드 티켓을 발급했습니다.\n\n요약: $summary\n\n이 빌드는 여기까지입니다. 아직 파일을 내려받거나 열지는 않습니다. 티켓 자체는 표시하지 않으므로 복사하거나 공유할 수 없습니다.';
  }

  @override
  String get chatAttachmentTicketFailed => '다운로드 요청 실패';

  @override
  String get chatAttachmentResolveAction => '다운로드 요청';

  @override
  String get chatAttachmentResolvingAction => '다운로드 요청 중';

  @override
  String get chatAttachmentEncryptedImage => '암호화된 이미지';

  @override
  String get chatAttachmentEncryptedVideo => '암호화된 영상';

  @override
  String get chatAttachmentEncryptedAudio => '암호화된 오디오';

  @override
  String get chatAttachmentEncryptedDocument => '암호화된 문서';

  @override
  String get chatAttachmentEncryptedFile => '암호화된 파일';

  @override
  String get chatAttachmentStateBanner => '첨부 상태';

  @override
  String get chatAttachmentCannotOpen => '이 버전에서는 첨부 파일을 열 수 없습니다.';

  @override
  String get reactionsMoreTooltip => '반응 더 보기';

  @override
  String get attachmentTitle => '첨부';

  @override
  String get attachmentHeroEyebrow => '첨부';

  @override
  String get attachmentHeroTitle => '보내기 전에 암호화됩니다.';

  @override
  String get attachmentHeroBody =>
      '이 기기에서 암호화한 뒤 내용을 알 수 없는 데이터로 올리고, 그 데이터를 가리키는 암호화된 메시지를 보냅니다.';

  @override
  String get attachmentPillOpaqueBlob => '암호화된 블롭';

  @override
  String get attachmentPillMetadataOnlyRelay => '릴레이는 메타데이터만';

  @override
  String get attachmentPillNoPlaintextPush => '평문 푸시 없음';

  @override
  String get attachmentNameLabel => '파일 이름';

  @override
  String get attachmentNameCaption =>
      '이 빌드에는 아직 파일 선택 기능이 없습니다. 이 이름으로 작은 자리표시용 파일을, 실제 첨부가 거칠 경로 그대로 보냅니다.';

  @override
  String get attachmentNameInputLabel => '파일 이름';

  @override
  String get attachmentRelayPolicyTitle => '릴레이 정책';

  @override
  String get attachmentRelayPolicyBody =>
      '비공개 베타에서는 현재 JPEG, PNG, WEBP, PDF와 그 밖의 바이너리 파일을 보낼 수 있습니다. 릴레이는 파일 이름의 평문이나 첨부 키를 받지 않습니다.';

  @override
  String get attachmentMetricType => '형식';

  @override
  String get attachmentMetricUpload => '업로드';

  @override
  String get attachmentMetricUploadValue => '티켓 방식';

  @override
  String get attachmentMetricBlob => '데이터';

  @override
  String get attachmentMetricBlobValue => '내용 비공개';

  @override
  String get attachmentStepsSection => '전송 과정';

  @override
  String get attachmentStep1Title => '티켓';

  @override
  String get attachmentStep1Body => '이 데이터만 올릴 수 있는 업로드 주소를 요청합니다.';

  @override
  String get attachmentStep2Title => '업로드';

  @override
  String get attachmentStep2Body =>
      '내용을 알 수 없는 데이터를 올립니다. 다시 시도하면 이 기기의 임시 파일을 다시 쓰고, 티켓이 만료되었으면 새로 받습니다.';

  @override
  String get attachmentStep3Title => '메시지';

  @override
  String get attachmentStep3Body =>
      '업로드를 가리키는 암호화된 메시지를 대기열에 넣고, 마무리되면 이 기기의 임시 파일을 지웁니다.';

  @override
  String get attachmentSendFailedTitle => '첨부 전송 실패';

  @override
  String get attachmentQueuedTitle => '이 기기에서 대기 중';

  @override
  String get attachmentQueuedBody =>
      '첨부 전송은 이제 대화 안에서 이어집니다. 진행 상황, 다시 시도, 취소는 해당 메시지에서 볼 수 있습니다.';

  @override
  String get attachmentSendAction => '암호화하여 보내기';

  @override
  String get attachmentSendingAction => '암호화하여 보내는 중';

  @override
  String get chatScreenshotToast =>
      '이 대화에서 스크린샷이 감지되었습니다. 이 기기에서는 VEIL이 이를 막을 수 없으며, 상대방에게 알림을 보내는 중입니다.';

  @override
  String get chatScreenshotSystemNotice => '상대방이 자신의 기기에서 이 대화를 스크린샷으로 캡처했습니다.';

  @override
  String get chatDecryptingEnvelope => '복호화하는 중…';

  @override
  String get chatDecryptFailed => '이 메시지를 복호화할 수 없습니다';

  @override
  String get chatDecryptReplayed => '중복되었거나 만료된 메시지';

  @override
  String get chatDecryptAwaitingKey => '보낸 사람의 키를 기다리는 중';

  @override
  String get chatDecryptSessionMissing => '보안 세션을 기다리는 중';

  @override
  String get chatDecryptIdentityRejected => '보류됨: 보낸 사람의 신원이 바뀌었습니다';

  @override
  String get chatLegacyUnverifiedBadge => '발신자 미확인(이전 방식)';

  @override
  String get chatNoticeIdentityChanged =>
      '연락처의 안전 번호가 바뀌었습니다. 다시 신뢰하기 전에 확인하세요.';

  @override
  String get chatNoticeIdentityNewDevice => '이 연락처가 새 기기를 사용하기 시작했습니다.';

  @override
  String get chatNoticeSenderKeysKept =>
      '서버가 이 그룹을 그룹 암호화 키 없이 표시했습니다. 이 기기는 계속 그 키를 사용합니다.';

  @override
  String get chatNoticeGroupMemberAdded =>
      '누군가 이 그룹에 추가되었습니다. 이제부터 보내는 메시지를 읽을 수 있습니다. 안전 번호에서 멤버를 확인하세요.';

  @override
  String get chatNoticeGroupMemberRemoved => '누군가 이 그룹을 나갔거나 그룹에서 제거되었습니다.';

  @override
  String get chatIdentityChangedTitle => '안전 번호가 바뀌었습니다';

  @override
  String get chatIdentityChangedBody => '확인하기 전에는 새 키로 아무것도 전송되지 않습니다.';

  @override
  String get chatIdentityChangedReview => '확인하기';

  @override
  String get chatIdentityChangedElsewhereTitle => '다른 대화에서 안전 번호가 바뀌었습니다';

  @override
  String get chatIdentityChangedElsewhereBody =>
      '함께 있는 그룹에서 상대가 새 키를 제시했습니다. 그 대화에서 확인하기 전까지 확인됨으로 표시되지 않습니다.';

  @override
  String get chatAccountHoldOtherTitle => '다른 계정입니다';

  @override
  String chatAccountHoldOtherBody(String handle) {
    return '이 대화는 전에 대화하던 이름(@$handle)으로 표시되지만, 그때의 계정이 아닙니다. 이 계정과 대화하겠다고 확인하기 전에는 여기서 아무것도 보내거나 열지 않습니다.';
  }

  @override
  String get chatAccountHoldUnissuedTitle => 'VEIL 서버가 발급하지 않는 이름';

  @override
  String get chatAccountHoldUnissuedBody =>
      '이 대화는 VEIL 서버가 발급하지 않는 이름으로 표시되어, 아는 사람처럼 보이기만 할 수 있습니다. 이 계정과 대화하겠다고 확인하기 전에는 여기서 아무것도 보내거나 열지 않습니다.';

  @override
  String get chatAccountHoldOwnTitle => '내 이름을 쓰는 다른 계정';

  @override
  String chatAccountHoldOwnBody(String handle) {
    return '이 대화는 내 이름(@$handle)으로 표시되지만 다른 계정입니다. 다른 사람은 내 이름을 가질 수 없습니다. 이 기기가 받은 목록이 바뀐 것이며, 누군가를 나처럼 보이게 하려는 것일 수 있습니다. 이 계정과 대화하겠다고 확인하기 전에는 여기서 아무것도 보내거나 열지 않습니다.';
  }

  @override
  String chatAccountHoldOwnConfirmTitle(String handle) {
    return '다른 @$handle 계정과 대화할까요?';
  }

  @override
  String get chatAccountHoldOwnConfirmBody =>
      '다른 VEIL 계정은 내 이름을 가질 수 없습니다. 서버가 이 계정을 그 이름으로 보여 준 것입니다. 다른 방법(직접 만나기, 전화)으로 누구의 계정인지 확인한 경우에만 계속하세요.';

  @override
  String get chatAccountHoldAcknowledge => '이 계정과 대화하기';

  @override
  String get chatPeerVerified => '확인됨';

  @override
  String get chatRetrySend => '다시 보내기';

  @override
  String get chatRetryUpload => '업로드 재시도';

  @override
  String get chatCancelAction => '취소';

  @override
  String get chatDeliveryQueued => '대기 중';

  @override
  String get chatDeliveryUploading => '업로드 중';

  @override
  String get chatDeliveryFailed => '재시도 필요';

  @override
  String get chatDeliverySent => '전송됨';

  @override
  String get chatDeliveryDelivered => '전달됨';

  @override
  String get chatDeliveryRead => '읽음';

  @override
  String get chatPhaseStaged => '준비됨';

  @override
  String get chatPhasePreparing => '준비 중';

  @override
  String get chatPhaseUploading => '업로드 중';

  @override
  String get chatPhaseFinalizing => '완료 중';

  @override
  String get chatPhaseFailed => '재시도 필요';

  @override
  String get chatPhaseCanceled => '취소됨';

  @override
  String chatPhaseDescStaged(String sizeLabel) {
    return '암호화된 블롭이 로컬에 준비되었습니다.$sizeLabel 릴레이에 연결되면 업로드가 시작됩니다.';
  }

  @override
  String get chatPhaseDescPreparing => '업로드 권한을 갱신하고 암호화된 메타데이터를 검증합니다.';

  @override
  String get chatPhaseDescUploading =>
      '객체 저장소로 암호문 바이트를 전송합니다. 릴레이는 평문을 보지 못합니다.';

  @override
  String get chatPhaseDescFinalizing => '업로드된 블롭을 암호화된 메시지 엔벨로프에 결합합니다.';

  @override
  String get chatPhaseDescFailed => '업로드 실패. 재시도 시 로컬의 암호화된 임시 블롭을 재사용합니다.';

  @override
  String get chatPhaseDescCanceled =>
      '이 기기에서 업로드가 중지되었습니다. 재시도 시 새 티켓을 요청하고 로컬 블롭을 재사용합니다.';

  @override
  String chatAttachmentSizeBytes(int count) {
    return ' $count바이트.';
  }

  @override
  String chatTypingSuffix(String handle) {
    return '@$handle님이 입력 중…';
  }

  @override
  String get chatTypingUnnamed => '입력 중…';

  @override
  String chatReactionSemantics(String emoji, int count) {
    return '$emoji, 반응 $count개';
  }

  @override
  String get chatSemanticsSent => '보낸';

  @override
  String get chatSemanticsReceived => '받은';

  @override
  String chatSemanticsBubble(String direction, String stateSegment) {
    return '$direction 메시지.$stateSegment';
  }

  @override
  String chatSemanticsStateSegment(String state) {
    return ' $state.';
  }

  @override
  String chatNetworkRecoveryFailed(int count, String retryLabel) {
    return '메시지 $count개가 릴레이 연결을 기다리고 있습니다. $retryLabel';
  }

  @override
  String chatNetworkRecoveryUploading(int count, String retryLabel) {
    return '릴레이에 다시 연결하는 동안 첨부 파일 $count개의 전송이 멈춰 있습니다. $retryLabel';
  }

  @override
  String chatNetworkRecoveryQueued(int count, String retryLabel) {
    return '메시지 $count개가 이 기기에서 대기 중입니다. $retryLabel';
  }

  @override
  String get chatRetryResumes => '릴레이에 다시 연결되면 이어서 보냅니다.';

  @override
  String chatRetryNextIn(String countdown) {
    return '$countdown 뒤에 다시 시도합니다.';
  }

  @override
  String chatCountdownSeconds(int seconds) {
    return '$seconds초';
  }

  @override
  String chatCountdownMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String chatCountdownMinutesSeconds(int minutes, int seconds) {
    return '$minutes분 $seconds초';
  }

  @override
  String chatDurationDays(int count) {
    return '$count일';
  }

  @override
  String chatDurationHours(int count) {
    return '$count시간';
  }

  @override
  String chatDurationMinutes(int count) {
    return '$count분';
  }

  @override
  String chatDurationSeconds(int count) {
    return '$count초';
  }

  @override
  String get chatExpiryExpired => '만료됨';

  @override
  String chatExpirySeconds(int count) {
    return '$count초 후 만료';
  }

  @override
  String chatExpiryMinutes(int count) {
    return '$count분 후 만료';
  }

  @override
  String chatExpiryHours(int count) {
    return '$count시간 후 만료';
  }

  @override
  String chatExpiryDays(int count) {
    return '$count일 후 만료';
  }

  @override
  String get errorSessionRequired => '이 기기에 더 이상 신뢰된 VEIL 세션이 없습니다.';

  @override
  String get errorTransferNeedsApi => '기기 이전은 VEIL 서버에 연결되어 있을 때만 할 수 있습니다.';

  @override
  String get errorClaimBeforeCompletion =>
      '먼저 이 새 기기를 등록한 다음, 기존 기기의 승인을 기다리세요.';

  @override
  String get errorUnexpectedResponse => '릴레이가 예상하지 못한 응답을 보냈습니다. 다시 시도하세요.';

  @override
  String get errorUploadFailed => '암호화된 파일을 올리지 못했습니다. 연결을 확인하고 다시 시도하세요.';

  @override
  String get errorSessionInvalid => '이 기기에서 이 세션은 더 이상 유효하지 않습니다.';

  @override
  String get errorNotAllowed => '현재 기기에서는 이 작업을 할 수 없습니다.';

  @override
  String get errorNotFound => '릴레이에서 요청한 항목을 찾지 못했습니다.';

  @override
  String get errorConflict => '요청이 현재 상태와 맞지 않습니다. 새로 고친 뒤 다시 시도하세요.';

  @override
  String get errorRejected => '입력한 값이 거부되었습니다. 확인한 뒤 다시 시도하세요.';

  @override
  String get errorRelayFailed => 'VEIL 릴레이가 요청을 처리하지 못했습니다. 잠시 후 다시 시도하세요.';

  @override
  String get errorApiNeedsTls => '로컬 개발 환경이 아니면 VEIL API 주소는 TLS를 사용해야 합니다.';

  @override
  String get errorRealtimeNeedsTls =>
      '로컬 개발 환경이 아니면 VEIL 실시간 연결 주소는 TLS를 사용해야 합니다.';

  @override
  String get conversationsEmptyTitle => '대화가 아직 없습니다';

  @override
  String get conversationsEmptyBody => '핸들로 상대를 찾아 첫 암호화 메시지를 보내보세요.';

  @override
  String get conversationsSearchHint => '대화 및 아카이브 검색';

  @override
  String get conversationsNewChat => '새 1:1 대화';

  @override
  String get conversationsNewGroup => '새 그룹';

  @override
  String get conversationsArchiveSection => '아카이브 결과';

  @override
  String get conversationsLoadingArchive => '아카이브 검색 중…';

  @override
  String get conversationsPreviewEmpty => '아직 메시지가 없습니다';

  @override
  String conversationsQueued(int count) {
    return '보내기 대기 중인 메시지 $count개';
  }

  @override
  String get conversationsPreviewExpired => '만료된 메시지';

  @override
  String get conversationsPreviewMessage => '암호화된 메시지';

  @override
  String get conversationsPreviewImage => '암호화된 이미지';

  @override
  String get conversationsPreviewAttachment => '암호화된 첨부 파일';

  @override
  String get conversationsPreviewSystem => '보안 알림';

  @override
  String get conversationsPreviewVoice => '암호화된 음성 메모';

  @override
  String get conversationsPreviewSticker => '암호화된 스티커';

  @override
  String get conversationsPreviewReaction => '암호화된 반응';

  @override
  String get conversationsPreviewCall => '암호화된 통화 기록';

  @override
  String get conversationsRelayLinked => '릴레이 연결됨';

  @override
  String get conversationsRelayIdle => '릴레이 연결 안 됨';

  @override
  String conversationsCount(int count) {
    return '대화 $count개';
  }

  @override
  String get conversationsNoBackup => '백업 없음';

  @override
  String get conversationsSyncIssueTitle => '동기화 문제';

  @override
  String get conversationsRelayInterruptedBody =>
      '릴레이와의 연결이 끊겼습니다. 보내기 대기 중인 메시지는 다시 연결되면 전송됩니다.';

  @override
  String get conversationsSearchHintCompact => '대화와 메시지 검색';

  @override
  String get conversationsSearchLocalNote => '검색은 이 기기 안에서만 이루어집니다.';

  @override
  String get conversationsFilterAllSenders => '모든 발신자';

  @override
  String get conversationsFilterMine => '내가 보낸';

  @override
  String get conversationsFilterTheirs => '상대가 보낸';

  @override
  String get conversationsFilterAllTypes => '모든 유형';

  @override
  String get conversationsFilterText => '텍스트';

  @override
  String get conversationsFilterMedia => '미디어';

  @override
  String get conversationsFilterAnyDate => '전체 기간';

  @override
  String get conversationsFilterLast7Days => '최근 7일';

  @override
  String get conversationsFilterLast30Days => '최근 30일';

  @override
  String get conversationsSectionLabel => '대화';

  @override
  String conversationsMatchCount(int count) {
    return '$count건 일치';
  }

  @override
  String get conversationsNoMatchTitle => '일치하는 대화가 없습니다';

  @override
  String get conversationsNoneYetTitle => '아직 대화가 없습니다';

  @override
  String get conversationsNoMatchBody => '이 기기에 일치하는 이름이나 핸들이 없습니다.';

  @override
  String get conversationsNoneYetBody =>
      '상대의 핸들로 대화를 시작하세요. VEIL은 연락처를 뒤져 사람을 찾지 않습니다. 상대가 알려 준 핸들을 직접 입력합니다.';

  @override
  String get conversationsStartDirect => '1:1 대화 시작';

  @override
  String get conversationsMessagesSection => '메시지';

  @override
  String conversationsResultCount(int count) {
    return '결과 $count건';
  }

  @override
  String get conversationsNoMessageMatchTitle => '일치하는 메시지가 없습니다';

  @override
  String get conversationsNoMessageMatchBody =>
      '이 기기에 있는 메시지 중 현재 필터에 맞는 것이 없습니다.';

  @override
  String get conversationsResultFromYou => '나';

  @override
  String get conversationsResultFromPeer => '상대';

  @override
  String get conversationsKindImage => '이미지';

  @override
  String get conversationsKindAttachment => '첨부 파일';

  @override
  String get conversationsKindSystem => '시스템';

  @override
  String get conversationsKindVoice => '음성';

  @override
  String get conversationsKindSticker => '스티커';

  @override
  String get conversationsKindReaction => '반응';

  @override
  String get conversationsKindCall => '통화';

  @override
  String get conversationsLoadingMore => '더 불러오는 중';

  @override
  String get conversationsLoadMore => '결과 더 보기';

  @override
  String get conversationsChoosePaneTitle => '대화를 선택하세요';

  @override
  String get conversationsChoosePaneBody =>
      '목록에서 대화를 고르거나, 목록 위의 버튼으로 새 대화를 시작하세요.';

  @override
  String get conversationsNewTooltip => '새 대화';

  @override
  String conversationsRowSemantics(String name) {
    return '$name님과의 대화';
  }

  @override
  String conversationsGroupRowSemantics(String names) {
    return '$names 그룹 대화';
  }

  @override
  String get conversationsGroupMark => '그룹';

  @override
  String get navChats => '채팅';

  @override
  String get navContacts => '연락처';

  @override
  String get navStories => '스토리';

  @override
  String get navCalls => '통화';

  @override
  String get navSettings => '설정';

  @override
  String get oneTimeLinkTitle => '일회성 비밀 링크';

  @override
  String get oneTimeLinkSettingsSubtitle =>
      '한 번 읽히면 사라지는 암호화 메시지 — 받는 사람은 앱 없이 열람';

  @override
  String get oneTimeLinkIntro =>
      '한 번 읽히면 사라지는 메시지를 만듭니다. 받는 사람은 앱이 없어도 됩니다. 복호화 키는 링크에만 담겨 서버로 전송되지 않습니다.';

  @override
  String get oneTimeLinkSecretLabel => '비밀 내용';

  @override
  String get oneTimeLinkSecretHint => '비밀번호, 계좌, 민감한 메모…';

  @override
  String get oneTimeLinkUsePassphrase => '암호문구 추가 (링크에 키를 넣지 않음 — 더 안전)';

  @override
  String get oneTimeLinkPassphraseLabel => '암호문구';

  @override
  String get oneTimeLinkCreate => '보안 링크 생성';

  @override
  String get oneTimeLinkFailed => '링크 생성에 실패했습니다. 잠시 후 다시 시도하세요.';

  @override
  String get oneTimeLinkCopy => '링크 복사';

  @override
  String get oneTimeLinkCopied => '링크를 복사했습니다';

  @override
  String get oneTimeLinkPillEncrypted => '종단간 암호화';

  @override
  String get oneTimeLinkPillServerBlind => '서버는 평문·키를 못 봄';

  @override
  String get oneTimeLinkPillBurns => '읽으면 소멸';

  @override
  String get contactsNotice =>
      '어떤 계정을 추가했는지는 릴레이에 저장됩니다. 직접 붙인 이름은 이 기기에만 남습니다.';

  @override
  String get contactsSearchHint => '연락처 검색…';

  @override
  String get contactsAdd => '연락처 추가';

  @override
  String get contactsWorking => '처리 중…';

  @override
  String get contactsErrorTitle => '연락처 오류';

  @override
  String get contactsEmptyTitle => '연락처가 없습니다';

  @override
  String get contactsEmptySearchBody => '검색과 일치하는 연락처가 없습니다.';

  @override
  String get contactsEmptyBody => '연락처를 추가하고 안전하게 대화를 시작하세요.';

  @override
  String get contactsAddSheetBody => '정확한 핸들을 입력하세요. VEIL은 주소록을 읽지 않습니다.';

  @override
  String get contactsHandleLabel => '핸들';

  @override
  String get contactsNicknameLabel => '별명 (선택)';

  @override
  String get contactsNicknameHint => '나만 보는 이름';

  @override
  String get contactsSave => '연락처 저장';

  @override
  String contactsAdded(String handle) {
    return '@$handle 님을 연락처에 추가했습니다';
  }

  @override
  String get contactsStartChat => '대화 시작';

  @override
  String get contactsStartChatFailed => '대화를 시작하지 못했습니다';

  @override
  String get contactsViewProfile => '프로필 보기';

  @override
  String get contactsRemove => '연락처 삭제';

  @override
  String contactsRemoved(String name) {
    return '$name 님을 연락처에서 삭제했습니다';
  }

  @override
  String get contactsRemoveFailed => '연락처를 삭제하지 못했습니다';

  @override
  String contactsYourNickname(String nickname) {
    return '내가 붙인 별명: $nickname';
  }

  @override
  String get callsMissed => '부재중';

  @override
  String get callsDeclined => '거절함';

  @override
  String get callsRinging => '연결 중';

  @override
  String get callsIncoming => '수신';

  @override
  String get callsOutgoing => '발신';

  @override
  String callsToday(String time) {
    return '오늘 $time';
  }

  @override
  String callsYesterday(String time) {
    return '어제 $time';
  }

  @override
  String get callsUnavailableTitle => '통화 기록을 불러올 수 없습니다';

  @override
  String get callsEmptyTitle => '통화 기록이 없습니다';

  @override
  String get callsEmptyBody => '걸거나 받은 통화가 여기에 표시됩니다.';

  @override
  String get callsNotAvailable => '이 빌드에서는 아직 통화를 사용할 수 없습니다.';

  @override
  String get notificationNewMessageTitle => 'VEIL';

  @override
  String get notificationNewMessageBody => '새로운 암호화 메시지';

  @override
  String get startDirectTitle => '핸들로 찾기';

  @override
  String get startDirectEyebrow => '다이렉트 검색';

  @override
  String get startDirectHeroTitle => '연락처 동기화 없음';

  @override
  String get startDirectHeroBody =>
      '핸들을 직접 입력하세요. VEIL은 연락처·전화번호부·소셜 그래프를 스캔하지 않습니다.';

  @override
  String get startDirectPillManual => '수동 검색';

  @override
  String get startDirectPillNoGraph => '소셜 그래프 없음';

  @override
  String get startDirectPillDirectOnly => '다이렉트 전용';

  @override
  String get startDirectBannerTitle => '의도된 검색';

  @override
  String get startDirectBannerBody =>
      '정확한 핸들을 알고 있을 때만 대화가 열립니다. 그래프로 인맥을 넓히는 기능은 없습니다.';

  @override
  String get startDirectMetricDiscovery => '검색';

  @override
  String get startDirectMetricDiscoveryValue => '수동';

  @override
  String get startDirectMetricGraph => '그래프';

  @override
  String get startDirectMetricGraphValue => '없음';

  @override
  String get startDirectMetricMode => '모드';

  @override
  String get startDirectMetricModeValue => '1:1 다이렉트';

  @override
  String get startDirectFieldLabel => '대상 핸들';

  @override
  String get startDirectAwaitingInput => '입력 대기 중';

  @override
  String get startDirectFieldCaption => '검색은 수동이며, 다이렉트 대화만 가능합니다.';

  @override
  String get startDirectInputLabel => '핸들';

  @override
  String get startDirectErrorTitle => '대화를 열 수 없음';

  @override
  String get startDirectOpening => '대화 여는 중';

  @override
  String get startDirectOpenButton => '다이렉트 대화 열기';

  @override
  String get startGroupTitle => '그룹 채팅 시작';

  @override
  String get startGroupEyebrow => '그룹 생성';

  @override
  String get startGroupHeroTitle => '초대로만 참여';

  @override
  String get startGroupHeroBody =>
      '그룹은 명시적입니다. 핸들로 멤버를 추가하세요 — VEIL은 연락처 그래프로 초대를 확장하지 않습니다.';

  @override
  String get startGroupPillInviteOnly => '초대 전용';

  @override
  String get startGroupPillManualRoster => '수동 명단';

  @override
  String get startGroupPillE2E => '종단간 암호화';

  @override
  String get startGroupNameLabel => '그룹 이름';

  @override
  String get startGroupRequired => '필수';

  @override
  String get startGroupNameCaption => '멤버에게 표시됩니다. 나중에 변경할 수 있어요.';

  @override
  String get startGroupNameInput => '이름';

  @override
  String get startGroupDescriptionLabel => '설명';

  @override
  String get startGroupDescriptionCaption => '선택. 그룹의 목적이나 배경을 적어주세요.';

  @override
  String get startGroupDescriptionInput => '설명';

  @override
  String get startGroupDescriptionHint => '이 그룹은 어떤 모임인가요?';

  @override
  String get startGroupMembersLabel => '초기 멤버';

  @override
  String get startGroupNoneYet => '아직 없음';

  @override
  String startGroupMembersCount(int count) {
    return '핸들 $count개';
  }

  @override
  String get startGroupMembersCaption =>
      '쉼표나 공백으로 핸들을 구분하세요. 생성 후에도 추가할 수 있어요.';

  @override
  String get startGroupMembersInput => '멤버 핸들';

  @override
  String get startGroupPublicTitle => '공개 디렉터리';

  @override
  String get startGroupPublicSubtitle => '공개 그룹은 핸들로 검색됩니다. 초대 전용 그룹은 꺼두세요.';

  @override
  String get startGroupErrorTitle => '그룹을 만들 수 없음';

  @override
  String get startGroupCreating => '그룹 만드는 중';

  @override
  String get startGroupCreateButton => '그룹 만들기';

  @override
  String get safetyNumbersTitle => '안전 번호';

  @override
  String get safetyNumbersLoadingTitle => '안전 번호 생성 중';

  @override
  String get safetyNumbersLoadingBody => '신원 키를 로컬에서 해싱하는 중입니다.';

  @override
  String get safetyNumbersMarkedVerified => '확인됨으로 표시했습니다';

  @override
  String get safetyNumbersRotateDialogTitle => '새 세션을 시작할까요?';

  @override
  String get safetyNumbersRotateDialogBody =>
      '상대방의 현재 키로 키 합의를 새로 수행하고, 다음 메시지부터 새 세션을 사용합니다. 이미 전송 중인 메시지는 계속 열립니다. 이 기기나 상대방 기기가 잠시 노출되었다고 의심되면 사용하세요. 탈취된 이전 세션 사본으로는 새 세션의 내용을 읽을 수 없습니다.';

  @override
  String get safetyNumbersCancel => '취소';

  @override
  String get safetyNumbersRotate => '시작';

  @override
  String get safetyNumbersSessionRotated => '새 세션이 준비되었습니다. 다음 메시지부터 사용됩니다.';

  @override
  String get safetyNumbersNoSessionYet => '아직 세션이 없습니다 — 먼저 메시지를 보내세요';

  @override
  String safetyNumbersRotationFailed(String error) {
    return '새 세션을 시작하지 못했습니다: $error';
  }

  @override
  String get safetyNumbersErrorTitle => '안전 번호를 불러올 수 없음';

  @override
  String get safetyNumbersRetry => '다시 시도';

  @override
  String get safetyNumbersNoMembersTitle => '다른 멤버 없음';

  @override
  String get safetyNumbersNoMembersBody =>
      '이 그룹에는 아직 다른 참여자가 없습니다 — 확인할 사람을 초대하세요.';

  @override
  String get safetyNumbersGroupEyebrow => '그룹 멤버 확인';

  @override
  String get safetyNumbersGroupTitleGeneric => '이 그룹의 각 멤버를 확인하세요';

  @override
  String safetyNumbersGroupTitleNamed(String groupName) {
    return '$groupName의 각 멤버를 확인하세요';
  }

  @override
  String get safetyNumbersGroupBody =>
      '멤버를 탭하면 60자리 안전 번호가 표시됩니다. 신뢰할 수 있는 채널로 비교하세요 — 통화로 읽어주거나 QR을 스캔하세요. 번호가 일치하지 않으면 해당 멤버의 기기가 위협받았을 수 있습니다.';

  @override
  String get safetyNumbersUnverified => '미확인';

  @override
  String get safetyNumbersVerified => '확인됨';

  @override
  String get safetyNumbersDetailEyebrow => '신원 확인';

  @override
  String safetyNumbersDetailTitle(String peer) {
    return '$peer님과 대화하고 있는지 확인하세요';
  }

  @override
  String get safetyNumbersDetailBody =>
      '두 사람 모두 같은 60자리 번호가 보여야 합니다. 신뢰할 수 있는 채널로 비교하세요 — 통화로 읽어주거나 QR을 스캔하세요. 번호가 일치하지 않으면 누군가 대화 중간에 끼어든 것입니다.';

  @override
  String get safetyNumbersKeyChangedTitle => '상대방 신원 키가 변경됨';

  @override
  String safetyNumbersKeyChangedMessage(String date) {
    return '이 상대방의 신원 키가 $date에 확인한 키와 다릅니다. 재설치 후 발생할 수도 있고 — 누군가 사칭하는 것일 수도 있습니다. 신뢰하기 전에 다시 확인하세요.';
  }

  @override
  String safetyNumbersVerifiedOn(String date) {
    return '$date에 확인함';
  }

  @override
  String get safetyNumbersVerifiedNote =>
      '이 상대방이 재설치하거나 기기를 변경하면 이 확인은 무효화되며 경고가 표시됩니다.';

  @override
  String get safetyNumbersReVerify => '새 키로 다시 확인';

  @override
  String get safetyNumbersMarkVerified => '확인됨으로 표시';

  @override
  String get safetyNumbersRotateEyebrow => '새 세션';

  @override
  String get safetyNumbersRotateBody =>
      '상대방의 현재 키로 키 합의를 새로 수행합니다. 다음 메시지부터 새 세션을 사용하며, 이미 전송 중인 메시지는 계속 열립니다. 이 기기나 상대방 기기가 잠시 노출되었다면 사용하세요.';

  @override
  String get safetyNumbersRotating => '시작 중…';

  @override
  String get safetyNumbersRotateButton => '새 세션 시작';

  @override
  String get safetyNumbersCardLabel => '안전 번호';

  @override
  String get safetyNumbersCardLabelCurrent => '현재 안전 번호';

  @override
  String get safetyNumbersCardLabelNew => '새 안전 번호';

  @override
  String get safetyNumbersScanLabel => '스캔하여 비교';

  @override
  String get safetyNumbersQrNote =>
      '이 QR에는 양쪽의 공개 신원 키와 사용자 ID만 담겨 있으며, 비밀 정보는 없습니다.';

  @override
  String get safetyNumbersNoPinTitle => '아직 고정된 신원이 없습니다';

  @override
  String get safetyNumbersNoPinBody => '먼저 메시지를 주고받으세요. 이 기기는 대화하는 신원을 고정합니다.';

  @override
  String get safetyNumbersDirectoryMismatchTitle => '키 서버가 다른 키를 제공합니다';

  @override
  String get safetyNumbersDirectoryMismatchBody =>
      '키 서버가 이 기기에 고정된 것과 다른 신원 키를 제공하고 있습니다. 비교하고 수락하기 전에는 그 키로 아무것도 보내지 않습니다.';

  @override
  String get safetyNumbersDirectoryOtherDeviceTitle => '키 서버가 다른 기기를 제공합니다';

  @override
  String get safetyNumbersDirectoryOtherDeviceBody =>
      '이 대화는 키 서버가 지금 이 연락처에 제공하는 기기와 다른 기기로 암호화됩니다. 위 번호는 이 대화가 암호화하는 기기의 번호입니다. 신뢰하기 전에 연락처와 비교하세요.';

  @override
  String get safetyNumbersPendingBody =>
      '이 연락처가 새 신원 키를 제시했습니다. 수락하기 전에 아래의 새 안전 번호를 비교하세요.';

  @override
  String get safetyNumbersAcceptNewKey => '새 키 수락';

  @override
  String get safetyNumbersKeepCurrentKey => '현재 키 유지';

  @override
  String get safetyNumbersScanAction => '스캔한 코드 비교';

  @override
  String get safetyNumbersScanFieldLabel => '스캔한 코드';

  @override
  String get safetyNumbersScanVerify => '비교';

  @override
  String get safetyNumbersScanMismatchTitle => '코드가 일치하지 않습니다';

  @override
  String get safetyNumbersScanMismatchBody =>
      '누군가 이 대화를 가로채고 있을 수 있습니다. 확인됨으로 표시하지 말고 직접 만나 다시 비교하세요.';

  @override
  String get safetyNumbersScanInvalid => 'VEIL 안전 코드가 아닙니다.';

  @override
  String get safetyNumbersScanUnsupported => '이 앱이 지원하지 않는 안전 번호 버전의 코드입니다.';

  @override
  String get safetyNumbersReverifyDialogTitle => '새 안전 번호 비교';

  @override
  String safetyNumbersReverifyDialogBody(String peer) {
    return '$peer님을 확인한 적이 있습니다. 직접 만나거나 신뢰할 수 있는 통화로 $peer님과 이 번호를 비교한 뒤에만 새 키를 확인됨으로 수락하세요.';
  }

  @override
  String safetyNumbersReverifyAffirm(String peer) {
    return '$peer님과 이 번호를 비교했고 일치합니다';
  }

  @override
  String get safetyNumbersReverifyAccept => '확인됨으로 수락';

  @override
  String get safetyNumbersChangeReplaced =>
      '검토하는 동안 안전 번호가 다시 바뀌었습니다. 수락하기 전에 새 번호를 비교하세요.';

  @override
  String get safetyNumbersChangedElsewhereTitle => '안전 번호가 바뀌었습니다';

  @override
  String safetyNumbersChangedElsewhereBody(String peer) {
    return '$peer님이 다른 대화에서 새 신원 키를 제시했습니다. 그 대화에서 확인하기 전까지 $peer님은 확인됨으로 표시되지 않습니다. 아래는 변경 전에 이 기기에 고정된 번호입니다.';
  }

  @override
  String get safetyNumbersReviewChange => '새 키 확인하기';

  @override
  String get profileTitle => '프로필';

  @override
  String get profileNicknameSaved => '닉네임을 이 기기에 저장했습니다';

  @override
  String get profileHandleLabel => '핸들';

  @override
  String get profileHandleCaption => '핸들은 변경할 수 없습니다.';

  @override
  String get profileNicknameLabel => '닉네임';

  @override
  String get profileNicknameCaption => '이 기기만 알고 있습니다. 상대방에게는 핸들이 보입니다.';

  @override
  String get profileNicknameHint => '이 기기에서 나를 부를 이름';

  @override
  String get profileNicknameNotSet => '설정되지 않음';

  @override
  String get profilePrivacyEyebrow => '개인정보';

  @override
  String get profilePrivacyTitle => '릴레이에는 나에 대한 정보가 없습니다';

  @override
  String get profilePrivacyBody =>
      '릴레이는 핸들로만 메시지를 전달하며 이름, 소개, 상태를 저장하지 않습니다. 닉네임은 이 기기에만 남고 기기와 함께 지워집니다.';

  @override
  String get profileSaveNickname => '닉네임 저장';

  @override
  String get profileEditNickname => '닉네임 수정';

  @override
  String get profileCancel => '취소';

  @override
  String get deviceTransferTitle => '기기 이전';

  @override
  String get deviceTransferHeroEyebrow => '이전';

  @override
  String get deviceTransferHeroTitle => '기존 기기가 필요합니다.';

  @override
  String get deviceTransferHeroBody =>
      '이전은 핸들을 새 기기로 옮깁니다. 기존 기기가 세션을 발급하고 새 기기가 보낸 바로 그 등록 요청을 승인하며, 이전이 완료되면 기존 기기는 로그아웃됩니다. 대화 기록은 옮겨지지 않습니다. VEIL은 복구 수단을 만들지 않습니다.';

  @override
  String get deviceTransferPillTrustedJoin => '신뢰된 기기 연결';

  @override
  String get deviceTransferPillNoFallback => '대체 수단 없음';

  @override
  String get deviceTransferPillNoCloud => '클라우드 복구 없음';

  @override
  String get deviceTransferChipOldDevice => '기존 기기';

  @override
  String get deviceTransferChipNewDevice => '새 기기';

  @override
  String get deviceTransferNoFallbackTitle => '대체 경로 없음';

  @override
  String get deviceTransferNoFallbackBody =>
      '기존 기기가 없으면 이전은 실패합니다. VEIL은 복구·초기화·내보내기·관리자 복원을 제공하지 않습니다.';

  @override
  String get deviceTransferWindowExpiredTitle => '이전 가능 시간 만료';

  @override
  String get deviceTransferSessionExpiredMessage =>
      '기존 기기의 이전 세션이 만료되었습니다. 기존 기기에서 새 세션을 발급하세요.';

  @override
  String get deviceTransferClaimExpiredMessage =>
      '이 새 기기의 등록 요청이 만료되었습니다. 새로 등록 요청을 보내고 다시 승인을 요청하세요.';

  @override
  String get deviceTransferMetricMode => '모드';

  @override
  String get deviceTransferMetricModeOld => '기존 기기';

  @override
  String get deviceTransferMetricModeNew => '새 기기';

  @override
  String get deviceTransferMetricSession => '세션';

  @override
  String get deviceTransferSessionExpired => '만료됨';

  @override
  String get deviceTransferSessionIdle => '대기';

  @override
  String get deviceTransferSessionLive => '활성';

  @override
  String get deviceTransferMetricClaim => '등록 요청';

  @override
  String get deviceTransferClaimMissing => '없음';

  @override
  String get deviceTransferClaimExpired => '만료됨';

  @override
  String get deviceTransferClaimIssued => '발급됨';

  @override
  String get deviceTransferPayloadCopied => '이전 코드를 복사했습니다.';

  @override
  String get deviceTransferReturnToConversations => '대화 목록으로 돌아가기';

  @override
  String get deviceTransferPayloadInvalid => '이전 코드 형식이 올바르지 않습니다.';

  @override
  String get deviceTransferPayloadImported =>
      '이전 코드를 가져왔습니다. 이전 가능 시간이 끝나기 전에 이 새 기기를 등록하세요.';

  @override
  String get deviceTransferImportFirst => '먼저 올바른 이전 코드를 가져오세요.';

  @override
  String get deviceTransferClaimRegistered =>
      '등록 요청을 보냈습니다. 이 요청 코드를 기존 기기에 전달하고 만료 전에 승인을 요청하세요.';

  @override
  String get deviceTransferClaimFailed => '등록 요청에 실패했습니다.';

  @override
  String get deviceTransferRegisterBeforeComplete =>
      '완료하기 전에 이 새 기기의 등록 요청을 보내세요.';

  @override
  String get deviceTransferClaimExpiredRegisterFresh =>
      '이 새 기기의 등록 요청이 만료되었습니다. 먼저 새로 등록 요청을 보내세요.';

  @override
  String get deviceTransferFinishStartedFirst =>
      '이 기기는 릴레이가 이미 마쳤을 수 있는 이전을 완료하는 중이었습니다. 다른 이전을 가져오기 전에 이 기기에서 그 이전을 완료하세요.';

  @override
  String get deviceTransferComplete =>
      '이전이 완료되었습니다. 이제 핸들이 이 기기에 있으며 기존 기기는 로그아웃되었습니다.';

  @override
  String get deviceTransferFailed => '이전에 실패했습니다.';

  @override
  String get deviceTransferOldRequiredTitle => '기존 기기 세션 필요';

  @override
  String get deviceTransferOldRequiredBody =>
      '현재 신뢰된 기기에서 로그인하여 이전을 발급하고 승인하세요.';

  @override
  String get deviceTransferStep1Title => '1. 기존 기기에서 시작';

  @override
  String get deviceTransferStep1BodyReady => '다음 기기를 위한 단기 세션과 토큰을 생성합니다.';

  @override
  String deviceTransferStep1BodyExpires(String when) {
    return '이 이전 세션은 $when 만료됩니다.';
  }

  @override
  String get deviceTransferStatusReady => '준비됨';

  @override
  String get deviceTransferStatusExpired => '만료됨';

  @override
  String get deviceTransferStatusIssued => '발급됨';

  @override
  String get deviceTransferIssuingToken => '토큰 발급 중';

  @override
  String get deviceTransferIssueToken => '이전 토큰 발급';

  @override
  String get deviceTransferStep2Title => '2. 기존 기기에서 승인';

  @override
  String get deviceTransferStep2BodyWaiting => '아직 이전 세션이 없습니다.';

  @override
  String get deviceTransferStep2BodyExpired =>
      '이 이전 세션이 만료되었습니다. 지우고 새로 발급하세요.';

  @override
  String get deviceTransferStep2BodyAwaiting =>
      '새 기기가 등록 요청을 보낼 때까지 기다린 뒤, 여기서 그 요청 코드를 승인하세요.';

  @override
  String get deviceTransferStatusWaiting => '대기 중';

  @override
  String get deviceTransferStatusAwaitingClaim => '등록 요청 대기 중';

  @override
  String get deviceTransferClaimFieldLabel => '새 기기 등록 요청';

  @override
  String get deviceTransferClaimFieldCaption =>
      '신뢰하는 새 기기에 표시된 바로 그 요청 코드만 승인하세요.';

  @override
  String get deviceTransferClaimInputLabel => '새 기기 요청 코드';

  @override
  String get deviceTransferClaimInputHint => '새 기기에 표시된 요청 코드를 붙여넣으세요';

  @override
  String get deviceTransferApproveClaim => '이 요청 승인';

  @override
  String get deviceTransferStep3Title => '3. 새 기기에 이전 코드 전달';

  @override
  String get deviceTransferReadyToCopy => '복사 준비됨';

  @override
  String get deviceTransferIssueTokenFirst => '먼저 이전 토큰을 발급하세요.';

  @override
  String get deviceTransferPayloadExpiredNote =>
      '이 이전 코드는 더 이상 유효하지 않습니다. 지우고 새 이전 세션을 발급하세요.';

  @override
  String get deviceTransferCompleteOnNewNote =>
      '새 기기에서 완료하세요. 완료되면 이 기기는 로그아웃되고 로컬 기록이 지워집니다. 대화 기록은 새 기기로 옮겨지지 않습니다.';

  @override
  String get deviceTransferCopyPayload => '이전 코드 복사';

  @override
  String get deviceTransferClear => '지우기';

  @override
  String get deviceTransferStatusTitle => '이전 상태';

  @override
  String get deviceTransferStatusNeedsApi => '기기 이전은 API 모드에서만 할 수 있습니다.';

  @override
  String get deviceTransferStatusTokenReady => '이전 세션을 열었습니다. 토큰이 준비되었습니다.';

  @override
  String get deviceTransferStatusNotStarted => '먼저 이전을 시작하세요.';

  @override
  String get deviceTransferStatusClaimCodeMissing => '먼저 새 기기의 요청 코드를 입력하세요.';

  @override
  String deviceTransferStatusClaimNotWaiting(String claimId) {
    return '이 이전에서 대기 중인 요청이 아닙니다: $claimId';
  }

  @override
  String deviceTransferStatusClaimApproved(String claimId, String fingerprint) {
    return '기존 기기에서 요청 $claimId 승인 완료. 키 지문: $fingerprint';
  }

  @override
  String get deviceTransferFailedTitle => '이전 실패';

  @override
  String get deviceTransferPayloadFieldLabel => '이전 코드';

  @override
  String get deviceTransferPayloadFieldCaption =>
      '신뢰된 기존 기기가 발급한 단기 세션과 토큰을 가져오세요.';

  @override
  String get deviceTransferPayloadInputLabel => '이전 코드 붙여넣기';

  @override
  String get deviceTransferImportPayload => '이전 코드 가져오기';

  @override
  String get deviceTransferNewDeviceLabel => '새 기기';

  @override
  String get deviceTransferNewDeviceCaption =>
      '이 기기는 등록 요청이 자신의 것임을 증명합니다. 기존 기기는 바로 그 요청만 승인합니다.';

  @override
  String get deviceTransferDeviceNameLabel => '기기 이름';

  @override
  String get deviceTransferSessionIdLabel => '세션 ID';

  @override
  String get deviceTransferTokenLabel => '이전 토큰';

  @override
  String get deviceTransferClaimNotRegistered => '등록 요청 전';

  @override
  String get deviceTransferClaimExpiredPill => '등록 요청 만료됨';

  @override
  String get deviceTransferClaimRegisteredPill => '등록 요청 보냄';

  @override
  String get deviceTransferOldApprovesExact => '기존 기기가 이 요청만 승인';

  @override
  String deviceTransferClaimCode(String claimId) {
    return '요청 코드 $claimId';
  }

  @override
  String deviceTransferClaimFingerprint(String fingerprint) {
    return '요청 지문 $fingerprint';
  }

  @override
  String get deviceTransferFingerprintUnavailable => '사용 불가';

  @override
  String deviceTransferExpires(String when) {
    return '$when 만료';
  }

  @override
  String get deviceTransferRegisteringClaim => '등록 요청 보내는 중';

  @override
  String get deviceTransferRegisterNewDevice => '이 새 기기 등록';

  @override
  String get deviceTransferCompleting => '이전 완료 중';

  @override
  String get deviceTransferCompleteOnDevice => '이 기기에서 완료';

  @override
  String get deviceTransferExpiryNow => '지금';

  @override
  String deviceTransferExpiryInSeconds(int seconds) {
    return '$seconds초 후';
  }

  @override
  String deviceTransferExpiryInMinutes(int minutes) {
    return '$minutes분 후';
  }

  @override
  String deviceTransferExpiryAt(String time) {
    return '$time';
  }

  @override
  String get themeModeTitle => '테마';

  @override
  String get themeModeSubtitle => '이 기기에서 VEIL의 표시 방식을 선택하세요.';

  @override
  String get themeModeLight => '라이트';

  @override
  String get themeModeDark => '다크';

  @override
  String get themeModeSystem => '시스템';

  @override
  String get aiDemoBannerTitle => '스크립트 데모';

  @override
  String get aiDemoBannerBody => '데모: 답변은 이 기기에 미리 정해진 내용입니다. 어디로도 전송되지 않습니다.';

  @override
  String get securityStatusTitle => '보안 상태';

  @override
  String get securityStatusEyebrow => '보안 상태';

  @override
  String get securityStatusHeroTitle => '백업 없음. 복구 없음. 유출 없음.';

  @override
  String get securityStatusHeroBody =>
      '신원과 런타임 항목은 이 기기와 이 빌드에서 읽어 옵니다. 제품 규칙은 모든 VEIL 빌드에 똑같이 적용됩니다.';

  @override
  String get securityStatusPillPrivateBeta => '비공개 베타';

  @override
  String get securityStatusMetricRuntime => '런타임';

  @override
  String get securityStatusMetricRelay => '릴레이';

  @override
  String get securityStatusMetricRelayLinked => '연결됨';

  @override
  String get securityStatusMetricCache => '캐시';

  @override
  String get securityStatusMetricCacheOff => '꺼짐';

  @override
  String get securityStatusSectionIdentity => '신원';

  @override
  String get securityStatusSectionRuntime => '런타임';

  @override
  String get securityStatusSectionProductRules => '제품 규칙';

  @override
  String get securityStatusChecking => '확인 중';

  @override
  String get securityStatusAvailable => '사용 가능';

  @override
  String get securityStatusUnavailable => '사용 불가';

  @override
  String get securityStatusEnabled => '켜짐';

  @override
  String get securityStatusDisabled => '꺼짐';

  @override
  String get securityStatusReady => '준비됨';

  @override
  String get securityStatusStarting => '시작 중';

  @override
  String get securityStatusBlocked => '차단됨';

  @override
  String get securityStatusIdle => '대기 중';

  @override
  String get securityStatusBoundDevice => '연결된 기기';

  @override
  String get securityStatusBoundDeviceUnbound => '연결 안 됨';

  @override
  String get securityStatusBoundDeviceNoneDetail => '활성 기기 세션이 없습니다.';

  @override
  String get securityStatusBoundDeviceDetail =>
      '이 기기가 현재 활성 VEIL 세션을 보유하고 있습니다.';

  @override
  String get securityStatusSecretRefs => '로컬 비밀 키 참조';

  @override
  String get securityStatusSecretRefsPresent => '있음';

  @override
  String get securityStatusSecretRefsMissing => '없음';

  @override
  String get securityStatusSecretRefsDetail =>
      '기기의 비밀 키 자료는 이 기기에만 남습니다. 서버는 이를 받지 않습니다.';

  @override
  String get securityStatusPin => '앱 잠금 PIN';

  @override
  String get securityStatusPinConfigured => '설정됨';

  @override
  String get securityStatusPinUnset => '설정 안 됨';

  @override
  String get securityStatusPinDetail =>
      '이 기기에만 적용되는 잠금입니다. VEIL은 앱 잠금을 대신 풀어 줄 수 없습니다.';

  @override
  String get securityStatusBiometrics => '생체 인식';

  @override
  String get securityStatusBiometricsDetail =>
      '기기 자체의 생체 인식 잠금 해제만 지원합니다. 원격 대체 수단은 없습니다.';

  @override
  String get securityStatusPrivacyShield => '개인정보 보호막';

  @override
  String get securityStatusPrivacyShieldDetail =>
      'VEIL이 백그라운드로 가면 미리보기를 가리고 로컬 잠금을 다시 겁니다.';

  @override
  String get securityStatusAppPreview => '최근 앱 미리보기';

  @override
  String get securityStatusAppPreviewProtected => '보호됨';

  @override
  String get securityStatusAppPreviewPartial => '일부만 보호';

  @override
  String get securityStatusAppPreviewDetail =>
      'VEIL이 백그라운드에 있는 동안 네이티브와 Flutter 보호막으로 앱 전환 화면의 내용을 가립니다.';

  @override
  String get securityStatusScreenCapture => '화면 캡처';

  @override
  String get securityStatusScreenCapturePlatformLimited => '플랫폼 제한';

  @override
  String get securityStatusScreenCaptureNotBlocked => '차단 안 됨';

  @override
  String get securityStatusScreenCaptureSupportedDetail =>
      'Android에서는 켜져 있을 때 보안 창 플래그로 스크린샷을 차단합니다.';

  @override
  String get securityStatusScreenCaptureUnsupportedDetail =>
      '이 플랫폼에는 스크린샷을 완전히 막는 공개 API가 없어, VEIL은 미리보기 가림과 빠른 재잠금으로 대신합니다.';

  @override
  String get securityStatusScreenCaptureCheckingDetail =>
      '네이티브 화면 캡처 정책을 확인하는 중입니다.';

  @override
  String get securityStatusClipboard => '클립보드 보호';

  @override
  String get securityStatusClipboardRestricted => '제한됨';

  @override
  String get securityStatusClipboardDetail =>
      '민감한 첨부파일 티켓은 서명된 URL을 그대로 복사·공유하지 않고 기기에서 요약해 보여 줍니다.';

  @override
  String get securityStatusTransport => '전송 정책';

  @override
  String get securityStatusTransportCompliant => '준수';

  @override
  String get securityStatusTransportDetail =>
      '설정된 엔드포인트가 현재 비공개 베타 전송 정책을 충족합니다.';

  @override
  String get securityStatusTlsPins => 'TLS 고정';

  @override
  String get securityStatusTlsPinsPinned => '고정됨';

  @override
  String get securityStatusTlsPinsUnpinned => '고정 안 됨';

  @override
  String securityStatusTlsPinsPinnedDetail(int count) {
    return '이 빌드는 릴레이의 TLS 키를 고정합니다($count개). 어느 키와도 맞지 않는 인증서는 거부됩니다.';
  }

  @override
  String get securityStatusTlsPinsUnpinnedDetail =>
      '이 빌드에는 TLS 고정 값(VEIL_TLS_PINS)이 없어, 릴레이 연결이 플랫폼이 신뢰하는 인증서를 모두 받아들입니다. 릴리스 빌드는 고정 값이 없으면 설정 오류에서 멈춥니다.';

  @override
  String get securityStatusApiMode => 'API 모드';

  @override
  String get securityStatusApiAttached => '연결됨';

  @override
  String get securityStatusApiAttachedDetail => '이 빌드에는 REST API가 설정되어 있습니다.';

  @override
  String get securityStatusApiUnavailableDetail =>
      'API 엔드포인트가 설정되지 않아 메시지를 주고받을 수 없습니다.';

  @override
  String get securityStatusRelayLink => '릴레이 연결';

  @override
  String get securityStatusRelayConnected => '연결됨';

  @override
  String get securityStatusRelayConnectedDetail =>
      '실시간 릴레이에 연결되어 있으며, 이벤트 데이터는 내용을 드러내지 않습니다.';

  @override
  String get securityStatusRelayIdleDetail => '실시간 릴레이 연결이 끊겼거나 아직 동기화 중입니다.';

  @override
  String get securityStatusLocalCache => '로컬 캐시';

  @override
  String get securityStatusLocalCacheDisabledDetail =>
      '이 빌드에서는 로컬 메시지 캐시가 꺼져 있습니다.';

  @override
  String get securityStatusLocalCacheDetail =>
      '대화와 엔벨로프는 현재 비공개 베타의 저장 시 암호화 계층 뒤에 로컬로 캐시되고, 앱 전환 화면 미리보기에서 가려지며, 기기 데이터를 지우는 이벤트가 일어나면 삭제됩니다.';

  @override
  String get securityStatusIntegrity => '기기 무결성';

  @override
  String get securityStatusIntegrityCompromised => '손상됨';

  @override
  String get securityStatusIntegrityClean => '정상';

  @override
  String get securityStatusIntegrityCompromisedDetail =>
      '이 기기에서 루팅 또는 탈옥 징후가 감지되었습니다. 이 상태에서는 VEIL이 로컬 잠금 해제를 막습니다.';

  @override
  String securityStatusIntegrityCompromisedReasons(String reasons) {
    return '이 기기에서 루팅 또는 탈옥 징후가 감지되었습니다. $reasons';
  }

  @override
  String get securityStatusIntegrityCleanDetail =>
      '이 기기에서는 네이티브 루팅·탈옥 탐지에 걸린 항목이 없습니다.';

  @override
  String get securityStatusIntegrityCheckingDetail => '네이티브 무결성 탐지를 확인하는 중입니다.';

  @override
  String get securityStatusCloudBackup => '클라우드 백업';

  @override
  String get securityStatusCloudBackupDetail =>
      'VEIL은 메시지 기록의 복구용 사본을 보관하지 않습니다.';

  @override
  String get securityStatusAccountRecovery => '계정 복구';

  @override
  String get securityStatusAccountRecoveryDetail =>
      '복구 이메일, 재설정 절차, 관리자 복원 경로가 없습니다.';

  @override
  String get securityStatusDeviceTransfer => '기기 이전';

  @override
  String get securityStatusDeviceTransferValue => '기존 기기 필요';

  @override
  String get securityStatusDeviceTransferDetail =>
      '기존 기기가 승인할 수 있을 때에만 이전이 완료됩니다.';

  @override
  String get securityStatusLocalWipe => '로컬 초기화';

  @override
  String get securityStatusLocalWipeDetail =>
      '이 기기는 복구 경로를 만들지 않고 로컬 세션 상태, 로컬 비밀 키, 암호화된 캐시, 로컬 잠금을 지울 수 있습니다.';

  @override
  String get securityStatusCryptoAdapter => '암호 어댑터';

  @override
  String get securityStatusCryptoVeilRatchet => '프로덕션 (감사 전)';

  @override
  String securityStatusCryptoVeilRatchetDetail(String adapterId) {
    return 'VEIL 자체 X3DH와 더블 래칫(X25519, AES-256-GCM, Ed25519)이 동작 중입니다($adapterId). 외부 감사는 아직 진행 전입니다.';
  }

  @override
  String get securityStatusCryptoLibsignal => 'libsignal 브리지 (감사 전)';

  @override
  String securityStatusCryptoLibsignalDetail(String adapterId) {
    return '세션과 메시지 암호화는 VEIL 네이티브 브리지를 거쳐 Signal의 libsignal에서 동작합니다($adapterId). 이 브리지는 아직 감사를 받지 않았습니다.';
  }

  @override
  String get securityStatusCryptoDevelopment => '개발용';

  @override
  String securityStatusCryptoDevelopmentDetail(String adapterId) {
    return '이 빌드는 프로덕션 암호화가 아닌 개발용 어댑터($adapterId)로 동작합니다. 실제 대화에 쓰지 마세요.';
  }

  @override
  String get securityStatusPushPlaintext => '푸시 평문';

  @override
  String get securityStatusPushPlaintextForbidden => '금지';

  @override
  String get securityStatusPushPlaintextDetail =>
      '푸시 알림 데이터에는 메시지 평문이 절대 담기지 않아야 합니다.';

  @override
  String get securityStatusPushProvider => '푸시 제공자';

  @override
  String get securityStatusPushProviderSeam => '연결부만 있음';

  @override
  String get securityStatusPushProviderSeamDetail =>
      '메타데이터만 담는 깨우기 경로는 정의되어 있지만, 이 빌드에는 실제 APNs/FCM 제공자가 연결되어 있지 않습니다.';

  @override
  String get securityStatusPushProviderUnavailableDetail =>
      'API 엔드포인트가 설정되지 않아 이 빌드에서는 푸시를 받을 수 없습니다.';

  @override
  String get securityStatusPushPayloads => '푸시 알림 데이터';

  @override
  String get securityStatusPushPayloadsMetadata => '메타데이터만';

  @override
  String get securityStatusPushPayloadsMetadataDetail =>
      '나중에 푸시가 켜지더라도 깨우기 신호에는 메타데이터만 담아야 합니다. 메시지 본문은 푸시에 담기지 않습니다.';

  @override
  String get securityStatusPushPayloadsUnavailableDetail =>
      'API 엔드포인트가 설정되지 않아 이 빌드에서는 푸시 알림 데이터를 만들지 않습니다.';
}
