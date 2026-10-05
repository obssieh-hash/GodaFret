#!/usr/bin/env bash
# Installation de GodaFret Banque sur un serveur Ubuntu du RÉSEAU LOCAL (sans nom de domaine).
# Usage : sudo ./install-local.sh            (détecte l'IP du serveur)
#         sudo ./install-local.sh 192.168.1.50
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Lancez ce script avec sudo : sudo ./install-local.sh" >&2
  exit 1
fi
cd "$(dirname "$0")"

SERVER_IP=${1:-$(hostname -I | awk '{print $1}')}
if [[ -z "$SERVER_IP" ]]; then
  echo "Impossible de détecter l'IP. Relancez avec : sudo ./install-local.sh <IP>" >&2
  exit 1
fi
echo "==> Adresse du serveur : $SERVER_IP"

echo "==> Paquets système"
apt-get update -y
apt-get install -y ca-certificates curl gnupg ufw python3 openssl

if ! command -v docker >/dev/null; then
  echo "==> Installation de Docker"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

if [[ ! -f .env ]]; then
  echo "==> Génération de .env (mots de passe aléatoires)"
  pw() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }
  cat > .env <<ENV
# Généré par install-local.sh le $(date -Is)
COMPOSE_FILE=docker-compose.yml:docker-compose.lan.yml
SERVER_IP=${SERVER_IP}
BANK_API_DOMAIN=${SERVER_IP}
ADMIN_DOMAIN=${SERVER_IP}
AUTH_DOMAIN=${SERVER_IP}:8081
ACME_EMAIL=admin@localhost
POSTGRES_SUPERUSER_PASSWORD=$(pw)
FINERACT_DB_PASSWORD=$(pw)
KEYCLOAK_DB_PASSWORD=$(pw)
FINERACT_TENANT=default
FINERACT_TIMEZONE=Europe/Paris
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(pw)
ENV
  chmod 600 .env
else
  # Met à jour l'IP si le serveur a changé d'adresse.
  sed -i "s/^SERVER_IP=.*/SERVER_IP=${SERVER_IP}/; s/^BANK_API_DOMAIN=.*/BANK_API_DOMAIN=${SERVER_IP}/; s/^ADMIN_DOMAIN=.*/ADMIN_DOMAIN=${SERVER_IP}/; s/^AUTH_DOMAIN=.*/AUTH_DOMAIN=${SERVER_IP}:8081/" .env
fi

echo "==> Pare-feu UFW : SSH + ports de la banque depuis le réseau local"
# NB : Docker publie ses ports en contournant UFW ; le serveur doit rester derrière la box.
LAN=$(ip -o -f inet addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $4}' | head -1)
LAN_NET=$(python3 -c "import ipaddress,sys;print(ipaddress.ip_interface(sys.argv[1]).network)" "${LAN:-$SERVER_IP/24}")
ufw allow OpenSSH
for port in 80 8081 8082; do ufw allow from "$LAN_NET" to any port "$port" proto tcp; done
ufw --force enable

echo "==> Téléchargement des images et démarrage (plusieurs minutes la première fois)"
docker compose pull
docker compose up -d

echo "==> Attente de Fineract (création de la base au premier démarrage : 2 à 5 min)"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -u mifos:password -H 'Fineract-Platform-TenantId: default' \
    "http://127.0.0.1/fineract-provider/api/v1/offices" || true)
  [[ "$code" == "200" || "$code" == "401" ]] && break
  sleep 10
done
for i in $(seq 1 60); do
  curl -sf -o /dev/null "http://127.0.0.1:8082/fineract-provider/actuator/health" && break
  sleep 10
done

set -a; . ./.env; set +a

echo "==> Keycloak : autorise HTTP (réseau local sans certificat)"
for i in $(seq 1 30); do
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" \
    --config /tmp/kcadm.config >/dev/null 2>&1 && break
  sleep 5
done
for realm in master godafret; do
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "realms/$realm" -s sslRequired=NONE --config /tmp/kcadm.config
done

cat <<MSG

==============================================================
 GodaFret Banque est démarrée sur http://${SERVER_IP}
==============================================================
 Mifos X (back-office)  : http://${SERVER_IP}
     utilisateur mifos / mot de passe « password »  → À CHANGER tout de suite
 Keycloak (admin)       : http://${SERVER_IP}:8081/admin
     utilisateur ${KEYCLOAK_ADMIN} / mot de passe : ${KEYCLOAK_ADMIN_PASSWORD}
 Espace sécurité client : http://${SERVER_IP}:8081/realms/godafret/account
 Application mobile     : adresse du serveur à saisir = ${SERVER_IP}

 Données de démonstration (client « camille ») :
   sudo ./demo-local.sh
 Les mots de passe sont dans $(pwd)/.env
==============================================================
MSG
