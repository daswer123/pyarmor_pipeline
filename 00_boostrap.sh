#!/bin/bash
# Скрипт начальной загрузки пайплайна PyArmor (v3 - объединенные шаги 3 и 4)

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Конфигурация ---
SCRIPTS_DIR="/root/scripts"
ENV_FILE="/root/.env"
# ОБНОВЛЕННЫЙ СПИСОК URL: убраны 03 и 04, добавлен новый 03_setup...
SCRIPT_URLS=(
  "https://github.com/daswer123/pyarmor_pipeline/raw/main/01_install_deps.sh"
  "https://github.com/daswer123/pyarmor_pipeline/raw/main/02_configure_pyarmor.sh"
  "https://github.com/daswer123/pyarmor_pipeline/raw/main/03_setup_ssh_and_clone.sh" # Новый объединенный скрипт
  "https://github.com/daswer123/pyarmor_pipeline/raw/main/04_build_and_push.sh"
)
# --- Конец Конфигурации ---

echo ">>> Запуск скрипта начальной загрузки пайплайна (v3)..."

# 0. Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
   echo "!!! Ошибка: Этот скрипт необходимо запускать с правами root (или через sudo)."
   exit 1
fi
echo "Проверка прав root пройдена."

# 1. Создание директории для скриптов
echo ">>> Создание директории для скриптов: $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"
echo "Директория создана (или уже существовала)."

# 2. Проверка наличия curl
# (Код проверки и установки curl остается без изменений)
if ! command -v curl &> /dev/null; then
    echo "Утилита 'curl' не найдена. Попытка установить..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &> /dev/null; then
        yum install -y curl
    elif command -v dnf &> /dev/null; then
        dnf install -y curl
    else
        echo "!!! Ошибка: Не удалось автоматически установить 'curl'. Пожалуйста, установите ее вручную и запустите скрипт снова."
        exit 1
    fi
    if ! command -v curl &> /dev/null; then
         echo "!!! Ошибка: Не удалось установить 'curl'. Пожалуйста, установите ее вручную и запустите скрипт снова."
         exit 1
    fi
fi
echo "Утилита 'curl' найдена."


# 3. Скачивание и настройка прав для скриптов
echo ">>> Скачивание скриптов пайплайна в $SCRIPTS_DIR..."
for url in "${SCRIPT_URLS[@]}"; do
    filename=$(basename "$url")
    output_path="$SCRIPTS_DIR/$filename"
    echo "   Скачивание $filename из $url..."
    if curl -fL -sS -o "$output_path" "$url"; then
        echo "   $filename успешно скачан."
        chmod +x "$output_path"
        echo "   Права на исполнение для $filename установлены."
    else
        echo "!!! Ошибка: Не удалось скачать $filename из $url."
        exit 1
    fi
done
# Убедимся, что скачали все нужные скрипты (теперь 4 штуки)
if [ $(ls -1 "$SCRIPTS_DIR"/*.sh | wc -l) -ne 4 ]; then
    echo "!!! Ошибка: Ожидалось скачать 4 скрипта, но найдено другое количество."
    echo "    Проверьте список URL в скрипте 00_bootstrap.sh и доступность файлов."
    # exit 1 # Можно раскомментировать для жесткой проверки
fi
echo ">>> Все скрипты успешно скачаны и настроены."

# 4. Создание/Проверка файла .env
echo ">>> Проверка файла конфигурации $ENV_FILE..."
if [ -e "$ENV_FILE" ]; then
    echo "--- ПРЕДУПРЕЖДЕНИЕ ---"
    echo "Файл $ENV_FILE уже существует."
    # (Сообщение остается без изменений)
    echo "----------------------"
else
    echo ">>> Файл $ENV_FILE не найден. Создание образца..."
    # Используем cat с Here Document для создания файла
    cat << 'EOF' > "$ENV_FILE"
# /root/.env - Конфигурационный файл для пайплайна сборки (v2)
# ЗАПОЛНИТЕ ЭТОТ ФАЙЛ СВОИМИ РЕАЛЬНЫМИ ЗНАЧЕНИЯМИ ПЕРЕД ЗАПУСКОМ СКРИПТОВ!
# Замените все значения в кавычках <...> на ваши собственные.

# Версии ПО
PYTHON_VERSION="3.10"
PYARMOR_VERSION="9.1.3" # Укажите точную версию, если нужно

# Данные для Git коммитов (ВАЖНО!)
GIT_USER_NAME="<Your Build Bot Name>" # Имя, которое будет отображаться в коммитах
GIT_USER_EMAIL="<buildbot@example.com>" # Email, который будет в коммитах

# --- Настройки Git SSH ---
GIT_SSH_HOST="github.com" # Имя хоста вашего Git-сервера (например, github.com, gitlab.com)
GIT_SSH_USER="git"        # Имя пользователя для SSH подключения (обычно 'git' для GitHub/GitLab)

# --- Настройки репозиториев (ВАЖНО!) ---
# Имена репозиториев в формате 'имя_пользователя_хостинга/имя_репозитория'
SOURCE_REPO_NAME="<your-github-username>/<your-source-repo>"     # Замените на ваш репозиторий с исходниками
OBF_REPO_NAME="<your-github-username>/<your-obfuscated-repo>" # Замените на ваш репозиторий для обфусцированного кода
# ПРИМЕЧАНИЕ: Полные SSH URL больше не нужны здесь, они будут собраны автоматически.
# -----------------------------

# Рабочая директория для клонирования репозиториев
WORK_DIR="/root/workdir" # Можно изменить при необходимости

# Команда для PyArmor (выберите или измените под вашу лицензию/настройки)
PYARMOR_BUILD_CMD="pyarmor gen -r --enable-rft --mix-str --obf-code 2 --assert-import --platform windows.x86_64,linux.x86_64,darwin.x86_64,darwin.aarch64 --outer ." # Пример PRO
# PYARMOR_BUILD_CMD_FREE="pyarmor gen -r --enable-jit --mix-str --obf-code 1 ." # Пример FREE

# Сообщение коммита для обфусцированного репозитория
COMMIT_MESSAGE="Automated build: Update obfuscated code [skip ci]"

EOF
    chmod 600 "$ENV_FILE"
    echo ">>> Образец файла $ENV_FILE успешно создан."
    echo "!!! НЕОБХОДИМО отредактировать $ENV_FILE и внести ваши данные вместо <...> !!!"
fi

# 5. Вывод инструкций (ОБНОВЛЕННЫЕ)
echo ""
echo "======================== ИНСТРУКЦИЯ ПО ДАЛЬНЕЙШИМ ДЕЙСТВИЯМ (v3) ========================"
echo ""
echo "1.  **Отредактируйте файл конфигурации:**"
echo "    Откройте файл '$ENV_FILE' ('nano $ENV_FILE')"
echo "    и **внимательно** замените ВСЕ значения в угловых скобках '<...>' вашими реальными данными."
echo "    (Особенно важны: GIT_USER_NAME, GIT_USER_EMAIL, GIT_SSH_HOST, SOURCE_REPO_NAME, OBF_REPO_NAME)."
echo ""
echo "2.  **Запустите скрипт установки зависимостей:**"
echo "    Выполните: bash $SCRIPTS_DIR/01_install_deps.sh"
echo ""
echo "3.  **Запустите скрипт настройки PyArmor:**"
echo "    Выполните: bash $SCRIPTS_DIR/02_configure_pyarmor.sh"
echo ""
echo "4.  **Запустите ОСНОВНОЙ скрипт настройки SSH и клонирования:**"
echo "    Выполните: bash $SCRIPTS_DIR/03_setup_ssh_and_clone.sh"
echo "    ---"
echo "    **ВНИМАНИЕ:** Этот скрипт сначала сгенерирует SSH-ключи и выведет инструкции"
echo "    по их добавлению на ваш Git-хостинг ($GIT_SSH_HOST)."
echo "    **Затем он ОСТАНОВИТСЯ и будет ждать вашего подтверждения (нажатия Enter),**"
echo "    что вы добавили ключи с правильными правами (не забудьте права на ЗАПИСЬ для OBF_REPO_NAME)."
echo "    После вашего подтверждения скрипт автоматически продолжит настройку SSH-конфига"
echo "    и клонирование/обновление репозиториев."
echo "    ---"
echo ""
echo "5.  **Запускайте скрипт сборки и публикации по необходимости:**"
echo "    Выполните: bash $SCRIPTS_DIR/04_build_and_push.sh"
echo "    (Выполняет цикл: git pull исходников -> pyarmor build -> git push обфускации)"
echo ""
echo "======================================================================================"
echo ""
echo ">>> Начальная настройка завершена. Следуйте инструкциям выше."

exit 0