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

# Обновление системы
echo "Обновление системы..."

sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" >> /etc/resolv.conf'

sudo apt-get update
if [ $? -ne 0 ]; then
    errors+=("Ошибка при обновлении системы.")
    echo -e "${RED}Ошибка при обновлении системы.${NC}"
fi

sudo apt-get upgrade --enable-upgrade -y
if [ $? -ne 0 ]; then
    errors+=("Ошибка при обновлении системы.")
    echo -e "${RED}Ошибка при обновлении системы.${NC}"
fi

# Установка необходимых пакетов
packages=(ubridge qemu-system curl vpcs git tmux sshpass docker-engine)

for package in "${packages[@]}"; do
    if rpm -q $package &> /dev/null; then
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

curl -L -o auto_download.py 'https://drive.usercontent.google.com/uc?id=1PFgfO0kqWszksEs59EW6kDxeLfT9mbFB&export=download'

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

echo "Установка дополнительных пакетов..."
pip install requests
pip install requests tqdm beautifulsoup4
pip3 install requests tqdm beautifulsoup4
if [ $? -ne 0 ]; then
    errors+=("Ошибка при установке дополнительных пакетов.")
    echo -e "${RED}Ошибка при установке дополнительных пакетов.${NC}"
else
    echo -e "${GREEN}Дополнительные пакеты успешно установлены.${NC}"
fi

cd ..

# Убедимся, что скрипт активации исполняемый
#chmod +x /home/$user/gns3/bin/activate

# Запуск GNS3 Server в сессии tmux
tmux_session="gns3_sessionS2"
if tmux has-session -t $tmux_session 2>/dev/null; then
    echo -e "${GREEN}Сессия tmux $tmux_session уже запущена.${NC}"
else
    echo "Создание сессии tmux $tmux_session..."
    tmux new-session -d -s $tmux_session
    tmux send-keys -t $tmux_session "cd /home/$user && sudo -u $user gns3/bin/gns3server" C-m
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

# Передача образа EcoRouter
echo "Передача образа EcoRouter..."
ECO_MIN_SIZE=1747058688  # Минимальный размер файла в байтах
ECO_FILE="/home/$user/GNS3/images/QEMU/EcoRouter.qcow2"

if [ -f "$ECO_FILE" ]; then
    filesize=$(stat -c%s "$ECO_FILE")
    if [ "$filesize" -lt "$ECO_MIN_SIZE" ]; then
        echo "Размер файла меньше ожидаемого, удаляем и скачиваем заново."
        rm -f "$ECO_FILE"
    else
        echo -e "${GREEN}EcoRouter.qcow2 уже существует и имеет достаточный размер, пропускаем передачу.${NC}"
    fi
fi

if [ ! -f "$ECO_FILE" ]; then
    sudo mkdir -p /home/$user/GNS3/images/QEMU
    python3 auto_download.py -url "https://drive.google.com/uc?id=1akd88n_rD558GKZPiglBs13wFX5i2KMV" && sudo mv EcoRouter.qcow2 /home/$user/GNS3/images/QEMU/
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при передаче образа EcoRouter.")
        echo -e "${RED}Ошибка при передаче образа EcoRouter.${NC}"
    else
        echo -e "${GREEN}Образ EcoRouter успешно передан.${NC}"
    fi
fi

# Передача образа alt.qcow2
echo "Передача образа alt.qcow2..."
ALT_MIN_SIZE=4906745856  # Минимальный размер файла в байтах
ALT_FILE="/home/$user/GNS3/images/QEMU/alt.qcow2"

if [ -f "$ALT_FILE" ]; then
    filesize=$(stat -c%s "$ALT_FILE")
    if [ "$filesize" -lt "$ALT_MIN_SIZE" ]; then
        echo "Размер файла меньше ожидаемого, удаляем и скачиваем заново."
        rm -f "$ALT_FILE"
    else
        echo -e "${GREEN}alt.qcow2 уже существует и имеет достаточный размер, пропускаем передачу.${NC}"
    fi
fi

if [ ! -f "$ALT_FILE" ]; then
    sudo mkdir -p /home/$user/GNS3/images/QEMU
    python3 auto_download.py -url "https://drive.google.com/uc?id=1BRbXMRJR_OlS3AoDjgEp-xT0vGonjlr6" && sudo mv alt.qcow2 /home/$user/GNS3/images/QEMU/
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при передаче образа ALT.")
        echo -e "${RED}Ошибка при передаче образа ALT.${NC}"
    else
        echo -e "${GREEN}Образ ALT успешно передан.${NC}"
    fi
fi


# Загрузка EcoRouter.json
echo "Загрузка EcoRouter.json..."
python3 auto_download.py -url "https://drive.google.com/uc?id=1mQGJ6WKLCGHWclksYp7M4Xf-jNDubU3e"
if [ $? -ne 0 ]; then
    errors+=("Ошибка при загрузке EcoRouter.json.")
    echo -e "${RED}Ошибка при загрузке EcoRouter.json.${NC}"
else
    echo -e "${GREEN}EcoRouter.json успешно загружен.${NC}"
fi
#Скрипт api-tes-t.py проверяет наличие шаблонов, YES или NO.
#python3 auto_download.py -url "https://drive.google.com/uc?id=1U_jPEHi4GRW8xw0BdN5HgSsB6BlHjgZi"
python3 auto_download.py -url "https://drive.google.com/uc?id=1U_jPEHi4GRW8xw0BdN5HgSsB6BlHjgZi"

# Загрузка api-im.py
echo "Загрузка api-im.py..."
python3 auto_download.py -url "https://drive.google.com/uc?id=1e_b7m4R1lYQ_gHgD3GdF8Sl-O4U60NuT"
if [ $? -ne 0 ]; then
    errors+=("Ошибка при загрузке api-im.py.")
    echo -e "${RED}Ошибка при загрузке api-im.py.${NC}"
else
    echo -e "${GREEN}api-im.py успешно загружен.${NC}"
fi
# Проверка и импорт шаблона EcoRouter
echo "Проверка, импортирован ли шаблон EcoRouter..."
ecorouter_status=$(python3 api-tes-t.py -ip 127.0.0.1 -p 3080 -n EcoRouter)

if [[ $ecorouter_status == *'YES' ]]; then
    echo -e "${GREEN}Шаблон EcoRouter уже импортирован.${NC}"
else
    echo "Импорт шаблона EcoRouter..."
    python3 api-im.py -ip 127.0.0.1 -p 3080 -f EcoRouter.json
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона EcoRouter.")
        echo -e "${RED}Ошибка при импорте шаблона EcoRouter.${NC}"
    else
        echo -e "${GREEN}Шаблон EcoRouter успешно импортирован.${NC}"
    fi
fi

# Проверка и импорт шаблона OpenvSwitch
echo "Проверка, импортирован ли шаблон OpenvSwitch..."
openvswitch_status=$(python3 api-tes-t.py -ip 127.0.0.1 -p 3080 -n OpenvSwitch)

if [[ $openvswitch_status == *'YES' ]]; then
    echo -e "${GREEN}Шаблон OpenvSwitch уже импортирован.${NC}"
else
    echo "Загрузка OpenvSwitch.json..."
    python3 auto_download.py -url "https://drive.google.com/uc?id=1kBr58wmheh_krnjOiKvRokCDhaKCI6nn"
    echo "Импорт шаблона OpenvSwitch..."
    python3 api-im.py -ip 127.0.0.1 -p 3080 -f OpenvSwitch.json
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона OpenvSwitch.")
        echo -e "${RED}Ошибка при импорте шаблона OpenvSwitch.${NC}"
    else
        echo -e "${GREEN}Шаблон OpenvSwitch успешно импортирован.${NC}"
    fi
fi

# Проверка и импорт шаблона ALT Server 10
echo "Проверка, импортирован ли шаблон alt..."
alt_status=$(python3 api-tes-t.py -ip 127.0.0.1 -p 3080 -n alt)

if [[ $alt_status == *'YES' ]]; then
    echo -e "${GREEN}Шаблон alt уже импортирован.${NC}"
else
    echo "Загрузка alt.json..."
    python3 auto_download.py -url "https://drive.google.com/uc?id=1Kp-E3bcTm4XllD81swACGuDBINa_WjPv"
    echo "Импорт шаблона ALT Server 10..."
    python3 api-im.py -ip 127.0.0.1 -p 3080 -f alt.json
    if [ $? -ne 0 ]; then
        errors+=("Ошибка при импорте шаблона alt.")
        echo -e "${RED}Ошибка при импорте шаблона alt.${NC}"
    else
        echo -e "${GREEN}Шаблон alt успешно импортирован.${NC}"
    fi
fi

# Установка Busybox

echo "Установка Busybox..."
if ! command -v busybox &> /dev/null; then
    sudo curl -O 'https://git.altlinux.org/tasks/archive/done/_323/331258/build/200/x86_64/rpms/busybox-1.36.1-alt1.x86_64.rpm'
    sudo curl -O 'https://git.altlinux.org/tasks/archive/done/_323/331258/build/200/x86_64/rpms/busybox-debuginfo-1.36.1-alt1.x86_64.rpm'

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
else
    echo -e "${GREEN}Busybox уже установлен.${NC}"
fi


sudo mkdir -p /home/$user/.config/GNS3/2.2/
sudo cp /root/.config/GNS3/2.2/gns3_controller.conf /home/$user/.config/GNS3/2.2/
sudo chown $user:$user /home/$user/.config/GNS3/2.2/gns3_controller.conf
sudo mkdir -p /home/$user/GNS3/images/QEMU /home/$user/GNS3/symbols /home/$user/GNS3/configs /home/$user/.local/share/GNS3/appliances
sudo chown -R $user:$user /home/$user/GNS3
sudo chown -R $user:$user /home/$user/.local/share/GNS3
sudo chmod -R 755 /home/$user/GNS3
sudo chmod -R 755 /home/$user/.local/share/GNS3


sudo apt-get install ubridge
sudo chmod +x /usr/bin/ubridge


# Очистка загруженных файлов
echo "Очистка временных файлов..."
rm -f api-im.py EcoRouter.json OpenvSwitch.json colortest alt.json auto-config-gns3-alt-server-10.sh
sudo rm -r gns3-server
echo -e "${GREEN}Установка завершена!${NC}"
echo "Для запуска GNS3 Server выполните: cd /home/$user && sudo -u $user gns3/bin/gns3server"

deactivate



# Вывод списка сетевых интерфейсов и их IP-адресов без маски
echo "Список сетевых интерфейсов:"
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev 'docker0|vmbr0|lo')

for interface in $interfaces; do
    ip_addr=$(ip addr show $interface | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$ip_addr" ]; then
        echo "$interface: $ip_addr"
        echo "GNS3 Server доступен по адресу: http://$ip_addr:3080"
        echo "И можно так ssh -L 3080:127.0.0.1:3080 {user_name}@{ip_addr_server} -i {'ssh_key'}"
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

