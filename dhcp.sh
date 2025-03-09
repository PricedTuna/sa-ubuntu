#!/bin/bash

source ./utils.sh  # Incluir las funciones comunes

# Función para configurar el servidor DHCP
function configurar_dhcp() {
    # Solicitar parámetros al usuario
    interfaz_v4=$(solicitar_input "Introduce la interfaz de red interna (enp0sX): ")
    red=$(solicitar_input "Introduce la red (192.168.1.10): ")
    subred=$(solicitar_input "Introduce la submáscara (255.255.255.0): ")
    ip_inicio=$(solicitar_input "Introduce la IP de inicio del rango (192.168.1.100): ")
    ip_fin=$(solicitar_input "Introduce la IP final el rango (192.168.1.200): ")
    puerta_enlace=$(solicitar_input "Introduce la puerta de enlace (192.168.1.1): ")
    dns=$(solicitar_input "Introduce el servidor DNS default (8.8.8.8): ")

    # Instalar ISC DHCP Server
    sudo apt install isc-dhcp-server -y

    # Configurar DHCP Server
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$interfaz_v4\"/" /etc/default/isc-dhcp-server
    sudo sed -i '/authoritative/d' /etc/dhcp/dhcpd.conf
    sudo sed -i 's/^\(option domain-name \)/# \1/' /etc/dhcp/dhcpd.conf
    sudo sed -i 's/^\(option domain-name-servers \)/# \1/' /etc/dhcp/dhcpd.conf

    sudo tee -a /etc/dhcp/dhcpd.conf > /dev/null <<EOL
subnet $red netmask $subred {
    range $ip_inicio $ip_fin;
    option routers $puerta_enlace;
    option domain-name-servers $dns;
}
EOL

    # Reiniciar servicio
    sudo systemctl start isc-dhcp-server
    sudo systemctl enable isc-dhcp-server

    PrintMessage "Configuración completada. El servidor DHCP está instalado y configurado." "info"
}
