# Quitegood Support : client RustDesk personnalisé

Fork de [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0) qui remplace TeamViewer pour l'assistance Quitegood.

## Ce que fait le fork

| Besoin | Mise en œuvre |
|---|---|
| Serveur `support.quitegood.be` préréglé | `quitegood/settings.json` est intégré au binaire à la compilation (`src/common.rs`, `load_quitegood_settings`) et appliqué en mode « override » : l'utilisateur ne peut pas le modifier |
| **Port 443 uniquement** | `allow-websocket=Y` + `api-server=https://…` : le client parle en `wss://support.quitegood.be/ws/id` et `wss://support.quitegood.be/ws/relay`. Comme `disable-udp=Y`, il n'y a ni UDP ni connexion directe : tout passe par le relais |
| Logo Quitegood | `flutter/assets/logo*.png` (bandeau de la fenêtre principale, versions claire et sombre), icônes de l'appli, de la barre d'état et du Dock (`res/`, `flutter/windows`, `flutter/macos`) |
| Pas de réglages à faire chez le client | Réglages serveur et WebSocket masqués, mot de passe à usage unique de 8 caractères par défaut |
| Pas d'écrasement par la version officielle | Mise à jour automatique et vérification des mises à jour amont désactivées |

Le nom interne de l'application reste « RustDesk », volontairement : sur macOS, le chemin `/Applications/RustDesk.app`, les LaunchAgents et l'identifiant de bundle en dépendent. Renommer l'appli est possible, mais c'est un chantier séparé.

## Construire les clients

1. Forker le dépôt sur GitHub, puis y pousser la branche `quitegood` (comme branche par défaut).
2. Dans **Settings → Actions → General**, activer les Actions et choisir **Workflow permissions : Read and write**.
3. La clé du serveur est déjà dans `quitegood/settings.json`. Si le serveur change de clé, mettre la nouvelle dans ce fichier, ou dans la variable de dépôt `QG_SERVER_KEY`.
4. Dans **Actions → « Quitegood - release client » → Run workflow**, lancer la compilation (environ 1 h à 1 h 30). Une alternative : pousser la branche `quitegood` sur `qg-release` (`git push origin quitegood:qg-release`) ou un tag `qg-v1.0.0`.
5. Les fichiers sont publiés sous des noms fixes dans la dernière release :
   `QuitegoodSupport-Windows.exe`, `QuitegoodSupport-Windows.msi`, `QuitegoodSupport-macOS-AppleSilicon.dmg` et `QuitegoodSupport-macOS-Intel.dmg`.

Pour récupérer une nouvelle version de RustDesk : fusionner `upstream/master` dans `quitegood`, lancer `python3 quitegood/ci/make_workflow.py` pour régénérer le workflow allégé, commiter, puis relancer la release.

## Serveur (`quitegood/server/`), installé le 09/11/2026 sur la VM Azure « RustDesk »

- `compose.yml` : hbbs et hbbr (image OSS) dans `/opt/quitegood-support`, en écoute seulement sur `127.0.0.1:21118/21119`. Clé publique : `/opt/quitegood-support/data/id_ed25519.pub`.
- `nginx-support.quitegood.be.conf` : sur le 443 (certificat Let's Encrypt via certbot), `/ws/id` renvoie vers hbbs et `/ws/relay` vers hbbr, `/download/*` redirige vers la dernière release GitHub, et `/api/*` répond 404.
- `install.sh` : sauvegarde (`/root/rustdesk-backup-*.tgz`) et supprime l'ancienne installation, puis déploie et affiche la clé.
- Pare-feu ufw : 22, 80 et 443 uniquement. Les ports 21114 à 21119 sont fermés.

## Site web

`quitegood/website/support-download.html` est à coller dans un bloc « Code intégré » d'Odoo. Il détecte Windows ou Mac et utilise les liens fixes `https://support.quitegood.be/download/{windows,mac,mac-intel,windows-msi}`.

## Limites connues

- **Signature du code** : sans certificat de signature Windows, SmartScreen affiche « Windows a protégé votre ordinateur ». Sans compte Apple Developer (99 $/an, signature et notarisation), macOS demande un clic droit → Ouvrir. Le workflow amont sait signer si on lui fournit les secrets (`MACOS_P12_BASE64`, etc.).
- **Licence AGPL-3.0** : le code modifié doit rester public. Un fork public sur GitHub y satisfait.
- **Relais systématique** : sans UDP, toutes les sessions passent par le serveur Azure. Prévoir de la bande passante (environ 1 à 3 Mb/s par session active).
