#!/bin/bash
# Скрипт начальной загрузки пайплайна PyArmor

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Конфигурация ---
SCRIPTS_DIR="/root/scripts"
ENV_FILE="/root/.env"
SCRIPT_URLS=(
  "https://raw.githubusercontent.com/daswer123/pyarmor_pipeline/refs/heads/main/01_install_deps.sh"
  "https://raw.githubusercontent.com/daswer123/pyarmor_pipeline/refs/heads/main/02_configure_pyarmor.sh"
  "https://raw.githubusercontent.com/daswer123/pyarmor_pipeline/refs/heads/main/03_generate_ssh_keys.sh"
  "https://raw.githubusercontent.com/daswer123/pyarmor_pipeline/refs/heads/main/04_configure_ssh_and_clone.sh"
  "https://raw.githubusercontent.com/daswer123/pyarmor_pipeline/refs/heads/main/05_build_and_push.sh"
)
# --- Конец Конфигурации ---

echo ">>> Запуск скрипта начальной загрузки пайплайна..."

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
if ! command -v curl &> /dev/null; then
    # Попытка установить curl, если его нет (Debian/Ubuntu)
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
    # Извлекаем имя файла из URL
    filename=$(basename "$url")
    output_path="$SCRIPTS_DIR/$filename"
    echo "   Скачивание $filename из $url..."
    # Используем curl: -f (fail fast), -L (follow redirects), -s (silent), -S (show error), -o (output)
    if curl -fL -sS -o "$output_path" "$url"; then
        echo "   $filename успешно скачан."
        # Делаем скрипт исполняемым
        chmod +x "$output_path"
        echo "   Права на исполнение для $filename установлены."
    else
        echo "!!! Ошибка: Не удалось скачать $filename из $url."
        exit 1
    fi
done
echo ">>> Все скрипты успешно скачаны и настроены."

# 4. Создание/Проверка файла .env
echo ">>> Проверка файла конфигурации $ENV_FILE..."
if [ -e "$ENV_FILE" ]; then
    echo "--- ПРЕДУПРЕЖДЕНИЕ ---"
    echo "Файл $ENV_FILE уже существует."
    echo "Новый файл не создавался. Убедитесь, что существующий файл содержит"
    echo "все необходимые и актуальные переменные для работы пайплайна."
    echo "Образец можно посмотреть ниже или в документации."
    echo "----------------------"
else
    echo ">>> Файл $ENV_FILE не найден. Создание образца..."
    # Используем cat с Here Document для создания файла
    # ЗАМЕНЕНЫ КОНКРЕТНЫЕ ИМЕНА РЕПО НА ПЛЕЙСХОЛДЕРЫ
    cat << 'EOF' > "$ENV_FILE"
# /root/.env - Конфигурационный файл для пайплайна сборки
# ЗАПОЛНИТЕ ЭТОТ ФАЙЛ СВОИМИ РЕАЛЬНЫМИ ЗНАЧЕНИЯМИ ПЕРЕД ЗАПУСКОМ СКРИПТОВ!
# Замените все значения в кавычках <...> на ваши собственные.

# Версии ПО
PYTHON_VERSION="3.10"
PYARMOR_VERSION="9.1.3" # Укажите точную версию, если нужно

# Данные для Git коммитов (ВАЖНО!)
GIT_USER_NAME="<Your Build Bot Name>" # Имя, которое будет отображаться в коммитах
GIT_USER_EMAIL="<buildbot@example.com>" # Email, который будет в коммитах

# --- Настройки репозиториев (ВАЖНО!) ---
# Имена репозиториев в формате 'имя_пользователя_github/имя_репозитория'
SOURCE_REPO_NAME="<your-github-username>/<your-source-repo>" # Замените на ваш репозиторий с исходниками
OBF_REPO_NAME="<your-github-username>/<your-obfuscated-repo>"    # Замените на ваш репозиторий для обфусцированного кода

# SSH URL репозиториев (ВАЖНО: Используйте именно SSH URL, не HTTPS!)
# Пример: git@github.com:username/repo.git
SOURCE_REPO_SSH_URL="<git@github.com:your-github-username/your-source-repo.git>" # Замените на ваш SSH URL
OBF_REPO_SSH_URL="<git@github.com:your-github-username/your-obfuscated-repo.git>"    # Замените на ваш SSH URL
# -----------------------------

# Рабочая директория для клонирования репозиториев
WORK_DIR="/root/workdir" # Можно изменить при необходимости

# Команда для PyArmor (выберите или измените под вашу лицензию/настройки)
# Оставьте одну из строк или напишите свою команду
PYARMOR_BUILD_CMD="pyarmor gen -r --enable-rft --mix-str --obf-code 2 --assert-import --platform windows.x86_64,linux.x86_64,darwin.x86_64,darwin.aarch64 --outer ." # Пример PRO
# PYARMOR_BUILD_CMD="pyarmor gen -r --enable-jit --mix-str --obf-code 1 ." # Пример FREE

# Сообщение коммита для обфусцированного репозитория
COMMIT_MESSAGE="Automated build: Update obfuscated code [skip ci]" # [skip ci] может быть полезно для некоторых CI/CD систем

EOF
    # Устанавливаем права доступа (только для владельца)
    chmod 600 "$ENV_FILE"
    echo ">>> Образец файла $ENV_FILE успешно создан."
    echo "!!! НЕОБХОДИМО отредактировать $ENV_FILE и внести ваши данные вместо <...> !!!"
fi

# 5. Вывод инструкций
echo ""
echo "======================== ИНСТРУКЦИЯ ПО ДАЛЬНЕЙШИМ ДЕЙСТВИЯМ ========================"
echo ""
echo "1.  **Отредактируйте файл конфигурации:**"
echo "    Откройте файл '$ENV_FILE' в текстовом редакторе (например, 'nano $ENV_FILE')"
echo "    и **внимательно** замените ВСЕ значения в угловых скобках '<...>' вашими реальными данными."
echo "    Особенно важны: GIT_USER_NAME, GIT_USER_EMAIL, SOURCE_REPO_NAME, OBF_REPO_NAME, SOURCE_REPO_SSH_URL, OBF_REPO_SSH_URL."
echo ""
echo "2.  **Запустите скрипт установки зависимостей:**"
echo "    Выполните: $SCRIPTS_DIR/01_install_deps.sh"
echo "    (Установит Python, Git, PyArmor и настроит Git)"
echo ""
echo "3.  **Запустите скрипт настройки PyArmor:**"
echo "    Выполните: $SCRIPTS_DIR/02_configure_pyarmor.sh"
echo "    (Применит глобальные настройки PyArmor)"
echo ""
echo "4.  **Запустите скрипт генерации SSH ключей:**"
echo "    Выполните: $SCRIPTS_DIR/03_generate_ssh_keys.sh"
echo "    Скрипт сгенерирует ключи и выведет инструкции."
echo ""
echo "5.  **!!! ВЫПОЛНИТЕ РУЧНОЙ ШАГ !!!**"
echo "    Следуя инструкциям из вывода предыдущего скрипта, добавьте"
echo "    сгенерированные ПУБЛИЧНЫЕ ключи (.pub) в настройки Deploy Keys"
echo "    соответствующих репозиториев на GitHub (тех, что вы указали в .env)."
echo "    **КРИТИЧЕСКИ ВАЖНО:** Для ключа репозитория с обфусцированным кодом"
echo "    (для OBF_REPO_NAME) **ОБЯЗАТЕЛЬНО** предоставьте права на запись ('Allow write access')."
echo ""
echo "6.  **Запустите скрипт настройки SSH и клонирования:**"
echo "    Выполните: $SCRIPTS_DIR/04_configure_ssh_and_clone.sh"
echo "    (Настроит ~/.ssh/config и склонирует репозитории в '$WORK_DIR', если ключи добавлены верно)"
echo ""
echo "7.  **Запускайте скрипт сборки и публикации по необходимости:**"
echo "    Выполните: $SCRIPTS_DIR/05_build_and_push.sh"
echo "    (Выполняет цикл: git pull исходников -> pyarmor build -> git push обфускации)"
echo ""
echo "===================================================================================="
echo ""
echo ">>> Начальная настройка завершена. Следуйте инструкциям выше."

exit 0