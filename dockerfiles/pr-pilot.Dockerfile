# Dockerfile for pr-pilot (both instances run this image). Bundles pr-pilot
# (editable), the opencode binary, git and gh. Home is /home/omar so the config
# tomls' absolute paths (/home/omar/...) and ~ expansions line up with the PVC mounts.
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# gh CLI (arm64 binary)
RUN curl -fsSL https://github.com/cli/cli/releases/download/v2.63.0/gh_2.63.0_linux_arm64.tar.gz \
      | tar xz -C /tmp \
    && cp /tmp/gh_*/bin/gh /usr/local/bin/ && rm -rf /tmp/gh_*

# opencode standalone binary → shared path readable by the runtime user
RUN curl -fsSL https://opencode.ai/install | bash \
    && cp /root/.opencode/bin/opencode /usr/local/bin/opencode \
    && chmod a+rx /usr/local/bin/opencode

RUN useradd --create-home --uid 1000 --home-dir /home/omar omar
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -e . && chown -R omar:omar /app /home/omar

# Entrypoint: configure git identity + gh credential helper (uses GH_TOKEN), then run.
RUN printf '%s\n' '#!/bin/sh' 'set -e' \
    'git config --global user.name "${GIT_AUTHOR_NAME:-pr-pilot}"' \
    'git config --global user.email "${GIT_AUTHOR_EMAIL:-pr-pilot@users.noreply.github.com}"' \
    'git config --global --add safe.directory "*"' \
    'gh auth setup-git 2>/dev/null || true' \
    'exec pr-pilot "$@"' > /usr/local/bin/entrypoint.sh \
    && chmod a+rx /usr/local/bin/entrypoint.sh

USER omar
WORKDIR /home/omar
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["telegram"]
