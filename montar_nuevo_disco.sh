#!/bin/bash
# Script para configurar disco de backup
set -e

#------------------------ZONA DE FUNCIONES----------------------------------------------------------------
function soy_root(){
    if [[ ! $UID -eq 0 ]]; then
        echo "Este script debe ejecutarse como root"
        exit 1
    fi
}

function listar_discos(){
    echo "=== Discos disponibles ==="
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
}

function seleccionar_disco(){
    read -p "Introduce el nombre del disco (ej: sdb, sdc, vdb): " disco
    disco_path="/dev/$disco"
    
    if [[ ! -b "$disco_path" ]]; then
        echo "El disco $disco_path no existe"
        exit 1
    fi
    
    echo "¡ADVERTENCIA! Esto borrará TODOS los datos en $disco_path"
    lsblk "$disco_path"
    read -p "¿Continuar? (escribe SI en mayúsculas): " confirmacion
    
    if [[ "$confirmacion" != "SI" ]]; then
        echo "Operación cancelada"
        exit 0
    fi
}

function particionar_disco(){
    echo "Creando partición en $disco_path..."
    
    # Limpiar cualquier partición existente y crear nueva
    (
        echo o      # Crear nueva tabla de particiones DOS
        echo n      # Nueva partición
        echo p      # Primaria
        echo 1      # Número de partición
        echo        # Primer sector (default)
        echo        # Último sector (default - usa todo el disco)
        echo w      # Escribir cambios
    ) | fdisk "$disco_path" > /dev/null 2>&1
    
    
    # Determinar nombre de la partición
    if [[ "$disco_path" =~ nvme|mmcblk ]]; then
        particion="${disco_path}p1"
    else
        particion="${disco_path}1"
    fi
    
    echo "Partición creada: $particion"
}

function formatear_particion(){
    echo "Formateando $particion con ext4..."
    mkfs.ext4 -F "$particion" > /dev/null 2>&1
    echo "Partición formateada"
}

function determinar_numero(){
    numero=1
    while [[ -d "/mnt/vol-backup$numero" ]]; do
        ((numero++))
    done
    vol_numero=$numero
    punto_montaje="/mnt/vol-backup$numero"
}

function crear_y_montar(){
    mkdir -p "$punto_montaje"
    mount "$particion" "$punto_montaje"
    echo "Disco montado en $punto_montaje"
}

function configurar_fstab(){
    uuid=$(blkid -s UUID -o value "$particion")
    
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid $punto_montaje ext4 defaults 0 2" >> /etc/fstab
        echo "Entrada añadida a /etc/fstab"
    fi
}

function actualizar_scripts(){
    echo ""
    echo "Actualizando scripts de backup..."
    
    script_full="/usr/local/bin/backup_equipo.sh"
    script_incr="/usr/local/bin/copia-incremental.sh"
    
    # Actualizar script full
    if [[ -f "$script_full" ]]; then
        # Hacer backup del original
        cp "$script_full" "${script_full}.bak.$(date +%Y%m%d-%H%M%S)"
        # Cambiar todas las rutas /mnt/vol-backupX/ por la nueva
        sed -i "s|/mnt/vol-backup[0-9]\+|$punto_montaje|g" "$script_full"
        echo "✓ Script full actualizado: $script_full"
    else
        echo "No se encontró: $script_full"
    fi
    
    # Actualizar script incremental
    if [[ -f "$script_incr" ]]; then
        # Hacer backup del original
        cp "$script_incr" "${script_incr}.bak.$(date +%Y%m%d-%H%M%S)"
        # Cambiar todas las rutas /mnt/vol-backupX/ por la nueva
        sed -i "s|/mnt/vol-backup[0-9]\+|$punto_montaje|g" "$script_incr"
        echo "✓ Script incremental actualizado: $script_incr"
    else
        echo "⚠ No se encontró: $script_incr"
    fi
    
    echo ""
    echo "Backups de scripts originales guardados con extensión .bak"
}

function mostrar_resumen(){
    echo ""
    echo "=== Configuración completada ==="
    echo "Disco: $disco_path"
    echo "Partición: $particion"
    echo "Punto de montaje: $punto_montaje"
    echo "UUID: $(blkid -s UUID -o value $particion)"
    echo ""
    df -h "$punto_montaje"
}

#-------------------------ZONA DE EJECUCIÓN------------------------------------------------------------
soy_root
listar_discos
seleccionar_disco
particionar_disco
formatear_particion
determinar_numero
crear_y_montar
configurar_fstab
actualizar_scripts
mostrar_resumen
