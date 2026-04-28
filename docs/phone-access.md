# 폰에서 VEIL 데모 사용하기

이 문서는 본인 노트북에서 VEIL 백엔드를 띄우고, 같은 Wi-Fi 의 휴대폰에서
브라우저로 데모 클라이언트에 접속하는 가장 빠른 길을 보여줍니다.

> 모바일 앱 (Flutter) 빌드는 별도입니다 — 그건 본인 PC에 Flutter SDK + 안드로이드
> 빌드 툴 + 실기기/에뮬레이터가 필요합니다. 이 문서는 **웹 데모**만 다룹니다.

---

## 한 명령으로 띄우기

```bash
docker compose -f docker-compose.demo.yml up
```

이 한 줄이 다음 5개 컨테이너를 띄웁니다:

| 컨테이너        | 역할                                  | 포트                    |
| -------------- | ------------------------------------- | ----------------------- |
| `postgres`     | 메시지/사용자 메타데이터              | `5432`                  |
| `redis`        | 챌린지 캐시 + 세션                    | `6379`                  |
| `minio`        | 첨부 파일 (암호화 객체 스토리지)      | `9000` (콘솔 `9001`)    |
| `minio-init`   | `veil-encrypted` 버킷 자동 생성       | (한 번 실행 후 종료)    |
| `api`          | NestJS API + 정적 데모 (`/demo/`)     | `3000`                  |

처음에는 API 이미지 빌드 때문에 1~3분 걸립니다. 두 번째부터는 5초 안에 뜹니다.

서버가 완전히 떴다는 표시:

```
api-1  | [Nest] LOG [NestApplication] Nest application successfully started
```

---

## 노트북에서 동작 확인

브라우저에서:

```
http://localhost:3000/demo/
```

- 로그인 화면이 뜨면 정상.
- 핸들 만들고 보내고 받고 가능.

---

## 폰에서 접속

같은 Wi-Fi 에 폰을 연결한 뒤, 폰 브라우저에 노트북의 LAN IP + `:3000/demo/` 입력.

### 1. 노트북 IP 찾기

| 운영체제           | 명령                                                          |
| ----------------- | ------------------------------------------------------------- |
| macOS             | `ipconfig getifaddr en0` (Wi-Fi 인터페이스 — `en1` 일 수도)   |
| Linux             | `hostname -I \| awk '{print $1}'`                             |
| Windows (PowerShell) | `(Get-NetIPAddress -AddressFamily IPv4 \| Where InterfaceAlias -like 'Wi-Fi*').IPAddress` |

예: `192.168.1.42`

### 2. 폰 브라우저에서 열기

```
http://192.168.1.42:3000/demo/
```

폰에서 핸들 새로 만들고, 노트북에서 만든 핸들로 다이렉트 챗 시작 → 양방향 채팅 가능.

> **첨부 업로드까지** 동작하려면 `VEIL_S3_PUBLIC_ENDPOINT` 가 폰에서 도달 가능한
> 주소여야 합니다. 같은 IP 로 명시:
>
> ```bash
> VEIL_S3_PUBLIC_ENDPOINT=http://192.168.1.42:9000 \
>   docker compose -f docker-compose.demo.yml up
> ```

### 3. 방화벽 허용

폰이 노트북 :3000 에 못 닿으면 방화벽 차단입니다.

- **macOS**: 시스템 설정 → 네트워크 → 방화벽 → 옵션 → "들어오는 연결 차단" 끄기
  (또는 Docker 만 허용)
- **Windows**: Windows Defender 방화벽 → 인바운드 규칙 → TCP 3000 허용
  (Docker Desktop 이 보통 자동 추가)
- **Linux (ufw)**: `sudo ufw allow 3000/tcp`

---

## 종료

`Ctrl+C` 후:

```bash
docker compose -f docker-compose.demo.yml down
```

볼륨까지 지우려면:

```bash
docker compose -f docker-compose.demo.yml down -v
```

---

## 작동 보장 범위

이 데모로 확인되는 것:

- 핸들 등록 (Ed25519 인증) + 세션 복원
- 다이렉트 챗 + 메시지 송수신
- **진짜 E2E 암호화** (X25519 ECDH + AES-GCM, 서버는 ciphertext 만 봄)
- WebSocket 실시간 (즉시 도착, 타이핑 인디케이터, 온라인 표시)
- 메시지 그룹핑, 답장, 읽음 표시
- IndexedDB 캐시 (새로고침해도 즉시 보임)
- 오프라인 큐잉 + 자동 재시도
- 다중 채팅 탭 + 분할 보기 (와이드 화면)
- 토큰 자동 갱신

이 데모로 확인되지 **않는** 것:

- Double Ratchet (forward secrecy / post-compromise security) — Flutter 앱에만 있음
- 첨부 업로드 UI — API 는 동작하지만 데모 UI 미구현
- 그룹 채팅 / 채널 / 음성·영상 통화 / 스토리 — API 는 동작하지만 데모 UI 미구현
- 푸시 알림 — `VEIL_PUSH_ENABLE_DELIVERY=false` 고정

---

## 트러블슈팅

**`docker compose` 가 실행이 안 됨**
→ Docker Desktop 또는 `docker-engine` 이 안 떠 있음. 시작하세요.

**API 가 자꾸 죽음 (`exit 1`)**
→ `docker compose -f docker-compose.demo.yml logs api` 확인. 보통 prisma 가 DB 에
연결을 못 한 경우인데, `db push` 실행 직후 일단 한 번 자동 재시작되니 30초
정도 두면 됩니다.

**폰에서 "사이트에 연결할 수 없습니다"**
→ (1) 같은 Wi-Fi 인지, (2) 노트북 방화벽이 3000 막는지, (3) IP 가 정확한지 확인.

**핸들 만들기 직후 401**
→ Throttle 에 걸렸을 수 있음. 1분 기다리거나 컨테이너 재시작.

**브라우저 콘솔에 `Web Crypto X25519 not supported`**
→ 폰 브라우저가 너무 오래된 버전. iOS Safari 17+ / Chrome 113+ 가 필요합니다.
