# Try Veil on an Android phone today

This guide gets Veil onto your Android phone and a few friends' phones today.
Your PC runs the server. Cloudflare gives it a public https address. GitHub
builds the Android app for that address. You do not need Flutter or Android
Studio. Plan for about an hour. There is no iPhone build yet.

## Read this first

- **This is a private test** for a few people you invite. It is not a public
  release.
- **The encryption has not been audited** by an outside firm yet. Do not use
  Veil for anything that must stay secret.
- **The server runs in development mode.** A production server refuses to
  start until an outside audit is done and attested, so this setup uses the
  mode meant for testing. That mode leaves out some production protections,
  for example the HSTS header and the check that refuses test-only message
  formats.
- **Keep the address to yourselves.** Anyone who has your tunnel address can
  make an account on your server. Give the address and the app only to the
  testers you invited, never in public. If your GitHub repository is public,
  anyone can see the address in the build log and the artifact name.
- **There is no account recovery.** If a tester loses the phone, resets it,
  uninstalls the app or clears its storage, that account is gone.

## What you need

- A PC with Docker (Docker Desktop on Windows or Mac) and Git. On Windows, run
  the commands below in Git Bash, which comes with Git.
- This repository on GitHub with the `beta/apk` branch pushed, and a copy of
  it on the PC.
- A free Cloudflare account with a domain name on it. Any cheap domain works.
  No domain? See [No domain](#no-domain-quick-tunnel) at the end.
- An Android phone for you and one for each friend.
- Admin access to this repository on GitHub.

Below, `veil.example.com` and `veil-files.example.com` stand for your two
addresses. Use your own domain everywhere you see them.

## 1. Make the tunnel (Cloudflare)

1. Open the Cloudflare Zero Trust dashboard (one.dash.cloudflare.com) and go
   to **Networks > Tunnels > Create a tunnel > Cloudflared**. Name it
   `veil-beta`.
2. On the install screen choose **Docker** and copy the token: the long text
   after `--token`, starting with `eyJ`. You need it in step 2.
3. Add two public hostnames (newer dashboards call them published
   application routes):

   | Hostname | Service type | URL |
   | --- | --- | --- |
   | `veil.example.com` | HTTP | `api:3000` |
   | `veil-files.example.com` | HTTP | `minio:9000` |

   The first is the app's server. The second carries encrypted photos and
   files. Keep both one level under your domain (`veil-files.example.com`,
   not `files.veil.example.com`): Cloudflare's free certificate covers only
   one level.

## 2. Start the server (your PC)

In your copy of this repository:

```bash
git fetch origin
git checkout beta/apk
cp .env.beta.example .env.beta
```

Open `.env.beta` in a text editor and replace every `replace`:

- `CLOUDFLARE_TUNNEL_TOKEN`: the token from step 1.
- `VEIL_ALLOWED_ORIGINS`: `https://veil.example.com`
- `VEIL_S3_PUBLIC_ENDPOINT`: `https://veil-files.example.com`
- `VEIL_JWT_SECRET` and `VEIL_RETIRED_HANDLE_PEPPER`: run `openssl rand -hex 32`
  twice and paste one result into each.
- `VEIL_MINIO_ROOT_PASSWORD`: the result of `openssl rand -hex 24`.

`grep replace .env.beta` must print nothing. Then start everything:

```bash
docker compose --env-file .env.beta -f docker-compose.demo.yml --profile tunnel up -d --build
```

The first start takes a few minutes. Then check it:

```bash
docker compose --env-file .env.beta -f docker-compose.demo.yml ps
curl -fsS https://veil.example.com/v1/health
curl -fsS -o /dev/null -w '%{http_code}\n' https://veil-files.example.com/minio/health/live
```

`ps` lists postgres, redis, minio, api and cloudflared as running. The first
`curl` prints a line starting with `{"status":"ok"`. The second prints `200`.

## 3. Build the app (GitHub)

1. On GitHub, open the repository's **Settings > Secrets and variables >
   Actions**, then the **Variables** tab, and add two repository variables:

   | Name | Value |
   | --- | --- |
   | `VEIL_BETA_API_BASE_URL` | `https://veil.example.com/v1` |
   | `VEIL_BETA_REALTIME_URL` | `https://veil.example.com` |

   No slash at the end. The build stops with an error if either one looks
   wrong.
2. Build the `beta/apk` branch: go to **Actions > private-beta-ci > Run
   workflow**, pick the branch `beta/apk` and press **Run workflow**. A push to
   `beta/apk` also starts a build. A run that started before you added the
   variables builds for localhost: use **Re-run jobs** on it, or start a new
   one.
3. Open the run and wait for the **android-build** job (10 to 20 minutes). The
   other jobs do not matter for the app.
4. At the bottom of the run page, under **Artifacts**, the name must be
   `veil-android-profile-veil.example.com`. If it says
   `veil-android-debug-points-at-localhost`, the build did not see the
   variables: check them and start a new run with **Run workflow**.

## 4. Install the app (phone)

1. Download the artifact (you must be signed in to GitHub; it is kept for 7
   days). It is a zip. Unzip it to get `app-profile.apk`.
2. Get the APK onto your phone, over a USB cable or by sending it to
   yourself. Send it to your friends privately the same way. Do not post it
   anywhere public: it has your server address inside.
3. On the phone, tap the APK. Android asks to allow installs from that app
   (your browser or Files): tap **Settings**, turn on **Allow from this
   source**, go back and tap **Install**. If Google Play Protect warns about an
   unknown app, tap **More details > Install anyway**.

Everyone should install the same APK and keep it. GitHub's build machine signs
each build with a throwaway debug key that can change between runs, so a newer
APK may fail with "App not installed". Then the old app has to be uninstalled first, which
deletes that phone's account for good.

## 5. Sign up and add a friend

1. Open Veil. On **Privacy notice**, tick the box and tap **Agree and
   continue**. On **Before you start**, tick **I understand a lost account
   can't be recovered** and tap **Continue**.
2. Choose a handle: 3 to 32 lowercase letters, numbers, dots or underscores.
   You can't change it later. Tap **Create account**.
3. Optional: **Settings > App lock** to set a PIN.
4. Your friend signs up too. Tell each other your handles in person or on a
   call. Then go to **Contacts > Add contact**, type the handle, tap **Add**,
   then **Message**. (Or **Chats > New chat** and type the handle.)
5. In the chat, tap the **Safety number** icon at the top. Compare the numbers
   with your friend's phone, side by side or on a call, then tap **Mark as
   verified**.

## What works and what does not

- **Works:** sign-up, one-to-one and group chats, messages arriving live while
  the app is open, disappearing messages, app lock, safety numbers. The same
  server also has the web version at `https://veil.example.com/demo/`.
- **Photos and files** work through `veil-files.example.com` from step 1.
  Without that hostname they fail to send and to download.
- **No push notifications.** Nothing tells you about a message while the app
  is closed; it shows up when you open the app.
- **No calls and no voice messages** in the Android app.
- **Your PC is the server.** When it sleeps, shuts down or goes offline, Veil
  stops working. Messages sent meanwhile go out once it is back.

## Stop, restart, reset

```bash
# Stop. Accounts and messages stay.
docker compose --env-file .env.beta -f docker-compose.demo.yml --profile tunnel down
# Start again, also after you change .env.beta.
docker compose --env-file .env.beta -f docker-compose.demo.yml --profile tunnel up -d
```

After a reboot the containers start again once Docker is running. Adding
`-v` to the stop command deletes every account and message on the server;
after that, every tester has to clear the app's storage (Android **Settings >
Apps > Veil > Storage**) and sign up again.

## No domain (quick tunnel)

Cloudflare can give you a random `trycloudflare.com` address without a domain
or a token. It works for a one-day test, with a big catch: the address changes
every time the tunnel restarts (a closed terminal, a reboot). A new address
means new GitHub variables, a new APK, and every tester uninstalling and
signing up again.

```bash
# 1. Start the server without the tunnel container.
docker compose --env-file .env.beta -f docker-compose.demo.yml up -d --build
# 2. Find the network: the one whose name ends in _default.
docker network ls
# 3. In two separate terminals, leave these running.
docker run --rm --network veil_default cloudflare/cloudflared:2024.12.2 tunnel --url http://api:3000
docker run --rm --network veil_default cloudflare/cloudflared:2024.12.2 tunnel --url http://minio:9000
```

Use your network's name in place of `veil_default`. Each command prints an
address like `https://some-random-words.trycloudflare.com`. Put the second one
in `VEIL_S3_PUBLIC_ENDPOINT` and the first in `VEIL_ALLOWED_ORIGINS`, run the
first command again, and use the first one for the GitHub variables in
[step 3](#3-build-the-app-github). Until then the API keeps restarting, which
is expected. `CLOUDFLARE_TUNNEL_TOKEN` is not used here.

## If something is wrong

- **The app says "Couldn't start":** the APK has a bad server address. Check
  the artifact name and the two variables, then build again.
- **Chats say "Connecting…" or sign-up fails:** open
  `https://veil.example.com/v1/health` in the phone's browser. If that fails,
  run `docker compose --env-file .env.beta -f docker-compose.demo.yml logs cloudflared --tail=20`
  and check the hostname points at `http://api:3000`. WebSockets must be on
  for your domain in Cloudflare (**Network > WebSockets**, on by default).
- **Photos don't send:** run the last `curl` from step 2, check
  `VEIL_S3_PUBLIC_ENDPOINT` is exactly your files address, and run the start
  command again after any change.
- **The server doesn't start:** `grep replace .env.beta` must print nothing.
  Then read `docker compose --env-file .env.beta -f docker-compose.demo.yml logs api --tail=50`.
  If you ran the demo before with its default MinIO password, the old data
  may not accept the new one: reset with `-v` as above.

More about the tunnel itself: [cloudflare-tunnel-deploy.md](cloudflare-tunnel-deploy.md)
(in Korean).
