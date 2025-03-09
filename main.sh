#!/bin/bash

source ./utils.sh
source ./static_ip.sh
source ./dns.sh
source ./dhcp.sh
source ./ssh.sh

# Menú interactivo
while true; do
    echo "\n===== Menú de Configuración ====="
    echo "1) Salir"
    echo "2) Configurar IP fija"
    echo "3) Configurar servidor DNS"
    echo "4) Configurar servidor DHCP"
    echo "5) Configrar ser vidor SSH"
    read -rp "Opción: " opcion

    case $opcion in
        1)
            echo "Saliendo..."
            exit 0
            ;;
        2)
            set_static_ip
            ;;
        3)
            configurar_dns
            ;;
        4)
            configurar_dhcp
            ;;
        5)
            configurar_ssh
            ;;
        *)
            PrintMessage "Opción no válida. Saliendo..." "error"
            exit 1
            ;;
    esac
done
