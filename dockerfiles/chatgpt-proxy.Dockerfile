# Reference Dockerfile for chatgpt-openai-proxy (currently a systemd venv service,
# no GitHub remote). Place in that repo, or build+push from the VM with
# scripts/push-from-vm.sh. Runs as uid 1000; reads Codex OAuth from CODEX_HOME.
FROM python:3.13-slim

RUN useradd --create-home --uid 1000 app
WORKDIR /app

COPY requirements.txt* pyproject.toml* uv.lock* ./
RUN pip install --no-cache-dir -e . 2>/dev/null || pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chown -R app:app /app
USER app
ENV CODEX_HOME=/home/app/.codex HOST=0.0.0.0 PORT=8765
EXPOSE 8765
CMD ["python", "-m", "chatgpt_proxy.server"]
