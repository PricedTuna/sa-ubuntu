#!/bin/bash

source ./utils.sh  # Incluir las funciones comunes

# Puertos permitidos (excluyendo puertos comunes reservados)
allowed_ports=(80 1024 8080 2019 3000 5000 8081 8443)

# Verificar si wget está instalado
if ! command -v wget &> /dev/null; then
    PrintMessage "wget no está instalado, debes instalarlo con 'sudo apt install wget'." error
    exit 1
fi

# Verificar si curl está instalado
if ! command -v curl &> /dev/null; then
    PrintMessage "curl no está instalado, debes instalarlo con 'sudo apt install curl'." error
    exit 1
fi

# Validar que el puerto sea un número válido, exista y no esté en uso
validate_port() {
    local port=$1

    # Verificar que el puerto sea un número y esté dentro del rango válido
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        PrintMessage "Escribe un número." error
        return 1
    fi

    # Verificar que el puerto esté permitido
    if [[ ! " ${allowed_ports[@]} " =~ " $port " ]]; then
        PrintMessage "El puerto $port no permitido. Puertos válidos: ${allowed_ports[*]}" error
        return 1
    fi

    # Verificar que el puerto no esté en uso
if ss -tuln | grep -q ":$port "; then
    PrintMessage "El puerto $port ya está en uso." error
    return 1
fi


    return 0
}

# Verificar si el puerto 80 está en uso por otro servicio
check_port_80_usage() {
    if lsof -i:80 &> /dev/null; then
        PrintMessage "El puerto 80 ya está en uso. Esto puede causar problemas con Nginx." error
        return 1
    else
        PrintMessage "Puerto 80 accesible." info
        return 0
    fi
}

# Obtener la última versión estable y de desarrollo de Tomcat desde la web oficial
get_latest_tomcat_versions() {
    local stable_url="https://tomcat.apache.org/download-90.cgi"
    local dev_url="https://tomcat.apache.org/download-11.cgi"

    # Extraer la versión más reciente del formato de enlaces de descarga
    local stable_version=$(curl -s $stable_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)
    local dev_version=$(curl -s $dev_url | grep -oP '(?<=apache-tomcat-)\d+\.\d+\.\d+(?=\.zip.asc)' | sort -Vr | head -1)

    echo "$stable_version $dev_version"
}

# Instalar Tomcat
install_tomcat() {
    local puerto=$1
    local tomcat_home="/opt/tomcat"

    # Obtener la última versión de Tomcat
    read stable_version dev_version <<< $(get_latest_tomcat_versions)

    PrintMessage "Versiones disponibles para instalar:"
    PrintMessage "1) LTS: $stable_version"
    PrintMessage "2) Desarrollo: $dev_version"

    while true; do
        read -p "Seleccione una versión [1-2]: " version_choice
        case $version_choice in
            1) version=$stable_version; 
	       break ;;
            2) version=$dev_version; 
               break ;;
            *) PrintMessage "Opcion invalida." error
	       ;;
        esac
    done

    # Verificar si Java está instalado
    if ! command -v java &>/dev/null; then
        echo "Instalando Java..."
        apt update && apt install -y default-jdk || { echo "Error al instalar Java"; exit 1; }
    fi

    if [ -d "$tomcat_home" ]; then
        echo "Tomcat ya está instalado en $tomcat_home."
        read -p "¿Desea reinstalar Tomcat? ("S" para "Sí" y cualquier otra cosa para "No" :) ): " respuesta
        if [[ "$respuesta" != "s" && "$respuesta" != "S" ]]; then
            echo "Omitiendo instalación de Tomcat."
            return
        fi

        if [ -f "$tomcat_home/bin/shutdown.sh" ]; then
            echo "Deteniendo Tomcat..."
            $tomcat_home/bin/shutdown.sh
            sleep 2
        fi

        echo "Eliminando instalación anterior de Tomcat..."
        rm -rf $tomcat_home
    fi

    mkdir -p $tomcat_home
    cd /tmp

    # Construir la URL de descarga
    local tomcat_major=$(echo "$version" | cut -d'.' -f1)
    local tomcat_url="https://downloads.apache.org/tomcat/tomcat-$tomcat_major/v$version/bin/apache-tomcat-$version.tar.gz"

    PrintMessage "Descargando Tomcat $version..." advertencia
    if ! curl -fsSL "$tomcat_url" -o tomcat.tar.gz; then
        echo "Error al descargar Tomcat. Verifique la URL o su conexión a Internet."
        return 1
    fi

    echo "Extrayendo archivos..."
    tar xf tomcat.tar.gz -C $tomcat_home --strip-components=1 && rm tomcat.tar.gz

    # Crear usuario tomcat si no existe
    if ! id -u tomcat &>/dev/null; then
        echo "Creando usuario tomcat..."
        useradd -m -d $tomcat_home -U -s /bin/false tomcat
    fi

    # Configurar permisos
    chown -R tomcat:tomcat $tomcat_home
    chmod +x $tomcat_home/bin/*.sh

    # Configurar puerto
    echo "Configurando Tomcat para el puerto $puerto..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/" $tomcat_home/conf/server.xml

    # Crear servicio systemd con reinicio automático
    if command -v systemctl &>/dev/null; then
        echo "Creando servicio systemd para Tomcat..."
        cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="CATALINA_HOME=$tomcat_home"
Environment="CATALINA_BASE=$tomcat_home"
Environment="CATALINA_PID=$tomcat_home/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M"

ExecStart=$tomcat_home/bin/startup.sh
ExecStop=$tomcat_home/bin/shutdown.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        # Recargar systemd y habilitar servicio
        systemctl daemon-reload
        systemctl enable tomcat
        systemctl start tomcat

        sleep 3 # Esperar a que Tomcat se inicie

        if systemctl is-active --quiet tomcat; then
            PrintMessage "Tomcat $version instalado en el puerto $puerto" info
        else
            PrintMessage "Error al iniciar Tomcat. revisa los logs:" error
            tail -n 20 $tomcat_home/logs/catalina.out
            systemctl status tomcat --no-pager
        fi
    else
        PrintMessage "Advertencia: systemctl no está disponible, Tomcat no se ejecutará como servicio." error
    fi
}

# Obtener la última versión estable y de desarrollo de Caddy desde GitHub
get_latest_caddy_versions() {
    local stable_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    local dev_version=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases | grep -oP '"tag_name": "\K[^"]+' | grep beta | head -1)

    echo "$stable_version $dev_version"
}

# Instalar Caddy
install_caddy() {
    local puerto=$1

    # Obtener la última versión de Caddy
    read stable_version dev_version <<< $(get_latest_caddy_versions)

    PrintMessage "Versiones disponibles para instalar:"
    PrintMessage "1) LTS: $stable_version"
    PrintMessage "2) Desarrollo: $dev_version"
    

    while true; do
	read -p "Seleccionar version: " version_choice
    	case $version_choice in
            1) 
            	repo_name="stable"
            	key_url='https://dl.cloudsmith.io/public/caddy/stable/gpg.key'
            	repo_url='https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt'
		break
            	;;
            2) 
            	repo_name="testing"
            	key_url='https://dl.cloudsmith.io/public/caddy/testing/gpg.key'
            	repo_url='https://dl.cloudsmith.io/public/caddy/testing/debian.deb.txt'
		break
            	;;
            *) 
            	PrintMessage "Opción no válida. Intente de nuevo." error
            	;;
    	esac
    done

    PrintMessage "Instalando Caddy $repo_name..." advertencia

    # Instalar dependencias necesarias
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    
    # Agregar clave GPG y repositorio
    curl -1sLf "$key_url" | sudo gpg --dearmor -o /usr/share/keyrings/caddy-$repo_name-archive-keyring.gpg
    curl -1sLf "$repo_url" | sudo tee /etc/apt/sources.list.d/caddy-$repo_name.list
    
    # Actualizar repositorios e instalar Caddy
    sudo apt update
    sudo apt install -y caddy

    PrintMessage "Configurando Caddy en el puerto $puerto..." advertencia
    
    # Crear configuración básica de Caddy
    cat > /etc/caddy/Caddyfile << EOF
{
    auto_https off
}

:$puerto {
    respond "Caddy funcionando en el puerto $puerto"
}
EOF

    # Ajustar permisos y reiniciar Caddy
    sudo chown caddy:caddy /etc/caddy/Caddyfile
    sudo systemctl restart caddy
    sudo systemctl enable caddy

    sleep 3 # Esperar a que Caddy se inicie

    if systemctl is-active --quiet caddy; then
        PrintMessage "Caddy $repo_name instalado y funcionando en el puerto $puerto" info
    else
        PrintMessage "Error al iniciar Caddy. Verifique el log:" error
        journalctl -u caddy --no-pager | tail -n 20
        systemctl status caddy --no-pager
    fi
}

# Obtener la última versión estable y de desarrollo de Nginx desde la web oficial
get_latest_nginx_versions() {
    local url="https://nginx.org/en/download.html"

    # Obtener todas las versiones disponibles
    local versions=$(curl -s $url | grep -oP '(?<=nginx-)[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr)

    # Extraer la versión estable (números pares en el segundo segmento)
    local stable_version=$(echo "$versions" | grep -E '^[0-9]+\.([0-9]*[02468])\.[0-9]+$' | head -1)

    # Extraer la versión de desarrollo (números impares en el segundo segmento)
    local dev_version=$(echo "$versions" | grep -E '^[0-9]+\.([0-9]*[13579])\.[0-9]+$' | head -1)

    echo "$stable_version $dev_version"
}

# Descargar e instalar Nginx desde el sitio oficial
install_nginx() {
    local puerto=$1

    # Obtener la última versión de Nginx
    read stable_version dev_version <<< $(get_latest_nginx_versions)

    PrintMessage "Versiones disponibles para instalar:"
    PrintMessage "1) LTS: $stable_version"
    PrintMessage "2) Desarrollo: $dev_version"

    while true; do
    	read -p "Seleccionar version: " version_choice
    	case $version_choice in
    	    1) version=$stable_version;
		break
            	;;
            2) version=$dev_version;
		break
            	;;
            *) PrintMessage "Opción no válida. Intente de nuevo." error
            	;;
        esac
    done

    # Crear directorios necesarios
    local temp_dir=$(mktemp -d)
    local nginx_tar="nginx-$version.tar.gz"
    local nginx_url="https://nginx.org/download/nginx-$version.tar.gz"

    echo "Descargando Nginx $version..." advertencia
    curl -L "$nginx_url" -o "$temp_dir/$nginx_tar"

    # Descomprimir el archivo
    echo "Descomprimiendo Nginx..." advertencia
    tar -xzvf "$temp_dir/$nginx_tar" -C "$temp_dir"

    # Instalar dependencias necesarias
    sudo apt update
    sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev

    # Compilar e instalar Nginx
    cd "$temp_dir/nginx-$version"
    ./configure
    make
    sudo make install

    # Configurar Nginx para usar el puerto especificado
    echo "Configurando Nginx en el puerto $puerto..."
    sudo sed -i "s/port=\"$puerto\"/port=\"$puerto\"/" /usr/local/nginx/conf/nginx.conf

    # Agregar /usr/local/nginx/sbin al PATH
    echo "Agregando Nginx al PATH..."

    echo 'export PATH=$PATH:/usr/local/nginx/sbin' >> ~/.bashrc
    source ~/.bashrc

    # Iniciar y habilitar el servicio
    echo "Iniciando Nginx..."
    sudo /usr/local/nginx/sbin/nginx

        PrintMessage "Nginx en el puerto $puerto."
    
}

# Desinstalar un servicio
uninstall_service() {
    # Crear un arreglo con solo los servicios instalados
    services=()
    
    if command -v caddy &>/dev/null; then
        services+=("Caddy")
    fi
    if [ -d "/opt/tomcat" ]; then
        services+=("Tomcat")
    fi
    if systemctl list-units --type=service | grep -q nginx; then
	services+=("Nginx")
    fi


    # Si no hay ninguno instalado, informar y salir
    if [ ${#services[@]} -eq 0 ]; then
        echo "No hay servicios instalados para desinstalar."
        return
    fi

    while true; do
        # Mostrar los servicios instalados disponibles para desinstalar
        echo "Servicio a desinstalar:"
        for i in "${!services[@]}"; do
            echo "$((i+1)). ${services[$i]}"
        done
        
        # Leer la opción del usuario
        read -p "Introduce el número del servicio que deseas desinstalar: " choice
        
        # Validar si la opción es válida (debe ser un número dentro del rango)
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#services[@]} ]; then
            service="${services[$((choice-1))]}"
            # Confirmar la desinstalación del servicio
            read -p "¿Estás seguro de que quieres desinstalar el servicio '$service'? (S para Sí y cualquier otra cosa para No): " confirm
            if [[ "$confirm" =~ ^[Ss]$ ]]; then
                # Detener el servicio
                echo "Deteniendo el servicio $service..."
                sudo systemctl stop "$service"

                # Deshabilitar el servicio
                echo "Deshabilitando el servicio $service..."
                sudo systemctl disable "$service"
                
                # Desinstalar el servicio dependiendo de cuál haya sido seleccionado
                case $service in
                    "Caddy")
                        echo "Desinstalando Caddy..."
                        sudo apt-get purge -y caddy
                        ;;
                    "Tomcat")
                        echo "Desinstalando Tomcat..."
	                
                        # Eliminar el archivo del servicio y recargar systemd
                        sudo rm -f /etc/systemd/system/tomcat.service
                        sudo systemctl daemon-reload
                        # Eliminar el directorio de Tomcat
                        sudo rm -rf /opt/tomcat
                        # Opcional: eliminar el usuario "tomcat" si existe
                        if id -u tomcat &>/dev/null; then
                            sudo userdel -r tomcat
                        fi
                        ;;
                    "Nginx")
                        echo "Desinstalando Nginx..."
                        sudo systemctl stop nginx
                        sudo systemctl disable nginx
                        sudo apt remove --purge -y nginx nginx-common nginx-full
                        sudo rm -rf /etc/nginx /var/www/html /var/log/nginx /usr/share/nginx
                        sudo pkill -f nginx || true
                        sudo systemctl daemon-reload
                        sudo systemctl reset-failed
                        ;;
                    *)
                        echo "Servicio no reconocido."
                        ;;
                esac

                # Limpiar dependencias no necesarias
                echo "Limpiando dependencias no necesarias..."
                sudo apt-get autoremove -y
                PrintMessage "El servicio '$service' ha sido desinstalado correctamente." info
                break
            else
                echo "Desinstalación cancelada para el servicio '$service'."
                break
            fi
        else
            echo "Opción inválida. Por favor, ingresa un número entre 1 y ${#services[@]}."
        fi
    done
}


# Menú principal
menu_http() {
  while true; do
    echo "============== Menú HTTP =============="
    echo "1) Instalar Tomcat"
    echo "2) Instalar Caddy"
    echo "3) Instalar Nginx"
    echo "4) Salir"
    echo "5) Desinstalar algún servicio"
    read -p "Opción: " choice

    case $choice in
    1)
	    while true; do
	    # Solicitar el puerto
	echo "Puertos seleccionables: <<80>> <<1024>> <<8080>> <<2019>> <<3000>> <<5000>> <<8081>> <<8443>>"
            read -p "Ingrese el puerto para Tomcat (default 8080): " puerto
            puerto=${puerto:-8080}
            if validate_port "$puerto"; then
                install_tomcat "$puerto"
                break
	    else
		echo "Intente de nuevo el puerto."
            fi
	    done
	    ;;
        2)
	    while true; do
	    # Solicitar el puerto
	    echo "Puertos seleccionables: <<80>> <<1024>> <<8080>> <<2019>> <<3000>> <<5000>> <<8081>> <<8443>>"
            read -p "Ingrese el puerto para Caddy (default 2019): " puerto
            puerto=${puerto:-2019}
            if validate_port "$puerto"; then
                install_caddy "$puerto"
		break
	    else
		echo "Intente de nuevo el puerto."
            fi
	    done
	    ;;
        3)
	    while true; do
            # Solicitar el puerto
echo "Puertos seleccionables: <<80>> <<1024>> <<8080>> <<2019>> <<3000>> <<5000>> <<8081>> <<8443>>"
            read -p "Ingrese el puerto para Nginx (default 80): " puerto
            puerto=${puerto:-80}
            if validate_port "$puerto"; then
                install_nginx "$puerto"
                break
	    else
		echo "Intente de nuevo el puerto."
            fi
	    done
            ;;
        4)
            echo "Saliendo del instalador..."
            exit 0
            ;;
        5)
            uninstall_service
            ;;
        *)
            PrintMessage "Opción no válida. Intente nuevamente." error
            ;;
    esac
done
}