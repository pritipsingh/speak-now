# Deploy the Speak backend to Railway

The backend is a Dockerized FastAPI app (agno / AgentOS) + Postgres. For small-team
hosting we run AgentOS with JWT off (`RUNTIME_ENV=dev`) and gate the whole app with a
single shared secret (`SPEAK_ACCESS_TOKEN`). See `app/main.py`.

## 1. Get the code on GitHub

Railway deploys from a repo. Push `agent-platform/` to a GitHub repo (private is fine).
`railway.json`, `Dockerfile`, and `.env` handling are already set up.
`.env` is gitignored, so you'll set secrets in Railway, not commit them.

## 2. Create the project + database

1. Railway → **New Project → Deploy from GitHub repo** → pick the repo.
2. In the project, **New → Database → PostgreSQL**. (Plain Postgres is fine. Speak
   uses sessions/runs only, no pgvector.)

## 3. Set env vars on the API service

Service → **Variables**:

| Variable | Value |
|---|---|
| `OPENAI_API_KEY` | your real key (`sk-...`) |
| `SPEAK_ACCESS_TOKEN` | a secret, generate with `openssl rand -hex 24` |
| `RUNTIME_ENV` | `dev` |
| `WAIT_FOR_DB` | `False` |
| `DATABASE_URL` | reference the DB: `${{Postgres.DATABASE_URL}}` |

`db/url.py` reads `DATABASE_URL` and normalizes it to the psycopg driver. The
Dockerfile's start command binds Railway's `$PORT` automatically.

## 4. Deploy + get the URL

Railway builds the Dockerfile and gives the service a public URL. Under
**Settings → Networking**, generate a domain if there isn't one, e.g.
`https://speak-production.up.railway.app`.

## 5. Verify

```bash
curl https://<your-url>/health                 # {"status":"ok"...}, open
curl https://<your-url>/dictation/health       # {"status":"ok","transcribe_model":...}
curl -o /dev/null -w "%{http_code}\n" https://<your-url>/sessions          # 401 (gated)
curl -o /dev/null -w "%{http_code}\n" -H "X-Speak-Token: <secret>" https://<your-url>/sessions   # 200
```

## 6. Point the app at it

In Speak: right-click the menu-bar icon → **Server settings…** → set the Backend URL
(`https://<your-url>`) and the Access token (`SPEAK_ACCESS_TOKEN`). Or bake them in as
the app defaults and rebuild the DMG for distribution.

## Notes

- **Cost:** every transcription uses your `OPENAI_API_KEY`. The shared secret keeps the
  endpoint private; rotate it by changing `SPEAK_ACCESS_TOKEN` (all clients must update).
- **Scaling later:** to open it up publicly, switch to real per-user auth (AgentOS JWT
  via os.agno.com, or per-user OpenAI keys) and add rate limiting.
- **CLI alternative:** `npm i -g @railway/cli`, `railway login`, `railway init`,
  `railway up`, then add Postgres and the variables above in the dashboard.
