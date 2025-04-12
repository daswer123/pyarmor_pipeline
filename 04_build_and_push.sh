#!/bin/bash
# Выполняет pull исходников, сборку PyArmor и push обфусцированного кода

set -e # Выход при ошибке
# set -x # Раскомментируй для детальной отладки команд

ENV_FILE="/root/.env"

# --- Функция загрузки .env ---
load_env() {
    if [ -f "$1" ]; then
        echo ">>> Загрузка переменных из $1..."
        set -a
        # shellcheck disable=SC1090
        source "$1"
        set +a
    else
        echo "!!! Ошибка: Файл конфигурации $1 не найден."
        exit 1
    fi
    # Проверка переменных
    if [ -z "$WORK_DIR" ] || [ -z "$SOURCE_REPO_NAME" ] || [ -z "$OBF_REPO_NAME" ] || [ -z "$PYARMOR_BUILD_CMD" ] || [ -z "$COMMIT_MESSAGE" ]; then
       echo "!!! Ошибка: Переменные WORK_DIR, SOURCE_REPO_NAME, OBF_REPO_NAME, PYARMOR_BUILD_CMD, COMMIT_MESSAGE должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Функция для выполнения команд с проверкой ---
run_command() {
    echo "--> Выполняю: $@"
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "!!! Ошибка: Команда '$1' завершилась с кодом $status." >&2
        # Вернуться в исходную директорию может быть полезно при ошибке
        cd "$initial_dir" || echo "Не удалось вернуться в $initial_dir"
        exit $status
    fi
    return $status
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# --- Определение путей ---
# Извлекаем имена директорий из полных имен репозиториев
SOURCE_DIR_NAME=$(basename "$SOURCE_REPO_NAME")
OBF_DIR_NAME=$(basename "$OBF_REPO_NAME")

SOURCE_REPO_PATH="$WORK_DIR/$SOURCE_DIR_NAME"
OBF_REPO_PATH="$WORK_DIR/$OBF_DIR_NAME"
DIST_PATH="$SOURCE_REPO_PATH/dist" # Путь к результатам сборки PyArmor

# Запоминаем исходную директорию
initial_dir=$(pwd)
echo "Начальная директория: $initial_dir"
echo "Рабочая директория: $WORK_DIR"
echo "Путь к исходникам: $SOURCE_REPO_PATH"
echo "Путь к обфускации: $OBF_REPO_PATH"


# --- 1. Обновление исходников ---
echo ""
echo "=== Шаг 1: Обновление исходного репозитория ($SOURCE_REPO_PATH) ==="
if [ ! -d "$SOURCE_REPO_PATH" ]; then
    echo "!!! Ошибка: Директория исходников не найдена: $SOURCE_REPO_PATH" >&2
    echo "   Возможно, нужно сначала запустить скрипт 04_configure_ssh_and_clone.sh"
    exit 1
fi
run_command cd "$SOURCE_REPO_PATH"
echo "Текущая директория: $(pwd)"
run_command git pull

# --- 2. Обфускация ---
echo ""
echo "=== Шаг 2: Запуск PyArmor в $SOURCE_REPO_PATH ==="
# Удаляем старую папку dist
if [ -d "$DIST_PATH" ]; then
    echo "Удаляем старую папку '$DIST_PATH'..."
    run_command rm -rf "$DIST_PATH"
fi
# Запускаем PyArmor (используем переменную из .env)
echo "--> Выполняю PyArmor: ${PYARMOR_BUILD_CMD}"
# Запускаем команду в текущей директории ($SOURCE_REPO_PATH)
if ! ${PYARMOR_BUILD_CMD}; then
     echo "!!! Ошибка: PyArmor завершился с ошибкой." >&2
     # Решаем, останавливаться или нет. Пока продолжим.
     # exit 1
fi
# Проверяем, создалась ли папка dist
if [ ! -d "$DIST_PATH" ]; then
    echo "!!! Ошибка: Папка 'dist' не была создана PyArmor в $SOURCE_REPO_PATH." >&2
    exit 1
fi
echo "PyArmor завершил работу."

# --- 3. Подготовка и копирование в репозиторий обфускации ---
echo ""
echo "=== Шаг 3: Копирование результатов в репозиторий обфускации ($OBF_REPO_PATH) ==="
if [ ! -d "$OBF_REPO_PATH" ]; then
    echo "!!! Ошибка: Директория репозитория обфускации не найдена: $OBF_REPO_PATH" >&2
    echo "   Возможно, нужно сначала запустить скрипт 04_configure_ssh_and_clone.sh"
    exit 1
fi
run_command cd "$OBF_REPO_PATH"
echo "Текущая директория: $(pwd)"

echo "Очистка старого содержимого в $OBF_REPO_PATH (кроме .git)..."
# Осторожная очистка
find . -maxdepth 1 -path './.git' -prune -o -path '.' -prune -o -exec rm -rf {} +
find_status=$?
if [ $find_status -ne 0 ]; then
    echo "!!! Ошибка: Не удалось очистить $OBF_REPO_PATH." >&2
    exit $find_status
fi

echo "Копирование нового содержимого из $DIST_PATH ..."
# Копируем содержимое папки dist
run_command cp -a "$DIST_PATH/." .

# --- 4. Коммит и Пуш изменений ---
echo ""
echo "=== Шаг 4: Коммит и Пуш изменений в $OBF_REPO_PATH ==="
# Проверяем, есть ли изменения
if [[ -z $(git status --porcelain) ]]; then
    echo "Нет изменений для коммита в $OBF_REPO_PATH."
else
    echo "Добавление изменений в индекс..."
    run_command git add .
    echo "Создание коммита..."
    run_command git commit -m "$COMMIT_MESSAGE" # Используем сообщение из .env
fi

echo "Отправка изменений на удаленный сервер (git push)..."
echo "ВАЖНО: Для этого шага у Deploy Key репозитория '${OBF_REPO_NAME}' должны быть права на ЗАПИСЬ!"
run_command git push

# --- 5. Очистка ---
echo ""
echo "=== Шаг 5: Очистка (удаление dist из $SOURCE_REPO_PATH) ==="
echo "Удаление папки '$DIST_PATH'..."
run_command rm -rf "$DIST_PATH"

# --- Завершение ---
echo ""
echo ">>> Этап 5 (Сборка и Пуш) завершен успешно! ==="
run_command cd "$initial_dir" # Возвращаемся в исходную директорию

exit 0