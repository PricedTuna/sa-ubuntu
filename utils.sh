#!/bin/bash

# Función para imprimir mensajes
function PrintMessage() {
    local mensaje=$1
    local tipo=$2
    case $tipo in
        "info")
            echo -e "\033[1;32m$mensaje\033[0m"  # Verde
            ;;
        "advertencia")
            echo -e "\033[1;33m$mensaje\033[0m"  # Amarillo
            ;;
        "error")
            echo -e "\033[1;31m$mensaje\033[0m"  # Rojo
            ;;
        *)
            echo "$mensaje"  # Normal
            ;;
    esac
}

# Función para solicitar entrada del usuario con validación
function solicitar_input() {
    local mensaje=$1
    local variable
    while true; do
        read -rp "$mensaje" variable
        if [[ -n $variable || -z $variable ]]; then
            echo "$variable"
            break
        else
            PrintMessage "Entrada no válida. Por favor, intentalo de nuevo." "error"
        fi
    done
}
