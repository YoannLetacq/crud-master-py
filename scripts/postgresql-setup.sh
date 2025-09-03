#!/bin/bash
set -euo pipefail
set -a 
source .env
set +a

echo "Starting postgreSQL installation and set up..."

# update packages
apt update -y 

# install PostgreSQL
if psql --version >/dev/null 2>&1; then 
    echo "PostgreSQL is already present : $(psql --version)"
else
    echo "Installing PostgreSQl..."
    apt install -y postgresql 
    echo " PostgreSQL installed."

    # install postgre-contrib (extensions and additions)
    apt install -y postgresql-contrib
fi 

# save the version installed
PG_version=$(psql -V | awk '{print $3}' | cut -d '.' -f1)


# Delete default cluster
if pg_lsclusters | awk '{print $1, $2}' | grep -q "^${PG_version} main$"; then 
    echo "Deletion of existing clusters..."
    pg_dropcluster --stop ${PG_version} main
fi


# stop postgre before set up
if systemctl is-active --quiet postgresql; then 
    echo "PostgreSQL service is running, stopping it now..."
    systemctl stop postgresql
    echo "PostgreSQL service correctly stopped."
else 
    echo "PostgreSQL service already stopped."
fi

# Reconstruc the postgreSQL cluster
echo "Reconstructing the cluster..."

# Create cluster 
echo "Creating new cluster..."
pg_createcluster ${PG_version} main --start
if ! pg_lsclusters | awk '$1 == "'${PG_version}'" && $2 == "main" {found=1} END{exit !found}'; then
    echo "Cluster creation failed!"
    exit 1
fi


PG_conf_dir="/etc/postgresql/${PG_version}/main"

# Enable public access
if ! grep -q "listen_addresses='*'" "${PG_conf_dir}/postgresql.conf"; then
    echo "listen_addresses='*'" >> "${PG_conf_dir}/postgresql.conf"
fi

# enable public access
if ! grep -q "host  all  all  0.0.0.0/0  md5" "${PG_conf_dir}/pg_hba.conf"; then
    echo "host  all  all  0.0.0.0/0  md5" >> "${PG_conf_dir}/pg_hba.conf"
fi

echo "Cluster recreate successfully and correctly reconfigure."

# restart postgre server after configuration
systemctl restart postgresql
if systemctl is-active --quiet postgresql; then
    echo "PostgreSQL correctly running."
else
    echo "Something has gone wrong, PostgreSQL not running."
    exit 1
fi

# Setup the database and user
sudo -u postgres psql -d postgres <<EOF
DO
\$body\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
      CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
   END IF;
END
\$body\$;
EOF

echo "Database and user setup complete!"
