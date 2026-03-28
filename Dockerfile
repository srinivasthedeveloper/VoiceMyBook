# ── Stage 1: Build frontend ────────────────────────────────────────────────────
FROM node:22-slim AS frontend-builder
WORKDIR /app/frontend
RUN npm install -g pnpm
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY frontend/ ./
RUN pnpm build

# ── Stage 2: Backend runtime ───────────────────────────────────────────────────
FROM node:22-slim
# Build tools needed by better-sqlite3 (native C++ module)
RUN apt-get update && apt-get install -y python3 make g++ wget && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend

# Install backend deps (postinstall runs patch-kokoro.js automatically)
COPY backend/package*.json ./
RUN npm install --omit=dev

# Copy backend source
COPY backend/ ./

# Download the 8 A/B-grade voices from HuggingFace Hub
# (patch-kokoro.js makes kokoro resolve: process.cwd()/../voices/ = /app/voices/)
RUN mkdir -p /app/voices && \
    for voice in af_heart af_bella af_nicole am_fenrir am_michael am_puck bf_emma bm_george; do \
      wget -q -O /app/voices/${voice}.bin \
        "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/${voice}.bin"; \
    done

# Copy built frontend for static serving
COPY --from=frontend-builder /app/frontend/dist /app/frontend/dist

# Pre-download ONNX model into image layer (avoids slow cold-start download)
RUN node scripts/download-model.mjs

EXPOSE 7860
ENV PORT=7860
ENV NODE_ENV=production

CMD ["node", "server.js"]
