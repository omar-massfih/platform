# Dockerfile for chatgpt-openai-proxy (systemd venv service, no GitHub remote).
# Build+import into k3s containerd, or push to ghcr via scripts/push-from-vm.sh.
# Runs as uid 1000; reads Codex OAuth from CODEX_HOME (mounted codex-auth PVC).
FROM python:3.13-slim

RUN useradd --create-home --uid 1000 app
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir .

USER app
# config.py reads PROXY_HOST/PROXY_PORT/CODEX_HOME (defaults 127.0.0.1:8765,~/.codex)
ENV CODEX_HOME=/home/app/.codex PROXY_HOST=0.0.0.0 PROXY_PORT=8765
EXPOSE 8765
CMD ["chatgpt-openai-proxy"]
