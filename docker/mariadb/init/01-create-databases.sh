#!/bin/bash
# Runs once, on the very first start of the mariadb container (empty data volume).
# MARIADB_DATABASE only creates the dragonite DB; this adds the golbat and koji DBs
# and gives the application user access to all of them (Unown# docs: one database
# for Dragonite, one for Golbat; Koji needs its own as well).
set -euo pipefail

dragonite_db="${MARIADB_DATABASE:-dragonite}"
golbat_db="${GOLBAT_DB_NAME:-golbat}"
koji_db="${KOJI_DB_NAME:-koji}"

echo "[init] databases: '${dragonite_db}' (exists), '${golbat_db}', '${koji_db}' for user '${MARIADB_USER}'"

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
ALTER DATABASE \`${dragonite_db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`${golbat_db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`${koji_db}\`   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${golbat_db}\`.* TO '${MARIADB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${koji_db}\`.*   TO '${MARIADB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
