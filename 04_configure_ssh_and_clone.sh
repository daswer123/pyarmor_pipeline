#!/bin/bash
# Настраивает ~/.ssh/config и клонирует репозитории (v2 - с авто-сборкой SSH URL)

# Выход при ошибке
set -e

# Путь к файлу .env
ENV_FILE="/root/.env"

# --- Функция загрузки .env ---
load_env() {
    if [ -f "$1" ]; then
        echo ">>> Загрузка переменных из $1..."
        set -a # Автоматически экспортировать переменные
        # shellcheck disable=SC1090 # Игнорировать предупреждение shellcheck о source
        source "$1"
        set +a # Прекратить автоматический экспорт
    else
        echo "!!! Ошибка: Файл конфигурации $1 не найден."
        exit 1
    fi
    # Проверка критически важных переменных для этого скрипта
    if [ -z "$WORK_DIR" ] || [ -z "$SOURCE_REPO_NAME" ] || [ -z "$OBF_REPO_NAME" ] || [ -z "$GIT_SSH_HOST" ] || [ -z "$GIT_SSH_USER" ]; then
       echo "!!! Ошибка: Переменные WORK_DIR, SOURCE_REPO_NAME, OBF_REPO_NAME, GIT_SSH_HOST, GIT_SSH_USER должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# --- Конфигурация SSH ---
# Имена ключей должны соответствовать скрипту 03 и порядку имен репо ниже
KEY_NAMES=("source" "obf")
# Имена репозиториев из .env
REPO_NAMES=("$SOURCE_REPO_NAME" "$OBF_REPO_NAME")
# Базовая директория для SSH ключей
SSH_BASE_DIR="$HOME/ssh" # $HOME обычно /root для root
# Файл конфигурации SSH
SSH_CONFIG_FILE="$HOME/.ssh/config"
# --- Конец Конфигурации ---


echo ">>> Этап 4: Настройка SSH Config и Клонирование (v2) ==="
echo "Предполагается, что ключи уже сгенерированы скриптом 03 и добавлены в Deploy Keys на $GIT_SSH_HOST."

# --- Настройка ~/.ssh/config ---
echo "Настройка файла $SSH_CONFIG_FILE..."
mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
touch "$SSH_CONFIG_FILE"
chmod 600 "$SSH_CONFIG_FILE"

CONFIG_APPEND="" # Переменная для сбора блоков конфигурации

# Готовим блоки конфигурации для каждого ключа/репозитория
for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  KEY_PATH="$SSH_BASE_DIR/$KEY_NAME/$KEY_NAME"
  # Создаем псевдоним хоста. Имя 'github.com-...' оставляем для простоты,
  # даже если реальный хост другой. Главное, что HostName ниже будет правильный.
  HOST_ALIAS="github.com-$KEY_NAME"

  # Проверяем, существует ли приватный ключ
  if [ ! -f "$KEY_PATH" ]; then
    echo "!!! Ошибка: Приватный ключ не найден: $KEY_PATH"
    echo "Убедись, что скрипт 03_generate_ssh_keys.sh отработал без ошибок."
    exit 1
  fi
  chmod 600 "$KEY_PATH" # Устанавливаем права на всякий случай

  # Формируем блок для файла конфигурации, используя переменные из .env
  CURRENT_BLOCK=$(cat <<EOF
# Конфигурация для ключа '$KEY_NAME' (репозиторий: ${REPO_NAMES[$i]})
Host $HOST_ALIAS
    HostName $GIT_SSH_HOST
    User $GIT_SSH_USER
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    # Опции ниже отключают проверку ключа хоста - используйте с осторожностью
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
)
  # Проверяем, нет ли уже такого хоста в конфиге
  if grep -q -E "^\s*Host\s+$HOST_ALIAS\s*$" "$SSH_CONFIG_FILE"; then
    echo "Предупреждение: Конфигурация для 'Host $HOST_ALIAS' уже существует в $SSH_CONFIG_FILE. Пропускаем добавление."
  else
    CONFIG_APPEND+="\n$CURRENT_BLOCK\n"
    echo "Подготовлен блок конфигурации для '$HOST_ALIAS' (HostName: $GIT_SSH_HOST, User: $GIT_SSH_USER)."
  fi
done

# Добавляем подготовленные блоки в конец файла конфигурации SSH
if [ -n "$CONFIG_APPEND" ]; then
  echo -e "$CONFIG_APPEND" >> "$SSH_CONFIG_FILE"
  echo "Конфигурационные блоки добавлены в $SSH_CONFIG_FILE"
fi

# --- Клонирование репозиториев ---
echo ""
echo "Клонирование/Обновление репозиториев в рабочую директорию: $WORK_DIR..."
mkdir -p "$WORK_DIR"

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}" # Имя репозитория (user/repo) из .env
  HOST_ALIAS="github.com-$KEY_NAME" # Используем тот же алиас, что и в конфиге SSH

  # --- Извлечение данных ---
  # Пример: user/repo -> repo
  REPO_DIR_NAME=$(basename "$REPO_NAME")
  # Полный путь к целевой директории клонирования
  TARGET_DIR="$WORK_DIR/$REPO_DIR_NAME"
  # Формируем URL для клонирования с использованием алиаса хоста и пользователя из .env
  # Пример: git@github.com-source:user/repo.git
  CLONE_URL="$GIT_SSH_USER@$HOST_ALIAS:$REPO_NAME.git"
  # Собираем "оригинальный" URL для логов/справок (не используется для клонирования)
  ORIGINAL_URL_INFO="${GIT_SSH_USER}@${GIT_SSH_HOST}:${REPO_NAME}.git"
  # --- Конец извлечения данных ---

  echo "---"
  echo "Обработка репозитория '$REPO_NAME' (ключ: '$KEY_NAME')..."
  echo "Целевая директория: $TARGET_DIR"
  echo "URL для клонирования: $CLONE_URL (Ориентировочный исходный URL: $ORIGINAL_URL_INFO)"

  # 1. Проверка соединения (Используем алиас и пользователя из .env)
  SSH_TEST_COMMAND="ssh -T ${GIT_SSH_USER}@${HOST_ALIAS}"
  echo "Проверка SSH соединения командой: ${SSH_TEST_COMMAND}"
  # Проверяем вывод stderr на наличие сообщения об успехе
  if timeout 15s ${SSH_TEST_COMMAND} 2>&1 | grep -q "successfully authenticated"; then
    echo "[OK] SSH соединение для '$HOST_ALIAS' успешно подтверждено (аутентификация прошла)."

    # 2. Клонирование или обновление
    if [ -d "$TARGET_DIR/.git" ]; then
        echo "Директория '$TARGET_DIR' уже является Git репозиторием. Выполняем git pull..."
        (cd "$TARGET_DIR" && git pull) || echo "[ПРЕДУПРЕЖДЕНИЕ] Не удалось выполнить git pull в $TARGET_DIR."

    elif [ -e "$TARGET_DIR" ]; then
        echo "[ПРЕДУПРЕЖДЕНИЕ] Путь '$TARGET_DIR' существует, но не является Git репозиторием. Пропускаем клонирование."

    else
        echo "Клонирование (через '$CLONE_URL') в '$TARGET_DIR'..."
        # Клонируем с использованием URL с алиасом хоста
        if git clone "$CLONE_URL" "$TARGET_DIR"; then
          echo "[OK] Репозиторий успешно склонирован в '$TARGET_DIR'."
        else
          echo "!!! Ошибка: Не удалось склонировать репозиторий. Проверь вывод git clone выше и права доступа ключа."
        fi
    fi
  else
    echo "!!! Ошибка: Не удалось подтвердить успешную аутентификацию для '$HOST_ALIAS'."
    echo "   Убедись, что SSH ключ добавлен на '$GIT_SSH_HOST' с нужными правами для репозитория '$REPO_NAME',"
    echo "   и что хост '$GIT_SSH_HOST' доступен."
    echo "   Попробуй проверить вручную: ssh -vT ${GIT_SSH_USER}@${HOST_ALIAS}"
  fi
  echo "---"
done

echo ""
echo ">>> Этап 4 (Настройка SSH и Клонирование) завершен!"
echo ">>> Репозитории должны находиться (или быть обновлены) в $WORK_DIR"

exit 0