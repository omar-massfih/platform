# Reference Dockerfile for chatgpt-browser-bridge (headless ChatGPT web -> OpenAI).
# Needs a real browser, so base on the Playwright image which bundles chromium +
# system libs. Confirm the app's listen port (assumed 8766) and entrypoint.
FROM mcr.microsoft.com/playwright/python:v1.49.0-noble

WORKDIR /app
COPY requirements.txt* pyproject.toml* ./
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || pip install --no-cache-dir -e .

COPY . .
ENV HOST=0.0.0.0 PORT=8766
EXPOSE 8766
CMD ["python", "browser_backend.py"]
