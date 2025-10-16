#!/bin/bash

#Script para la configuración de copia de seguridad

set -e  # Detiene el script si un comando falla

#------------------------ZONA DE FUNCIONES----------------------------------------------------------------

#Comprobamos si eres root

function soy_root(){
echo "Comprobando que eres root..."
sleep 1
if [[ ! $UID -eq 0 ]]; then
 echo -e "${YELLOW}Este script debe ejecutarse como root, vuelve a entrar como usuario root${RESET}"
exit
fi
}

#Creamos directorio en el destino para guardar la copia del sistema, el nombre del directorio llevará la fecha y hora de creación

function mk_dir(){

dir_name=$(date +"%Y-%m-%d")-full

if sudo mkdir "/mnt/copias_seguridad/$dir_name"; then
	echo "Directorio creado: $dir_name"
else
	echo "No se pudo crear directorio de destino."
fi
}

#Comprobamos si está instalada herramienta rsync

function check_rsync(){

if command -v rsync &> /dev/null; then
	return 0
fi

echo "Instalando rsync..."
   sleep 1
   sudo apt update && sudo apt install rsync -y

#Comprobamos de nuevo que se haya instalado bien
if command -v rsync &> /dev/null; then
        return 0
else
   echo "Parece que no es posible instalar rsync en este equipo"
   return 1
fi
}

#Generamos el fichero con la paqueteria instalada

function fich_paquetes(){

dir_name=$(date +"%Y-%m-%d")-full
destino="/mnt/copias_seguridad/$dir_name"

dpkg --get-selections > "$destino/pkg_instalados.txt"

}


#Función pricncipal para copia de seguridad con herramienta rsync

function backup(){

dir_name=$(date +"%Y-%m-%d")-full
destino="/mnt/copias_seguridad/$dir_name"

echo "Iniciando copia de seguridad del sistema en $destino..."

if sudo rsync -aHAXvz  --info=progress2 \
        --exclude={"/proc/*","/sys/*","/dev/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
        / "$destino"; then
        echo "Copia de seguridad completada correctamente."
    else
	sudo rm -rf "$destino"
        echo "Error durante la copia de seguridad."
        return 1
    fi
}


#-------------------------ZONA DE EJECUCIÓN------------------------------------------------------------

soy_root
check_rsync
mk_dir
fich_paquetes
backup
