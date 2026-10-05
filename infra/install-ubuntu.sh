#!/usr/bin/env bash
# Installation de GodaFret Banque sur Ubuntu Server 22.04 / 24.04.
# Usage : sudo ./install-ubuntu.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Lancez ce script avec sudo." >&2
  exit 1
fi

cd "$(dirname "$0")"

echo "==> Mise à jour du système"
apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg ufw fail2ban unattended-upgrades

echo "==> Installation de Docker Engine + Compose"
if ! command -v docker >/dev/null; then
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

echo "==> Pare-feu : SSH, HTTP, HTTPS uniquement"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Mises à jour de sécurité automatiques + fail2ban"
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now fail2ban

if [[ ! -f .env ]]; then
  cp .env.example .env
  chmod 600 .env
  echo
  echo "Fichier .env créé. Renseignez vos domaines et mots de passe :"
  echo "  nano $(pwd)/.env"
  echo "puis relancez : sudo ./install-ubuntu.sh"
  exit 0
fi

if grep -q "change-me" .env; then
  echo "Le fichier .env contient encore des valeurs « change-me »." >&2
  exit 1
fi

echo "==> Démarrage des services"
docker compose pull
docker compose up -d

echo
echo "Services démarrés. Fineract met 2 à 4 minutes à initialiser la base au premier lancement :"
echo "  docker compose logs -f fineract"
echo
set -a; . ./.env; set +a
echo "  API mobile    : https://${BANK_API_DOMAIN}/fineract-provider/api/v1"
echo "  Mifos X       : https://${ADMIN_DOMAIN}  (utilisateur mifos / password — À CHANGER IMMÉDIATEMENT)"
echo "  Keycloak      : https://${AUTH_DOMAIN}/realms/godafret/account"
echo "  Admin Keycloak: tunnel SSH  ssh -L 8081:localhost:8081 <serveur>  puis http://localhost:8081/admin"
