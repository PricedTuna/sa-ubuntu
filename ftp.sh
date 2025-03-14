#!/bin/bash

# Variables
FTP_ROOT="/srv/ftp"
GROUP1="reprobados"
GROUP2="recursadores"
GENERAL="general"
ANON="anon"
PROFTPD_CONF="/etc/proftpd/proftpd.conf"

menu_ftp() {
    while true; do
    echo "\n===== Menú de FTP ====="
    echo "1) Salir"
    echo "2) Instalar FTP"
    echo "3) Configurar FTP"
    read -rp "Opción: " opcion

    case $opcion in
        1)
            echo "Saliendo..."
            exit 0
            ;;
        2)
            install_ftp
            ;;
        3)
            create_users
            ;;
        *)
            PrintMessage "Opción no válida. Saliendo..." "error"
            exit 1
            ;;
    esac
done
}

# Función para instalar y configurar ProFTPD
install_ftp() {
    PrintMessage "Instalando ProFTPD y acl"
    apt update && apt install -y proftpd acl

    PrintMessage "Configurando ProFTPD..."
    sed -i 's/# DefaultRoot/DefaultRoot/g' $PROFTPD_CONF
    sed -i 's/# RequireValidShell/RequireValidShell/g' $PROFTPD_CONF

    echo -e "\nPassivePorts 49152 65534" >> $PROFTPD_CONF

    PrintMessage "Configurando grupos..."
    getent group $GROUP1 || groupadd $GROUP1
    getent group $GROUP2 || groupadd $GROUP2

    mkdir -p "$FTP_ROOT/$GENERAL" "$FTP_ROOT/$GROUP1" "$FTP_ROOT/$GROUP2" "$FTP_ROOT/usuarios"
    mkdir -p "$FTP_ROOT/$ANON"

    PrintMessage "Configurando los permisos..."
    chown -R root:root "$FTP_ROOT"
    chmod 755 "$FTP_ROOT"
    chown -R root:root "$FTP_ROOT/$GENERAL"
    chmod 777 "$FTP_ROOT/$GENERAL"
    chown -R root:$GROUP1 "$FTP_ROOT/$GROUP1"
    chmod 775 "$FTP_ROOT/$GROUP1"
    chown -R root:$GROUP2 "$FTP_ROOT/$GROUP2"
    chmod 775 "$FTP_ROOT/$GROUP2"

    mkdir -p "$FTP_ROOT/$ANON/general"
    mount --bind "$FTP_ROOT/$GENERAL" "$FTP_ROOT/$ANON/general"

    cat <<EOF > /etc/proftpd/conf.d/anonymous.conf
<Anonymous $FTP_ROOT/$ANON>
    User                ftp
    Group               nogroup
    UserAlias           anonymous ftp
    <Directory general>
        <Limit WRITE>
            DenyAll
        </Limit>
        <Limit READ>
            AllowAll
        </Limit>
    </Directory>
</Anonymous>
EOF

    PrintMessage "Configurando reglas..."
    cat <<EOF >> $PROFTPD_CONF

# Los usuarios inician en su carpeta personal (enjaulados en ~)
DefaultRoot ~
EOF

    systemctl restart proftpd

    PrintMessage "Configuracion finalizada"
}

# Función para crear usuarios
create_users() {
    PrintMessage "Usuarios a crear" info
    read -r NUM_USERS

    if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]]; then
        PrintMessage "Ingresa un número válido." error
        return
    fi

    for ((i=1; i<=NUM_USERS; i++)); do
        echo -e "USUARIO $i"
	while true; do
        read -p "Nombre de usuario: " USERNAME
        USERNAME=$(PrintMessage "$USERNAME" | tr '[:upper:]' '[:lower:]')
        if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
            PrintMessage "Nombre de usuario inválido." error
            continue
        fi
	break
        done

        while true; do
            read -s -p "Contraseña del usuario: " PASSWORD
            PrintMessage ""

            if [ ${#PASSWORD} -lt 8 ]; then
                PrintMessage "La contraseña debe tener al menos 8 caracteres." error
                continue
            fi

            if ! [[ "$PASSWORD" =~ [0-9] ]]; then
                PrintMessage "La contraseña debe contener al menos un número." error
                continue
            fi

            if ! [[ "$PASSWORD" =~ [A-Z] ]]; then
                PrintMessage "La contraseña debe contener al menos una letra mayúscula." error
                continue
            fi

            if ! [[ "$PASSWORD" =~ [a-z] ]]; then
                PrintMessage "La contraseña debe contener al menos una letra minúscula." error
                continue
            fi

            if ! [[ "$PASSWORD" =~ [\@\#\$\%\^\&\*\(\)\_\+\!] ]]; then
                PrintMessage "La contraseña debe contener al menos un carácter especial (@, #, $, %, ^, &, *, (, ), _, +, !)." error
                continue
            fi

            break
        done

        while true; do
            PrintMessage "Elige el grupo del usuario"
            PrintMessage "1) $GROUP1"
            PrintMessage "2) $GROUP2"
            read -p "grupo: " group
            case $group in
                1)
                    group=$GROUP1
                    break
                    ;;
                2)
                    group=$GROUP2
                    break
                    ;;
                *)
                    echo "Grupo no válido. Por favor, introduce '1' o '2'."
                    ;;
            esac
        done

        if id "$USERNAME" &>/dev/null; then
            PrintMessage " El usuario $USERNAME ya existe, el proceso volvera a comenzar." error
            ((i--))
            continue
        fi

        useradd -m -s /bin/false -G "$group" "$USERNAME"
        usermod -d "$FTP_ROOT/usuarios/$USERNAME" "$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chown "$USERNAME:$group" "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chmod 700 "$FTP_ROOT/usuarios/$USERNAME/$USERNAME"
        chown -R "$USERNAME:$group" "$FTP_ROOT/usuarios/$USERNAME"
        chmod 770 "$FTP_ROOT/usuarios/$USERNAME"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/general"
        mkdir -p "$FTP_ROOT/usuarios/$USERNAME/$group"
        mount --bind "$FTP_ROOT/$GENERAL" "$FTP_ROOT/usuarios/$USERNAME/general"
        mount --bind "$FTP_ROOT/$group" "$FTP_ROOT/usuarios/$USERNAME/$group"
        echo "$USERNAME:$PASSWORD" | chpasswd

        PrintMessage "Usuario $USERNAME creado."
    done

    PrintMessage "Reiniciando ProFTPD..."
    systemctl restart proftpd

    PrintMessage "Usuarios creados."
}