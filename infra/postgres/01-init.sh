#!/bin/bash
# Crée les bases Fineract (tenants + tenant par défaut) et Keycloak.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER fineract WITH PASSWORD '${FINERACT_DB_PASSWORD}';
  CREATE DATABASE fineract_tenants OWNER fineract;
  CREATE DATABASE fineract_default OWNER fineract;

  CREATE USER keycloak WITH PASSWORD '${KEYCLOAK_DB_PASSWORD}';
  CREATE DATABASE keycloak OWNER keycloak;
EOSQL
