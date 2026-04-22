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
  String get splashEyebrow => '비공개 베타';

  @override
  String get splashBody => '백업 없음. 복구 없음. 유출 없음.';

  @override
  String get splashErrorTitle => '런타임 구성이 차단됨';

  @override
  String get splashPreparingTitle => '로컬 상태 준비 중';

  @override
  String get splashPreparingBody => '온보딩, 세션 바인딩, 로컬 보안 상태를 확인하는 중입니다.';

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
  String get privacyConsentAgree =>
      '위 개인정보 수집·이용에 동의합니다. (필수)\nI agree to the collection and use of personal information as described above. (Required)';

  @override
  String get privacyConsentAccept => '동의하고 계속하기';

  @override
  String get privacyConsentCollectTitle => '수집하는 개인정보';

  @override
  String get privacyConsentCollectItem1 => '사용자 핸들 (고유 식별자)';

  @override
  String get privacyConsentCollectItem2 => '디바이스 정보 (플랫폼, 디바이스명)';

  @override
  String get privacyConsentCollectItem3 => '공개키 (암호화 통신용)';

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
  String get privacyConsentRetentionItem2 => '디바이스 해제 시 해당 디바이스 정보 삭제';

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
  String get privacyConsentNotCollectedItem3 => '연락처, 통화 기록 등 디바이스 개인정보';

  @override
  String get privacyConsentThirdPartyTitle => '제3자 제공';

  @override
  String get privacyConsentThirdPartyBody =>
      'VEIL은 수집한 개인정보를 제3자에게 제공하지 않습니다. 다만 법령에 의한 요청이 있는 경우 관련 법령에 따라 처리합니다.';

  @override
  String get authCreateTitle => '계정 만들기';

  @override
  String get authCreateEyebrow => '기기 바인딩';

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
      '핸들은 검색 계층입니다. 이 레이블은 표시용이며 검색에는 사용되지 않습니다.';

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
  String get authHandleFieldCaption => '소문자. 간결하게. 의미를 가질 만큼 영속적으로.';

  @override
  String get authHandleInputLabel => '핸들';

  @override
  String get authHandleInputHint => 'cold.operator';

  @override
  String get authHandleChoosePrompt => '핸들을 입력하세요';

  @override
  String get authHandleBindingSection => '바인딩 절차';

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
  String get authHandleStep4Title => '검증 및 바인딩';

  @override
  String get authHandleStep4Body => '검증을 완료하고 기기 세션을 활성화합니다.';

  @override
  String get authHandleFailedTitle => '바인딩 실패';

  @override
  String get authHandleBindCta => '이 기기 바인딩';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsEyebrow => '로컬 기기';

  @override
  String get settingsNoDeviceBound => '바인딩된 기기 세션이 없습니다.';

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
  String get chatEmptyTitle => '메시지가 아직 없습니다';

  @override
  String get chatEmptyBody => '첫 메시지를 보내보세요. 종단간 암호화로 보호됩니다.';

  @override
  String get chatComposeHint => '메시지를 입력하세요';

  @override
  String get chatSendAction => '보내기';

  @override
  String get chatAttachAction => '첨부';

  @override
  String get chatLoadingTitle => '세션 여는 중';

  @override
  String get chatLoadingBody => '암호화 채널을 준비하고 있습니다…';

  @override
  String get chatConversationNotFound => '대화를 찾을 수 없습니다';

  @override
  String get chatRelockTitle => '세션 잠김';

  @override
  String get chatRelockBody => '이 대화를 이어가려면 앱 잠금을 해제하세요.';

  @override
  String get chatTitleFallback => '보안 대화';

  @override
  String get chatHeroEyebrow => '보안 대화';

  @override
  String get chatHeroBody =>
      '1:1 직접 교환만 가능합니다. 메시지 본문은 서버에서 읽을 수 없으며, 설정한 경우 로컬에서 만료됩니다.';

  @override
  String get chatSubtitleOnline => '온라인';

  @override
  String get chatSubtitleEmbedded =>
      '로컬 검색은 이 기기에만 남습니다. 메시지 본문은 릴레이에서 읽을 수 없습니다.';

  @override
  String get chatSubtitleStandalone =>
      '1:1 직접 교환만 가능합니다. 메시지 본문은 서버에서 읽을 수 없습니다.';

  @override
  String get chatSearchHint => '이 기기의 캐시된 메시지 검색';

  @override
  String get chatSearchClearTooltip => '검색 지우기';

  @override
  String get chatPillAttachmentsEncrypted => '첨부파일 암호화됨';

  @override
  String get chatPillLocalSearchOnly => '로컬 검색 전용';

  @override
  String get chatMetricRelay => '릴레이';

  @override
  String get chatMetricRelayLinked => '연결됨';

  @override
  String get chatMetricRelayRecovering => '복구 중';

  @override
  String get chatMetricLoaded => '로드됨';

  @override
  String get chatMetricHistory => '기록';

  @override
  String get chatMetricHistoryLoading => '이전 메시지 로딩';

  @override
  String get chatMetricHistoryPaged => '페이지됨';

  @override
  String get chatMetricHistoryComplete => '완료';

  @override
  String get chatMetricSearch => '검색';

  @override
  String get chatMetricSearchIdle => '대기';

  @override
  String chatMetricSearchHits(int count) {
    return '$count건 일치';
  }

  @override
  String get chatBannerHistoryLoadingTitle => '이전 기록 동기화 중';

  @override
  String get chatBannerHistoryLoadingBody =>
      '이 신뢰 기기를 위해 릴레이에서 오래된 암호화 기록을 불러옵니다.';

  @override
  String get chatBannerHistoryCompleteTitle => '대화 창 완전 로드됨';

  @override
  String get chatBannerHistoryCompleteBody =>
      '현재 이 기기의 로컬 창이 완전히 로드되었습니다. 더 이상 대기 중인 이전 기록은 없습니다.';

  @override
  String get chatBannerConversationIssue => '대화 문제';

  @override
  String get chatBannerRelayReconnecting => '릴레이 재연결 중';

  @override
  String get chatBannerDeliveryStalled => '전송 정지됨';

  @override
  String get chatBannerQueuedLocally => '로컬에 대기 중';

  @override
  String chatBannerFailedSends(int count) {
    return '$count개 메시지 전송 실패. 릴레이에 연결되면 다시 시도하세요.';
  }

  @override
  String chatBannerUploadingAttachments(int count) {
    return '$count개 첨부 메시지가 전송 전 암호화된 블롭을 업로드 중입니다.';
  }

  @override
  String chatBannerQueuedMessages(int count) {
    return '$count개 메시지가 로컬에 대기 중이며 재연결 후 재시도됩니다.';
  }

  @override
  String get chatRetryFailedSendsAction => '실패한 전송 재시도';

  @override
  String get chatSearchBannerSearchingTitle => '로컬 검색 중';

  @override
  String get chatSearchBannerIdleTitle => '로컬 메시지 검색';

  @override
  String get chatSearchBannerSearchingBody =>
      '이 기기의 캐시된 메시지 텍스트를 스캔합니다. 릴레이 상태는 변경되지 않습니다.';

  @override
  String get chatSearchBannerEmptyBody => '현재 대화에서 이 쿼리와 일치하는 캐시된 메시지가 없습니다.';

  @override
  String chatSearchBannerResultBody(int count) {
    return '캐시된 일치 항목 $count건을 표시 중입니다. 검색을 지우면 전체 대화로 돌아갑니다.';
  }

  @override
  String get chatComposerExpiryOff => '규칙을 변경하지 않으면 이 메시지는 만료되지 않습니다.';

  @override
  String chatComposerExpiryOn(String duration) {
    return '이 메시지는 수신한 모든 기기에서 $duration 후 만료됩니다.';
  }

  @override
  String get chatLoadOlder => '이전 메시지 불러오기';

  @override
  String get chatLoadingOlder => '이전 메시지 로딩 중';

  @override
  String get chatSearchEmptyTitle => '로컬에서 찾을 수 없음';

  @override
  String get chatSearchEmptyBody => '현재 대화에서 일치하는 캐시된 메시지를 찾지 못했습니다.';

  @override
  String get chatTtlSheetTitle => '사라지는 메시지';

  @override
  String get chatTtlOff => '끔';

  @override
  String get chatTtlOffCaption => '수동으로 삭제할 때까지 메시지가 유지됩니다.';

  @override
  String get chatTtl10s => '10초';

  @override
  String get chatTtl10sCaption => '가장 강력한 순간성. 수신자가 보고 있을 때 사용하세요.';

  @override
  String get chatTtl1m => '1분';

  @override
  String get chatTtl5m => '5분';

  @override
  String get chatTtl1h => '1시간';

  @override
  String get chatTtl1d => '1일';

  @override
  String get chatTtl1dCaption => '일상적인 비공개 대화의 기본값.';

  @override
  String get chatTtlCustom => '사용자 TTL';

  @override
  String get chatTtlDisabledLabel => '사라짐 꺼짐';

  @override
  String get chatAttachmentTicketTitle => '첨부 티켓 준비됨';

  @override
  String chatAttachmentTicketBody(String summary) {
    return '이 기기를 위한 단기 로컬 다운로드 티켓이 발급되었습니다.\n\n요약: $summary\n\n원본 티켓 복사 및 공유는 의도적으로 비활성화되어 있습니다.';
  }

  @override
  String get chatAttachmentTicketFailed => '첨부 티켓 실패';

  @override
  String get chatAttachmentResolveAction => '다운로드 티켓 발급';

  @override
  String get chatAttachmentResolvingAction => '티켓 발급 중';

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
  String get chatReplyLocally => '로컬 답장';

  @override
  String get chatReplyPrimed => '이 대화에서 빠른 응답을 위한 입력창이 활성화되었습니다.';

  @override
  String get chatScreenshotToast =>
      '이 대화에서 스크린샷이 감지되었습니다. 이 기기에서는 VEIL이 이를 막을 수 없으며 상대방에게 알림이 전송되었습니다.';

  @override
  String get chatScreenshotSystemNotice => '상대방이 자신의 기기에서 이 대화를 스크린샷으로 캡처했습니다.';

  @override
  String get chatDecryptingEnvelope => '엔벨로프 복호화 중...';

  @override
  String get chatDecryptingSystemNotice => '시스템 알림 복호화 중...';

  @override
  String get chatRetrySend => '전송 재시도';

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
    return '@$handle님이 입력 중';
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
    return '$count개 메시지가 릴레이 복구를 기다리는 중입니다. $retryLabel';
  }

  @override
  String chatNetworkRecoveryUploading(int count, String retryLabel) {
    return '$count개 첨부 메시지가 릴레이 재연결 중 일시중지되었습니다. $retryLabel';
  }

  @override
  String chatNetworkRecoveryQueued(int count, String retryLabel) {
    return '$count개 메시지가 이 기기에 대기 중입니다. $retryLabel';
  }

  @override
  String get chatRetryResumes => '릴레이에 재연결되면 재시도가 재개됩니다.';

  @override
  String chatRetryNextIn(String countdown) {
    return '다음 재시도: $countdown 후.';
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
  String get conversationsTitle => '대화';

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
  String get conversationsQueuedOne => '로컬에 메시지 1개 대기 중';

  @override
  String conversationsQueuedMany(int count) {
    return '로컬에 메시지 $count개 대기 중';
  }

  @override
  String get notificationNewMessageTitle => 'VEIL';

  @override
  String get notificationNewMessageBody => '새로운 암호화 메시지';
}
