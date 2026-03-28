# VoiceMyBook

Turn PDF textbooks into audiobooks with **local neural TTS** (Kokoro). After upload, the app detects chapters, lets you pick which ones to narrate, streams progress over SSE, and plays audio per chapter with an optional synced transcript.

## Stack

- **Frontend**: React 19, TypeScript, Tailwind CSS v4, React Router 7, Zustand, axios, react-dropzone — **vite-plus** (Vite-based toolchain)
- **Backend**: Node.js, Express, SQLite (**better-sqlite3**), **multer** uploads
- **TTS**: **kokoro-js** — Kokoro 82M ONNX, runs locally, no cloud API key needed
- **Audio**: **fluent-ffmpeg** (+ `@ffmpeg-installer/ffmpeg`) for MP3 encoding and stitching
- **PDF**: **pdf-parse** for text extraction + custom chapter boundary detection

## Local setup

### Backend

```bash
cd backend
npm install
cp .env.example .env   # adjust if needed
npm run dev            # http://localhost:3001
```

The first run downloads the Kokoro ONNX model (~82 MB from HuggingFace). Voice `.bin` files must be present in `voices/` at the project root — they are auto-downloaded during the Docker build but for local dev you can grab them manually or run the Docker image.

### Frontend

```bash
cd frontend
# Requires Node 22+ (vite-plus uses node:util styleText, added in Node 20.12)
nvm use 22
pnpm install
pnpm dev               # http://localhost:5173
```

The Vite dev server proxies `/api` to `http://localhost:3001` automatically. To override:

```bash
# frontend/.env.local
VITE_API_BASE_URL=http://localhost:3001/api
```

## How it works

1. **Upload** a PDF — the backend parses it, detects chapters, and pushes `analyzing → analyzed` events over SSE.
2. **Choose voice & speed**, optionally select chapters, then start conversion — runs on an in-process queue.
3. **Listen** at `/player/:jobId` as soon as the first chapter is ready. Remaining chapters appear as they finish. The player supports chapter navigation, playback speed, karaoke-style transcript, `?ch=<index>` deep links, and light/dark theme.

## API

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/upload` | Multipart `file` — creates job, analysis runs async (SSE) |
| POST | `/api/convert` | JSON: `jobId`, `voice`, `speed`, optional `selectedChapterIndices` |
| GET | `/api/progress/:id` | SSE stream (`status` / `close` events) |
| GET | `/api/job/:id` | Job JSON (polling fallback) |
| GET | `/api/audio/:id` | Full-book MP3; redirects to first chapter if only per-chapter files exist |
| GET | `/api/audio/:id/ch/:n` | Per-chapter MP3 (Range requests supported) |
| GET | `/api/voices` | List of available voices |
| GET | `/api/voices/preview?voice=<id>` | On-demand MP3 sample (cached) |

## Available voices (Kokoro)

Default: **Heart** (`af_heart`).

| ID | Label | Notes |
|----|-------|-------|
| `af_heart` | Heart | US Female |
| `af_bella` | Bella | US Female |
| `af_nicole` | Nicole | US Female |
| `am_fenrir` | Fenrir | US Male |
| `am_michael` | Michael | US Male |
| `am_puck` | Puck | US Male |
| `bf_emma` | Emma | British Female |
| `bm_george` | George | British Male |

## Backend environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `3001` | HTTP port |
| `DB_PATH` | `./voicemybook.db` | SQLite database path |
| `UPLOAD_DIR` | `./uploads` | PDFs, chunks, audio, previews |
| `MAX_FILE_SIZE_MB` | `50` | Upload limit |
| `TTS_CONCURRENCY` | `3` | Parallel TTS workers per job |
| `TTS_CHUNK_SIZE` | `1000` | Target characters per chunk |
| `TTS_VOICE` | `af_heart` | Default voice |
| `CLEANUP_AFTER_HOURS` | `24` | Auto-delete old jobs (`0` = disabled) |

## Deployment

### Docker (self-hosted)

A multi-stage `Dockerfile` is included. It builds the frontend, installs backend dependencies, downloads voice `.bin` files from HuggingFace, and pre-caches the ONNX model so cold starts are fast.

```bash
docker build -t voicemybook .
docker run -p 7860:7860 \
  -v voicemybook-data:/app/data \
  -e DB_PATH=/app/data/voicemybook.db \
  -e UPLOAD_DIR=/app/data/uploads \
  voicemybook
```

### Render (backend) + Netlify (frontend)

A `render.yaml` is included for one-click Render deployment. It provisions a **persistent disk** at `/app/data` for the SQLite database and uploaded files.

**Render steps:**
1. Push repo to GitHub
2. New Web Service → connect repo → Render detects `render.yaml` automatically
3. Deploy (first build takes ~5–10 min — model download)

**Netlify steps:**
1. New Site → connect the same GitHub repo → Netlify detects `netlify.toml`
2. Set environment variable in Netlify dashboard:
   ```
   VITE_API_BASE_URL = https://<your-render-service>.onrender.com/api
   ```
3. Trigger a redeploy (Vite bakes the URL into the bundle at build time)

> **Note:** The Render free tier sleeps after 15 min of inactivity and has no persistent disk. Use the **Starter plan** ($7/mo) for always-on service and persistent storage.
