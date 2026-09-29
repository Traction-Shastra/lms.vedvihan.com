#!/usr/bin/env bash
# One-time bootstrap.
#
# Why this exists: a Python venv hardcodes absolute shebangs and editable-install
# paths, so the bench cannot be built at one path and moved to another. It has to
# be created at /home/frappe/frappe-bench and stay there. We build it in a
# throwaway container with no volume, then copy it out to ./frappe-bench, which
# compose bind-mounts back over the same path.
#
# Only needed on a fresh machine. After this, docker-compose.yml + init.sh
# handle everything.

set -euo pipefail
cd "$(dirname "$0")/.."

NAME=lms-vedvihan-init

docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "==> Building bench (20-40 min, needs internet)"
docker run --name "$NAME" \
    -e SHELL=/bin/bash \
    frappe/bench:latest \
    bash -lc '
        set -e
        export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"
        bench init --skip-redis-config-generation /home/frappe/frappe-bench
        cd /home/frappe/frappe-bench
        bench get-app payments https://github.com/frappe/payments.git --branch develop
        bench get-app lms https://github.com/Traction-Shastra/lms.vedvihan.com.git --branch develop
    '

echo "==> Copying out to ./frappe-bench"
mkdir -p frappe-bench
docker cp "$NAME":/home/frappe/frappe-bench/. frappe-bench/
docker rm "$NAME" >/dev/null

chown -R 1000:1000 frappe-bench

echo "==> Done. Next: docker compose up -d"
