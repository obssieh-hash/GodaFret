#!/usr/bin/env bash
# Crée la cliente de démonstration « Fatouma » (tél. 77101010) avec contact, marchand et agent.
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
  --username "${DEMO_USER:-77101010}" --password "$PASSWORD" ${DEMO_NO_OTP:+--no-otp}
echo
echo "Cliente de démo : téléphone « ${DEMO_USER:-77101010} », mot de passe « $PASSWORD »."
echo "Contacts : Ahmed 77202020 · marchand 21350001 · agent 77990001"
if [[ -z "${DEMO_NO_OTP:-}" ]]; then
  echo "1re étape : ouvrez http://${SERVER_IP}:8081/realms/goldenbridge/account sur le téléphone,"
  echo "connectez-vous (77101010) et scannez le QR code avec Google Authenticator / FreeOTP."
  echo "(Pour tester sans OTP : sudo DEMO_NO_OTP=1 ./demo-local.sh)"
fi
