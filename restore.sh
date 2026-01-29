#!/bin/bash
# Script simple para restaurar desde backup
# PREREQUISITOS:
# - Estar en una máquina de rescate con ambos volúmenes acoplados
# - vol-backup montado en /mnt/backup
# - vol-dañado montado en /mnt/restaurar

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   RESTAURACIÓN SIMPLE DE BACKUP${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Verificar que somos root
if [[ $UID -ne 0 ]]; then
    echo -e "${RED}Error: Este script debe ejecutarse como root${NC}"
    exit 1
fi

# Pedir rutas de montaje
echo "Introduce la ruta donde está montado el VOLUMEN DE BACKUP:"
read -p "(ej: /mnt/backup): " BACKUP_PATH
BACKUP_PATH=${BACKUP_PATH:-/mnt/backup}

echo ""
echo "Introduce la ruta donde está montado el VOLUMEN A RESTAURAR (tu disco dañado):"
read -p "(ej: /mnt/restaurar): " RESTORE_PATH
RESTORE_PATH=${RESTORE_PATH:-/mnt/restaurar}

# Verificar que existen los directorios
if [[ ! -d "$BACKUP_PATH" ]]; then
    echo -e "${RED}Error: No existe el directorio $BACKUP_PATH${NC}"
    exit 1
fi

if [[ ! -d "$RESTORE_PATH" ]]; then
    echo -e "${RED}Error: No existe el directorio $RESTORE_PATH${NC}"
    exit 1
fi

# Listar backups disponibles
echo ""
echo -e "${YELLOW}Backups disponibles:${NC}"
echo ""

FULL_BACKUPS=($(ls -1d $BACKUP_PATH/*-full 2>/dev/null | sort))
INCR_BACKUPS=($(ls -1d $BACKUP_PATH/*-incr 2>/dev/null | sort))

if [[ ${#FULL_BACKUPS[@]} -eq 0 ]]; then
    echo -e "${RED}No se encontraron backups full en $BACKUP_PATH${NC}"
    exit 1
fi

echo "COPIAS COMPLETAS (FULL):"
for i in "${!FULL_BACKUPS[@]}"; do
    echo "  $((i+1))) $(basename ${FULL_BACKUPS[$i]})"
done

echo ""
if [[ ${#INCR_BACKUPS[@]} -gt 0 ]]; then
    echo "COPIAS INCREMENTALES (INCR):"
    for i in "${!INCR_BACKUPS[@]}"; do
        echo "  $((i+1))) $(basename ${INCR_BACKUPS[$i]})"
    done
else
    echo "(No hay copias incrementales)"
fi

# Seleccionar backup FULL
echo ""
read -p "Selecciona el número de la copia FULL a restaurar: " FULL_NUM
FULL_NUM=$((FULL_NUM-1))

if [[ $FULL_NUM -lt 0 ]] || [[ $FULL_NUM -ge ${#FULL_BACKUPS[@]} ]]; then
    echo -e "${RED}Selección inválida${NC}"
    exit 1
fi

SELECTED_FULL="${FULL_BACKUPS[$FULL_NUM]}"

# Preguntar si quiere aplicar incremental
SELECTED_INCR=""
if [[ ${#INCR_BACKUPS[@]} -gt 0 ]]; then
    echo ""
    read -p "¿Quieres aplicar también una copia INCREMENTAL? (s/N): " APPLY_INCR
    if [[ "$APPLY_INCR" == "s" ]] || [[ "$APPLY_INCR" == "S" ]]; then
        read -p "Selecciona el número de la copia INCREMENTAL: " INCR_NUM
        INCR_NUM=$((INCR_NUM-1))
        
        if [[ $INCR_NUM -ge 0 ]] && [[ $INCR_NUM -lt ${#INCR_BACKUPS[@]} ]]; then
            SELECTED_INCR="${INCR_BACKUPS[$INCR_NUM]}"
        else
            echo -e "${YELLOW}Número inválido, se omitirá la incremental${NC}"
        fi
    fi
fi

# Mostrar resumen
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}RESUMEN DE RESTAURACIÓN:${NC}"
echo -e "${YELLOW}========================================${NC}"
echo "Origen FULL: $(basename $SELECTED_FULL)"
if [[ -n "$SELECTED_INCR" ]]; then
    echo "Origen INCR: $(basename $SELECTED_INCR)"
fi
echo "Destino:     $RESTORE_PATH"
echo ""
echo -e "${RED}ADVERTENCIA: Esto BORRARÁ todos los datos actuales en $RESTORE_PATH${NC}"
echo ""
read -p "¿Estás SEGURO de continuar? Escribe 'SI' para confirmar: " CONFIRM

if [[ "$CONFIRM" != "SI" ]]; then
    echo "Restauración cancelada"
    exit 0
fi

# Instalar rsync si no está
if ! command -v rsync &> /dev/null; then
    echo "Instalando rsync..."
    apt update && apt install -y rsync
fi

# RESTAURAR COPIA FULL
echo ""
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}Restaurando copia FULL...${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""

rsync -aHAXvz --info=progress2 \
    --exclude={"/proc/*","/sys/*","/dev/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    --delete \
    "$SELECTED_FULL/" "$RESTORE_PATH/"

echo ""
echo -e "${GREEN}✓ Copia FULL restaurada${NC}"

# RESTAURAR COPIA INCREMENTAL (si se seleccionó)
if [[ -n "$SELECTED_INCR" ]]; then
    echo ""
    echo -e "${GREEN}=======================================${NC}"
    echo -e "${GREEN}Aplicando copia INCREMENTAL...${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo ""
    
    rsync -aHAXvz --info=progress2 \
        --exclude={"/proc/*","/sys/*","/dev/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
        "$SELECTED_INCR/" "$RESTORE_PATH/"
    
    echo ""
    echo -e "${GREEN}✓ Copia INCREMENTAL aplicada${NC}"
fi

# Recrear directorios del sistema
echo ""
echo "Recreando directorios del sistema..."
mkdir -p "$RESTORE_PATH"/{proc,sys,dev,tmp,run,mnt,media,lost+found}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   RESTAURACIÓN COMPLETADA${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Siguientes pasos:"
echo ""
echo "1. Verifica /etc/fstab en el volumen restaurado:"
echo "   nano $RESTORE_PATH/etc/fstab"
echo ""
echo "2. Si el UUID del volumen cambió, ajústalo:"
echo "   blkid  # para ver el UUID real del disco restaurado"
echo ""
echo "3. Instalar GRUB (si es necesario para bootear):"
echo "   mount --bind /dev $RESTORE_PATH/dev"
echo "   mount --bind /proc $RESTORE_PATH/proc"
echo "   mount --bind /sys $RESTORE_PATH/sys"
echo "   chroot $RESTORE_PATH"
echo "   grub-install /dev/vdX  # reemplaza vdX con tu disco"
echo "   update-grub"
echo "   exit"
echo "   umount $RESTORE_PATH/{dev,proc,sys}"
echo ""
echo "4. Desmontar y desacoplar volúmenes de esta VM de rescate"
echo "5. Acoplar el volumen restaurado a tu instancia original"
echo ""
