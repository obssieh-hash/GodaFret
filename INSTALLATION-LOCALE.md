# Installer Golden Bridge Bank sur un serveur Ubuntu du réseau local

Ce guide installe **Golden Bridge Bank** (serveur + console des agences) sur **un serveur Ubuntu chez vous / au bureau** (sans nom de domaine),
puis l'application **Golden Bridge Pay** sur un **téléphone Android connecté au même Wi-Fi**.

```
 Téléphone (même Wi-Fi) ──► http://IP:8081  Keycloak (connexion + code OTP)
                        ──► http://IP:8082  Fineract (API de l'application)
 Navigateur des agences ──► http://IP       Golden Bridge Bank (Mifos X : clients, comptes, prêts, caisse)
                                     │
                              PostgreSQL (données)
```

> ⚠️ Mode **réseau local de test** : le trafic est en HTTP non chiffré. Ne l'ouvrez pas sur
> Internet et n'y mettez pas de vrais clients. Pour la production, voir `infra/README.md`.

## ⚡ Installation en une seule commande

Sur la VM Ubuntu (connectée à Internet), copiez-collez cette ligne : elle télécharge le code depuis
GitHub, installe tout, démarre la banque et crée la cliente de démonstration.

```bash
sudo apt-get update && sudo apt-get install -y git && { [ -d /opt/golden-bridge/.git ] && sudo git -C /opt/golden-bridge pull || sudo git clone -b claude/flutter-banking-app-3xii1t https://github.com/obssieh-hash/GodaFret.git /opt/golden-bridge; } && cd /opt/golden-bridge/infra && sudo bash install-local.sh && sudo bash demo-local.sh
```

Comptez 10 à 15 minutes la première fois. À la fin, les adresses et mots de passe s'affichent.
Les étapes détaillées ci-dessous expliquent la même chose pas à pas.

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
sudo git clone -b claude/flutter-banking-app-3xii1t https://github.com/obssieh-hash/GodaFret.git /opt/golden-bridge
```

(Si le dépôt est privé, git demande votre identifiant GitHub et un *personal access token* comme mot de passe.)

**Option B — avec l'archive `golden-bridge-serveur.zip`** (depuis votre PC) :

```bash
scp golden-bridge-serveur.zip utilisateur@IP:~
ssh utilisateur@IP
sudo apt install -y unzip && sudo unzip ~/golden-bridge-serveur.zip -d /opt   # crée /opt/golden-bridge
```

---

## Étape 2 — Installer et démarrer la banque (une seule commande)

```bash
cd /opt/golden-bridge/infra
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
   echo "MIFOS_PASSWORD='VotreNouveauMotDePasse'" | sudo tee -a /opt/golden-bridge/infra/.env
   ```

Le mot de passe administrateur **Keycloak** est dans `.env` (`KEYCLOAK_ADMIN_PASSWORD`) :
`sudo grep KEYCLOAK_ADMIN_PASSWORD /opt/golden-bridge/infra/.env` — console : http://IP:8081/admin

---

## Étape 4 — Créer le client de démonstration

```bash
cd /opt/golden-bridge/infra
sudo bash demo-local.sh                       # mot de passe de la cliente : Demo-Banque-2026
# ou : sudo bash demo-local.sh 'MonMotDePasse-2026'
```

Cela crée la cliente **Fatouma Ali Houssein** (téléphone `77101010`) : portefeuille GB Pay
(150 000 Fdj), épargne (120 000 Fdj), un prêt en cours, et trois correspondants pour essayer :

| Qui | Numéro | Pour tester |
|---|---|---|
| Ahmed Hassan Moussa | `77202020` | **Envoyer** |
| Boulangerie La Palmeraie | `21350001` | **Payer** (marchand) |
| Agent GB Balbala | `77990001` | **Retrait** chez un agent |

**Activer le code OTP (obligatoire, une seule fois)** — sur le téléphone :
1. ouvrez **http://IP:8081/realms/goldenbridge/account** ;
2. connectez-vous avec `77101010` / `Demo-Banque-2026` ;
3. scannez le QR code avec votre appli d'authentification et saisissez le code affiché.

---

## Étape 5 — Installer l'application Golden Bridge Pay (Android)

**Le plus simple** : sur le téléphone, ouvrez la page des versions du dépôt GitHub
(**Releases**) et téléchargez la dernière **`golden-bridge-pay.apk`**, puis ouvrez-la et autorisez
l'installation. Elle est reconstruite automatiquement à chaque modification de l'application.

**Ou la construire vous-même** (PC avec Flutter + Android Studio) :

```bash
cd mobile
flutter pub get
flutter build apk --release --android-project-arg=allowCleartext=true
```

L'APK est dans `mobile/build/app/outputs/flutter-apk/app-release.apk`.

> `allowCleartext=true` autorise le HTTP du réseau local. Sans cette option, Android bloque la connexion.

---

## Étape 6 — Se connecter dans l'application

1. Ouvrez **Golden Bridge Pay** → icône **⚙️** en haut à droite.
2. Choisissez **Mon serveur**, saisissez l'**IP du serveur** (ex. `192.168.1.50`) → **Enregistrer**.
   La pastille affiche « Serveur 192.168.1.50 · MFA ».
3. Numéro de téléphone `77 10 10 10`, mot de passe `Demo-Banque-2026` → **Se connecter**.
4. Saisissez le **code à 6 chiffres** de votre appli d'authentification.
5. Créez votre **code PIN** (6 chiffres, pas de suite comme 123456).

Vous voyez l'accueil : solde, et 8 actions — **Envoyer** (à `77202020`), **Payer** (`21350001`),
**Retrait** chez l'agent (`77990001`), **Recevoir** / **Dépôt** (votre QR code), **Prêts**,
**Rembourser**, **Historique**. Chaque opération apparaît aussi dans la console des agences (http://IP).

---

## Ajouter un vrai client, un marchand ou un agent

1. **Console des agences** (http://IP) : Clients → Créer → **Téléphone mobile** et **External Id** = son numéro
   (ex. `77445566`) → activez → ouvrez et activez son compte **Portefeuille GB Pay**.
   Un marchand ou un agent est un client comme un autre (forme juridique « entité ») : on le paie
   ou on retire chez lui avec son numéro.
2. Admin › Utilisateurs → Créer : identifiant = son numéro, rôle **Client mobile**, mot de passe au hasard
   (seulement pour ceux qui utilisent l'application).
3. **Keycloak** (http://IP:8081/admin) → royaume **goldenbridge** → Users → Add user : identifiant = son numéro,
   e-mail, prénom, nom → onglet *Credentials* → mot de passe (*Temporary* : Off).
4. Le client active son OTP (étape 4) puis se connecte dans l'application (étape 6).

---

## Commandes utiles (dans `/opt/golden-bridge/infra`)

| Action | Commande |
|---|---|
| État des services | `sudo docker compose ps` |
| Journaux | `sudo docker compose logs -f fineract-mobile` (ou `keycloak`, `fineract`) |
| Arrêter / démarrer | `sudo docker compose stop` / `sudo docker compose start` |
| Mettre à jour | `sudo git pull && sudo docker compose pull && sudo docker compose up -d` |
| Sauvegarder | `sudo bash backup.sh` → `/var/backups/golden-bridge` |
| L'IP du serveur a changé | `sudo bash install-local.sh` (met à jour la configuration) |

## Dépannage

| Symptôme | Solution |
|---|---|
| L'appli dit « Connexion impossible » | même Wi-Fi ? IP correcte dans ⚙️ ? APK construit avec `allowCleartext=true` ? Testez http://IP:8081 dans le navigateur du téléphone |
| « Votre compte doit être finalisé… » | l'OTP n'est pas encore configuré : faites l'étape 4 (page *account*) |
| « Identifiant, mot de passe ou code OTP incorrect » | vérifiez l'heure du téléphone (automatique) ; code OTP valable 30 s |
| « Aucun client n'est rattaché à l'identifiant » | External Id du client dans Mifos X ≠ identifiant Keycloak |
| Erreur 403 dans l'appli | l'utilisateur Fineract n'a pas le rôle **Client mobile** |
| « Aucun compte Golden Bridge ne correspond » | le numéro saisi n'est pas le téléphone mobile d'un client ayant un compte actif |
| Dépôt d'espèces | se fait au guichet ou chez un agent (console des agences → compte du client → Dépôt), jamais depuis l'appli |
| `HTTPS required` | relancez `sudo bash install-local.sh` (il autorise le HTTP sur le réseau local) |
| Fineract ne démarre pas | `sudo docker compose logs fineract` ; au moins 8 Go de RAM nécessaires |
