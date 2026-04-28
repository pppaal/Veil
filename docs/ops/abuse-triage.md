# Abuse triage runbook (private beta)

VEIL 은 종단간 암호화 메신저라 운영자는 메시지 내용을 볼 수 없습니다.
그 전제 위에서, 신고가 들어왔을 때 어디까지 할 수 있고 어디부터는 못
하는지를 정리한 문서입니다.

## 1. 운영자가 볼 수 있는 것 / 볼 수 없는 것

볼 수 있음 (메타데이터):
- 핸들, displayName, 가입 시각
- 디바이스 등록 시각, last seen
- 누가 누구한테 언제 메시지를 보냈는지 (envelope 헤더)
- 메시지 길이, 첨부 여부, 첨부 크기

볼 수 없음:
- 메시지 본문 (ciphertext)
- 첨부 내용 (S3 객체도 client-side 암호화)
- 통화 내용 (P2P SRTP)

## 2. 신고 접수 채널

베타 단계에선 단일 이메일/Signal: `abuse@veil.example` (또는 운영자 핸들).
폼은 안 만듭니다 — 자동화 스팸 줄이려고.

신고에 포함되도록 안내:
- 신고자 핸들
- 가해자 핸들
- 사건 일시 (대략)
- 패턴 (스팸/도용/위협 중 하나)

> ⚠️ "내용을 보냈다" 식의 본문 인용은 운영자가 검증할 수 없습니다.
> 신고 처리에 본문 검증은 없으며, 메타데이터+신고자 진술만으로 판단합니다.

## 3. 처리 단계

### 3.1 신고 접수 (15분 이내)

1. 신고자에게 수신 확인 회신.
2. `docs/ops/abuse-log.csv` (수동 운영) 에 한 줄 추가:
   `timestamp, reporter, target, pattern, status=triage`

### 3.2 트리아지 (24시간 이내)

운영자는 다음 SQL 만 사용. 메시지 본문 컬럼 (`ciphertext`) 은 절대 조회
금지 — 어차피 ciphertext 라 의미 없음 + 정책 위반.

```sql
-- 가해자 핸들로 가입 시각, 마지막 활동, 디바이스 수 확인
SELECT u.handle, u.created_at, u.status,
       (SELECT MAX(d.last_seen_at) FROM devices d WHERE d.user_id=u.id) AS last_seen,
       (SELECT COUNT(*) FROM devices d WHERE d.user_id=u.id) AS device_count
FROM users u
WHERE u.handle = $1;

-- 동일 IP 다중 가입 의심 (registration 후 15분간 IP 로깅 시점만)
SELECT handle, created_at FROM users
WHERE created_at > now() - interval '7 days'
ORDER BY created_at DESC LIMIT 50;

-- 신고된 사용자가 보낸 메시지 패턴 (수신자 분포 + 빈도, 본문 X)
SELECT m.conversation_id,
       count(*) AS msg_count,
       min(m.server_received_at) AS first_msg,
       max(m.server_received_at) AS last_msg
FROM messages m
JOIN devices d ON d.id = m.sender_device_id
JOIN users u ON u.id = d.user_id
WHERE u.handle = $1
  AND m.server_received_at > now() - interval '7 days'
GROUP BY m.conversation_id
ORDER BY msg_count DESC LIMIT 20;
```

판정:
- **명백 스팸** (10명 이상에게 1시간 안에 메시지) → 3.3
- **수신자가 차단했는데 우회 가입 정황** (디바이스 여러 개) → 3.3
- **신고자 진술만 있고 메타데이터로 검증 불가** → 신고자에게 차단/뮤트
  안내, 운영자는 사건 종결 (`status=insufficient_evidence`)

### 3.3 조치

```sql
-- 사용자 정지 (status='suspended'). JwtAuthGuard 가 토큰 무효화.
UPDATE users SET status='suspended' WHERE handle = $1;
```

이후 24시간:
- 새 메시지 못 보냄 (게이트가 401 반환)
- 받기는 가능 (신고자 입장에서 인지 가능)
- 토큰 만료 시 재로그인 시도하면 거부

복원 가능 (false positive 시): `UPDATE users SET status='active' WHERE handle=$1;`

영구 처분 (재범 또는 위협): `DELETE` 는 안 됨 (외래키 cascade 위험).
`status='terminated'` 로 두고 핸들 재가입 차단은 가입 정책에서
처리 (이미 `handle_taken` 이 영구 보존).

### 3.4 신고자 회신 (48시간 이내)

조치 결과 1줄:
- 정지: "해당 계정은 정지 처리되었습니다."
- 증거 부족: "메타데이터로는 위반을 확인할 수 없어 종결합니다.
  앱 내 차단/신고 기능을 사용해주세요."

## 4. 절대 안 되는 일

- ❌ 메시지 ciphertext 복호화 시도 (서버에 키 없음, 시도 자체가 공격)
- ❌ 운영자 권한 사용자 추가 (코드 베이스에 admin 없음, 도입 금지)
- ❌ 신고자 핸들을 가해자에게 노출
- ❌ 사용자 ID/디바이스 ID 외부 공유 (신고자 포함)
- ❌ 백업 데이터에서 메시지 본문 복구 (ciphertext 라도 정책 위반)

## 5. 통계

매주 일요일 23:00 운영자 노트:
- 신고 접수 건수
- 정지 처분 건수
- 평균 응답 시간 (접수 → 회신)
- 신규 가입 / 정지 비율 (스팸 봇 추세 감시)

베타 종료 시 누적 통계는 launch-runbook 의 "공개 신뢰 보고서" 섹션에 요약.
