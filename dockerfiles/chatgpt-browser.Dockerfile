# Dockerfile for chatgpt-browser-bridge (headless ChatGPT web -> OpenAI).
# Self-contained: installs playwright + chromium so versions always match.
# Browsers go to a world-readable path so the non-root runtime user can use them.
FROM python:3.13-slim

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN pip install --no-cache-dir playwright fastapi "uvicorn[standard]" \
    && playwright install --with-deps chromium \
    && chmod -R a+rx /ms-playwright

RUN useradd --create-home --uid 1000 app
WORKDIR /app
COPY browser_backend.py .
RUN chown -R app:app /app
USER app

# browser_backend.py reads BROWSER_HOST/BROWSER_PORT/HEADLESS/STATE from env.
ENV BROWSER_HOST=0.0.0.0 BROWSER_PORT=8766 HEADLESS=1 STATE=/state/chatgpt-state.json
EXPOSE 8766
CMD ["python", "browser_backend.py"]
