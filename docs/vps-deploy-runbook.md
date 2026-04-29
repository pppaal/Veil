# VPS 프로덕션 배포 런북

베타 단계의 노트북 + Cloudflare Tunnel 에서 24/7 VPS 운영으로
넘어가는 절차. 약 90분 소요.

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

> ⚠️ `VEIL_AUDITED_CRYPTO_ATTESTED=false` 이라 production 모드 부팅이
> 거부됩니다. 외부 감사 전까지는 `VEIL_ENV=development` 로 임시 운영하거나,
> private beta 면 `docker-compose.demo.yml` 을 그대로 쓰면서 Caddy 만
> 별도로 띄우는 방법도 있습니다 (런북 부록 A).

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

## 6. DB 백업 cron

```bash
mkdir -p $HOME/veil-backups
crontab -e
# 매일 03:30, 14일 보관:
30 3 * * * docker exec veil-postgres-1 pg_dump -U veil -d veil -F c \
  > $HOME/veil-backups/veil-$(date +\%Y\%m\%d).dump 2>>$HOME/veil-backups/cron.log && \
  find $HOME/veil-backups -name 'veil-*.dump' -mtime +14 -delete
```

복구 시뮬 (월 1회 권장):
```bash
docker exec -i veil-postgres-1 pg_restore -U veil -d veil --clean --if-exists \
  < $HOME/veil-backups/veil-YYYYMMDD.dump
```

오프사이트: `rclone sync $HOME/veil-backups r2:veil-prod-backups/` (Cloudflare R2,
$0.015/GB·월, 베타 백업 100GB = 월 $1.50)

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

## 부록 A — 베타 단계 임시 운영 (audit 게이트 우회 X)

`VEIL_AUDITED_CRYPTO_ATTESTED=false` 면 production 부팅이 거부됩니다.
이건 **버그가 아니라** 외부 감사 전 정식 production 출시를 막는 정책
게이트입니다. 사적 베타 (5-50명 친구) 면 `VEIL_ENV=development` 로
운영하고, 감사 끝나면 production 으로 승격하세요. 사용자 화면에
`PRIVATE BETA` 배너가 그대로 떠야 합니다.

## 부록 B — Cloudflare Tunnel 변형

VPS 가 있는데 도메인 노출 + DDoS 보호를 Cloudflare 에 맡기고 싶으면
Caddy 빼고 cloudflared 사이드카만 띄우면 됩니다 — `--profile tunnel` 로
demo compose 와 동일. TLS, HSTS, 액세스 로그는 Cloudflare 쪽에서 관리.
