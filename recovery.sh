#!/bin/bash

# Script de recuperación de backups
# Uso: sudo ./recovery.sh

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuración - AJUSTA ESTOS VALORES
BACKUP_DEVICE="/dev/vdb1"      # Dispositivo del volumen de backup
MACHINE_DEVICE="/dev/vdc1"     # Dispositivo de la máquina rota
BACKUP_MOUNT="/mnt/backup"     # Punto de montaje para backups
MACHINE_MOUNT="/mnt/maquina"   # Punto de montaje para máquina rota

# Directorios a excluir en el rsync
EXCLUDE_DIRS="/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}  Script de Recuperación Backup${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root (sudo)${NC}" 
   exit 1
fi

# Función para limpiar montajes al salir
cleanup() {
    echo ""
    echo -e "${YELLOW}Desmontando volúmenes...${NC}"
    umount "$MACHINE_MOUNT" 2>/dev/null || true
    umount "$BACKUP_MOUNT" 2>/dev/null || true
    echo -e "${GREEN}Limpieza completada${NC}"
}

trap cleanup EXIT

# Crear puntos de montaje si no existen
echo -e "${YELLOW}Preparando puntos de montaje...${NC}"
mkdir -p "$BACKUP_MOUNT"
mkdir -p "$MACHINE_MOUNT"

# Montar volumen de backup
echo -e "${YELLOW}Montando volumen de backup desde $BACKUP_DEVICE...${NC}"
if mount | grep -q "$BACKUP_MOUNT"; then
    echo -e "${YELLOW}El volumen de backup ya estaba montado${NC}"
else
    mount "$BACKUP_DEVICE" "$BACKUP_MOUNT"
    echo -e "${GREEN}✓ Volumen de backup montado${NC}"
fi

# Montar volumen de máquina rota
echo -e "${YELLOW}Montando volumen de máquina rota desde $MACHINE_DEVICE...${NC}"
if mount | grep -q "$MACHINE_MOUNT"; then
    echo -e "${YELLOW}El volumen de la máquina ya estaba montado${NC}"
else
    mount "$MACHINE_DEVICE" "$MACHINE_MOUNT"
    echo -e "${GREEN}✓ Volumen de máquina montado${NC}"
fi

echo ""
echo -e "${GREEN}Volúmenes montados correctamente${NC}"
echo ""

# Listar backups disponibles
echo -e "${YELLOW}Buscando backups disponibles...${NC}"
echo ""

# Crear array con todos los backups ordenados
mapfile -t all_backups < <(ls -1 "$BACKUP_MOUNT" | grep -v "lost+found" | sort)

if [ ${#all_backups[@]} -eq 0 ]; then
    echo -e "${RED}No se encontraron backups en $BACKUP_MOUNT${NC}"
    exit 1
fi

# Identificar backups FULL y crear puntos de restauración
declare -A restore_points
last_full=""

for backup in "${all_backups[@]}"; do
    if [[ $backup == *"-full" ]]; then
        last_full="$backup"
        restore_points[$backup]="$backup"
    elif [[ $backup == *"-incr" ]] && [[ -n "$last_full" ]]; then
        restore_points[$backup]="$last_full → ... → $backup"
    fi
done

# Convertir a array ordenado para el menú
mapfile -t restore_dates < <(printf '%s\n' "${!restore_points[@]}" | sort)

if [ ${#restore_dates[@]} -eq 0 ]; then
    echo -e "${RED}No se encontraron backups válidos${NC}"
    exit 1
fi

# Mostrar menú de puntos de restauración
echo -e "${GREEN}Puntos de restauración disponibles:${NC}"
echo -e "${YELLOW}(Se restaurará el FULL correspondiente + todos los incrementales hasta la fecha)${NC}"
echo ""

for i in "${!restore_dates[@]}"; do
    restore_date="${restore_dates[$i]}"
    
    if [[ $restore_date == *"-full" ]]; then
        printf "  %2d) ${GREEN}%-20s${NC} [FULL únicamente]\n" $((i+1)) "$restore_date"
    else
        printf "  %2d) ${YELLOW}%-20s${NC} [FULL + incrementales]\n" $((i+1)) "$restore_date"
    fi
done

echo ""
echo -e "${YELLOW}Opciones especiales:${NC}"
echo "   0) Salir sin hacer nada"
echo ""

# Solicitar selección
while true; do
    read -p "Selecciona el punto de restauración (0-${#restore_dates[@]}): " selection
    
    if [[ "$selection" == "0" ]]; then
        echo -e "${YELLOW}Operación cancelada${NC}"
        exit 0
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#restore_dates[@]}" ]; then
        break
    else
        echo -e "${RED}Selección inválida. Introduce un número entre 0 y ${#restore_dates[@]}${NC}"
    fi
done

TARGET_DATE="${restore_dates[$((selection-1))]}"

# Determinar qué backups aplicar
echo ""
echo -e "${GREEN}Punto seleccionado: $TARGET_DATE${NC}"
echo ""

# Encontrar el FULL base
FULL_BACKUP=""
for backup in "${all_backups[@]}"; do
    if [[ $backup == *"-full" ]]; then
        FULL_BACKUP="$backup"
    fi
    if [[ "$backup" == "$TARGET_DATE" ]]; then
        break
    fi
done

if [[ -z "$FULL_BACKUP" ]]; then
    echo -e "${RED}Error: No se encontró backup FULL base${NC}"
    exit 1
fi

# Crear lista de backups a aplicar
BACKUPS_TO_APPLY=("$FULL_BACKUP")

if [[ "$TARGET_DATE" != "$FULL_BACKUP" ]]; then
    # Añadir incrementales hasta la fecha objetivo
    found_full=false
    for backup in "${all_backups[@]}"; do
        if [[ "$backup" == "$FULL_BACKUP" ]]; then
            found_full=true
            continue
        fi
        
        if $found_full && [[ $backup == *"-incr" ]]; then
            BACKUPS_TO_APPLY+=("$backup")
            if [[ "$backup" == "$TARGET_DATE" ]]; then
                break
            fi
        fi
    done
fi

# Mostrar plan de restauración
echo -e "${YELLOW}Plan de restauración:${NC}"
for i in "${!BACKUPS_TO_APPLY[@]}"; do
    backup="${BACKUPS_TO_APPLY[$i]}"
    if [[ $i -eq 0 ]]; then
        echo -e "  ${GREEN}1. $backup${NC} [FULL con --delete]"
    else
        echo -e "  ${YELLOW}$((i+1)). $backup${NC} [INCREMENTAL]"
    fi
done

# Confirmación final
echo ""
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}  CONFIRMACIÓN DE RESTAURACIÓN${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "  Destino: ${RED}$MACHINE_MOUNT${NC}"
echo -e "  Backups a aplicar: ${GREEN}${#BACKUPS_TO_APPLY[@]}${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""
read -p "¿Proceder con la restauración? (s/N): " final_confirm

if [[ ! "$final_confirm" =~ ^[sS]$ ]]; then
    echo -e "${YELLOW}Operación cancelada${NC}"
    exit 0
fi

# Ejecutar restauración
echo ""
echo -e "${GREEN}Iniciando restauración...${NC}"
echo ""

SUCCESS=true

for i in "${!BACKUPS_TO_APPLY[@]}"; do
    backup="${BACKUPS_TO_APPLY[$i]}"
    backup_path="$BACKUP_MOUNT/$backup"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Paso $((i+1))/${#BACKUPS_TO_APPLY[@]}: $backup${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Construir comando rsync
    RSYNC_CMD="rsync -aAXv --exclude={$EXCLUDE_DIRS}"
    
    # Solo el primer backup (FULL) usa --delete
    if [[ $i -eq 0 ]]; then
        RSYNC_CMD="$RSYNC_CMD --delete"
        echo -e "${YELLOW}Modo: FULL (con --delete)${NC}"
    else
        echo -e "${YELLOW}Modo: INCREMENTAL (sin --delete)${NC}"
    fi
    
    RSYNC_CMD="$RSYNC_CMD $backup_path/ $MACHINE_MOUNT/"
    
    echo -e "${YELLOW}Ejecutando: rsync...${NC}"
    echo ""
    
    # Ejecutar rsync
    if ! eval $RSYNC_CMD; then
        echo ""
        echo -e "${RED}✗ Error al aplicar $backup${NC}"
        SUCCESS=false
        break
    fi
    
    echo ""
    echo -e "${GREEN}✓ $backup aplicado correctamente${NC}"
    echo ""
done

if $SUCCESS; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ RESTAURACIÓN COMPLETADA${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    # Mostrar resumen
    echo -e "${YELLOW}Resumen:${NC}"
    echo "  - Punto de restauración: $TARGET_DATE"
    echo "  - Backups aplicados: ${#BACKUPS_TO_APPLY[@]}"
    echo "  - Destino: $MACHINE_MOUNT"
    echo ""
    
    # Recordatorio importante
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  RECORDATORIOS IMPORTANTES:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo "  1. Verifica/edita /etc/fstab si es necesario"
    echo "  2. Considera establecer contraseñas si están bloqueadas:"
    echo "     - mount --bind /dev $MACHINE_MOUNT/dev"
    echo "     - mount --bind /proc $MACHINE_MOUNT/proc"
    echo "     - mount --bind /sys $MACHINE_MOUNT/sys"
    echo "     - chroot $MACHINE_MOUNT"
    echo "     - passwd root"
    echo "     - exit"
    echo "  3. El volumen será desmontado automáticamente"
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo ""
    
    read -p "Presiona Enter para desmontar y finalizar..."
    
else
    echo ""
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}  ✗ ERROR EN LA RESTAURACIÓN${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}Revisa los mensajes de error anteriores${NC}"
    exit 1
fi
