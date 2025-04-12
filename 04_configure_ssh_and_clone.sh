#!/bin/bash
# Настраивает ~/.ssh/config и клонирует репозитории

set -e

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
    if [ -z "$WORK_DIR" ] || [ -z "$SOURCE_REPO_SSH_URL" ] || [ -z "$OBF_REPO_SSH_URL" ] ; then
       echo "!!! Ошибка: Переменные WORK_DIR, SOURCE_REPO_SSH_URL, OBF_REPO_SSH_URL должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# --- Конфигурация ---
KEY_NAMES=("source" "obf") # Должны соответствовать порядку URL ниже
REPO_SSH_URLS=("$SOURCE_REPO_SSH_URL" "$OBF_REPO_SSH_URL")
SSH_BASE_DIR="$HOME/ssh"
SSH_CONFIG_FILE="$HOME/.ssh/config"
# --- Конец Конфигурации ---


echo ">>> Этап 4: Настройка SSH Config и Клонирование ==="
echo "Предполагается, что ключи уже сгенерированы и добавлены в Deploy Keys на GitHub."

# Создаем директорию ~/.ssh и файл config, если их нет
mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
touch "$SSH_CONFIG_FILE"
chmod 600 "$SSH_CONFIG_FILE"

CONFIG_APPEND="" # Собираем блоки для добавления

# Готовим блоки конфигурации для каждого ключа
for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  KEY_PATH="$SSH_BASE_DIR/$KEY_NAME/$KEY_NAME"
  HOST_ALIAS="github.com-$KEY_NAME"

  # Проверяем, существует ли приватный ключ
  if [ ! -f "$KEY_PATH" ]; then
    echo "!!! Ошибка: Приватный ключ не найден: $KEY_PATH"
    echo "Убедись, что скрипт 03_generate_ssh_keys.sh отработал без ошибок."
    exit 1
  fi
  chmod 600 "$KEY_PATH" # Устанавливаем права на всякий случай

  # Формируем блок для файла конфигурации
  CURRENT_BLOCK=$(cat <<EOF
# Конфигурация для ключа '$KEY_NAME' (добавлено скриптом)
Host $HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    StrictHostKeyChecking no # Опционально: отключает проверку ключа хоста при первом подключении
    UserKnownHostsFile /dev/null # Опционально: не сохранять ключ хоста
EOF
)
  # Проверяем, нет ли уже такого хоста в конфиге
  # Используем grep -q -F -e "Host $HOST_ALIAS" для точного совпадения строки
  if grep -q -F -e "Host $HOST_ALIAS" "$SSH_CONFIG_FILE"; then
    echo "Предупреждение: Конфигурация для 'Host $HOST_ALIAS' уже существует в $SSH_CONFIG_FILE. Пропускаем добавление."
  else
    CONFIG_APPEND+="\n$CURRENT_BLOCK\n"
    echo "Подготовлен блок конфигурации для '$HOST_ALIAS'."
  fi
done

# Добавляем подготовленные блоки в конец файла конфигурации SSH
if [ -n "$CONFIG_APPEND" ]; then
  echo -e "$CONFIG_APPEND" >> "$SSH_CONFIG_FILE"
  echo "Конфигурационные блоки добавлены в $SSH_CONFIG_FILE"
fi

# --- Клонирование репозиториев ---
echo ""
echo "Клонирование репозиториев в $WORK_DIR..."
mkdir -p "$WORK_DIR" # Создаем рабочую директорию, если её нет

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  HOST_ALIAS="github.com-$KEY_NAME"
  ORIGINAL_URL="${REPO_SSH_URLS[$i]}" # Берем URL из .env

  # Извлекаем 'username/repo.git' из URL
  USER_REPO_PART=$(echo "$ORIGINAL_URL" | sed 's/git@github\.com://')
  # Извлекаем имя репозитория для имени папки
  REPO_DIR_NAME=$(basename "$USER_REPO_PART" .git)
  TARGET_DIR="$WORK_DIR/$REPO_DIR_NAME"

  # Формируем правильный URL для клонирования с алиасом хоста
  CLONE_URL="git@$HOST_ALIAS:$USER_REPO_PART"

  echo "---"
  echo "Обработка репозитория '$REPO_DIR_NAME' ($KEY_NAME)..."

  # Проверяем соединение перед клонированием
  echo "Проверка SSH соединения с использованием '$HOST_ALIAS'..."
  if ssh -T "git@$HOST_ALIAS"; then
    echo "SSH соединение для '$HOST_ALIAS' успешно."

    # Клонируем, если директории еще нет
    if [ -d "$TARGET_DIR" ]; then
        echo "Директория '$TARGET_DIR' уже существует. Пропускаем клонирование."
        echo "Если нужно обновить, сделайте 'git pull' вручную или используйте скрипт 05_build_and_push.sh для source репо."
    else
        echo "Клонирование '$ORIGINAL_URL' в '$TARGET_DIR'..."
        if git clone "$CLONE_URL" "$TARGET_DIR"; then
          echo "Репозиторий успешно склонирован в '$TARGET_DIR'."
        else
          echo "!!! Ошибка: Не удалось склонировать репозиторий $ORIGINAL_URL. Проверь вывод git clone."
          # Можно добавить exit 1, если клонирование критично для продолжения
        fi
    fi
  else
    echo "!!! Ошибка: Не удалось установить SSH соединение для '$HOST_ALIAS'."
    echo "   Проверь, что ключ добавлен на GitHub с правильными правами доступа."
    echo "   Проверь вывод ssh -T git@$HOST_ALIAS для деталей."
    # Можно добавить exit 1
  fi
  echo "---"
done

echo ""
echo ">>> Этап 4 (Настройка SSH и Клонирование) завершен!"
echo ">>> Репозитории должны находиться в $WORK_DIR"

exit 0