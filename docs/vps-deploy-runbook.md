# VPS 프로덕션 배포 런북

외부 크립토 감사가 끝난 뒤의 production 배포 절차. 약 90분 소요.
`VEIL_ENV=production` 은 `VEIL_AUDITED_CRYPTO_ATTESTED=true` 와 서명된 감사
보고서의 `VEIL_AUDIT_REPORT_SHA256` 없이는 부팅이 거부됩니다 (부록 A).

## 0. 사전 준비물

- VPS (Hetzner CX22 €4/월, DO basic $6, AWS t4g.small ~$15 — 최소 2vCPU /
  2GB RAM / 40GB SSD)
- 도메인 1개 (예: `veil.example.com`)
- 본인 SSH 키
- 본인 GitHub 자격증명 (이 저장소 clone 용)

## 1. VPS 초기 셋업

```bash
ssh root@VPS_IP

# Ubuntu 24.04 가정. 비-root 운영 사용자 생성.
adduser veil --disabled-password
usermod -aG sudo veil
mkdir -p /home/veil/.ssh
cp ~/.ssh/authorized_keys /home/veil/.ssh/
chown -R veil:veil /home/veil/.ssh
chmod 700 /home/veil/.ssh
chmod 600 /home/veil/.ssh/authorized_keys

# 패스워드 SSH 차단, root 직접 SSH 차단.
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh

# 방화벽: 22, 80, 443 만.
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Docker 설치.
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker veil

# 자동 보안 업데이트.
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
exit
```

## 2. DNS

도메인 등록 기관에서:

| Type | Name | Value |
|---|---|---|
| A | `veil` | VPS_IP |
| A | `s3.veil` | VPS_IP |

`dig +short veil.example.com` 으로 5분 이내 전파 확인.

## 3. 코드 + 환경 변수

```bash
ssh veil@VPS_IP

git clone https://github.com/pppaal/veil.git
cd veil

cp .env.prod.example .env.prod
# 자동 생성기로 secrets 채우기:
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)|" .env.prod
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)|" .env.prod
sed -i "s|^MINIO_ROOT_USER=.*|MINIO_ROOT_USER=veil-$(openssl rand -hex 4)|" .env.prod
sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)|" .env.prod
sed -i "s|^VEIL_JWT_SECRET=.*|VEIL_JWT_SECRET=$(openssl rand -base64 32)|" .env.prod
# 삭제된 계정 핸들의 격리용 HMAC 키. 한 번 만들고 절대 바꾸지 마세요:
# 바꾸면 격리 중인 핸들이 일찍 다시 등록 가능해집니다.
sed -i "s|^VEIL_RETIRED_HANDLE_PEPPER=.*|VEIL_RETIRED_HANDLE_PEPPER=$(openssl rand -base64 32)|" .env.prod
sed -i "s|^VEIL_METRICS_AUTH_TOKEN=.*|VEIL_METRICS_AUTH_TOKEN=$(openssl rand -hex 24)|" .env.prod
sed -i "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24)|" .env.prod

# 호스트명과 ACME 이메일은 직접 편집:
nano .env.prod
# CADDY_PUBLIC_HOSTNAME=veil.example.com
# CADDY_S3_HOSTNAME=s3.veil.example.com
# VEIL_ALLOWED_ORIGINS=https://veil.example.com
# VEIL_S3_PUBLIC_ENDPOINT=https://s3.veil.example.com
# ACME_EMAIL=ops@example.com

chmod 600 .env.prod
```

## 4. 첫 부팅

```bash
# 빌드 + 핵심 서비스 (postgres/redis/minio/api/caddy).
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build

# 로그 따라가며 헬스체크 통과 확인:
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f api

# 다른 터미널에서:
curl -s https://veil.example.com/v1/health
# {"status":"ok",...}
```

Caddy 가 첫 요청 시 Let's Encrypt 인증서 자동 발급. 1-2분 소요.

> ⚠️ `VEIL_AUDITED_CRYPTO_ATTESTED=false` 이면 production 모드 부팅이
> 거부됩니다. 이 런북은 감사 후의 production 배포용입니다. 감사 전에는
> 공개 대상 운영을 하지 마세요. 초대한 소수 테스터 대상 비공개 리허설만
> 가능하고, 그 방법은 부록 A 에 있습니다.

## 5. 관측 (Prometheus + Grafana)

```bash
# observability 프로필 활성화:
docker compose --env-file .env.prod -f docker-compose.prod.yml \
  --profile observability up -d
```

내부 포트로만 노출되므로 SSH 터널로 접근:

```bash
# 본인 노트북에서:
ssh -L 3001:localhost:3001 veil@VPS_IP
# 브라우저에서 http://localhost:3001 (Grafana, admin / 위 비밀번호)
```

`VEIL — Production Overview` 대시보드가 자동 provision. 패널:
- API uptime / Active WS connections
- HTTP RPS by status class
- p50/p95 latency by route
- Messages sent / minute
- Auth events / minute
- Process memory / event loop lag

알림 (`infra/prometheus/alerts.yml`): API down, 5xx 비율 5% 초과, p95
1.5s 초과, WS 동접 50% 급감, RSS 700MB 초과.

> Alertmanager 와 페이저는 별도 운영자 결정. 무료 Pushover ($5/월) +
> Pushcut, 또는 Discord/Slack 웹훅이 1인 베타 운영에 충분합니다.

## 6. DB 백업은 없습니다

production 스택은 데이터베이스 덤프를 만들지 않습니다. 덤프는 삭제된 계정과
핸들, 이미 열린 일회성 링크, 만료되거나 한 번 보기로 사라진 암호문, 수신
확인, 연락처 그래프를 [metadata-retention.md](metadata-retention.md) 가
공개한 보관 기간보다 오래, 이 호스트와 복사된 모든 곳에 남깁니다. Redis
AOF 를 끈 것과 같은 이유입니다.

그 결과: Postgres 볼륨을 잃으면 모든 사용자가 새로 가입합니다. 복구 없음
원칙이 원래 뜻하는 바와 같습니다. 디스크 고장은 미러(RAID1)로 대비할 수
있지만, 덤프·볼륨 스냅샷·오프사이트 복사는 만들지 마세요: 지난 상태를
보관하는 것은 모두 같은 문제를 만듭니다. `scripts/policy-check.mjs` 의 `no-database-dumps` 규칙이
compose 파일과 `infra/` 에 덤프 도구가 들어오면 CI 를 실패시킵니다.

이전 릴리스로 운영하던 스택은 한 번만:

```bash
# postgres-backup 서비스가 남긴 덤프 볼륨 삭제 (프로젝트 이름이 다르면 맞게)
docker volume rm veil_veil_prod_backups
# 호스트 cron 으로 뜨던 덤프가 있었다면 cron 항목과 파일 삭제
crontab -l | grep -v pg_dump | crontab -
# R2 등 오프사이트로 복사했다면 그쪽 버킷도 비우기
rclone purge r2:veil-prod-backups
```

## 7. 헬스체크

```bash
# VPS 로컬:
curl -s -H "Authorization: Bearer $(grep VEIL_METRICS_AUTH_TOKEN .env.prod | cut -d= -f2)" \
  https://veil.example.com/v1/metrics | head -20

# 외부 (테스터 본인 노트북):
pnpm demo:status   # VEIL_API_PUBLIC=https://veil.example.com pnpm demo:status
```

## 8. 업데이트

```bash
cd /home/veil/veil
git pull
docker compose --env-file .env.prod -f docker-compose.prod.yml pull
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
docker compose --env-file .env.prod -f docker-compose.prod.yml exec api \
  pnpm prisma migrate deploy
```

마이그레이션은 멱등이므로 재실행 안전.

### 8.1 업그레이드 주의: 마이그레이션 0018 (plaintext 제거) 이 들어간 릴리스

이미 운영 중인 스택을 이 릴리스로 올릴 때는 `git pull` 전에 아래를 순서대로
하세요.

1. **`VEIL_RETIRED_HANDLE_PEPPER` 추가.** 없으면 compose 가 어떤 컨테이너도
   띄우지 않고 (`VEIL_RETIRED_HANDLE_PEPPER required`) 멈춥니다. 마이그레이션
   전에 멈추므로 데이터는 그대로입니다. 값이 비어 있을 때만 채우므로 이미 있는
   pepper 는 바뀌지 않습니다 (바꾸면 격리 중인 핸들이 일찍 풀립니다):

   ```bash
   grep -q '^VEIL_RETIRED_HANDLE_PEPPER=' .env.prod || echo 'VEIL_RETIRED_HANDLE_PEPPER=' >> .env.prod
   sed -i "s|^VEIL_RETIRED_HANDLE_PEPPER=$|VEIL_RETIRED_HANDLE_PEPPER=$(openssl rand -base64 32)|" .env.prod
   ```

2. **마이그레이션 0018–0020 은 되돌릴 수 없습니다.** 0018 은 `reactions`,
   `user_profiles`, `recovery_blobs` 테이블과 표시 이름·아바타·연락처 별명·신고
   메모 컬럼을 지우고, 모든 스토리를 삭제합니다. 0019 와 0020 은 서버가 필요
   없이 들고 있던 메타데이터를 지웁니다: 대화별 마지막 활동 시각, 나간 멤버의
   에포크·동기화 커서·음소거 행, 해제된 기기의 이름과 one-time prekey, 그리고
   더 이상 그 대화의 멤버가 아닌 사람의 id 가 남아 있던 1:1 대화 키
   (`direct_key`: 삭제된 계정, 이전 릴리스에서 삭제가 중간에 멈춘 계정, 예전
   그룹 나가기 경로로 1:1 대화를 나간 사용자. 아무도 남지 않은 1:1 대화는
   통째로 삭제). 진행 중인 계정 삭제는 1:1 멤버십이 남아 있으므로 키도 그대로
   두고, 삭제를 다시 실행하면 그때 지워집니다. 이전 이미지는 마이그레이션된 스키마에서
   돌지 않으므로, 롤백은 덤프 복원뿐입니다. 업그레이드 직전에 이 한 번만 덤프를
   뜨고 (상시 백업은 없습니다, 6절):

   ```bash
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec -T postgres \
     pg_dump -U veil -d veil -F c > ./veil-pre-upgrade-$(date +%Y%m%d-%H%M%S).dump
   chmod 600 ./veil-pre-upgrade-*.dump
   ```

   이 덤프에는 0018–0020 이 지우는 평문과 메타데이터, 그리고 덤프 시점의
   모든 계정이 남아 있습니다. 호스트 밖으로 복사하지 말고, 업그레이드가
   확인되는 즉시 지우세요 (`shred -u ./veil-pre-upgrade-*.dump`). 이전
   릴리스의 `veil_prod_backups` 볼륨은 6절대로 삭제하세요.

3. **Redis append-only 파일 끄기.** 이 릴리스의 compose 는 Redis 를
   `--appendonly no --save "60 1"` 로 띄웁니다 (이유는
   [metadata-retention.md](metadata-retention.md)). 그냥 재배포하면 Redis 가
   AOF 를 읽지 않고 빈 상태로 떠서 모든 모바일 기기가 로그아웃됩니다. 재배포
   전에 살아 있는 키를 스냅샷으로 옮기고, 재배포 후 AOF 를 지우세요:

   ```bash
   REDIS_PASSWORD=$(grep '^REDIS_PASSWORD=' .env.prod | cut -d= -f2-)
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec redis \
     redis-cli -a "$REDIS_PASSWORD" --no-auth-warning CONFIG SET appendonly no
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec redis \
     redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SAVE
   # 여기서 위의 업데이트 절차 (git pull, up -d --build) 진행.
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec redis \
     rm -rf /data/appendonlydir
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec redis \
     redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO persistence | grep aof_enabled
   # aof_enabled:0 이어야 합니다.
   ```

   `appendonlydir` 를 지우지 않으면 만료된 키의 기록이 볼륨에 그대로 남습니다.

## 9. 사고 대응 (1인 베타 운영용)

| 증상 | 1차 점검 | 2차 점검 |
|---|---|---|
| 사이트 안 열림 | `docker compose ps` — 모두 `Up` 인가? | Caddy 로그: 인증서 발급 실패? |
| 메시지 송신 실패 | API 로그 grep ERROR | Postgres healthcheck |
| 첨부 업로드 401 | MinIO healthcheck | `VEIL_S3_PUBLIC_ENDPOINT` 매치 |
| Grafana 알림: p95 1.5s+ | Postgres 슬로우 쿼리 | Redis 메모리 |
| WS 동접 급감 | Caddy 액세스 로그 | 사용자가 진짜로 빠짐 vs 인프라 |

런북 짧으니 운영자가 머릿속에 두기. 더 늘어나면 별도 wiki.

## 10. 종료

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml down
# 볼륨까지 (모든 데이터 손실): down -v
```

---

## 부록 A — 외부 감사 전: 초대 테스터 비공개 리허설만

`VEIL_AUDITED_CRYPTO_ATTESTED=false` 면 production 부팅이 거부됩니다.
이건 **버그가 아니라** 외부 감사 전 공개 출시를 막는 정책 게이트이고,
우회 방법은 없습니다. `VEIL_ENV=development` 로 이 런북의 스택을 공개
대상으로 돌리는 것은 우회입니다: development 모드는 CSP·HSTS 를 끄고,
개발용 envelope 를 받고, 감사·JWT·CORS·pepper·보관 기간·Swagger 검사를
모두 건너뜁니다.

감사 전에 할 수 있는 것은 직접 초대한 소수 테스터 대상의 비공개 리허설
뿐입니다. `apps/api/.env.alpha.example` 과
`infra/docker/docker-compose.alpha.yml` 로 띄우고 (`VEIL_ENV=development`,
`PRIVATE BETA` 배너 표시), 테스터에게 미감사 상태를 알리세요.
`docker-compose.demo.yml` 은 고정 자격증명으로 Postgres·Redis·MinIO 를
공개하므로 Caddy 뒤에 두더라도 인터넷에 노출하지 마세요 (파일 머리말 참고).

## 부록 B — Cloudflare Tunnel 변형

VPS 가 있는데 도메인 노출 + DDoS 보호를 Cloudflare 에 맡기고 싶으면
Caddy 빼고 cloudflared 사이드카만 띄우면 됩니다 — `--profile tunnel` 로
demo compose 와 동일. TLS, HSTS, 액세스 로그는 Cloudflare 쪽에서 관리.
