# glqos — dashboard QoS 4G/5G en direct pour le GL.iNet GL-E5800 (Mudi 7)

*[English version](README.md)*

`glqos` transforme le GL-E5800 en analyseur radio : le routeur interroge son modem Quectel RG650V
chaque seconde, pingue une cible cinq fois par seconde et sert sur le LAN un dashboard en direct avec
historique. Un second paquet, facultatif, `glqos-simguard`, corrige la perte de paquets causée par la
deuxième SIM (voir [Pourquoi la deuxième SIM pose problème](#pourquoi-la-deuxième-sim-pose-problème)).

Projet indépendant, sans lien avec GL.iNet ni Quectel.

## Fonctions

- **Mesure radio à 1 Hz** en un seul appel AT (`AT+QENG`, `QCAINFO`, `QRSRP`, `QSINR` ; `QTEMP` toutes les 10 s) :
  techno (LTE / NR NSA), cellule de service (bande, PCI, EARFCN, eNB, TAC), RSRP / RSRQ / SINR / RSSI / CQI /
  puissance d'émission, RSRP et SINR par antenne (4 chaînes de réception, LTE et NR), chaque porteuse agrégée,
  température du modem.
- **Ping à 5 Hz** vers une cible réglable : RTT, gigue, perte (déduite des trous de séquence).
- **Débit écoulé** d'après les compteurs rmnet, état de la session data, opérateur (MCC-MNC), SIM active.
- **Dashboard en direct** (`http://<IP LAN du routeur>:8088/`), rafraîchi chaque seconde, sans dépendance
  externe (fonctionne quand le lien est coupé), thèmes clair et sombre :
  - un **diagnostic** en langage clair de la dernière minute, qui ne liste que ce qui mérite l'attention, avec la cause probable ;
  - une **carte des fréquences** (700 à 3500 MHz) : ce qui est utilisé maintenant et à quelle fréquence sur la période ;
  - les **porteuses** agrégées avec fréquence, rôle, largeur et un mot pour le signal, lisibles par tous ;
  - chiffres en direct, courbes empilées et synchronisées, événements (handovers, NR ajouté ou perdu, changements
    d'agrégation, rafales de pertes, coupures, reconnexions, changements d'opérateur), statistiques par cellule
    et synthèse par opérateur ;
  - une explication derrière chaque libellé. Fenêtres de 2 minutes à 7 jours.
- **Historique** dans `/data/glqos` : un CSV par jour, jours passés compressés en gzip (~4 Mo/jour au lieu de ~19), 30 jours par défaut.
- **Survit aux mises à jour du firmware** : les fichiers sont déclarés dans `/lib/upgrade/keep.d`, que la mise à
  jour A/B de GL (`abfota_update`) restaure ; l'historique est sur `/data`, que les mises à jour n'effacent pas.

## Pourquoi la deuxième SIM pose problème

Le GL-E5800 est double SIM en veille simultanée avec **une seule chaîne radio**. Quand les deux SIM sont
inscrites au réseau, la SIM en veille prend régulièrement la radio à la SIM qui porte la data (écoute des appels
réseau, mesures, changements de cellule, mises à jour de localisation). Le trafic se fige de 1 à 13 secondes et des
paquets se perdent, bien plus en roulant.

Mesures du 11/11/2026 (ping 5 Hz vers 8.8.8.8 ; un Pixel 10 avec la même SIM posé à côté du routeur, même endroit, même moment) :

| Configuration du Mudi 7 | Perte | RTT p95 | RTT max |
|---|---|---|---|
| Deux SIM inscrites, en roulant (15 min) | 13,9 % | 3,0 s | 13 s |
| Deux SIM inscrites, à l'arrêt (15 min) | 0,5 % | 995 ms | 6,5 s |
| Deuxième SIM désinscrite, à l'arrêt (5 min) | 0 % | 65 ms | 289 ms |
| Deuxième SIM désinscrite, en roulant (15 min) | 0,3 % | 73 ms | 1,1 s |
| *Pixel 10, une seule SIM, même réseau* | *0–0,1 %* | *64–71 ms* | *< 0,5 s* |

Le firmware (GL 4.10.0 et 4.10.2 beta7, modem `01.005.01.005`), l'accélération réseau, le type d'APN, le
verrouillage de bandes et la 5G n'y changeaient rien. Désinscrire la SIM en veille, si. Ça a aussi rétabli
l'accroche 5G NSA et les mesures de CQI et de puissance d'émission, qui manquaient chaque fois que la radio
était prise.

`glqos-simguard` garde désinscrite la SIM qui ne porte pas la data (`AT+COPS=2`). Si la SIM active ne répond
plus au ping pendant 30 s, il réinscrit la SIM de secours et y bascule la data via l'événement de bascule de GL
(mesuré : environ 60 s entre la panne et le retour d'Internet) ; une fois la nouvelle SIM stable, l'ancienne est
endormie. **Une SIM endormie ne reçoit pas les SMS.**

## Installation

Téléchargez les deux `.ipk` depuis la [dernière release](https://github.com/huguesdelamure/glqos/releases), copiez-les
sur le routeur, puis :

```sh
mkdir -p /data/glqos && cd /data/glqos      # garder les .ipk sur /data facilite une réinstallation
opkg install ./glqos_*_all.ipk
opkg install ./glqos-simguard_*_all.ipk     # facultatif, voir plus haut
```

Ouvrez `http://192.168.8.1:8088/` (ou votre IP LAN).

Avec `glqos-simguard`, laissez désactivée la bascule automatique de SIM de l'interface GL : la garde s'en charge.
Elle n'a pas été testée avec la bascule de GL activée.

## Configuration

`/etc/config/glqos` (UCI), puis `/etc/init.d/glqos restart` (et `/etc/init.d/glqos-simguard restart`) :

| Option | Défaut | Rôle |
|---|---|---|
| `main.port` | `8088` | port du dashboard |
| `main.listen` | IP LAN | adresse d'écoute d'uhttpd |
| `main.ping_target` | `8.8.8.8` | cible du ping à 5 Hz |
| `main.retention_days` | `30` | jours d'historique conservés |
| `simguard.down_s` | `30` | secondes sans réponse ping avant bascule |
| `simguard.calm_s` | `120` | secondes de bonne santé avant d'endormir la SIM de secours |
| `simguard.check_s` | `60` | fréquence de vérification de l'état de la SIM de secours |

Pour intervenir sur les SIM à la main sans que la garde interfère : `touch /tmp/glqos/simguard.pause` (supprimer
le fichier pour reprendre). Les actions de la garde sont dans `logread -e glqos-simguard` et `/data/glqos/simguard.log`.

## Données

- `/data/glqos/AAAA-MM-JJ.csv[.gz]` : une ligne par seconde ; l'en-tête liste les colonnes
  (`lat,lon,speed,sats` sont réservées et restent vides : le E5800 n'a pas de GNSS exploitable).
- `GET /cgi-bin/q?since=<epoch>` : lignes brutes postérieures à `epoch` (mises à jour en direct).
- `GET /cgi-bin/q?from=<epoch>&to=<epoch>&step=<s>` : lignes d'un intervalle, agrégées par pas de `step` secondes.

## Désinstallation

```sh
opkg remove glqos-simguard   # réveille la SIM de secours
opkg remove glqos            # l'historique dans /data/glqos est conservé
```

## Limites

- Testé uniquement sur le GL-E5800 (firmware GL 4.10.0 et 4.10.2 beta7, modem
  `QRM650VEU00ADR02A04G8G_OCPU_RGH_01.005.01.005`), avec des opérateurs français. `glqos-simguard` refuse de
  démarrer sur un autre modèle.
- La survie à une vraie mise à jour du firmware repose sur le mécanisme `keep.d` de GL et **n'a pas encore été
  vérifiée**. Si les fichiers ont disparu après une mise à jour, réinstallez depuis `/data/glqos/*.ipk` ;
  l'historique est intact.
- Le dashboard n'a pas d'authentification ; il n'écoute que sur l'adresse LAN.
- Le débit à la seconde est en dents de scie (compteurs du déchargement modem) ; les moyennes sur quelques
  secondes sont fiables.

## Construction

```sh
./build-ipk.sh   # produit dist/glqos_<version>_all.ipk et dist/glqos-simguard_<version>_all.ipk
```

Uniquement du shell, de l'awk et une page HTML statique : les paquets sont indépendants de l'architecture.

## Licence

[MIT](LICENSE). Les polices embarquées, Host Grotesk et Atkinson Hyperlegible Mono, sont sous licence SIL Open Font License 1.1 (`src/fonts/OFL-*.txt`).
