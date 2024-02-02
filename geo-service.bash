#!/bin/bash
set -e

check_docker_permissions() {
    # Проверка доступности Docker
    if ! command -v docker &> /dev/null; then
        echo "Ошибка: Docker не найден. Убедитесь, что Docker установлен и доступен в вашей системе."
        exit 1
    fi

    # Проверка принадлежности пользователя к группе Docker
    if ! groups | grep -q "\bdocker\b"; then
        echo "Ошибка: Пользователь не принадлежит к группе Docker. Добавьте пользователя в группу Docker и перезапустите скрипт."
        exit 1
    fi
}

check_git() {
    # Проверка доступности Git
    if ! command -v git &> /dev/null; then
        echo "Ошибка: Git не найден. Убедитесь, что Git установлен и доступен в вашей системе."
        exit 1
    fi
}

get_archive_path() {
    local archive_path
    if [ "$1" == "-t" ]; then
        shift
        archive_path="$1"
    else
        read -p "Введите путь к архиву (например, /путь/к/HPS_ST3D.tar.gz): " archive_path
    fi

    echo "$archive_path"
}

create_docker_compose() {
    local geo_service_path="$1"

    cat <<EOF > "$geo_service_path/docker-compose.yml"
version: '3'
services:
  geo-backend:
    container_name: geo-back
    build:
      context: ./geo-backend
    restart: always
    networks:
      - geo-net
    ports:
      - "4422:8000"

  #geo-frontend:
    #container_name: geo-front
    #build:
      #context: ./geo-frontend
      #args:
        #API_BASE_URL: "http://84.237.52.214:4422
    #restart: always
    #networks:
      #- geo-net
    #ports:
      #- "4444:80"

networks:
  geo-net:
    driver: bridge

EOF
}

help_message() {
    echo "Использование: $0 {start|stop|rebuild|help} [-t path/to/tar.gz] [-r]"
    echo "  start   - Запустить geo services"
    echo "  stop    - Остановить и, при указании -r, удалить geo services"
    echo "  rebuild - Пересобрать и перезапустить geo services"
    echo "  help    - Вывести это сообщение"
    echo "  -t      - Указать путь к архиву (например, /путь/к/HPS_ST3D.tar.gz)"
    echo "  -r      - При указании удаляет данные при остановке (только совместно с командой stop)"
    exit 1
}

start_services() {
    check_git
    check_docker_permissions

    # Проверка наличия флага -t
    archive_path=$(get_archive_path "$1")

    # Создание папки geo-service
    mkdir -p geo-service

    # Клонирование репозиториев geo-backend и geo-frontend в geo-service
    git clone https://github.com/nsu-geo-service/geo-backend.git geo-service/geo-backend
    #git clone https://github.com/geo-frontend-repo.git geo-service/geo-frontend

    # Создание временной папки
    temp_dir=$(mktemp -d)

    # Распаковка архива во временную папку
    tar -xzvf "$archive_path" -C "$temp_dir"

    # Переименование родительской директории в HPS_ST3D
    mv "$temp_dir"/*/* "$temp_dir"/HPS_ST3D

    # Перемещение папки HPS_ST3D в geo-backend
    mv "$temp_dir"/HPS_ST3D geo-service/geo-backend

    # Создание файла docker-compose.yml
    create_docker_compose geo-service

    # Переход в папку geo-service и запуск Docker Compose с флагом --build
    cd geo-service
    docker-compose up -d --build

    # Проверка статуса контейнеров
    if docker ps -a | grep -E "Restarting|Exited"; then
        echo "Ошибка: Один или несколько контейнеров завершили работу или находятся в состоянии перезапуска."
        exit 1
    else
        echo "Скрипт успешно выполнен. Контейнеры запущены."
    fi

    # Удаление временной папки
    rm -r "$temp_dir"
}

stop_services() {
    check_docker_permissions

    # Проверка наличия флага -r
    remove_data=false
    while getopts ":r" opt; do
        case $opt in
            r)
                remove_data=true
                ;;
            \?)
                echo "Неверный параметр: -$OPTARG" >&2
                help_message
                ;;
        esac
    done

    # Переход в папку geo-service и остановка Docker Compose
    cd geo-service
    docker-compose down

    # Проверка статуса контейнеров
    if docker ps -a | grep "geo-backend\|geo-frontend"; then
        echo "Ошибка: Не удалось остановить контейнеры."
        exit 1
    else
        echo "Скрипт успешно выполнен. Контейнеры остановлены."
    fi

    # Удаление данных (включая папку geo-service) при наличии флага -r
    if [ "$remove_data" == true ]; then
        rm -rf geo-service
        echo "Данные успешно удалены."
    else
        echo "Для полного удаления данных используйте флаг -r при команде stop."
    fi
}

rebuild_services() {
    check_git
    check_docker_permissions

    # Остановка и, при наличии флага -r, удаление контейнеров
    stop_services -r

    # Проверка наличия флага -t
    archive_path=$(get_archive_path "$1")

    # Создание временной папки
    temp_dir=$(mktemp -d)

    # Распаковка архива во временную папку
    tar -xzvf "$archive_path" -C "$temp_dir"

    # Переименование родительской директории в HPS_ST3D
    mv "$temp_dir"/*/* "$temp_dir"/HPS_ST3D

    # Создание папки geo-service
    mkdir -p geo-service

    # Клонирование репозиториев geo-backend и geo-frontend в geo-service
    git clone https://github.com/nsu-geo-service/geo-backend.git geo-service/geo-backend
    #git clone https://github.com/geo-frontend-repo.git geo-service/geo-frontend

    # Перемещение папки HPS_ST3D в geo-backend
    mv "$temp_dir"/HPS_ST3D geo-service/geo-backend

    # Создание файла docker-compose.yml
    create_docker_compose geo-service

    # Переход в папку geo-service и запуск Docker Compose с флагом --build
    cd geo-service
    docker-compose up -d --build

    # Проверка статуса контейнеров
    if docker ps -a | grep -E "Restarting|Exited"; then
        echo "Ошибка: Один или несколько контейнеров завершили работу или находятся в состоянии перезапуска."
        exit 1
    else
        echo "Скрипт успешно выполнен. Контейнеры запущены."
    fi

    # Удаление временной папки
    rm -r "$temp_dir"
}

case "$1" in
    start)
        start_services "$@"
        ;;
    stop)
        stop_services "$@"
        ;;
    rebuild)
        rebuild_services "$@"
        ;;
    help)
        help_message
        ;;
    *)
        help_message
        ;;
esac
