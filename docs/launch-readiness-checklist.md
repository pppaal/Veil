# Veil 런치 준비 체크리스트 (Launch Readiness Checklist)

> 권위 있는 단일 출처 (authoritative source of truth). 마지막 갱신: 2026-06-24

## 솔직한 현실: 오늘 당장 App Store 출시는 불가능합니다

App-Store-same-day는 **불가능**합니다. 이유는 단순합니다:

1. **외부 암호 감사가 조직 차원의 ship gate입니다.** `VEIL_AUDITED_CRYPTO_ATTESTED=false`인 동안 프로덕션 API는 부팅을 거부합니다 (`apps/api/src/common/config/app-config.service.ts:129-140`). 이 감사는 외부 제3자 암호학자가 수행해야 하며, 통상 4~8주가 소요됩니다. 에이전트나 운영자가 코드로 끝낼 수 없습니다.
2. **Apple Developer Program 등록과 서명 자격이 없습니다.** `DEVELOPMENT_TEAM`, 프로비저닝 프로파일이 전혀 설정되어 있지 않고 (`apps/mobile/ios/Runner.xcodeproj/project.pbxproj`), App Store Connect 앱 레코드도 없습니다. 등록·심사에는 시간이 걸립니다.
3. **서명된 `.ipa`를 빌드·업로드하려면 Mac + Xcode가 필요합니다.** 이 Linux 환경에서는 아카이브/서명/업로드가 물리적으로 불가능합니다.

좋은 소식: 암호화 자체는 **실제 구현**입니다 (목(mock) 아님). `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart`에 진짜 Double Ratchet (X25519 + AES-256-GCM + Ed25519 + HKDF-SHA256)이 들어 있고, 게이팅 스크립트 `scripts/crypto-architecture-check.mjs`와 `scripts/policy-check.mjs`는 모두 통과(exit 0)합니다. 따라서 아래 5개 버킷 중 **버킷 1(code-today)** 작업으로 제출 직전 상태까지 끌어올린 뒤, 외부 감사·계정·Mac 작업이 병렬로 진행되어야 합니다.

---

## (1) 오늘 코드로 끝낼 수 있는 것 (owner = code-today)

이 환경(Linux, Mac/계정 불필요)에서 즉시 처리 가능. App Store 거절 위험을 제거하고 제출 메타데이터를 정리합니다.

- [ ] **Cydia jailbreak-probe 제거 (App Store 거절 위험)** — `apps/mobile/ios/Runner/Info.plist`의 `LSApplicationQueriesSchemes` 배열(29~32행, `cydia` 항목)을 삭제. Apple은 jailbreak 스킴 탐지를 흔히 거절하며 이 앱에서 기능적 용도가 없음. (참고: `README.md:129`는 이미 "removed cydia probe"라고 주장하지만 실제 plist에는 남아 있어 README와 불일치 — 코드 수정으로 정합성 회복.)

- [ ] **수출 규정 준수 키 추가: `ITSAppUsesNonExemptEncryption` = YES (true)** — `apps/mobile/ios/Runner/Info.plist`에 `<key>ITSAppUsesNonExemptEncryption</key><true/>` 추가. Veil은 자체 E2E 암호(Double Ratchet)를 탑재하므로 OS-only/auth-only/HTTPS-only 면제에 해당하지 않음 → 값은 **YES**가 truthful (false 금지). 이 키가 있으면 매 업로드마다 뜨는 수출 규정 질문지가 억제됨. (면제 주장은 self-classification report와 App Store Connect 답변으로 별도 처리.)

- [ ] **`ITSEncryptionExportComplianceCode` / CCATS / ERN 추가하지 말 것** — `docs/launch/app-store-listing.md` (149~153행)가 CCATS/ERN 코드를 추가하라고 잘못 안내함. Veil은 표준·공개 알고리즘(X25519, AES-256-GCM, Ed25519, HKDF-SHA256, `docs/crypto-envelope-spec.md`)만 사용 → 15 CFR 740.17(b)(1) mass-market 자가분류로 **CCATS 불필요**. 해당 plist 라인과 CCATS/ERN 안내를 listing 문서에서 **삭제**.

- [ ] **`docs/launch-runbook.md` 수출 규정 단계 수정** — 53행 "Tick 'Standard encryption algorithms (exempt)'"는 오해 소지. Veil 암호는 non-exempt이되 표준 알고리즘으로 mass-market 자가분류 면제에 해당. 단계를 재작성: `ITSAppUsesNonExemptEncryption=YES` → 질문지 Yes → qualifies for exemption → standard-algorithms/mass-market self-classification → CCATS 없음 → BIS+NSA 연례 self-classification report 제출 → 프랑스(ANSSI) 선언(FR 배포 시). 알고리즘 목록(X25519, AES-GCM, Ed25519)은 정확하므로 유지.

- [ ] **`docs/launch/app-store-listing.md` 수출 규정 섹션 전면 교정** — 144~153행 블록과 체크리스트 164행("Export compliance CCATS/ERN filed") 교체. 교정 내용: `ITSAppUsesNonExemptEncryption = YES`; `ITSEncryptionExportComplianceCode` 없음; ASC 답변 = Yes/qualifies/standard-algorithm self-classification; 연례 BIS(crypt@bis.doc.gov)+NSA(enc@nsa.gov) self-classification report(ECCN 5D992.c); 프랑스/ANSSI 선언(FR 배포 시). 164행을 "Annual BIS self-classification report filed + French/ANSSI declaration filed (if FR distribution)"로 변경.

- [ ] **EN 서브타이틀 30자 초과 위반 수정** — `store/appstore/metadata-en.txt` 5행 "End-to-end encrypted privacy messenger" = 38자, Apple 30자 한도 초과. ≤30자로 재작성 (예: "Encrypted privacy messenger" = 27자, 또는 "E2E encrypted private chat" = 26자). (KO 서브타이틀 17자는 OK.)

- [ ] **App Review Notes(데모 계정·심사 노트) 초안 작성** — `store/appstore/`에 누락. Veil은 계정/전화번호/복구가 없어 심사자가 "로그인"할 수 없음. 무계정 모델, 첫 실행 시 신원 생성 방법, 1:1/그룹 메시징 테스트법(시뮬레이터 2대), 데모 자격증명 불필요임을 설명하는 Review Notes 작성. (ASC "App Review Information" 노트 필드에 입력.)

- [ ] **카테고리 추천 명시** — `store/appstore/` 패키지에 카테고리 미선언. 추천: Primary = Social Networking, Secondary = Utilities(또는 Productivity). 사양 deliverable로 초안 작성(최종 선택은 ASC에서 사람이).

- [ ] **CFBundleURLName 불일치 정렬(선택, cosmetic)** — `apps/mobile/ios/Runner/Info.plist` 39행 `CFBundleURLName`이 `app.veil.messenger`로 실제 bundle id `io.veil.mobile`와 불일치. 기능 영향 없으나 정렬 권장.

- [ ] **handoff 번들의 production-blockers-report.json 재생성 결함 수정** — `scripts/audit-handoff-bundle.mjs`가 `artifacts/production-blockers-report.json`을 복사하지만 `beta:external:bundle` 체인이 `beta:production:blockers`를 호출하지 않아 stale/누락. root `package.json`의 `beta:external:bundle` 체인에 `pnpm beta:production:blockers`를 추가하거나 번들 스크립트 내에서 copy 전에 호출.

- [ ] **mock-vs-real 암호 모순 제거** — `scripts/external-review-manifest.mjs`의 `explicitCaveats`가 "Mock crypto remains active." 등을 하드코딩하고 `docs/external-security-review-request-template.md`도 "crypto layer is still mock-backed"라고 함. 그러나 packet/master-checklist/threat-model/RFP/OTF는 실제 LibCryptoAdapter 통합을 명시. caveat을 "Production crypto adapter integrated but not yet externally audited"로 수정하고 superseded된 request-template를 폐기/교정 (`docs/audit-rfp-email-en.md`가 대체).

- [ ] **(빌드 검증 — open egress CI 한정) Prisma client 생성 후 API 체인 실행** — `pnpm db:generate`(= `pnpm -C apps/api prisma:generate`)를 API 명령 **최초** 단계로 실행. 없으면 build/lint/unit/e2e 전부 TS2339로 실패. 이후 `pnpm build` → `pnpm lint` → `pnpm -C apps/api test` → `pnpm -C apps/api test:e2e`. (이 sandbox는 Prisma 엔진 CDN egress 차단으로 실패하지만, egress 열린 CI 러너에서는 통과.)

- [ ] **(검증) 정적 게이트는 지금 통과 확인** — `pnpm format:check`, `pnpm policy:check`(`scripts/policy-check.mjs`), `pnpm architecture:check`(`scripts/crypto-architecture-check.mjs`), `pnpm -C apps/web-demo test`(47/47) 모두 현재 통과.

---

## (2) Mac + Xcode 필요 (owner = mac-only)

macOS + Xcode 없이는 불가능. 계정/팀이 먼저 마련된 뒤 수행.

- [ ] **첫 빌드: `flutter pub get` + `pod install` + 아카이브** — `Generated.xcconfig` 부재, Podfile/Pods 미설치 상태. macOS에서 최초 빌드 부트스트랩 필요.

- [ ] **배포 서명 설정(인증서 + 프로비저닝 프로파일)** — Runner 타겟에 Automatic signing 활성화(또는 Distribution 인증서 + App Store 프로비저닝 프로파일 임포트) 후 `flutter build ipa` / Xcode Archive.

- [ ] **서명된 `.ipa` 생성 및 TestFlight/App Store Connect 업로드** — iOS CI 레인 부재(`.github/workflows/ci.yml`만 존재), Fastfile 없음. Mac에서 수동 또는 Mac 러너에서 수행.

- [ ] **`ExportOptions.plist` 작성** — 비대화형 `xcodebuild -exportArchive` 또는 CI용. `teamID`, `method=app-store-connect`, 서명 스타일 지정 필요(Team ID는 계정 단계 산출물). 보통 첫 export 시 Mac에서 생성.

- [ ] **필수 디바이스 사이즈 스크린샷 캡처** — `store/appstore/`에 이미지 자산 전무. 6.9" iPhone 스크린샷(6.5" 세트도 허용/자동 스케일) 필요. 앱이 universal(iPad)이면 13" iPad 스크린샷도 필요. 시뮬레이터/디바이스에서 캡처 후 ASC 업로드. (iPad 지원 여부 먼저 확정.)

- [ ] **(선택) App preview 영상** — 필수 아님. 원하면 Apple 사양대로 녹화/인코딩(Mac 툴링) 후 업로드.

- [ ] **(coverage) Flutter unit/widget 테스트 + integration_test** — `apps/mobile/test`(27개 suite, 암호/세션/래칫 커버리지) 및 `apps/mobile/integration_test/auth_smoke_test.dart`. 단위/위젯은 headless로 Flutter 툴체인만 있으면 되지만 integration_test는 실제 디바이스/에뮬레이터 필요. 이 Linux sandbox에 Flutter 미설치. CI에서 `subosito/flutter-action`으로 프로비저닝 필요.

---

## (3) Apple 계정 / 자격증명 필요 (owner = human-account)

계정 보유자만 수행 가능. 코드/Linux로 생성 불가.

- [ ] **Apple Developer Program 등록 + Team ID 확보** — 유료 멤버십($99/yr). `project.pbxproj`에 `DEVELOPMENT_TEAM` 설정, `CODE_SIGN_IDENTITY` 플레이스홀더 "iPhone Developer" 교체의 전제. (`apps/mobile/ios/Runner.xcodeproj/project.pbxproj:339,459,516`.)

- [ ] **Bundle id `io.veil.mobile`를 Developer 포털에 등록** — 현재 코드에는 설정됨(`project.pbxproj:375`), 포털 등록은 계정 작업.

- [ ] **App Store Connect 앱 레코드 생성 + 메타데이터** — 이름, 카테고리, 개인정보처리방침 URL, App Privacy(영양표) 답변, 스크린샷, 설명 입력. 포털 작업.

- [ ] **수출 규정 질문지 답변(ASC UI)** — ① 암호 사용? → YES. ② Category 5 Part 2 면제 해당? → Yes. ③ standard(published) 알고리즘 mass-market 자가분류 옵션 선택(HTTPS/OS-only 아님, 독자 알고리즘 아님). ④ 연례 self-classification report 제출 여부에 정직히 답변. 계정 보유자 액션.

- [ ] **연령 등급 질문지 완료** — Apple 2026 연령 질문지를 ASC에서 작성. 무계정·무유해 콘텐츠이나 메시징 통한 비제한 UGC로 17+/18+로 상향될 수 있음(에이전트가 답변 초안 가능, 제출은 계정 측).

- [ ] **콘텐츠 권리 선언** — ASC "Content Rights" 질문. Veil 예상 답변: "No, third-party content 없음"(암호화 메시지는 first-party UGC). 체크박스는 계정 측.

- [ ] **푸시 App ID capability + APNs 키 활성화(푸시 사용 시)** — `.entitlements`와 pbxproj 참조는 code-today지만, App ID capability 활성화와 APNs 키 발급은 포털 작업. **단, 프라이빗 베타에서는 푸시 비활성(`.env.prod.example:46-47`, `VEIL_PUSH_PROVIDER=none`)이라 런치 블로커 아님.**

- [ ] **외부 감사 정리 후 프로덕션 게이트 전환** — critical findings 패치·재테스트 후 remediation tracker에 closure 기록하고 `VEIL_AUDITED_CRYPTO_ATTESTED=true`로 프로덕션 부팅 해제. 최종 go/no-go 결정.

- [ ] **(handoff) 아웃바운드 템플릿의 `[TODO]` 채우기** — `docs/audit-rfp-email-en.md`([first-name], [Your name], 연락처, 핀 SHA/태그), `docs/otf-application-template.md`(라이선스, 유지보수자 bio/PGP, diversity plan, SHA). 개인/계정 정보.

- [ ] **(handoff) RFP 이메일 발송 / OTF 신청 / NDA / 펌 선정 / 계약** — `docs/external-audit-firm-shortlist.md` 실행 계획대로: OTF 신청(opentech.fund, $0 경로) + Cure53(mario@cure53.de) 병렬 RFP, 무응답 시 NCC/Atredis. 이메일 발송·NDA·계약은 운영자 액션.

---

## (4) 외부 감사 필요 (owner = external)

조직 차원의 ship gate. 제3자만 수행 가능.

- [ ] **외부 암호 감사 수행 (조직 ship gate)** — `.env.prod.example:39-42`가 `VEIL_AUDITED_CRYPTO_ATTESTED=false`를 외부 감사 통과 전까지 유지하도록 명시. `apps/api/src/common/config/app-config.service.ts:129-140`(`assertProductionReady`)이 false인 동안 프로덕션 API 부팅 거부. `README.md:47-48`에 product non-negotiable로 등재. Double Ratchet 구현 자체는 실제(`lib_crypto_adapter.dart`)이나 제3자 암호학자 서명이 필요. handoff 번들(`pnpm audit:handoff`)과 RFP 템플릿은 준비됨. **에이전트가 끝낼 수 없음.**

- [ ] **감사 펌이 리뷰 수행 후 findings JSON 반환** — 핀된 SHA에서 클론, 우선순위 코드 경로 리뷰, HTML/PDF 리포트 + `artifacts/external-review-findings-template.json` 형식(id, severity, location, description, reproduction, recommendation, status) findings 반환. 통상 4~6주(최대 8주) + 워크스루 + ~2주 비동기 follow-up. 펌 측 작업.

- [ ] **(검증 인프라) BIS 연례 self-classification report 제출** — 15 CFR 740.17(b)(1)/742.15(b)에 따라 mass-market 소프트웨어는 BIS(crypt@bis.doc.gov) + NSA(enc@nsa.gov)에 연례 self-classification report(ECCN 5D992.c) 제출. 최초 수출 시점/매년 2/1까지. 법무/수출 컴플라이언스 소유자와 조율. Apple 질문지가 확인을 요구하는 그 리포트.

- [ ] **프랑스(ANSSI) 암호 import 선언(프랑스 배포 시)** — Veil이 자체 암호를 구현하므로 EU/프랑스 배포 시 ANSSI 암호 선언 필요(처리 ~1개월). ASC 프롬프트 시 업로드. 프랑스를 geo-restrict하면 불필요. 법무/계정 액션.

- [ ] **(coverage, 인프라) Flutter 암호 suite를 CI 기본 레인에 + 모바일 auth 플로우 검증** — 가장 보안 민감한 코드(Double Ratchet, forward secrecy, prekey 서명, safety numbers, secure storage, backup envelope)가 Flutter에만 있고 별도 CI 잡(subosito/flutter-action)에만 커버됨. integration_test는 boot-only scaffold라 register→challenge→verify·session-restore·secure-wipe 경로가 자동 검증 없음. CI에 Flutter 프로비저닝 + 디바이스/에뮬레이터(또는 headless harness) 필요.

---

## (5) 이미 완료됨 (owner = done)

검증 완료. 추가 작업 불필요.

- [x] **암호 어댑터 seam + mock 제거 게이트** — `scripts/crypto-architecture-check.mjs` exit 0. `apps/mobile/lib/src/app/app_state.dart`가 `crypto_adapter_registry.dart`를 통해 실제 `LibCryptoAdapter` 와이어링(`crypto_adapter_registry.dart:4-6`), 메시징 컨트롤러/캐시가 mock 내부 미참조. 경계 인터페이스(DeviceIdentityProvider, CryptoEnvelopeCodec, ConversationSessionBootstrapper 등)가 `crypto_engine.dart`에 존재.

- [x] **Product non-negotiables** — `scripts/policy-check.mjs` exit 0. 푸시 payload에 plaintext/envelope 필드 없음, `auth.controller.ts`에 password-reset/recovery 없음, admin message viewer 없음, helmet + ApiExceptionFilter + 로그 redaction, device-transfer 소유증명, mobile에 print/debugPrint·crashlytics·sentry_flutter 없음. `README.md:42-48` 항목 전부 통과.

- [x] **실제 Double Ratchet 구현** — `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart`에 `cryptography` Dart 패키지 기반 전체 Double Ratchet(X25519 + AES-256-GCM + Ed25519 + HKDF-SHA256) 구현. mock 아님.

- [x] **Bundle identifier** — `PRODUCT_BUNDLE_IDENTIFIER = io.veil.mobile` (Debug/Release/Profile, `project.pbxproj:375,554,576`). Info.plist `CFBundleIdentifier`가 `$(PRODUCT_BUNDLE_IDENTIFIER)` 참조.

- [x] **버전/빌드 번호** — pubspec `0.1.0+1` → `CFBundleShortVersionString=$(FLUTTER_BUILD_NAME)=0.1.0`, `CFBundleVersion=$(FLUTTER_BUILD_NUMBER)=1`. (재업로드 시 pubspec의 build 번호 +1 필요 — 반복 시 code-today.)

- [x] **배포 타겟** — `IPHONEOS_DEPLOYMENT_TARGET = 14.0` 전 config 일관(Debug 479, Release 530, Profile 353). `TARGETED_DEVICE_FAMILY='1,2'`(iPhone+iPad).

- [x] **Privacy manifest + usage-description 문자열** — `apps/mobile/ios/Runner/PrivacyInfo.xcprivacy` 존재. Info.plist에 NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSPhotoLibraryAddUsageDescription, NSFaceIDUsageDescription 모두 존재. 누락 없음.

- [x] **App 아이콘** — `Assets.xcassets/AppIcon.appiconset`에 1024x1024 마케팅 아이콘 포함 21개 PNG. `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`. `flutter_launcher_icons`에 `remove_alpha_ios:true`(알파 제거, Apple 요구).

- [x] **앱 이름(EN+KO)** — `store/appstore/metadata-en.txt` "VEIL Messenger"(14자), `metadata-ko.txt` "VEIL 메신저"(8자). 30자 한도 내.

- [x] **서브타이틀(KO)** — "종단간 암호화 프라이버시 메신저" 17자, 한도 내. (EN은 버킷 1에서 수정 필요.)

- [x] **설명/키워드/URL** — 설명(EN+KO) 4000자 내, promo text 170자 내; 키워드 EN 69자/KO 36자(100자 한도 내); Support URL `https://veil.app/support`, Marketing URL `https://veil.app`, Privacy Policy URL `https://veil.app/privacy` 모두 양 언어 존재. (URL이 실제 라이브인지 사람이 확인.)

- [x] **App Privacy 질문지 답변 초안** — `store/appstore/app-privacy-answers.md`에 data collection, 식별자(User ID, Device ID), user content(ciphertext), crash diagnostics, tracking=No, data-not-collected 목록 포함. (ASC UI 전사는 사람이.)

- [x] **handoff 머신러리** — `pnpm audit:handoff`(`scripts/audit-handoff-bundle.mjs`)가 dirty tree 거부, SHA/branch 핀, `pnpm beta:external:bundle` 실행, 15개 문서 + 4개 JSON 아티팩트 + 생성 README를 스테이징하고 tar로 패키징. 펌 shortlist(`docs/external-audit-firm-shortlist.md`), RFP 이메일, OTF 신청서, intake/remediation tracker 모두 작성됨.

- [x] **정적 품질 게이트 + web-demo 테스트** — 현재 sandbox에서 통과 확인: `pnpm format:check`, `pnpm policy:check`, `pnpm architecture:check`, `pnpm -C apps/web-demo test`(47/47).

---

## 권장 실행 순서

1. **지금(병렬 시작):** 버킷 1 코드 수정 전부 처리 (cydia 제거, `ITSAppUsesNonExemptEncryption=YES`, CCATS 안내 삭제, runbook/listing 교정, EN 서브타이틀 단축, Review Notes/카테고리 초안, handoff 모순·재생성 결함 수정).
2. **동시에:** 외부 감사 착수 — OTF 신청 + Cure53 RFP (버킷 3/4). 가장 긴 리드타임이므로 **즉시** 시작.
3. **동시에:** Apple Developer Program 등록 + Team ID 확보 (버킷 3).
4. **계정 확보 후:** Mac+Xcode에서 첫 빌드·서명·스크린샷·`.ipa` 업로드 (버킷 2).
5. **감사 통과 후:** remediation 기록 + `VEIL_AUDITED_CRYPTO_ATTESTED=true` 전환, BIS/ANSSI 파일링, ASC 제출 (버킷 3/4).

> Critical path는 외부 암호 감사(4~8주)입니다. 다른 모든 작업은 그 안에 끝낼 수 있으므로, 감사 착수를 늦추지 마십시오.
