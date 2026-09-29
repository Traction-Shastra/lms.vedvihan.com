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

if [ -d "${BENCH_DIR}/apps/frappe" ]; then
    echo "Bench already exists."
    cd "${BENCH_DIR}"
else
    echo "Creating new bench..."
    rm -rf "${BENCH_DIR}"
    bench init --skip-redis-config-generation frappe-bench
    cd "${BENCH_DIR}"

    bench set-mariadb-host "${DB_HOST}"

    bench set-redis-cache-host "redis://${REDIS_HOST}:${REDIS_PORT}"
    bench set-redis-queue-host "redis://${REDIS_HOST}:${REDIS_PORT}"
    bench set-redis-socketio-host "redis://${REDIS_HOST}:${REDIS_PORT}"

    # redis + watch run in separate containers in the official architecture;
    # here they are unused, so drop them from the Procfile.
    sed -i '/redis/d' ./Procfile
    sed -i '/watch/d' ./Procfile

    if [ ! -d "apps/payments" ]; then
        echo "Installing payments..."
        bench get-app https://github.com/frappe/payments.git --branch develop
    fi

    if [ ! -d "apps/lms" ]; then
        echo "Installing Traction-Shastra LMS fork..."
        bench get-app https://github.com/Traction-Shastra/lms.vedvihan.com.git --branch develop
    fi
fi

if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo "Creating Frappe site ${SITE_NAME}..."
    bench new-site "${SITE_NAME}" \
        --db-type mariadb \
        --db-name "${DB_NAME}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT}" \
        --admin-password "${ADMIN_PASSWORD}" \
        --no-mariadb-socket

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
