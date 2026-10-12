# Golden Bridge Bank — serveur et console des agences (Ubuntu Server)

Côté banque : **Golden Bridge Bank** (Fineract + console Mifos X aux couleurs de la banque +
connexion Keycloak). Côté clients : l'application mobile **Golden Bridge Pay** (`../mobile`).

Pile recommandée : **Apache Fineract** (cœur bancaire) · **Mifos X** (back-office) ·
**PostgreSQL** · **Keycloak + MFA** · **Caddy** (HTTPS automatique), le tout en Docker Compose.

```
                    ┌──────────── Caddy (443, Let's Encrypt) ────────────┐
 App mobile ──────► │ api.…   → fineract-mobile (jetons Keycloak uniquement)│
 Agents agence ───► │ admin.… → Mifos X web-app + fineract (Basic)        │
 Clients (MFA) ───► │ auth.…  → Keycloak (console admin non exposée)       │
                    └──────────────────────────┬─────────────────────────┘
                                               ▼
                      PostgreSQL : fineract_tenants, fineract_default, keycloak
```

### Pourquoi deux instances Fineract ?

Dans la version actuelle de Fineract, lorsque *OIDC Federation* est activée, sa chaîne de sécurité
traite toutes les requêtes `/api/**` et n'accepte plus que les jetons Bearer : l'authentification
Basic utilisée par Mifos X ne passe plus. On fait donc tourner deux instances sur **la même base** :

- `fineract` : Basic, pour Mifos X ; applique les migrations et exécute les traitements batch ;
- `fineract-mobile` : n'accepte que les jetons Keycloak ; batch désactivé.

Elle nécessite aussi `SPRING_MAIN_ALLOW_CIRCULAR_REFERENCES=true` (bug de dépendance circulaire
au démarrage avec OIDC). Les deux points ont été vérifiés avec l'image `apache/fineract:latest`.

## Installation

> Serveur du **réseau local, sans nom de domaine** : suivez [`../INSTALLATION-LOCALE.md`](../INSTALLATION-LOCALE.md)
> (`install-local.sh` + `docker-compose.lan.yml`). La procédure ci-dessous concerne un serveur public avec HTTPS.

Pré-requis : Ubuntu Server 22.04/24.04, 4 vCPU, 8 Go de RAM, 3 enregistrements DNS vers le serveur.

```bash
sudo git clone https://github.com/obssieh-hash/GodaFret /opt/golden-bridge
cd /opt/golden-bridge/infra
sudo ./install-ubuntu.sh       # Docker, pare-feu UFW, fail2ban, mises à jour auto ; crée .env
sudo nano .env                 # domaines + mots de passe (openssl rand -base64 32)
sudo ./install-ubuntu.sh       # démarre la pile
```

Au premier démarrage Fineract crée la base (2 à 4 min) : `docker compose logs -f fineract`.

**Immédiatement** : connectez-vous à Mifos X (`mifos` / `password`) et changez ce mot de passe.

## Ouvrir l'accès mobile à un client

1. **Mifos X** : créer le client, renseigner son **External Id** = son identifiant de connexion,
   ouvrir et activer ses comptes.
2. **Mifos X › Admin › Utilisateurs** : créer un utilisateur du même identifiant, rôle
   **« Client mobile »** (mot de passe aléatoire : la connexion passe par Keycloak).
3. **Keycloak** (tunnel `ssh -L 8081:localhost:8081 serveur`, puis http://localhost:8081/admin) :
   royaume `goldenbridge` › Utilisateurs › créer le même identifiant, définir un mot de passe.
   Facultatif : attribut `fineract_client_id` = id du client (sinon l'External Id est utilisé).
4. Le client se connecte une première fois sur `https://auth…/realms/goldenbridge/account` pour
   **enregistrer son application d'authentification** (TOTP obligatoire, action par défaut du royaume).
   Ensuite il se connecte dans l'application : mot de passe + code OTP, puis crée son PIN.

Le script `scripts/seed_demo.py` fait tout cela automatiquement pour un client de démonstration
(produits, comptes, prêt décaissé, bénéficiaire, rôle, utilisateurs Fineract et Keycloak) :

```bash
python3 scripts/seed_demo.py --fineract http://localhost:8080/fineract-provider/api/v1 \
  --admin-password '<mot de passe mifos>' --password '<mot de passe du client>' \
  --keycloak-url http://localhost:8081 --keycloak-password '<admin keycloak>'
```

(Pour l'exécuter, publiez temporairement le port 8080 de `fineract` sur `127.0.0.1`.)

Rôle « Client mobile » : `READ_CLIENT`, `READ_SAVINGSACCOUNT`, `READ_LOAN`, `READ_LOANPRODUCT`,
`READ_ACCOUNTTRANSFER`, `CREATE_ACCOUNTTRANSFER`, `CREATE_LOAN`, `CREATE_LOANNOTE`.
Pas de dépôt ni de retrait direct : un client ne peut pas créditer son propre compte (testé : HTTP 403).
Les espèces passent par un agent ou le guichet ; envoyer, payer, retirer chez un agent et rembourser
un prêt sont des virements entre comptes.

## Personnalisation Golden Bridge Bank

| Élément | Fichier |
|---|---|
| Logos (clair, foncé, icône) et image d'accueil des agences | `branding/` |
| Console des agences (Mifos X) : nom, logos, couleurs | `docker-compose.yml` (service `mifos-web-app`) + `branding/mifos-golden-bridge.css` |
| Page de connexion Keycloak | `keycloak/themes/goldenbridge/` |
| Royaume, client `gbpay-mobile`, MFA, langue | `keycloak/goldenbridge-realm.json` |

Le royaume est importé au **premier** démarrage seulement. Si vous aviez installé l'ancienne
version (royaume `godafret`), repartez d'une base vide : `sudo docker compose down -v` puis
`sudo bash install-local.sh` (⚠️ efface toutes les données).

## ⚠️ Limite à connaître avant la production

Fineract contrôle des **permissions**, pas la **propriété** des données : un utilisateur qui a
`READ_CLIENT` peut lire *n'importe quel* client via l'API, et `DEPOSIT_SAVINGSACCOUNT` s'applique à
tout compte. L'ancien module « self-service » qui limitait l'accès aux comptes du client n'existe
plus dans Fineract. Avant d'ouvrir le service à de vrais clients, placez entre l'application et
`fineract-mobile` une **passerelle (BFF)** qui vérifie que chaque compte demandé appartient bien au
client du jeton, et réservez les dépôts aux canaux réellement encaissés (agent, mobile money).

## Exploitation

| Tâche | Commande |
|---|---|
| État | `docker compose ps` |
| Journaux | `docker compose logs -f fineract-mobile` |
| Mise à jour | `docker compose pull && docker compose up -d` |
| Sauvegarde | `./backup.sh` (cron conseillé : `30 2 * * *`), copiez `/var/backups/golden-bridge` hors du serveur |
| Restauration | `docker compose exec -T postgres pg_restore -U postgres -d <base> --clean < fichier.dump` |

## Tester toute la chaîne en local

```bash
cd infra && cp .env.example .env    # mots de passe quelconques
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d postgres keycloak fineract fineract-mobile
python3 scripts/seed_demo.py --password 'Demo-Banque-2026' \
  --keycloak-url http://localhost:8081 --keycloak-password '<KEYCLOAK_ADMIN_PASSWORD>' --no-otp
cd ../mobile && LIVE_FINERACT=1 flutter test test/live
```

Sur un émulateur Android, redirigez les ports pour que le jeton soit émis pour `localhost:8081`
(l'issuer attendu par `fineract-mobile`) :

```bash
adb reverse tcp:8081 tcp:8081 && adb reverse tcp:8082 tcp:8082
flutter run --dart-define=AUTH_MODE=keycloak \
  --dart-define=KEYCLOAK_URL=http://localhost:8081 \
  --dart-define=FINERACT_URL=http://localhost:8082/fineract-provider/api/v1
```
