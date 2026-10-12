# Golden Bridge Pay — application mobile (Flutter)

Le portefeuille mobile des clients de **Golden Bridge Bank**, branché sur **Apache Fineract**,
avec connexion **Keycloak + MFA (TOTP)** puis code PIN. Montants en **francs Djibouti (Fdj)**.

| Accueil | Ce que ça fait | API Fineract |
|---|---|---|
| 🔐 Connexion | n° de téléphone + mot de passe → code OTP → création du PIN ; ensuite PIN ou biométrie | Keycloak `/token` |
| 💰 Solde | solde disponible du portefeuille, masquable ; « Mes comptes » si plusieurs | `GET /clients/{id}/accounts` |
| 💸 Envoyer | vers un **n° de téléphone** (ou n° de compte), validé par PIN, reçu | `GET /search`, `POST /accounttransfers` |
| 🏪 Payer | paiement d'un marchand par son numéro | `POST /accounttransfers` |
| 📥 Recevoir | mon numéro + **QR code** à montrer | — |
| ➖ Retrait | retrait d'espèces **chez un agent** (virement vers l'agent qui remet le cash) | `POST /accounttransfers` |
| ➕ Dépôt | dépôt d'espèces chez un agent ou en agence (QR code / numéro) | fait par l'agent |
| 💳 Prêts | demande avec simulation, 📅 échéancier | `POST /loans?command=calculateLoanSchedule`, `POST /loans` |
| 💵 Rembourser | depuis le portefeuille | `POST /accounttransfers` (vers le prêt) |
| 📜 Historique · 🔔 Notifications · 👤 Profil · 🔑 Sécurité | | |

Navigation : 3 onglets (Accueil, Historique, Profil).

## Lancer en mode démo (sans serveur)

```bash
flutter pub get
flutter run                 # n'importe quel numéro/mot de passe, code OTP 123456
```

## Brancher sur votre serveur

```bash
flutter run --release \
  --dart-define=AUTH_MODE=keycloak \
  --dart-define=FINERACT_URL=https://api.goldenbridge.dj/fineract-provider/api/v1 \
  --dart-define=KEYCLOAK_URL=https://auth.goldenbridge.dj \
  --dart-define=KEYCLOAK_REALM=goldenbridge
```

| Variable | Défaut | Rôle |
|---|---|---|
| `AUTH_MODE` | `demo` | `demo`, `keycloak` (recommandé) ou `fineract` (Basic + 2FA Fineract) |
| `FINERACT_URL` | `http://localhost:8082/...` | API de l'instance Fineract « mobile » |
| `FINERACT_TENANT` | `default` | tenant Fineract |
| `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID` | `…:8081`, `goldenbridge`, `gbpay-mobile` | Keycloak |
| `CURRENCY` | `DJF` | devise affichée par défaut |
| `MFA_REQUIRED` | `true` | affiche l'étape OTP |
| `LOCK_AFTER_SECONDS` | `60` | verrouillage après passage en arrière-plan |
| `ALLOW_SELF_SIGNED` | `false` | certificat auto-signé accepté **en debug uniquement** |

Builds : `flutter build apk --release`, `flutter build appbundle`, `flutter build ipa`.

## Sécurité côté application

- Jetons et clé de session dans le Keychain / Keystore (`flutter_secure_storage`), jamais en clair.
- PIN à 6 chiffres : empreinte SHA-256 salée et itérée, comparaison à temps constant,
  PIN triviaux refusés, session effacée après 5 erreurs.
- Retrait, transfert, remboursement et demande de prêt revalidés par PIN ou biométrie.
- Verrouillage automatique en arrière-plan, montants masquables, `allowBackup=false` sur Android.

## Tests

```bash
flutter analyze
flutter test                                   # unitaires + parcours complet en mode démo
LIVE_FINERACT=1 flutter test test/live         # contre une vraie pile (voir ../infra/README.md)
```

## Architecture

```
lib/
  config/       configuration (--dart-define)
  core/         thème, formats français
  models/       Client, comptes, prêts, échéances, transactions (JSON Fineract)
  services/     API Fineract (dio), auth Keycloak / Fineract / démo, PIN, dépôt démo
  state/        SessionController (connexion → OTP → PIN → verrouillage), BankController
  ui/           écrans et composants
```
