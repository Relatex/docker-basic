#!/bin/bash
# ============================================
# Laravel Docker Setup - Automatische Port-Verwaltung
# ============================================
# Erstellt und verwaltet .env Dateien fuer Docker-Projekte
# mit automatischer Port-Zuweisung ohne Konflikte.
#
# Verwendung:
#   ./setup.sh                    Interaktive Einrichtung
#   ./setup.sh <projektname>      Direkte Einrichtung
#   ./setup.sh init-laravel       Laravel installieren + .env deployen
#   ./setup.sh list               Alle Projekte anzeigen
#   ./setup.sh remove <name>      Projekt entfernen
#   ./setup.sh status             Laufende Container anzeigen
#   ./setup.sh ports              Port-Uebersicht aller Projekte
# ============================================

set -euo pipefail

# Farben fuer Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Registry-Verzeichnis und Datei
REGISTRY_DIR="$HOME/.docker-projects"
REGISTRY_FILE="$REGISTRY_DIR/registry.json"

# Aktuelles Verzeichnis (wo das Skript liegt)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# ============================================
# Hilfsfunktionen
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FEHLER]${NC} $1"
}

# WSL User-ID erkennen
detect_uid() {
    local current_uid
    local current_gid
    current_uid=$(id -u)
    current_gid=$(id -g)

    echo -e "${BOLD}User-ID Erkennung:${NC}"
    echo -e "  Aktueller WSL-User: ${CYAN}$(whoami)${NC} (UID: ${CYAN}${current_uid}${NC}, GID: ${CYAN}${current_gid}${NC})"

    read -rp "  UID/GID uebernehmen? [J/n]: " confirm
    confirm="${confirm:-J}"

    if [[ "$confirm" =~ ^[JjYy]$ ]]; then
        WWWUSER="$current_uid"
        WWWGROUP="$current_gid"
    else
        read -rp "  Gewuenschte UID [${current_uid}]: " custom_uid
        read -rp "  Gewuenschte GID [${current_gid}]: " custom_gid
        WWWUSER="${custom_uid:-$current_uid}"
        WWWGROUP="${custom_gid:-$current_gid}"
    fi

    log_success "Verwende UID: ${WWWUSER}, GID: ${WWWGROUP}"
}

# ============================================
# Registry-Funktionen
# ============================================

init_registry() {
    if [ ! -d "$REGISTRY_DIR" ]; then
        mkdir -p "$REGISTRY_DIR"
        log_info "Registry-Verzeichnis erstellt: $REGISTRY_DIR"
    fi

    if [ ! -f "$REGISTRY_FILE" ]; then
        cat > "$REGISTRY_FILE" << 'JSONEOF'
{
  "projects": {},
  "next_index": 0
}
JSONEOF
        log_info "Registry-Datei erstellt: $REGISTRY_FILE"
    fi
}

# Prueft ob ein Projekt existiert
project_exists() {
    local name="$1"
    python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
if '$name' in data.get('projects', {}):
    exit(0)
else:
    exit(1)
"
}

# Naechsten freien Index holen
get_next_index() {
    python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
print(data.get('next_index', 0))
"
}

# Ports fuer einen Index berechnen
calc_ports() {
    local index=$1
    # Port-Schema
    APP_PORT=$((8000 + index * 100))
    PHPMYADMIN_PORT=$((APP_PORT + 80))
    LDAPADMIN_PORT=$((APP_PORT + 81))
    APP_VITE_PORT=$((5173 + index))
    MYSQL_PORT=$((3306 + index))
    REDIS_PORT=$((6379 + index))
    LDAP_PORT=$((389 + index))
    LDAPS_PORT=$((636 + index))
    DOCKER_SUBNET="172.$((20 + index)).0.0/16"
}

# Projekt in Registry speichern
save_project() {
    local name="$1"
    local index="$2"
    local path="$3"

    calc_ports "$index"

    python3 -c "
import json
from datetime import date

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

data['projects']['$name'] = {
    'index': $index,
    'path': '$path',
    'created': str(date.today()),
    'ports': {
        'app': $APP_PORT,
        'phpmyadmin': $PHPMYADMIN_PORT,
        'ldapadmin': $LDAPADMIN_PORT,
        'vite': $APP_VITE_PORT,
        'mysql': $MYSQL_PORT,
        'redis': $REDIS_PORT,
        'ldap': $LDAP_PORT,
        'ldaps': $LDAPS_PORT
    },
    'subnet': '$DOCKER_SUBNET'
}

# next_index hochzaehlen wenn noetig
if $index >= data.get('next_index', 0):
    data['next_index'] = $index + 1

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
}

# Projekt aus Registry entfernen
remove_project() {
    local name="$1"

    if ! project_exists "$name"; then
        log_error "Projekt '$name' nicht in der Registry gefunden."
        return 1
    fi

    python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

if '$name' in data['projects']:
    del data['projects']['$name']

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
    log_success "Projekt '$name' aus Registry entfernt."
}

# ============================================
# .env Datei generieren (Docker)
# ============================================

generate_env() {
    local name="$1"
    local index="$2"

    calc_ports "$index"

    cat > "$SCRIPT_DIR/.env" << ENVEOF
# ============================================
# Generiert durch setup.sh - $(date '+%Y-%m-%d %H:%M:%S')
# Projekt-Index: $index
# ============================================

# Projektname
PROJECT_NAME=$name
COMPOSE_PROJECT_NAME=$name

# ============================================
# User (WSL-Kompatibilitaet)
# ============================================
WWWUSER=$WWWUSER
WWWGROUP=$WWWGROUP

# ============================================
# Netzwerk
# ============================================
DOCKER_SUBNET=$DOCKER_SUBNET

# ============================================
# Ports (automatisch zugewiesen)
# ============================================
APP_PORT=$APP_PORT
PHPMYADMIN_PORT=$PHPMYADMIN_PORT
LDAPADMIN_PORT=$LDAPADMIN_PORT
APP_VITE_PORT=$APP_VITE_PORT
MYSQL_PORT=$MYSQL_PORT
REDIS_PORT=$REDIS_PORT
LDAP_PORT=$LDAP_PORT
LDAPS_PORT=$LDAPS_PORT

# ============================================
# MySQL
# ============================================
MYSQL_DATABASE=$name
MYSQL_ROOT_PASSWORD=secret
MYSQL_USER=laravel
MYSQL_PASSWORD=secret

# ============================================
# Redis
# ============================================
REDIS_PASSWORD=

# ============================================
# LDAP (Testumgebung)
# ============================================
LDAP_ORGANISATION=MeineOrganisation
LDAP_DOMAIN=example.local
LDAP_ADMIN_PASSWORD=admin123
LDAP_CONFIG_PASSWORD=config123

# ============================================
# Timezone
# ============================================
TZ=Europe/Berlin
ENVEOF
}

# ============================================
# Laravel .env Vorlage generieren
# ============================================

generate_laravel_env() {
    local name="$1"
    local index="$2"

    calc_ports "$index"

    local laravel_env_file="$SCRIPT_DIR/laravel.env"

    cat > "$laravel_env_file" << LARAVELEOF
# ============================================
# Laravel .env - Generiert durch setup.sh
# Projekt: $name
# ============================================

APP_NAME="$name"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_TIMEZONE=Europe/Berlin
APP_URL=http://localhost:${APP_PORT}

APP_LOCALE=de
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=de_DE

LOG_CHANNEL=stack
LOG_STACK=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

# ============================================
# Datenbank (MySQL im Docker-Netzwerk)
# ============================================
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=$name
DB_USERNAME=laravel
DB_PASSWORD=secret

# ============================================
# Cache / Queue / Session
# ============================================
BROADCAST_DRIVER=log
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

# ============================================
# Redis (im Docker-Netzwerk)
# ============================================
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_CLIENT=phpredis

# ============================================
# LDAP-Anbindung
# ============================================
# Lokaler OpenLDAP (Docker Testumgebung):
LDAP_HOST=openldap
LDAP_PORT=389
LDAP_BASE_DN=dc=example,dc=local
LDAP_USERNAME=cn=admin,dc=example,dc=local
LDAP_PASSWORD=admin123
LDAP_USE_TLS=false

# Active Directory on-prem (auskommentiert):
# LDAP_HOST=dein-ad-server.domain.local
# LDAP_PORT=389
# LDAP_BASE_DN=DC=domain,DC=local
# LDAP_USERNAME=CN=ldap-reader,OU=Service,DC=domain,DC=local
# LDAP_PASSWORD=geheim
# LDAP_USE_TLS=false

# Microsoft Entra ID (auskommentiert):
# LDAP_HOST=
# AZURE_TENANT_ID=
# AZURE_CLIENT_ID=
# AZURE_CLIENT_SECRET=

# ============================================
# Mail (Mailpit fuer Entwicklung empfohlen)
# ============================================
MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="noreply@${name}.local"
MAIL_FROM_NAME="\${APP_NAME}"

# ============================================
# Vite
# ============================================
VITE_DEV_SERVER_URL=http://localhost:${APP_VITE_PORT}

# ============================================
# Debugbar (nur in Entwicklung)
# ============================================
DEBUGBAR_ENABLED=true
LARAVELEOF

    log_success "Laravel .env Vorlage erstellt: ${CYAN}laravel.env${NC}"
}

# ============================================
# Kommandos
# ============================================

cmd_setup() {
    local name="$1"

    # Validierung: Nur Kleinbuchstaben, Zahlen, Bindestriche
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z0-9]$ ]]; then
        log_error "Projektname darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten."
        log_error "Muss mit Buchstabe/Zahl beginnen und enden."
        exit 1
    fi

    init_registry

    # UID/GID erkennen
    detect_uid

    echo ""

    if project_exists "$name"; then
        log_warn "Projekt '$name' ist bereits registriert."

        # Bestehende Daten laden
        local index
        index=$(python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
print(data['projects']['$name']['index'])
")

        # Pfad aktualisieren (falls Projekt verschoben wurde)
        save_project "$name" "$index" "$SCRIPT_DIR"

        calc_ports "$index"
        generate_env "$name" "$index"
        generate_laravel_env "$name" "$index"

        log_success ".env wurde mit bestehenden Ports neu generiert."
    else
        local index
        index=$(get_next_index)

        save_project "$name" "$index" "$SCRIPT_DIR"
        calc_ports "$index"
        generate_env "$name" "$index"
        generate_laravel_env "$name" "$index"

        log_success "Neues Projekt '$name' registriert (Index: $index)."
        log_success ".env wurde generiert."
    fi

    echo ""
    echo -e "${BOLD}Zugewiesene Ports:${NC}"
    echo -e "  App (Nginx):    ${CYAN}http://localhost:${APP_PORT}${NC}"
    echo -e "  phpMyAdmin:     ${CYAN}http://localhost:${PHPMYADMIN_PORT}${NC}"
    echo -e "  phpLdapAdmin:   ${CYAN}http://localhost:${LDAPADMIN_PORT}${NC}"
    echo -e "  Vite Dev:       ${CYAN}http://localhost:${APP_VITE_PORT}${NC}"
    echo -e "  MySQL:          ${CYAN}localhost:${MYSQL_PORT}${NC}"
    echo -e "  Redis:          ${CYAN}localhost:${REDIS_PORT}${NC}"
    echo -e "  LDAP:           ${CYAN}localhost:${LDAP_PORT}${NC}"
    echo -e "  Subnet:         ${CYAN}${DOCKER_SUBNET}${NC}"
    echo -e "  User:           ${CYAN}${WWWUSER}:${WWWGROUP}${NC}"
    echo ""
    echo -e "${BOLD}Naechste Schritte:${NC}"
    echo -e "  1. docker compose build"
    echo -e "  2. docker compose up -d"
    echo -e "  3. ./setup.sh init-laravel    ${YELLOW}(Laravel installieren + .env deployen)${NC}"
}

cmd_init_laravel() {
    # Docker .env lesen um PROJECT_NAME zu ermitteln
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        log_error "Keine .env gefunden. Zuerst ./setup.sh <projektname> ausfuehren."
        exit 1
    fi

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"

    local container_name="${PROJECT_NAME}-app"

    # Pruefen ob Container laeuft
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_error "Container '${container_name}' laeuft nicht."
        log_error "Zuerst: docker compose up -d"
        exit 1
    fi

    # Pruefen ob src/ existiert
    if [ ! -d "$SRC_DIR" ]; then
        mkdir -p "$SRC_DIR"
        log_info "Verzeichnis src/ erstellt."
    fi

    # Pruefen ob src/ leer ist (oder nur .gitkeep enthaelt)
    local file_count
    file_count=$(find "$SRC_DIR" -mindepth 1 -not -name '.gitkeep' -not -name '.git' | head -5 | wc -l)

    if [ "$file_count" -gt 0 ]; then
        log_warn "Das Verzeichnis src/ ist nicht leer."
        echo ""
        echo -e "  Optionen:"
        echo -e "  ${CYAN}1${NC}) Laravel .env trotzdem nach src/.env kopieren (bestehende wird ueberschrieben)"
        echo -e "  ${CYAN}2${NC}) Abbrechen"
        echo ""
        read -rp "  Auswahl [1/2]: " choice

        case "$choice" in
            1)
                if [ -f "$SCRIPT_DIR/laravel.env" ]; then
                    cp "$SCRIPT_DIR/laravel.env" "$SRC_DIR/.env"
                    log_success "laravel.env nach src/.env kopiert."

                    # APP_KEY generieren
                    log_info "Generiere APP_KEY..."
                    docker exec "$container_name" php artisan key:generate
                    log_success "APP_KEY wurde generiert."
                else
                    log_error "laravel.env nicht gefunden. Zuerst ./setup.sh <projektname> ausfuehren."
                fi
                ;;
            *)
                log_info "Abgebrochen."
                ;;
        esac
        return
    fi

    # src/ ist leer -> Laravel installieren
    echo ""
    echo -e "${BOLD}Laravel 11 Installation${NC}"
    echo ""
    log_info "Installiere Laravel 11 via Composer..."

    docker exec "$container_name" composer create-project laravel/laravel . "11.*"

    if [ $? -eq 0 ]; then
        log_success "Laravel 11 installiert."

        # Berechtigungen korrigieren (Composer lief als Root im Container)
        log_info "Korrigiere Dateiberechtigungen..."
        docker exec "$container_name" chown -R "${WWWUSER:-1000}:${WWWGROUP:-1000}" /var/www/html
        log_success "Berechtigungen korrigiert."

        # SQLite-Datei und Default-Migration entfernen (wir nutzen MySQL)
        rm -f "$SRC_DIR/database/database.sqlite"

        # Laravel .env deployen (MySQL statt SQLite)
        if [ -f "$SCRIPT_DIR/laravel.env" ]; then
            cp "$SCRIPT_DIR/laravel.env" "$SRC_DIR/.env"
            log_success "laravel.env nach src/.env kopiert (MySQL + Redis + LDAP)."

            # APP_KEY generieren
            log_info "Generiere APP_KEY..."
            docker exec "$container_name" php artisan key:generate
            log_success "APP_KEY wurde generiert."

            # Migration auf MySQL ausfuehren
            log_info "Fuehre Datenbank-Migration aus (MySQL)..."
            docker exec "$container_name" php artisan migrate --force
            log_success "Migration abgeschlossen."
        fi

        # Laravel Debugbar installieren
        log_info "Installiere Laravel Debugbar..."
        docker exec "$container_name" composer require barryvdh/laravel-debugbar --dev

        # Berechtigungen nochmals korrigieren
        docker exec "$container_name" chown -R "${WWWUSER:-1000}:${WWWGROUP:-1000}" /var/www/html
        log_success "Laravel Debugbar installiert."

        echo ""
        echo -e "${GREEN}========================================${NC}"
        log_success "Laravel 11 ist bereit!"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BOLD}Erreichbar unter:${NC}"
        echo -e "  App:            ${CYAN}http://localhost:${APP_PORT}${NC}"
        echo -e "  phpMyAdmin:     ${CYAN}http://localhost:${PHPMYADMIN_PORT}${NC}"
        echo -e "  phpLdapAdmin:   ${CYAN}http://localhost:${LDAPADMIN_PORT}${NC}"
        echo -e "  Vite Dev:       ${CYAN}http://localhost:${APP_VITE_PORT}${NC}"
        echo ""
        echo -e "${BOLD}Datenbank:${NC}"
        echo -e "  MySQL:          ${CYAN}localhost:${MYSQL_PORT}${NC}  (User: laravel / secret)"
        echo -e "  Redis:          ${CYAN}localhost:${REDIS_PORT}${NC}"
        echo -e "  LDAP:           ${CYAN}localhost:${LDAP_PORT}${NC}  (Admin: admin123)"
        echo ""
        echo -e "${BOLD}Container:${NC}"
        echo -e "  ${CYAN}docker exec -it ${container_name} bash${NC}"
    else
        log_error "Laravel-Installation fehlgeschlagen."
        exit 1
    fi
}

cmd_list() {
    init_registry

    echo -e "${BOLD}Registrierte Docker-Projekte:${NC}"
    echo ""

    python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

projects = data.get('projects', {})
if not projects:
    print('  Keine Projekte registriert.')
else:
    # Header
    print(f'  {\"Projekt\":<20} {\"Index\":<7} {\"App\":<7} {\"PMA\":<7} {\"MySQL\":<7} {\"Redis\":<7} {\"LDAP\":<7} {\"Erstellt\":<12}')
    print(f'  {\"─\"*20} {\"─\"*7} {\"─\"*7} {\"─\"*7} {\"─\"*7} {\"─\"*7} {\"─\"*7} {\"─\"*12}')
    for name, info in sorted(projects.items(), key=lambda x: x[1]['index']):
        ports = info.get('ports', {})
        print(f'  {name:<20} {info[\"index\"]:<7} {ports.get(\"app\",\"-\"):<7} {ports.get(\"phpmyadmin\",\"-\"):<7} {ports.get(\"mysql\",\"-\"):<7} {ports.get(\"redis\",\"-\"):<7} {ports.get(\"ldap\",\"-\"):<7} {info.get(\"created\",\"-\"):<12}')
"
    echo ""
}

cmd_status() {
    init_registry

    echo -e "${BOLD}Docker-Container Status:${NC}"
    echo ""

    python3 -c "
import json, subprocess, sys

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

projects = data.get('projects', {})
if not projects:
    print('  Keine Projekte registriert.')
    sys.exit(0)

for name in sorted(projects.keys()):
    print(f'  \033[1m{name}\033[0m:')
    try:
        result = subprocess.run(
            ['docker', 'ps', '--filter', f'name={name}-', '--format', '    {{.Names}}\t{{.Status}}\t{{.Ports}}'],
            capture_output=True, text=True, timeout=5
        )
        output = result.stdout.strip()
        if output:
            print(output)
        else:
            print('    (keine laufenden Container)')
    except Exception as e:
        print(f'    (Fehler: {e})')
    print()
"
}

cmd_ports() {
    init_registry

    echo -e "${BOLD}Port-Uebersicht aller Projekte:${NC}"
    echo ""

    python3 -c "
import json

with open('$REGISTRY_FILE') as f:
    data = json.load(f)

projects = data.get('projects', {})
if not projects:
    print('  Keine Projekte registriert.')
else:
    for name, info in sorted(projects.items(), key=lambda x: x[1]['index']):
        ports = info.get('ports', {})
        subnet = info.get('subnet', '-')
        print(f'  \033[1m{name}\033[0m (Index {info[\"index\"]}):')
        print(f'    App:          http://localhost:{ports.get(\"app\", \"-\")}')
        print(f'    phpMyAdmin:   http://localhost:{ports.get(\"phpmyadmin\", \"-\")}')
        print(f'    phpLdapAdmin: http://localhost:{ports.get(\"ldapadmin\", \"-\")}')
        print(f'    Vite Dev:     http://localhost:{ports.get(\"vite\", \"-\")}')
        print(f'    MySQL:        localhost:{ports.get(\"mysql\", \"-\")}')
        print(f'    Redis:        localhost:{ports.get(\"redis\", \"-\")}')
        print(f'    LDAP:         localhost:{ports.get(\"ldap\", \"-\")}')
        print(f'    Subnet:       {subnet}')
        print()
"
}

cmd_help() {
    echo -e "${BOLD}Laravel Docker Setup - Automatische Port-Verwaltung${NC}"
    echo ""
    echo -e "Verwendung:"
    echo -e "  ${CYAN}./setup.sh${NC}                    Interaktive Einrichtung"
    echo -e "  ${CYAN}./setup.sh <projektname>${NC}      Direkte Einrichtung"
    echo -e "  ${CYAN}./setup.sh init-laravel${NC}       Laravel installieren + .env deployen"
    echo -e "  ${CYAN}./setup.sh list${NC}               Alle Projekte anzeigen"
    echo -e "  ${CYAN}./setup.sh remove <name>${NC}      Projekt entfernen"
    echo -e "  ${CYAN}./setup.sh status${NC}             Laufende Container anzeigen"
    echo -e "  ${CYAN}./setup.sh ports${NC}              Port-Uebersicht"
    echo -e "  ${CYAN}./setup.sh help${NC}               Diese Hilfe"
    echo ""
    echo -e "Typischer Ablauf:"
    echo -e "  1. ${CYAN}./setup.sh mein-projekt${NC}        Projekt registrieren + .env generieren"
    echo -e "  2. ${CYAN}docker compose build${NC}           Image bauen"
    echo -e "  3. ${CYAN}docker compose up -d${NC}           Container starten"
    echo -e "  4. ${CYAN}./setup.sh init-laravel${NC}        Laravel 11 installieren + konfigurieren"
    echo ""
    echo -e "Port-Schema (pro Projekt-Index):"
    echo -e "  App:       8000 + (Index * 100)"
    echo -e "  PMA:       App-Port + 80"
    echo -e "  LdapAdmin: App-Port + 81"
    echo -e "  Vite:      5173 + Index"
    echo -e "  MySQL:     3306 + Index"
    echo -e "  Redis:     6379 + Index"
    echo -e "  LDAP:      389 + Index"
    echo -e "  Subnet:    172.(20+Index).0.0/16"
    echo ""
    echo -e "Registry: ${CYAN}$REGISTRY_FILE${NC}"
}

# ============================================
# Hauptprogramm
# ============================================

# Pruefen ob python3 vorhanden ist
if ! command -v python3 &> /dev/null; then
    log_error "python3 wird benoetigt aber nicht gefunden."
    log_error "Installiere mit: sudo apt install python3"
    exit 1
fi

case "${1:-}" in
    "")
        # Interaktiver Modus
        echo -e "${BOLD}Laravel Docker Setup${NC}"
        echo ""
        read -rp "Projektname (kleinbuchstaben, bindestriche erlaubt): " PROJECT_NAME
        if [ -z "$PROJECT_NAME" ]; then
            log_error "Projektname darf nicht leer sein."
            exit 1
        fi
        cmd_setup "$PROJECT_NAME"
        ;;
    init-laravel)
        cmd_init_laravel
        ;;
    list)
        cmd_list
        ;;
    remove)
        if [ -z "${2:-}" ]; then
            log_error "Projektname fehlt. Verwendung: ./setup.sh remove <name>"
            exit 1
        fi
        remove_project "$2"
        ;;
    status)
        cmd_status
        ;;
    ports)
        cmd_ports
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        cmd_setup "$1"
        ;;
esac
