# Reference Dockerfile for pr-pilot. Bundles python + pr-pilot (editable install),
# the standalone opencode binary, git and gh. Both k8s Deployments (wakiru and
# omarmassfih) run this same image with different args/config/secrets.
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates gh \
    && rm -rf /var/lib/apt/lists/*

# opencode standalone binary (arm64)
RUN curl -fsSL https://opencode.ai/install | bash \
    && ln -s /root/.opencode/bin/opencode /usr/local/bin/opencode

RUN useradd --create-home --uid 1000 app
WORKDIR /app
COPY pyproject.toml uv.lock* ./
RUN pip install --no-cache-dir -e .
COPY . .

# opencode config pointing at the in-cluster proxy Service (was 127.0.0.1:8765).
# Provide opencode.json referencing http://chatgpt-proxy.platform.svc:8765/v1.
RUN mkdir -p /home/app/.config/opencode && chown -R app:app /app /home/app
USER app
ENTRYPOINT ["pr-pilot"]
CMD ["telegram"]
