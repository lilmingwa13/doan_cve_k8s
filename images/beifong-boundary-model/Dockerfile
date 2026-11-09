# Deliberately vulnerable teaching model derived from the Beifong source tree.
# The filename routes accept multi-segment paths so the existing unsafe
# os.path.join primitive can be exercised with a local, non-sensitive canary.
# Do not label this image as an unmodified upstream build.
FROM node:22-bookworm-slim AS frontend
WORKDIR /web
COPY sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/web/package.json sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/web/package-lock.json ./
RUN npm ci --legacy-peer-deps --no-audit --no-fund
COPY sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/web/public ./public
COPY sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/web/src ./src
COPY images/beifong-frontend/prepare.cjs /tmp/prepare.cjs
COPY images/beifong-frontend/tailwind-input.css ./tailwind-input.css
RUN node /tmp/prepare.cjs \
    && mkdir -p ./public/static \
    && ./node_modules/.bin/tailwindcss -i ./tailwind-input.css -o ./public/static/lab-tailwind.css --minify \
    && CI=false npm run build \
    && test -s ./build/index.html

FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    CLIENT_BUILD_PATH=/app/web/build
WORKDIR /app
COPY sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/beifong/requirements.txt /tmp/beifong-requirements.txt
RUN grep -Ev '^(torch|nvidia-|triton|sentence-transformers|transformers|tokenizers|safetensors|spacy|thinc|curated-|kokoro|misaki|phonemizer|espeakng-loader|mem0ai)' /tmp/beifong-requirements.txt > /tmp/beifong-lab-requirements.txt \
    && pip install --no-cache-dir -r /tmp/beifong-lab-requirements.txt
COPY sources/awesome-llm-apps/advanced_ai_agents/multi_agent_apps/ai_news_and_podcast_agents/beifong/ /app/
COPY --from=frontend /web/build/ /app/web/build/
COPY images/beifong-frontend/seed_demo.py /app/seed_demo.py
RUN mkdir -p /app/podcasts/audio /app/podcasts/images /app/podcasts/recordings \
    && printf 'LAB_AUDIO_BASELINE\n' > /app/podcasts/audio/demo-audio.txt
EXPOSE 7000
CMD ["sh", "-c", "python /app/seed_demo.py && exec python /app/main.py"]
