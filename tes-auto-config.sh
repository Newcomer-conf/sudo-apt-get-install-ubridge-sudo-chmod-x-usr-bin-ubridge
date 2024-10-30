#!/bin/bash

# Цветовые переменные
GREEN='\033[92m'     # Зелёный
RED='\033[91m'       # Красный
NC='\033[0m'         # Сброс цвета до стандартного

# Массив для сбора ошибок
errors=()

# Проверяем, запущен ли скрипт с правами root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root (используйте sudo).${NC}"
    exit 1
fi

# Определяем имя пользователя
while getopts u: flag
do
    case "${flag}" in
        u) user=${OPTARG};;
    esac
done

if [ -z "$user" ]; then
    echo "Использование: sudo bash $0 -u <имя_пользователя>"
    exit 1
fi

# Функция для проверки и загрузки файлов с md5sum, используя auto_download.py
download_with_md5check() {
    local url="$1"
    local filename="$2"
    local expected_md5="$3"

    if [ -f "$filename" ]; then
        md5=$(md5sum "$filename" | awk '{print $1}')
        if [ "$md5" != "$expected_md5" ]; then
            echo "MD5 для $filename не совпадает, удаляем и скачиваем заново."
            rm -f "$filename"
        else
            echo -e "${GREEN}$filename уже существует и MD5 совпадает, пропускаем загрузку.${NC}"
            return
        fi
    fi

    # Скачиваем файл с помощью auto_download.py
    python3 auto_download.py -url "$url" -o "$filename"
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при загрузке $filename.")
        echo -e "${RED}Ошибка при загрузке $filename.${NC}"
    else
        # Проверяем MD5 загруженного файла
        md5=$(md5sum "$filename" | awk '{print $1}')
        if [ "$md5" != "$expected_md5" ]; then
            errors+=("MD5 для $filename не совпадает после загрузки.")
            echo -e "${RED}MD5 для $filename не совпадает после загрузки.${NC}"
            rm -f "$filename"
        else
            echo -e "${GREEN}$filename успешно загружен.${NC}"
        fi
    fi
}

# Обновление системы
echo "Обновление системы..."

sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" >> /etc/resolv.conf'
sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

sudo apt-get update
if [ $? -ne 0 ]; then
    errors+=("Ошибка при обновлении системы.")
    echo -e "${RED}Ошибка при обновлении системы.${NC}"
fi

sudo apt-get upgrade --allow-downgrades --allow-remove-essential --allow-change-held-packages -y
if [ $? -ne 0 ]; then
    errors+=("Ошибка при обновлении системы.")
    echo -e "${RED}Ошибка при обновлении системы.${NC}"
fi

# Установка необходимых пакетов
packages=(ubridge vpcs git tmux sshpass docker.io python3-pip python3-venv)

for package in "${packages[@]}"; do
    if dpkg -l | grep -qw $package; then
        echo -e "${GREEN}$package уже установлен.${NC}"
    else
        echo "Установка $package..."
        sudo apt-get install -y $package
        if [ $? -ne 0 ]; then
            errors+=("Ошибка при установке $package.")
            echo -e "${RED}Ошибка при установке $package.${NC}"
        else
            echo -e "${GREEN}$package успешно установлен.${NC}"
        fi
    fi
done

# Установка GNS3 Server
if [ ! -d "gns3-server" ]; then
    echo "Клонирование репозитория GNS3 Server..."
    git clone https://github.com/GNS3/gns3-server.git
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при клонировании репозитория GNS3 Server.")
        echo -e "${RED}Ошибка при клонировании репозитория GNS3 Server.${NC}"
    else
        echo -e "${GREEN}Репозиторий GNS3 Server успешно клонирован.${NC}"
    fi
else
    echo -e "${GREEN}Каталог gns3-server уже существует, пропускаем клонирование.${NC}"
fi

pip3 install --upgrade pip
pip3 install requests tqdm beautifulsoup4

# Загрузка auto_download.py
echo "Загрузка auto_download.py..."
download_with_md5check "https://drive.google.com/uc?id=1PFgfO0kqWszksEs59EW6kDxeLfT9mbFB&export=download" "auto_download.py" "7ec13f4aff855f6ada25b92e9987f681"

# Создание и активация виртуального окружения
if [ ! -d "gns3" ]; then
    echo "Создание виртуального окружения..."
    python3 -m venv gns3
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при создании виртуального окружения.")
        echo -e "${RED}Ошибка при создании виртуального окружения.${NC}"
    else
        echo -e "${GREEN}Виртуальное окружение успешно создано.${NC}"
    fi
else
    echo -e "${GREEN}Виртуальное окружение 'gns3' уже существует.${NC}"
fi

echo "Активация виртуального окружения..."
source gns3/bin/activate
if [ $? -ne 0 ]; then
    errors+=("Ошибка при активации виртуального окружения.")
    echo -e "${RED}Ошибка при активации виртуального окружения.${NC}"
fi

cd gns3-server/

echo "Установка зависимостей GNS3 Server..."
pip install -r requirements.txt
if [ $? -ne 0 ]; then
        errors+=("Ошибка при установке зависимостей GNS3 Server.")
        echo -e "${RED}Ошибка при установке зависимостей GNS3 Server.${NC}"
else
        echo -e "${GREEN}Зависимости GNS3 Server успешно установлены.${NC}"
fi

echo "Установка GNS3 Server..."
pip install .
if [ $? -ne 0 ]; then
        errors+=("Ошибка при установке GNS3 Server.")
        echo -e "${RED}Ошибка при установке GNS3 Server.${NC}"
else
        echo -e "${GREEN}GNS3 Server успешно установлен.${NC}"
fi

cd ..

# Убедимся, что скрипт активации исполняемый
chmod +x /home/$user/gns3/bin/activate

# Запуск GNS3 Server в сессии tmux
tmux_session="gns3_sessionS2"
if tmux has-session -t $tmux_session 2>/dev/null; then
    echo -e "${GREEN}Сессия tmux $tmux_session уже запущена.${NC}"
else
    echo "Создание сессии tmux $tmux_session..."
    tmux new-session -d -s $tmux_session
    tmux send-keys -t $tmux_session "cd /home/$user && source gns3/bin/activate && gns3server" C-m
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при запуске GNS3 Server в tmux сессии.")
        echo -e "${RED}Ошибка при запуске GNS3 Server в tmux сессии.${NC}"
    else
        echo -e "${GREEN}GNS3 Server запущен в сессии tmux $tmux_session.${NC}"
    fi
fi

# Настройка Docker
echo "Добавление пользователя $user в группу docker..."
sudo usermod -aG docker $user
if [ $? -ne 0 ]; then
        errors+=("Ошибка при добавлении пользователя $user в группу docker.")
        echo -e "${RED}Ошибка при добавлении пользователя $user в группу docker.${NC}"
else
        echo -e "${GREEN}Пользователь $user добавлен в группу docker.${NC}"
fi

echo "Настройка прав Docker..."
sudo chmod 666 /var/run/docker.sock
sudo systemctl enable --now docker
if [ $? -ne 0 ]; then
        errors+=("Ошибка при настройке Docker.")
        echo -e "${RED}Ошибка при настройке Docker.${NC}"
else
        echo -e "${GREEN}Docker успешно настроен.${NC}"
fi

# Создание директории для образов
sudo mkdir -p /home/$user/GNS3/images/QEMU

# Загрузка EcoRouter.qcow2
echo "Загрузка EcoRouter.qcow2..."
download_with_md5check "https://drive.google.com/uc?id=1akd88n_rD558GKZPiglBs13wFX5i2KMV" "/home/$user/GNS3/images/QEMU/EcoRouter.qcow2" "7c6a9163e964d8942eb1ced84f5c1f70"

# Загрузка alt.qcow2
echo "Загрузка alt.qcow2..."
download_with_md5check "https://drive.google.com/uc?id=1BRbXMRJR_OlS3AoDjgEp-xT0vGonjlr6" "/home/$user/GNS3/images/QEMU/alt.qcow2" "e2104b7adb47de73a684135751ca927d"

# Загрузка EcoRouter.json
echo "Загрузка EcoRouter.json..."
download_with_md5check "https://drive.google.com/uc?id=1mQGJ6WKLCGHWclksYp7M4Xf-jNDubU3e" "EcoRouter.json" "d4b60b8359a72a545b2808950ae4eb53"

# Загрузка api-im.py
echo "Загрузка api-im.py..."
download_with_md5check "https://drive.google.com/uc?id=1e_b7m4R1lYQ_gHgD3GdF8Sl-O4U60NuT" "api-im.py" "86592bfe62db86749fbf22c98ebe6797"

# Загрузка OpenvSwitch.json
echo "Загрузка OpenvSwitch.json..."
download_with_md5check "https://drive.google.com/uc?id=1kBr58wmheh_krnjOiKvRokCDhaKCI6nn" "OpenvSwitch.json" "b3cc0a18bd3439dd48bb3b2b12451852"

# Загрузка alt.json
echo "Загрузка alt.json..."
download_with_md5check "https://drive.google.com/uc?id=1Kp-E3bcTm4XllD81swACGuDBINa_WjPv" "alt.json" "99939d07c7392ef1dbd3a36fa58986de"

# Проверка на наличие ошибок после загрузки файлов
if [ ${#errors[@]} -ne 0 ]; then
    echo -e "${RED}Были обнаружены ошибки во время загрузки файлов:${NC}"
    for error in "${errors[@]}"; do
        echo -e "${RED}- $error${NC}"
    done
    exit 1
else
    echo -e "${GREEN}Все файлы успешно загружены.${NC}"
fi

# Импорт шаблона EcoRouter
echo "Импорт шаблона EcoRouter..."
python3 api-im.py -ip 127.0.0.1 -p 3080 -f EcoRouter.json
if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона EcoRouter.")
        echo -e "${RED}Ошибка при импорте шаблона EcoRouter.${NC}"
else
        echo -e "${GREEN}Шаблон EcoRouter успешно импортирован.${NC}"
fi

# Импорт шаблона OpenvSwitch
echo "Импорт шаблона OpenvSwitch..."
python3 api-im.py -ip 127.0.0.1 -p 3080 -f OpenvSwitch.json
if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона OpenvSwitch.")
        echo -e "${RED}Ошибка при импорте шаблона OpenvSwitch.${NC}"
else
        echo -e "${GREEN}Шаблон OpenvSwitch успешно импортирован.${NC}"
fi

# Импорт шаблона ALT Server 10
echo "Импорт шаблона ALT Server 10..."
python3 api-im.py -ip 127.0.0.1 -p 3080 -f alt.json
if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона ALT Server 10.")
        echo -e "${RED}Ошибка при импорте шаблона ALT Server 10.${NC}"
else
        echo -e "${GREEN}Шаблон ALT Server 10 успешно импортирован.${NC}"
fi

# Установка Busybox
echo "Установка Busybox..."
if ! command -v busybox &> /dev/null; then
    wget https://git.altlinux.org/tasks/331258/build/200/x86_64/rpms/busybox-1.36.1-alt1.x86_64.rpm
    wget https://git.altlinux.org/tasks/331258/build/200/x86_64/rpms/busybox-debuginfo-1.36.1-alt1.x86_64.rpm
    sudo apt-get install -y rpm
    sudo rpm -i busybox-1.36.1-alt1.x86_64.rpm
    sudo rpm -i busybox-debuginfo-1.36.1-alt1.x86_64.rpm
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при установке Busybox.")
        echo -e "${RED}Ошибка при установке Busybox.${NC}"
    else
        echo -e "${GREEN}Busybox успешно установлен.${NC}"
    fi
    # Удаление RPM файлов
    rm -f busybox-1.36.1-alt1.x86_64.rpm
    rm -f busybox-debuginfo-1.36.1-alt1.x86_64.rpm
	sudo apt-get install ubridge
	sudo chmod +x /usr/bin/ubridge
else
    echo -e "${GREEN}Busybox уже установлен.${NC}"
fi

sudo chmod +x /usr/bin/ubridge

# Очистка загруженных файлов
echo "Очистка временных файлов..."
rm -f api-im.py EcoRouter.json OpenvSwitch.json alt.json auto-config-gns3-alt-server-10.sh
sudo rm -rf gns3-server
echo -e "${GREEN}Установка завершена!${NC}"
echo "Для запуска GNS3 Server выполните: cd /home/$user && sudo -S gns3/bin/gns3server"

deactivate

# Вывод списка сетевых интерфейсов и их IP-адресов без маски
echo "Список сетевых интерфейсов:"
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev 'docker0|vmbr0|lo')

for interface in $interfaces; do
    ip_addr=$(ip addr show $interface | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$ip_addr" ]; then
        echo "$interface: $ip_addr"
        echo "GNS3 Server доступен по адресу: http://$ip_addr:3080"
    fi
done

# Вывод ошибок, если они есть
if [ ${#errors[@]} -ne 0 ]; then
    echo -e "${RED}Произошли следующие ошибки:${NC}"
    for err in "${errors[@]}"; do
        echo -e "${RED}- $err${NC}"
    done
else
    echo -e "${GREEN}Скрипт выполнен успешно без ошибок.${NC}"
fi