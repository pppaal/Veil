# Data subject request runbook (PIPA · GDPR)

이 문서는 베타 운영자가 사용자로부터 **개인정보 열람·정정·삭제·처리정지**
요청을 받았을 때 따라야 하는 절차입니다. 한국 PIPA §35–§37, GDPR
Art. 15–18 모두 동일한 골격을 사용합니다.

법적 SLA:
- PIPA: **10일 이내** 응답 (필요 시 1회 10일 연장 가능, 사유 통지 의무)
- GDPR: **1개월 이내** (복잡 시 추가 2개월 연장 가능)

VEIL 사내 SLA: **영업일 3일 이내** 1차 응답.

---

## 0. 채널

요청 수신 채널은 단일화합니다.

- 메일: `privacy@veil.app`
- 모든 요청을 운영자 PC 의 `~/veil-ops/dsr-log/<YYYY>-<MM>/<request-id>.md` 에
  타임스탬프와 함께 보존 (3년 보존, 그 후 파기)

---

## 1. 신원 확인 — challenge/verify

문제: 누가 "이 핸들 지워주세요" 라고 메일 보내면 그게 진짜 그 사람인지
어떻게 알지? — VEIL 은 핸들이 디바이스의 Ed25519 키와 묶여 있으므로,
사용자가 그 디바이스에서 challenge/verify 라운드를 통과해야 본인입니다.

운영자가 보내는 응답 메일 템플릿:

```
안녕하세요. 요청을 받았습니다.

본인 확인을 위해 다음 절차를 따라주세요:

1. 베타 클라이언트에서 사용 중이신 핸들로 로그인 상태를 유지합니다.
2. 응답 메일에 사용 중인 핸들을 그대로 적어주세요. 예: @alice123
3. 보낸 메일의 X-Veil-Challenge 헤더에 적힌 nonce 를 다음 명령으로 서명해
   다시 회신해 주세요:
   (서명 절차는 별도 안내 또는 본인이 보유한 디바이스에서 직접
   "challenge/verify" 흐름을 거치는 방법으로 대체)

영업일 3일 이내 1차 회신 약속드립니다.
```

운영자가 보낸 메일에 X-Veil-Challenge 헤더에 적은 nonce 를 서버 로그에서
challenge/verify 호출과 매칭해 본인 검증을 마칩니다. 의심스러우면
삭제 대신 처리정지로 전환하고 추가 신원 증빙 요구.

---

## 2. 요청 유형별 처리

### 2-1. 열람 (PIPA §35 / GDPR Art. 15)

VEIL 이 보관하는 한 사용자의 데이터는 다음과 같습니다 (모두 ciphertext 기반):

```sql
-- 운영자 호스트에서:
docker exec veil-postgres-1 psql -U veil -d veil -c "
SELECT
  u.id, u.handle, u.display_name, u.status, u.created_at,
  (SELECT COUNT(*) FROM devices d WHERE d.user_id = u.id) AS device_count,
  (SELECT COUNT(*) FROM conversation_members cm WHERE cm.user_id = u.id) AS conversation_count,
  (SELECT COUNT(*) FROM messages m
     JOIN devices d ON d.id = m.sender_device_id WHERE d.user_id = u.id) AS message_count
FROM users u WHERE u.handle = '<handle>';
"
```

이 결과를 **표 형태로** 회신 메일에 첨부. 메시지 본문(ciphertext) 은
서버에서 복호화 불가하므로 보내지 않으며 그 사실을 명시합니다.

### 2-2. 정정 (PIPA §36 / GDPR Art. 16)

`displayName` / `avatarPath` / `statusMessage` 정도만 정정 대상.
`UPDATE user_profiles SET ...` 직접 적용 후 dsr-log 에 SQL 사본 보존.

핸들 자체는 변경 불가 (디바이스 키와 묶여 있음). 정정 대신 새 핸들로
재가입 + 기존 핸들 삭제로 안내.

### 2-3. 삭제 (PIPA §36 / GDPR Art. 17)

본인 확인 통과 후 다음 명령:

```bash
# 사용자 ID 확인
USER_ID=$(docker exec veil-postgres-1 psql -U veil -d veil -tA -c \
  "SELECT id FROM users WHERE handle = '<handle>';")

# 운영자가 직접 access token 을 만들거나, /v1/account DELETE 를
# 사용자에게 발급한 토큰으로 호출하도록 유도. 가장 안전한 길은
# 사용자에게 자기 디바이스에서 deleteAccount 를 실행하도록 안내하는 것.

# 직접 처리해야 하는 경우 (사용자가 디바이스를 잃었음, 강제 삭제 등):
docker exec veil-postgres-1 psql -U veil -d veil -c "
  -- AccountService.deleteAccount 와 동일한 3-phase 동작을 수동으로 재현.
  -- Phase 1
  UPDATE users SET status='revoked', active_device_id=NULL WHERE id='$USER_ID';
  UPDATE devices SET is_active=false WHERE user_id='$USER_ID';
"

# 그 후 API 가 동작 중이라면 동일 사용자 토큰으로:
# DELETE /v1/account
# 가 자동으로 Phase 2 + Phase 3 을 실행.
# 토큰이 없는 강제 삭제 시는 별도 admin 스크립트 또는 위 SQL 절차를
# 모방하는 manual cascade 가 필요. (Phase L 의 chunked-delete 코드 참고)
```

삭제 완료 후:
- dsr-log 에 SQL 트랜스크립트 + 시작/완료 타임스탬프 보존
- 사용자에게 "처리 완료" 회신 (실행 시각 포함)
- 30일 후 dsr-log 자체도 파기 (retention 30일)

### 2-4. 처리정지 (PIPA §37 / GDPR Art. 18)

로그인은 막지만 데이터는 보존. `users.status='locked'` 만 set:

```sql
UPDATE users SET status='locked' WHERE handle='<handle>';
```

해제 요청 시 다시 `active`. 처리정지는 본인 확인이 부담스러운 경우의
중간 안전판입니다.

---

## 3. 침해 사고 (PIPA §29, §34)

운영자가 다음 중 하나를 인지한 경우:
- 무단 접근 (DB dump 유출, JWT 키 노출 등)
- 디바이스 분실 + 키 유출 정황
- 정보주체 식별이 가능한 평문이 어떤 경로로든 외부로 유출

72시간 이내 KISA 침해사고 신고 + 영향받은 정보주체에게 통지 의무.
신고 채널: https://www.boho.or.kr/

dsr-log 의 별도 디렉토리 `incidents/<YYYY>-<MM>-<incident-id>/` 에 보존.

---

## 4. 거부할 수 있는 경우

- **다른 사람의 데이터 요청**: 본인 확인 실패 → 거부 + 사유 통지
- **사법 협조 요청 등 법적 의무**: 영장/공문 첨부 필수, 법무 검토 후 처리
- **악의적 반복 요청** (DoS 성격): PIPA §38 ④ 합리적 기간 내 거부 가능

거부 시에도 사유와 이의제기 절차를 함께 통지해야 합니다.

---

## 5. 양식 (이의제기 절차 안내문)

```
회신 결과에 이의가 있으시면 다음 경로로 신청 가능합니다:

- 개인정보분쟁조정위원회: 1833-6972 / https://www.kopico.go.kr
- 개인정보침해신고센터: 118 / https://privacy.kisa.or.kr
- 대검찰청 사이버수사과: 1301 / https://cyberbureau.police.go.kr
```

---

## 6. dsr-log 디렉터리 구조 (운영자 PC)

```
~/veil-ops/dsr-log/
  2026-04/
    req-001-deletion-alice.md      # 요청 본문 + 응답 + SQL 트랜스크립트
    req-002-access-bob.md
  incidents/
    2026-04-jwt-secret-rotation/
      timeline.md
      kisa-report-draft.md
```

각 파일은 마크다운으로 보존. 30일 / 3년 보존 정책 명시.
