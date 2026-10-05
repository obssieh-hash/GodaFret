# Installer GodaFret Banque sur un serveur Ubuntu du réseau local

Ce guide installe la banque sur **un serveur Ubuntu chez vous / au bureau** (sans nom de domaine),
puis l'application sur un **téléphone Android connecté au même Wi-Fi**.

```
 Téléphone (même Wi-Fi) ──► http://IP:8081  Keycloak (connexion + code OTP)
                        ──► http://IP:8082  Fineract (API de l'application)
 Navigateur du PC       ──► http://IP       Mifos X (back-office : clients, comptes, prêts)
                                     │
                              PostgreSQL (données)
```

> ⚠️ Mode **réseau local de test** : le trafic est en HTTP non chiffré. Ne l'ouvrez pas sur
> Internet et n'y mettez pas de vrais clients. Pour la production, voir `infra/README.md`.

---

## Étape 0 — Ce qu'il faut

| | Minimum |
|---|---|
| Serveur | Ubuntu Server 22.04 ou 24.04, **4 cœurs, 8 Go de RAM**, 30 Go de disque, accès Internet |
| Réseau | le serveur et le téléphone sur le même réseau ; **IP fixe** pour le serveur (réservation DHCP dans la box) |
| PC (pour l'appli) | Windows / macOS / Linux avec [Flutter](https://docs.flutter.dev/get-started/install) et Android Studio |
| Téléphone | Android 7+ et une appli d'authentification (Google Authenticator, FreeOTP, Microsoft Authenticator) |

Trouver l'IP du serveur : `hostname -I` (ex. `192.168.1.50`). Dans la suite, remplacez `IP` par cette adresse.

---

## Étape 1 — Mettre le code sur le serveur

**Option A — avec git** (sur le serveur) :

```bash
sudo apt update && sudo apt install -y git
sudo git clone -b claude/flutter-banking-app-3xii1t https://github.com/obssieh-hash/GodaFret.git /opt/godafret
```

(Si le dépôt est privé, git demande votre identifiant GitHub et un *personal access token* comme mot de passe.)

**Option B — avec l'archive `godafret-banque.zip`** (depuis votre PC) :

```bash
scp godafret-banque.zip utilisateur@IP:~
ssh utilisateur@IP
sudo apt install -y unzip && sudo unzip ~/godafret-banque.zip -d /opt/godafret
```

---

## Étape 2 — Installer et démarrer la banque (une seule commande)

```bash
cd /opt/godafret/infra
sudo bash install-local.sh            # ou : sudo bash install-local.sh 192.168.1.50
```

Le script :
1. installe Docker et le pare-feu UFW (SSH + ports 80, 8081, 8082 autorisés depuis le réseau local) ;
2. crée le fichier `.env` avec des **mots de passe aléatoires** ;
3. télécharge et démarre PostgreSQL, Fineract (×2), Mifos X, Keycloak et Caddy ;
4. attend que tout soit prêt (5 à 10 min la première fois) et affiche les adresses et mots de passe.

Vérifier : `sudo docker compose ps` → tous les services `Up` / `healthy`.

> Docker publie ses ports en contournant UFW : la vraie protection est votre **box / routeur**.
> N'ouvrez ni ne redirigez les ports 80, 8081, 8082 vers Internet.

---

## Étape 3 — Sécuriser le back-office

1. Ouvrez **http://IP** sur le PC → Mifos X, connexion `mifos` / `password`.
2. Menu utilisateur (en haut à droite) → **Changer le mot de passe** (12 caractères min., majuscule,
   minuscule, chiffre, caractère spécial).
3. Notez le nouveau mot de passe, puis sur le serveur :
   ```bash
   echo "MIFOS_PASSWORD='VotreNouveauMotDePasse'" | sudo tee -a /opt/godafret/infra/.env
   ```

Le mot de passe administrateur **Keycloak** est dans `.env` (`KEYCLOAK_ADMIN_PASSWORD`) :
`sudo grep KEYCLOAK_ADMIN_PASSWORD /opt/godafret/infra/.env` — console : http://IP:8081/admin

---

## Étape 4 — Créer le client de démonstration

```bash
cd /opt/godafret/infra
sudo bash demo-local.sh                       # mot de passe du client : Demo-Banque-2026
# ou : sudo bash demo-local.sh 'MonMotDePasse-2026'
```

Cela crée « Camille Martin » : compte courant (2 500 €), livret (6 000 €), un prêt en cours,
un bénéficiaire (« Lucas », compte `000000003`) et ses accès Fineract + Keycloak.

**Activer le code OTP (obligatoire, une seule fois)** — sur le téléphone :
1. ouvrez **http://IP:8081/realms/godafret/account** ;
2. connectez-vous avec `camille` / `Demo-Banque-2026` ;
3. scannez le QR code avec votre appli d'authentification et saisissez le code affiché.

---

## Étape 5 — Construire l'application Android (sur votre PC)

```bash
# copiez le dossier « mobile » sur le PC (git clone ou archive), puis :
cd mobile
flutter pub get
flutter build apk --release --android-project-arg=allowCleartext=true
```

L'APK est dans `mobile/build/app/outputs/flutter-apk/app-release.apk`.
Copiez-le sur le téléphone (câble, Drive…) et installez-le (autorisez « sources inconnues »).

> `allowCleartext=true` autorise le HTTP du réseau local. Sans cette option, Android bloque la connexion.
> Téléphone branché en USB ? `flutter run --release --android-project-arg=allowCleartext=true` l'installe directement.

---

## Étape 6 — Se connecter dans l'application

1. Ouvrez **GodaFret Banque** → icône **⚙️** en haut à droite.
2. Choisissez **Mon serveur**, saisissez l'**IP du serveur** (ex. `192.168.1.50`) → **Enregistrer**.
   La pastille affiche « Serveur 192.168.1.50 · MFA ».
3. Identifiant `camille`, mot de passe `Demo-Banque-2026` → **Se connecter**.
4. Saisissez le **code à 6 chiffres** de votre appli d'authentification.
5. Créez votre **code PIN** (6 chiffres, pas de suite comme 123456).

Vous voyez le tableau de bord avec les vrais comptes Fineract. Essayez un dépôt, un transfert vers
`000000003`, une demande de prêt : tout apparaît aussi dans Mifos X (http://IP).

---

## Ajouter un vrai client

1. **Mifos X** : Clients → Créer → renseignez **External Id = identifiant de connexion** (ex. `awa.diallo`) →
   activez → ouvrez et activez ses comptes épargne.
2. **Mifos X** › Admin › Utilisateurs → Créer : même identifiant, rôle **Client mobile**, mot de passe au hasard.
3. **Keycloak** (http://IP:8081/admin) → royaume **godafret** → Users → Add user : même identifiant,
   e-mail, prénom, nom → onglet *Credentials* → mot de passe (*Temporary* : Off).
4. Le client active son OTP (étape 4) puis se connecte dans l'application (étape 6).

---

## Commandes utiles (dans `/opt/godafret/infra`)

| Action | Commande |
|---|---|
| État des services | `sudo docker compose ps` |
| Journaux | `sudo docker compose logs -f fineract-mobile` (ou `keycloak`, `fineract`) |
| Arrêter / démarrer | `sudo docker compose stop` / `sudo docker compose start` |
| Mettre à jour | `sudo git pull && sudo docker compose pull && sudo docker compose up -d` |
| Sauvegarder | `sudo bash backup.sh` → `/var/backups/godafret` |
| L'IP du serveur a changé | `sudo bash install-local.sh` (met à jour la configuration) |

## Dépannage

| Symptôme | Solution |
|---|---|
| L'appli dit « Connexion impossible » | même Wi-Fi ? IP correcte dans ⚙️ ? APK construit avec `allowCleartext=true` ? Testez http://IP:8081 dans le navigateur du téléphone |
| « Votre compte doit être finalisé… » | l'OTP n'est pas encore configuré : faites l'étape 4 (page *account*) |
| « Identifiant, mot de passe ou code OTP incorrect » | vérifiez l'heure du téléphone (automatique) ; code OTP valable 30 s |
| « Aucun client n'est rattaché à l'identifiant » | External Id du client dans Mifos X ≠ identifiant Keycloak |
| Erreur 403 dans l'appli | l'utilisateur Fineract n'a pas le rôle **Client mobile** |
| `HTTPS required` | relancez `sudo bash install-local.sh` (il autorise le HTTP sur le réseau local) |
| Fineract ne démarre pas | `sudo docker compose logs fineract` ; au moins 8 Go de RAM nécessaires |
