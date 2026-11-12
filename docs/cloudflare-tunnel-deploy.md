# VEIL · Cloudflare Tunnel 비공개 베타 가이드

본인 PC 에서 띄워둔 데모를 HTTPS URL 로 노출해, **직접 초대한 소수
테스터**가 어디서든 접속하게 하는 가장 빠른 길입니다. 공개 베타가
아닙니다: 외부 크립토 감사 전에는 초대한 테스터 밖으로 URL 을 퍼뜨리지
마세요.

- 비용: **0 원** (Cloudflare Tunnel 무료, `*.trycloudflare.com` 또는
  본인 도메인 가능)
- 외부 의존: Cloudflare 계정 (무료), 선택적으로 본인 도메인
- 결과: `https://veil-beta.example.com/demo/` 같은 공개 URL → 폰·노트북
  어디서든 같은 데모 사용 가능

> ⚠️ **PRIVATE BETA**. 외부 크립토 감사 전이라 `VEIL_ENV=production` 부팅이
> 의도적으로 막혀 있습니다. 이 가이드의 스택은 `VEIL_ENV=development` 로
> 돌고, 그 모드는 production 게이트가 지키는 것(CSP·HSTS, 개발용 envelope
> 거부, CORS·Swagger·시크릿 검사)을 끕니다. 그래서 초대한 테스터에게
> 사실을 알리고 그들에게만 씁니다. 공개 대상 운영은 감사 후
> [`vps-deploy-runbook.md`](vps-deploy-runbook.md) 로.

---

## 1. 사전 준비

| 필요한 것 | 어디서 | 비용 |
| --- | --- | --- |
| Cloudflare 계정 | https://dash.cloudflare.com/sign-up | 무료 |
| 본인 도메인 (선택) | 가비아 / Namecheap / Cloudflare Registrar | 연 1.5만 원 ~ |
| Docker + pnpm | (이미 데모 띄우고 있다면 OK) | — |

> 도메인이 없어도 `*.trycloudflare.com` 무료 임시 URL 로 30일까지 시험 가능합니다.
> "이번 주 친구 10명만 베타" 면 그걸로 충분.

---

## 2. Cloudflare Tunnel 만들기

1. https://one.dash.cloudflare.com/ 접속 → 좌측 메뉴 **Networks → Tunnels**.
2. **`Create a tunnel`** → **`Cloudflared`** 선택.
3. 터널 이름 자유롭게 (예: `veil-beta`). 저장.
4. 다음 화면에서 **Token** 을 복사해두기. `eyJh...` 로 시작하는 긴 문자열.
5. **Public Hostnames** 탭에서 라우팅 추가:
   - **Subdomain**: `veil-beta` (혹은 원하는 이름)
   - **Domain**: 본인 도메인 (Cloudflare 에 등록된 것 선택)
   - **Service**: `http://api:3000`  ← 매우 중요. docker 네트워크 내부 호스트
6. **Save**.

> 도메인이 없다면 **Quick Tunnel** 옵션. 3단계의 두 export
> (`VEIL_CLIENT_IP_SOURCE`, `VEIL_API_BIND_ADDRESS`) 로 스택을 띄운 뒤,
> cloudflared 를 compose 네트워크에 붙여 `api:3000` 으로 보냅니다
> (3000 포트는 루프백에만 열려 있으므로 `host.docker.internal` 로는 닿지
> 않습니다):
> ```bash
> docker run --rm --network veil_default cloudflare/cloudflared:2024.12.2 tunnel --url http://api:3000
> ```
> 네트워크 이름은 `<compose 프로젝트>_default` 입니다 (리포 폴더가 `veil`
> 이면 `veil_default`). 일회성 `*.trycloudflare.com` URL 출력. 30일 후 만료.

---

## 3. 데모 + 터널 띄우기

리포 루트에서:

```bash
# 1) 새 JWT 시크릿 생성 (한 번만, 영구 저장)
openssl rand -base64 32 > .veil-jwt-secret
chmod 600 .veil-jwt-secret

# 2) 환경변수 + 터널 토큰으로 부팅
export CLOUDFLARE_TUNNEL_TOKEN='eyJh…ZyXP'        # 2단계에서 복사한 값
export VEIL_JWT_SECRET="$(cat .veil-jwt-secret)"
export VEIL_ALLOWED_ORIGINS='https://veil-beta.example.com'  # 본인 공개 도메인
export VEIL_CLIENT_IP_SOURCE=cf-connecting-ip   # 터널 뒤 필수: 없으면 모든 사용자가 cloudflared IP 하나의 rate-limit 버킷을 공유
export VEIL_API_BIND_ADDRESS=127.0.0.1          # 3000 포트는 루프백만. cloudflared 는 compose 네트워크로 접근
export VEIL_ENABLE_SWAGGER=false                    # 운영엔 swagger 끄기

docker compose -f docker-compose.demo.yml --profile tunnel up -d --build
```

확인:

```bash
# 컨테이너 5개 다 떠 있는지
docker compose -f docker-compose.demo.yml ps

# 터널 로그 (Connected 라인 떠야 정상)
docker compose -f docker-compose.demo.yml logs cloudflared --tail=20

# API 자체 헬스 (로컬)
curl -fsS http://localhost:3000/v1/health
```

이제 폰 / 다른 컴퓨터에서:

```
https://veil-beta.example.com/demo/
```

에 접속해 핸들 만들고 채팅 가능. 친구한테 같은 URL 공유 → 동시 접속 가능.

---

## 4. 점검 체크리스트

- [ ] **PRIVATE BETA 배너** 가 화면 상단에 보이는지 (감사 미완료 명시)
- [ ] `VEIL_CLIENT_IP_SOURCE=cf-connecting-ip`, `VEIL_API_BIND_ADDRESS=127.0.0.1` 로 떴는지
      (`docker compose -f docker-compose.demo.yml --profile tunnel config | grep -E 'CLIENT_IP_SOURCE|host_ip'`).
      둘은 함께여야 합니다: 3000 포트가 공개된 채 헤더만 믿으면 아무나 헤더로 자기 버킷을 고릅니다.
- [ ] 새 핸들 등록 → 챌린지/검증 통과 → 채팅 가능
- [ ] `Origin: https://veil-beta.example.com` 헤더가 CORS 통과하는지
- [ ] WebSocket 메시지 즉시 도착 (실시간 pill: 🟢 실시간)
- [ ] 폰에서 접속 시 v2 envelope 암호화로 정상 수신

### 🛟 자주 보는 함정

- **WS pill 이 🟠 "재연결 중..." / 🔴 에서 안 풀린다** → 거의 항상
  `VEIL_ALLOWED_ORIGINS` 와 Cloudflare 의 public hostname 이 정확히
  일치하지 않습니다 (subdomain 오타 / `https://` 빠짐 / 끝 슬래시
  여분). 정확히:
  ```
  VEIL_ALLOWED_ORIGINS=https://veil-beta.example.com
  ```
  형태여야 하고, Cloudflare 대시보드의 public hostname 도 똑같이
  `https://veil-beta.example.com` 이어야 합니다. 환경변수 갈고
  `pnpm demo:tunnel:up` 다시.

- **`pnpm demo:tunnel:logs` 에서 `tunnel: not found`** → docker-compose
  의 `services.api.name` 이 다른 값이면 Cloudflare 의 public hostname
  Service 도 그 이름으로 바꿔야 합니다. 기본 compose 에선 정확히
  `http://api:3000`.

- **첨부 업로드가 401/403/CORS 에러** → 알려진 한계. MinIO (`:9000`)
  가 별도 호스트로 안 노출되어 있어 polution presigned PUT 이
  `localhost:9000` 으로 가다 막힙니다. 다음 단계 (B: VPS) 에서 함께.

- DB 직접 조회 → 메시지 본문이 ciphertext 로만 저장된 것 확인 (핸들·연락처·
  대화 멤버·통화 기록·그룹 이름은 읽을 수 있는 형태입니다,
  [서버 데이터 목록](server-data-inventory.md)):
  ```bash
  docker exec veil-postgres-1 psql -U veil -d veil -c \
    "SELECT substring(ciphertext from 1 for 60), nonce FROM messages ORDER BY server_received_at DESC LIMIT 3;"
  ```

### 4-1. DB 스냅샷은 만들지 않습니다

DB 덤프는 삭제된 계정, 이미 열린 일회성 링크, 만료된 암호문, 수신
확인과 연락처 그래프를 공개한 보관 기간보다 오래 남깁니다
([`metadata-retention.md`](metadata-retention.md)). 그래서 이 스택은 덤프를
만들지 않고, cron 도 걸지 않습니다. 디스크가 날아가면 테스터는 새로
가입합니다. 복구 없음 원칙과 같은 결과입니다.

---

## 5. 알려진 한계 (이번 단계)

1. **첨부 업로드는 불가** — MinIO 가 `localhost:9000` 에서만 노출. 폰에서
   presigned PUT 못 닿음. 두 번째 터널 호스트 (`s3.veil-beta.example.com →
   http://minio:9000`) 를 추가하거나, 단일 터널에서 path-routed nginx
   sidecar 를 두면 해결. **다음 단계 (B: VPS) 에서 함께**.
2. **푸시 없음** — `VEIL_PUSH_ENABLE_DELIVERY=false` 고정. 백그라운드면
   알림 안 뜸. 별도 APNs/FCM 자격증명 + privacy review 필요.
3. **노트북이 꺼지면 사이트도 꺼짐** — Cloudflare Tunnel 은 우리 PC 의
   터널을 노출하는 구조. 24/7 운영하려면 VPS (B 단계).
4. **세션 영속성** — Postgres/Redis/MinIO 가 docker volume 에 있어 컨테이너
   재시작해도 데이터 유지. 단, 노트북 자체 디스크가 날아가면 끝입니다
   (DB 덤프는 만들지 않습니다, 4-1).

---

## 6. 종료

```bash
docker compose -f docker-compose.demo.yml --profile tunnel down
```

볼륨까지 날리려면 `down -v`. 터널 자체는 Cloudflare 대시보드에서
삭제하기 전까지 살아있음 (다음에 다시 `up` 하면 같은 URL 로 복구).

---

## 7. 다음 단계 (B: VPS 본격 호스팅 — 외부 감사 후)

외부 크립토 감사가 끝나고 `VEIL_AUDITED_CRYPTO_ATTESTED=true` 로 production
이 부팅되면 VPS 로 옮기세요:

- **Hetzner CX22** (월 €4) 또는 DigitalOcean $6 droplet
- 본인 도메인 → Cloudflare Tunnel 그대로 → VPS docker
- 24/7 운영 + 첨부 업로드까지 동작 + 모니터링

절차: [`docs/vps-deploy-runbook.md`](vps-deploy-runbook.md).
