# Laravel Docker Setup

Wiederverwendbares Docker-Template fuer Laravel 11 Projekte mit automatischer Port-Verwaltung.

## Enthaltene Services

| Service      | Image                        | Beschreibung                          |
|-------------|------------------------------|---------------------------------------|
| app         | php:8.4-fpm (custom)         | PHP-FPM + Supervisor + Node.js        |
| nginx       | nginx:alpine                 | Webserver                             |
| mysql       | mysql:8.0                    | Datenbank                             |
| redis       | redis:7-alpine               | Cache / Queue-Backend                 |
| phpmyadmin  | phpmyadmin/phpmyadmin        | Datenbank-Verwaltung                  |
| openldap    | osixia/openldap:1.5.0        | LDAP-Testumgebung                     |
| ldapadmin   | osixia/phpldapadmin:0.9.0    | LDAP-Verwaltung                       |

## PHP-Extensions

pdo_mysql, mysqli, ldap, gd (FreeType + WebP), imagick, mbstring, xml, curl, zip, bcmath, intl, opcache, pcntl, exif, redis

## System-Tools

- **ImageMagick** - Bildverarbeitung
- **wkhtmltopdf** - PDF-Generierung aus HTML
- **Node.js 20 LTS** - Asset-Kompilierung (Vite)
- **Composer** - PHP-Paketmanager
- **Supervisor** - Queue-Worker Management

---

## Voraussetzungen

- Windows mit WSL2 (Ubuntu empfohlen)
- Docker Desktop mit WSL2-Integration
- Git in WSL installiert

### Git auf WSL-Ebene global konfigurieren

```bash
cd ~
git config --global user.name "Dein Name"
git config --global user.email "deine@email.de"
git config --global credential.helper store
git config --global core.editor "nano"
```

---

## Schnellstart

### 1. Projektstruktur anlegen

Windows CMD starten, oben neben dem Tab auf den Pfeil und "Ubuntu" waehlen.

```bash
cd ~
mkdir -p projekte/mein-projekt
cd projekte/mein-projekt
mkdir docker src
```

### 2. Docker-Setup klonen

```bash
cd docker
git clone <repo-url> .
```

### 3. Setup ausfuehren (automatische Port-Zuweisung)

```bash
./setup.sh mein-projekt
```

Das Skript:
- Registriert das Projekt in `~/.docker-projects/registry.json`
- Weist automatisch freie Ports zu (keine Konflikte mit anderen Projekten)
- Generiert die `.env` Datei

### 4. Container bauen und starten

```bash
docker compose build
docker compose up -d
docker compose ps
```

### 5. Laravel installieren (neues Projekt)

```bash
./setup.sh init-laravel
```

Das Skript erledigt automatisch:
- Installiert Laravel 11 via Composer
- Korrigiert Dateiberechtigungen (WSL-kompatibel)
- Deployt eine vorkonfigurierte `.env` (MySQL, Redis, LDAP)
- Generiert den APP_KEY
- Fuehrt die Datenbank-Migration aus
- Installiert Laravel Debugbar
- Zeigt alle URLs und Zugangsdaten an

### 5b. Bestehendes Projekt einbinden

```bash
cd ../src
git clone <laravel-repo-url> .
docker exec <projektname>-app composer install
docker exec <projektname>-app npm install
# Dann init-laravel ausfuehren um die .env zu deployen:
./setup.sh init-laravel
# (Erkennt automatisch, dass src/ nicht leer ist und bietet an, nur die .env zu kopieren)
```

---

## Setup-Skript Kommandos

```bash
./setup.sh                    # Interaktive Einrichtung
./setup.sh <projektname>      # Direkte Einrichtung
./setup.sh init-laravel       # Laravel 11 installieren + .env deployen
./setup.sh list               # Alle registrierten Projekte anzeigen
./setup.sh remove <name>      # Projekt aus Registry entfernen
./setup.sh status             # Laufende Container aller Projekte
./setup.sh ports              # Port-Uebersicht aller Projekte
./setup.sh help               # Hilfe
```

### Projekt-Registry

Alle registrierten Projekte und ihre Ports werden zentral gespeichert unter:

```
~/.docker-projects/registry.json
```

Die Datei wird beim ersten `./setup.sh`-Aufruf automatisch erstellt. So koennen mehrere Projekte parallel laufen, ohne dass Ports manuell verwaltet werden muessen.

### Port-Schema (automatisch pro Projekt)

| Port         | Formel              | Projekt 0 | Projekt 1 | Projekt 2 |
|-------------|---------------------|-----------|-----------|-----------|
| App         | 8000 + (Index*100)  | 8000      | 8100      | 8200      |
| phpMyAdmin  | App + 80            | 8080      | 8180      | 8280      |
| LdapAdmin   | App + 81            | 8081      | 8181      | 8281      |
| Vite        | 5173 + Index        | 5173      | 5174      | 5175      |
| MySQL       | 3306 + Index        | 3306      | 3307      | 3308      |
| Redis       | 6379 + Index        | 6379      | 6380      | 6381      |
| LDAP        | 389 + Index         | 389       | 390       | 391       |
| Subnet      | 172.(20+Index)      | 172.20    | 172.21    | 172.22    |

---

## Verzeichnisstruktur

```
projekt/
├── docker/
│   ├── Dockerfile              # PHP-FPM App-Container
│   ├── docker-compose.yml      # Service-Definitionen
│   ├── setup.sh                # Setup mit Port-Automatik
│   ├── .env.example            # Vorlage
│   ├── .env                    # Generiert durch setup.sh (gitignored)
│   ├── laravel.env             # Generiert durch setup.sh (gitignored)
│   ├── nginx/
│   │   └── default.conf        # Nginx vHost
│   ├── php/
│   │   └── php.ini             # PHP-Einstellungen
│   ├── supervisor/
│   │   ├── supervisord.conf    # Supervisor Hauptkonfiguration
│   │   └── laravel-worker.conf # PHP-FPM + Queue-Worker
│   └── ldap/
│       ├── ReadMe              # LDAP-Importanleitung
│       └── *.ldif              # Testdaten
├── src/                        # Laravel-Quellcode
└── ~/.docker-projects/
    └── registry.json           # Zentrale Port-Registry (alle Projekte)
```

---

## Haeufige Befehle

```bash
# Container verwalten
docker compose up -d            # Starten
docker compose down             # Stoppen
docker compose restart          # Neustarten
docker compose logs -f app      # Logs anzeigen

# Im App-Container arbeiten
docker exec -it <name>-app bash
docker exec <name>-app php artisan migrate
docker exec <name>-app composer install
docker exec <name>-app npm install
docker exec <name>-app npm run dev

# LDAP-Testdaten importieren (siehe ldap/ReadMe fuer Details)
docker cp ldap/example-users.ldif <name>-openldap:/tmp/example-users.ldif
docker exec <name>-openldap ldapadd -x -D "cn=admin,dc=example,dc=local" \
    -w admin123 -f /tmp/example-users.ldif
```

---

## XDebug aktivieren

XDebug ist nicht standardmaessig installiert (spart Ressourcen). Bei Bedarf:

```bash
docker exec <name>-app pecl install xdebug
docker exec <name>-app docker-php-ext-enable xdebug
```

Dann in `php/php.ini` die XDebug-Zeilen einkommentieren und Container neustarten.
