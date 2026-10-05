#!/usr/bin/env bash
# Crée le client de démonstration « camille » (comptes, prêt, bénéficiaire, accès mobile).
# Usage : sudo ./demo-local.sh [mot-de-passe-du-client]
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
PASSWORD=${1:-Demo-Banque-2026}
python3 scripts/seed_demo.py \
  --fineract "http://127.0.0.1/fineract-provider/api/v1" \
  --admin-user mifos --admin-password "${MIFOS_PASSWORD:-password}" \
  --keycloak-url "http://127.0.0.1:8081" \
  --keycloak-admin "$KEYCLOAK_ADMIN" --keycloak-password "$KEYCLOAK_ADMIN_PASSWORD" \
  --username camille --password "$PASSWORD" ${DEMO_NO_OTP:+--no-otp}
echo
echo "Client de démo : identifiant « camille », mot de passe « $PASSWORD »."
if [[ -z "${DEMO_NO_OTP:-}" ]]; then
  echo "1re étape : ouvrez http://${SERVER_IP}:8081/realms/godafret/account sur le téléphone,"
  echo "connectez-vous et scannez le QR code avec Google Authenticator / FreeOTP."
  echo "(Pour tester sans OTP : sudo DEMO_NO_OTP=1 ./demo-local.sh)"
fi
