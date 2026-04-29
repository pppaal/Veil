# 외부 크립토 감사 후보 명단

VEIL 의 production 게이트 (`VEIL_AUDITED_CRYPTO_ATTESTED`) 를 해제하기
위해 필요한 외부 보안 감사. 운영자가 직접 컨택할 후보 목록.

> ⚠️ 가격은 2026-04 기준 추정치. 정식 견적은 회사마다 NDA 후 산출.
> "범위" 는 우리 입장에서 본 우선순위, 회사가 제안할 범위가 더 넓을 수
> 있음. RFP 보내기 전에 `docs/external-security-review-packet.md` 와
> `docs/forward-secrecy-ratchet-design.md`,
> `docs/envelope-v3-unified-spec.md`,
> `docs/group-sender-keys-design.md`,
> `docs/sealed-sender-design.md` 4종을 미리 첨부할 것.

## Tier 1 — 글로벌 톱

### Trail of Bits
- 사이트: trailofbits.com
- 강점: Signal, Zoom 검토 경험. Rust/C 강함. 자체 정적 분석 도구
  (`Slither`, `Echidna`).
- 추정 비용: $80K-$200K (4-8주)
- 컨택: services@trailofbits.com 또는 RFP submission form
- 우리 입장: 베타 단계 단일 dev 라 톱티어가 받을지 불확실. 먼저 작은
  scoped engagement (envelope v3 spec 만, ratchet impl 만) 가능 여부
  타진.

### NCC Group
- 사이트: nccgroup.com
- 강점: WhatsApp 멀티-디바이스, Threema 검토. 영국+미국+호주 글로벌
  팀. 비교적 베타 단계 친화적.
- 추정 비용: $60K-$150K (3-6주)
- 컨택: contact@nccgroup.com
- 우리 입장: WhatsApp/Threema 경험이 우리한테 가장 직접적.

### Cure53
- 사이트: cure53.de
- 강점: Mullvad, Mastodon, Nextcloud 검토. 베를린 기반. 베타급 OSS
  프로젝트 다수 검토 (Open Tech Fund 펀딩 통한 무료 검토 사례 있음).
- 추정 비용: €40K-€90K (2-4주) — 공개 검토 사례 펀딩 가능
- 컨락: mario@cure53.de 또는 contact@cure53.de
- 우리 입장: **1순위 추천**. 비용 대비 톱티어, OSS-friendly, 한국어
  메신저에 영어 검토 결과를 한국어로 다시 풀이할 필요는 있음.

## Tier 2 — 적합한 작은 회사들

### Atredis Partners
- 사이트: atredis.com
- 강점: 모바일 앱 + 백엔드 풀스택 검토. 펜테스트 + 크립토 합쳐서.
- 추정 비용: $40K-$80K (2-4주)
- 컨택: hello@atredis.com

### Kudelski Security (구 Nagra)
- 사이트: kudelskisecurity.com
- 강점: 스위스 기반, 크립토 라이브러리 검토 전문. 가격 비싸지만
  ZK/PQ 마이그레이션까지 포함 가능.
- 추정 비용: $100K-$250K
- 컨택: corporate-security-info@kudelskisecurity.com

### Atomicorp / Quarkslab
- 강점: 프랑스 기반, 모바일 + 임베디드 강함
- 추정 비용: €50K-€120K
- 컨택: contact@quarkslab.com

## Tier 3 — 한국 / 동아시아

### KISA (Korea Internet & Security Agency) 인증
- 한국 정부 산하. SaaS 한국어 메신저면 통신비밀보호법 / 정보통신망법
  관련 인증 필요. 크립토 자체 검토는 약하지만 한국 출시면 사실상 필수.
- 비용: 인증료 + 컨설팅 합쳐 ₩20M-₩60M
- 컨택: kisa.or.kr 인증제도 안내

### NSHC / SK shieldus
- 한국 펜테스트 회사. 백엔드 + 모바일 풀스택, 한국어 보고서.
- 추정 비용: ₩50M-₩150M (4-8주)
- 컨택: 회사 웹사이트 RFP 폼

### Cellcom (이스라엘) — 크립토 라이브러리 한정
- WhatsApp 등 검토 이력. 우리는 메신저라 적합.
- 비용: $40K-$100K

## Tier 4 — 학계 / OSS 펀딩

### Open Technology Fund (OTF)
- 사이트: opentech.fund
- 강점: 인권/프라이버시 OSS 프로젝트에 무료 또는 저비용 보안 검토.
  Cure53/Trail of Bits 가 실제 작업 수행. **신청서 → 6-8주 검토 →
  통과 시 회사 매칭**.
- 비용: $0 (펀딩 받으면)
- 컨택: opentech.fund/funds (Internet Freedom Fund / Surveillance
  Self-Defense Fund 둘 다 후보)
- 우리 입장: VEIL 의 "no recovery, no plaintext, device-bound" 포지션
  은 OTF 미션과 정렬됨. **신청 강력 추천**. 무료 또는 보조금.

### Mozilla Open Source Support (MOSS) / SOS Awards
- 사이트: mozilla.org/moss
- 강점: 베타급 OSS 보안 검토에 $5K-$50K 보조금
- 컨택: 사이트 application 폼

### EFF (Electronic Frontier Foundation) 레퍼럴
- 직접 검토는 안 하지만 검토 회사 추천 가능. 우리 메시지가 EFF
  ideology 와 정렬되면 도움.
- 컨택: info@eff.org (시간 걸림, 우선순위 낮음)

## 추천 진행 순서

1. **OTF 신청서 작성 + 제출** (0주차) — 통과해서 무료 검토 매칭되면
   비용 0으로 톱티어 (Cure53/Trail of Bits) 받음. 신청서 작성에
   1-2일.
2. **OTF 결과 대기 중 (6-8주)** Cure53 직접 견적 요청 병행 — OTF
   거절되면 Cure53 직접 진행.
3. **Tier 2 백업** Cure53 가 4-6주 못 잡으면 Atredis 또는 NCC Group.
4. **Tier 3 (한국)** 한국 출시 결정 시 별도 트랙. KISA 인증은
   기술적 검토와 다른 트랙 — 컴플라이언스만.

## RFP 핵심 항목

- 우리 한 줄: "Private-beta E2E 메신저, X25519+AES-256-GCM, 모바일 더블
  래칫 구현 완료, 웹 데모는 단순 envelope (v3 통합 작업 예정), 외부
  감사 후 production 게이트 해제"
- 검토 범위 우선순위:
  1. `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart` (실 구현)
  2. `docs/forward-secrecy-ratchet-design.md` (현 ratchet 스펙)
  3. `docs/envelope-v3-unified-spec.md` (다음 wire format)
  4. `docs/group-sender-keys-design.md` (그룹 미구현, 설계만)
  5. `docs/sealed-sender-design.md` (메타데이터 감축, 미구현)
  6. `apps/api/src/modules/auth` (challenge/verify)
  7. `apps/api/src/modules/device-transfer` (transfer + atomic revoke)
  8. `apps/api/src/modules/messages` (envelope routing)
- 일정 희망: 4-6주 wall clock
- 산출물: HTML/PDF 보고서 + 발견사항 JSON (우리
  `external-review-findings-template.json` 와 호환), 30분 프리젠테이션
- NDA: 필요. 양측 표준 NDA 양식 검토 후 서명.

## 컨택 우선순위 (운영자 To-Do)

- [ ] 1주차: OTF 신청서 제출 (`docs/otf-application-template.md` 참조)
- [ ] 1주차: Cure53 RFP 메일 송부 (`docs/audit-rfp-email-en.md` 참조)
- [ ] 2주차: 응답 없으면 NCC Group + Atredis 병행 송부
- [ ] 4주차: 응답 받은 회사들과 NDA 검토 + 견적 비교
- [ ] 6주차: 한 회사 선정 + 계약 + 킥오프 미팅
- [ ] 10-14주차: 검토 진행
- [ ] 14-16주차: 보고서 수령 + 발견사항 patch + retest
- [ ] 16-18주차: 최종 sign-off + `VEIL_AUDITED_CRYPTO_ATTESTED=true`
