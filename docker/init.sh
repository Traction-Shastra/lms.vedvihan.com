#!/bin/bash

set -e

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

SITE_NAME="${FRAPPE_SITE_NAME:-lms.vedvihan.com}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_DATABASE:-lms_vedvihan}"
DB_USER="${DB_USERNAME:-lms_vedvihan_user}"
DB_PASSWORD="${DB_PASSWORD}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
BENCH_DIR="/home/frappe/frappe-bench"

echo "=========================================="
echo "Frappe LMS initialization"
echo "=========================================="
echo "Site:        ${SITE_NAME}"
echo "Database:    ${DB_NAME}"
echo "DB host:     ${DB_HOST}:${DB_PORT}"
echo "Redis host:  ${REDIS_HOST}:${REDIS_PORT}"
echo "=========================================="

if [ ! -f "${BENCH_DIR}/apps/frappe/frappe/__init__.py" ]; then
    echo "ERROR: no bench at ${BENCH_DIR}"
    echo "Run this once on the host first:  bash docker/bootstrap.sh"
    exit 1
fi

cd "${BENCH_DIR}"

# Idempotent: rewrites common_site_config.json and strips the redis/watch
# entries we run as separate processes (or not at all) here.
bench set-mariadb-host "${DB_HOST}"
bench set-redis-cache-host "redis://${REDIS_HOST}:${REDIS_PORT}"
bench set-redis-queue-host "redis://${REDIS_HOST}:${REDIS_PORT}"
bench set-redis-socketio-host "redis://${REDIS_HOST}:${REDIS_PORT}"

sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

if [ ! -d "apps/payments" ]; then
    echo "Installing payments..."
    bench get-app payments https://github.com/frappe/payments.git --branch develop
fi

if [ ! -d "apps/lms" ]; then
    echo "Installing Traction-Shastra LMS fork..."
    # bench derives the app directory from the repo URL, and this fork is not
    # named "lms". Stage it under the right name so get-app resolves apps/lms.
    rm -rf apps/lms.vedvihan.com /tmp/lms
    git clone --branch develop --depth 1 https://github.com/Traction-Shastra/lms.vedvihan.com.git /tmp/lms
    bench get-app /tmp/lms
    # get-app points `upstream` at the local staging path; put the real fork back.
    git -C apps/lms remote set-url upstream https://github.com/Traction-Shastra/lms.vedvihan.com.git
    rm -rf /tmp/lms
fi

# site_config.json is written before new-site touches the database, so a
# failed install leaves it behind and the next restart would "migrate" an
# empty DB. Decide from the database instead. A query failure (DB down,
# bad password) exits so the container retries rather than reinstalls.
# No root anywhere: the shared MariaDB's root is not reachable from other
# containers, so the DB and its user are provisioned by hand beforehand.
FRAPPE_TABLES=$(MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u"${DB_USER}" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='tabDefaultValue'")

if [ "${FRAPPE_TABLES}" = "1" ] && [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo "ERROR: ${DB_NAME} holds a Frappe install but sites/${SITE_NAME} is missing."
    echo "Refusing to reinstall over it. Restore the site folder or drop the DB by hand."
    exit 1
fi

if [ "${FRAPPE_TABLES}" != "1" ]; then
    echo "Creating Frappe site ${SITE_NAME}..."
    # Leftovers from a failed attempt: the site folder blocks new-site, and
    # a half-bootstrapped schema would collide. The app user's grant on
    # ${DB_NAME}.* is enough to recreate its own database.
    rm -rf "sites/${SITE_NAME}"
    MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u"${DB_USER}" -e \
        "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    # --no-setup-db: skip Frappe's CREATE USER / CREATE DATABASE, which
    # need root, and only bootstrap the schema into the existing DB.
    bench new-site "${SITE_NAME}" \
        --no-setup-db \
        --db-type mariadb \
        --db-name "${DB_NAME}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT}" \
        --admin-password "${ADMIN_PASSWORD}"

    echo "Installing payments..."
    bench --site "${SITE_NAME}" install-app payments

    echo "Installing LMS..."
    bench --site "${SITE_NAME}" install-app lms

    bench --site "${SITE_NAME}" set-config host_name "https://${SITE_NAME}"
    bench --site "${SITE_NAME}" set-config developer_mode 0
    bench --site "${SITE_NAME}" clear-cache
else
    echo "Site already exists, running migrate..."
    bench --site "${SITE_NAME}" migrate
    bench --site "${SITE_NAME}" clear-cache
fi

bench use "${SITE_NAME}"

echo "=========================================="
echo "Starting Frappe"
echo "=========================================="

exec bench start
