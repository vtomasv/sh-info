#!/bin/sh
# recon_basico.sh
# Recolección básica de información Linux usando comandos esenciales.
# Uso:
#   chmod +x recon_basico.sh
#   sudo ./recon_basico.sh [directorio_salida]

LC_ALL=C
export LC_ALL

have() {
    command -v "$1" >/dev/null 2>&1
}

HOST=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo desconocido)
DATE=$(date +%Y%m%d_%H%M%S)
OUTDIR="${1:-./recon_${HOST}_${DATE}}"

mkdir -p "$OUTDIR" || {
    echo "No se pudo crear el directorio $OUTDIR"
    exit 1
}

LOG="$OUTDIR/report.txt"
: > "$LOG"

if have tee; then
    log() { printf '%s\n' "$*" | tee -a "$LOG"; }
else
    log() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$LOG"; }
fi

run() {
    log ""
    log "== $* =="
    TMP="$OUTDIR/.tmp.$$"
    "$@" > "$TMP" 2>&1
    while IFS= read -r line; do
        log "$line"
    done < "$TMP"
    rm -f "$TMP"
}

run_if() {
    cmd="$1"
    shift
    if have "$cmd"; then
        run "$@"
    else
        log ""
        log "== $cmd no disponible =="
    fi
}

show_file() {
    f="$1"
    log ""
    log "--- $f ---"
    if [ -e "$f" ]; then
        ls -l "$f" 2>&1 | while IFS= read -r line; do log "$line"; done
        if [ -r "$f" ]; then
            cat "$f" 2>&1 | while IFS= read -r line; do log "$line"; done
        else
            log "[Sin permiso de lectura]"
        fi
    else
        log "[No existe]"
    fi
}

show_dir() {
    d="$1"
    log ""
    log "--- $d ---"
    if [ -d "$d" ]; then
        ls -la "$d" 2>&1 | while IFS= read -r line; do log "$line"; done
    else
        log "[No existe]"
    fi
}

# Decodifica puertos en escucha desde /proc/net/tcp y /proc/net/tcp6
hexport() {
    awk '
        function h2d(s,   i,c,v) {
            v=0
            s=toupper(s)
            for (i=1; i<=length(s); i++) {
                c=substr(s,i,1)
                v = v*16 + index("0123456789ABCDEF", c) - 1
            }
            return v
        }
        NR>1 && $4=="0A" {
            split($2,a,":")
            printf "%s:%d\n", a[1], h2d(a[2])
        }
    ' "$1" 2>/dev/null
}

log "=============================================="
log " RECON BÁSICO LINUX"
log " Fecha: $(date)"
log " Host: $HOST"
log " Usuario: $(id 2>/dev/null || whoami)"
log " Directorio: $OUTDIR"
log "=============================================="

log ""
log "### SISTEMA ###"
run_if uname uname -a
[ -f /etc/os-release ] && show_file /etc/os-release
[ -f /etc/issue ] && show_file /etc/issue
run_if uptime uptime
run_if id id
run_if who who
run_if w w

if have awk && [ -r /proc/cpuinfo ]; then
    log ""
    log "--- Número de CPUs ---"
    awk '/^processor/{c++} END{print c+0}' /proc/cpuinfo | while IFS= read -r line; do log "$line"; done
fi

run_if free free -m
run_if df df -h
run_if mount mount
run_if lsblk lsblk

log ""
log "### RED ###"
if have ip; then
    run ip addr
    run ip route
elif have ifconfig; then
    run ifconfig
    run_if route route -n
else
    log ""
    log "== Ni ip ni ifconfig disponibles =="
fi

[ -f /etc/resolv.conf ] && show_file /etc/resolv.conf
[ -f /etc/hosts ] && show_file /etc/hosts
[ -f /etc/hostname ] && show_file /etc/hostname

log ""
log "### PUERTOS EN ESCUCHA ###"
if have ss; then
    run ss -tulpn
elif have netstat; then
    run netstat -tulpn
else
    log "ss/netstat no disponibles. Usando /proc/net/tcp*"
    if [ -r /proc/net/tcp ]; then
        log ""
        log "--- /proc/net/tcp LISTEN (IP_HEX:PUERTO) ---"
        hexport /proc/net/tcp | while IFS= read -r line; do log "$line"; done
    fi
    if [ -r /proc/net/tcp6 ]; then
        log ""
        log "--- /proc/net/tcp6 LISTEN (IP_HEX:PUERTO) ---"
        hexport /proc/net/tcp6 | while IFS= read -r line; do log "$line"; done
    fi
fi

log ""
log "### USUARIOS Y CONTRASEÑAS ###"
show_file /etc/passwd
show_file /etc/shadow
show_file /etc/group
show_file /etc/gshadow

if [ -r /etc/passwd ] && have awk; then
    log ""
    log "--- Usuarios con UID 0 / equivalentes a root ---"
    awk -F: '$3==0 {print}' /etc/passwd | while IFS= read -r line; do log "$line"; done
fi

log ""
log "### SUDOERS ###"
show_file /etc/sudoers
for f in /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    show_file "$f"
done

log ""
log "### SSH ###"
show_file /etc/ssh/sshd_config
show_file /etc/ssh/ssh_config

log ""
log "### CLAVES SSH ###"
for d in /root/.ssh /home/*/.ssh; do
    [ -d "$d" ] || continue
    show_dir "$d"
    for f in "$d/authorized_keys" "$d/known_hosts" "$d/config"; do
        [ -e "$f" ] && show_file "$f"
    done
done

log ""
log "### PROCESOS ###"
if have ps; then
    if ps aux >/dev/null 2>&1; then
        run ps aux
    else
        run ps -ef
    fi
else
    log "ps no disponible. Listando /proc/[pid]/comm:"
    for p in /proc/[0-9]*; do
        [ -d "$p" ] || continue
        pid=${p#/proc/}
        comm="?"
        [ -r "$p/comm" ] && comm=$(cat "$p/comm" 2>/dev/null)
        log "$pid $comm"
    done
fi

log ""
log "### TAREAS PROGRAMADAS ###"
show_file /etc/crontab
for f in /etc/cron.d/*; do
    [ -f "$f" ] || continue
    show_file "$f"
done
show_dir /var/spool/cron
show_dir /var/spool/cron/crontabs

if have crontab; then
    run crontab -l
fi

if have systemctl; then
    log ""
    log "### SERVICIOS SYSTEMD EN EJECUCIÓN ###"
    run systemctl list-units --type=service --state=running
fi

log ""
log "=============================================="
log " Reporte guardado en: $LOG"
log "=============================================="
