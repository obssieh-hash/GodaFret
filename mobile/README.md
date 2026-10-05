# GodaFret Banque — application mobile Flutter

Application bancaire mobile (Android, iOS, web) branchée sur **Apache Fineract**, avec
authentification **Keycloak + MFA (TOTP)** et code PIN local.

| Fonction | Écran | API Fineract |
|---|---|---|
| 🔐 Connexion + PIN | Connexion → OTP → création du PIN, verrouillage auto, biométrie | Keycloak `/token` |
| 🔑 MFA / OTP | Code TOTP (Keycloak) ou code e-mail/SMS (2FA Fineract) | `/twofactor` |
| 👤 Profil | Identité, agence, préférences, thème clair/sombre | `GET /clients/{id}` |
| 💰 Solde | Accueil, Comptes, détail d'un compte | `GET /clients/{id}/accounts`, `/savingsaccounts/{id}` |
| ➕ Dépôt / ➖ Retrait | Montant, compte, moyen de paiement (retrait validé par PIN) | `POST /savingsaccounts/{id}/transactions` |
| 💸 Transfert interne | Vers mes comptes ou un bénéficiaire (n° de compte vérifié) | `GET /search`, `POST /accounttransfers` |
| 💳 Demande de prêt | Produit, curseurs montant/durée, simulation en direct | `POST /loans?command=calculateLoanSchedule`, `POST /loans` |
| 📅 Échéancier | Anneau de progression, échéances payées / à venir / en retard | `GET /loans/{id}?associations=repaymentSchedule` |
| 💵 Remboursement | Échéance, impayés ou solde total (validé par PIN) | `POST /loans/{id}/transactions?command=repayment` |
| 📜 Historique | Groupé par jour, recherche, filtres | transactions épargne + prêts |
| 🔔 Notifications | Non lues, « tout lire » | `GET/PUT /notifications` |
| 📊 Tableau de bord | Solde total, encours, flux 6 mois, taux d'épargne, prochaine échéance | — |

## Lancer en mode démo (sans serveur)

```bash
flutter pub get
flutter run                 # identifiant/mot de passe quelconques, code OTP 123456
```

## Brancher sur votre serveur

```bash
flutter run --release \
  --dart-define=AUTH_MODE=keycloak \
  --dart-define=FINERACT_URL=https://api.banque.example.com/fineract-provider/api/v1 \
  --dart-define=KEYCLOAK_URL=https://auth.banque.example.com \
  --dart-define=KEYCLOAK_REALM=godafret
```

| Variable | Défaut | Rôle |
|---|---|---|
| `AUTH_MODE` | `demo` | `demo`, `keycloak` (recommandé) ou `fineract` (Basic + 2FA Fineract) |
| `FINERACT_URL` | `http://localhost:8082/...` | API de l'instance Fineract « mobile » |
| `FINERACT_TENANT` | `default` | tenant Fineract |
| `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID` | `…:8081`, `godafret`, `godafret-mobile` | Keycloak |
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
