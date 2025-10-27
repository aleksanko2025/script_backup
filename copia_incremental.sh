#!/bin/bash

# Script para copia de seguridad incremental

set -e

#------------------------ZONA DE FUNCIONES----------------------------------------------------------------

function soy_root(){
    echo "Comprobando que eres root..."
    sleep 1
    if [[ ! $UID -eq 0 ]]; then
        echo "Este script debe ejecutarse como root"
        exit
    fi
}

function check_rsync(){
    if command -v rsync &> /dev/null; then
        return 0
    fi

    echo "Instalando rsync..."
    sleep 1
    sudo apt update && sudo apt install rsync -y

    if command -v rsync &> /dev/null; then
        return 0
    else
        echo "No es posible instalar rsync en este equipo"
        return 1
    fi
}

# Función para generar directorio incremental basado en la fecha y última copia
function mk_dir_incremental(){
    last_full=$(ls -1d /mnt/vol-backup/*-full 2>/dev/null | sort | tail -n1)
    if [[ -z "$last_full" ]]; then
        echo "No se encontró copia full. Ejecuta primero el backup completo."
        exit 1
    fi

    dir_name=$(date +"%Y-%m-%d")-incr
    destino="/mnt/vol-backup/$dir_name"

    if mkdir "$destino"; then
        echo "Directorio incremental creado: $destino"
    else
        echo "No se pudo crear el directorio incremental."
        exit 1
    fi
}

# Guardamos la lista de paquetes instalados
function fich_paquetes(){
    dpkg --get-selections > "$destino/pkg_instalados.txt"
}

# Copia incremental usando rsync con --link-dest
function backup_incremental(){
    last_full=$(ls -1d /mnt/vol-backup/*-full 2>/dev/null | sort | tail -n1)

    echo "Iniciando copia incremental basada en $last_full..."

    rsync -aHAXvz --info=progress2 \
        --link-dest="$last_full" \
        --exclude={"/proc/*","/sys/*","/dev/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
        / "$destino"

    echo "Copia incremental completada correctamente."
}

#-------------------------ZONA DE EJECUCIÓN------------------------------------------------------------

soy_root
check_rsync
mk_dir_incremental
fich_paquetes "$destino"
backup_incremental "$destino"
