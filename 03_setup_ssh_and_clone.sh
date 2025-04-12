#!/bin/bash
# ОБЪЕДИНЕННЫЙ СКРИПТ: Генерирует SSH ключи, ждет добавления на хостинг,
# настраивает SSH конфиг и клонирует/обновляет репозитории.

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
        echo "   Пожалуйста, создайте его из .env.example или запустите 00_bootstrap.sh"
        exit 1
    fi
    # Проверка всех переменных, нужных для этого скрипта
    if [ -z "$SOURCE_REPO_NAME" ] || [ -z "$OBF_REPO_NAME" ] || \
       [ -z "$GIT_SSH_HOST" ] || [ -z "$GIT_SSH_USER" ] || [ -z "$WORK_DIR" ]; then
       echo "!!! Ошибка: Переменные SOURCE_REPO_NAME, OBF_REPO_NAME, GIT_SSH_HOST, GIT_SSH_USER, WORK_DIR должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# --- Константы и переменные ---
# Имена ключей/алиасов
SOURCE_KEY_NAME="source"
OBF_KEY_NAME="obf"
KEY_NAMES=("$SOURCE_KEY_NAME" "$OBF_KEY_NAME")
# Имена репозиториев из .env
REPO_NAMES=("$SOURCE_REPO_NAME" "$OBF_REPO_NAME")
# Базовая директория для SSH ключей
SSH_BASE_DIR="$HOME/ssh" # $HOME обычно /root для root
# Файл конфигурации SSH
SSH_CONFIG_FILE="$HOME/.ssh/config"
# URL-база для инструкций
GITHUB_URL_BASE="https://${GIT_SSH_HOST}" # Используем GIT_SSH_HOST
# --- Конец Констант и переменных ---

echo ">>> Этап 3 (Комбинированный): Настройка SSH и Клонирование ==="

# === ЧАСТЬ 1: Генерация SSH ключей ===
echo ""
echo "--- ШАГ 3.1: Генерация SSH ключей ---"
mkdir -p "$SSH_BASE_DIR"
echo "Базовая директория для ключей: $SSH_BASE_DIR"

declare -A PUB_KEY_PATHS # Ассоциативный массив для хранения путей к публичным ключам

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}" # Берем из загруженного .env
  KEY_DIR="$SSH_BASE_DIR/$KEY_NAME"
  KEY_PATH="$KEY_DIR/$KEY_NAME"
  PUB_KEY_PATH="$KEY_PATH.pub"
  PUB_KEY_PATHS["$KEY_NAME"]="$PUB_KEY_PATH" # Сохраняем путь

  echo "---"
  echo "Обработка ключа для '$KEY_NAME' (Репозиторий: $REPO_NAME)..."
  mkdir -p "$KEY_DIR"
  echo "Создана директория: $KEY_DIR"

  ssh-keygen -t ed25519 -f "$KEY_PATH" -N '' -C "key_${KEY_NAME}_${REPO_NAME//\//_}_$(date +%Y%m%d)" < /dev/null
  echo "Сгенерирован ключ: $KEY_PATH и $PUB_KEY_PATH"

  chmod 600 "$KEY_PATH"
  chmod 644 "$PUB_KEY_PATH"
  echo "Установлены права 600 для приватного ключа: $KEY_PATH"
done


# === ЧАСТЬ 2: Инструкции и Ожидание ===
echo ""
echo "--- ШАГ 3.2: Добавление ключей на $GIT_SSH_HOST ---"
echo "======================== !!! ВАЖНО: РУЧНОЙ ШАГ !!! ========================"
echo "Ниже показаны ПУБЛИЧНЫЕ ключи (.pub), которые необходимо добавить"
echo "в раздел 'Deploy Keys' настроек соответствующих репозиториев на $GIT_SSH_HOST:"

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}"
  PUB_KEY_PATH="${PUB_KEY_PATHS[$KEY_NAME]}"
  REPO_URL="$GITHUB_URL_BASE/$REPO_NAME"
  # Генерируем URL настроек (может отличаться для не-GitHub хостов)
  if [[ "$GIT_SSH_HOST" == "github.com" ]]; then
      SETTINGS_URL="$REPO_URL/settings/keys"
  elif [[ "$GIT_SSH_HOST" == *"gitlab.com"* ]]; then
       SETTINGS_URL="$REPO_URL/-/settings/repository" # Пример для GitLab
  else
       SETTINGS_URL="$REPO_URL (найдите настройки Deploy Keys вручную)"
  fi

  echo ""
  echo "--- Ключ для репозитория: $REPO_NAME ($KEY_NAME) ---"
  echo "1. Перейди в настройки Deploy Keys этого репозитория (примерный URL):"
  echo "   $SETTINGS_URL"
  echo "2. Нажми 'Add deploy key' (или аналогичную кнопку)."
  echo "3. Дай ключу имя (например, 'build_pipeline_${KEY_NAME}')."
  echo "4. Скопируй и вставь ВЕСЬ следующий публичный ключ:"
  echo ""
  cat "$PUB_KEY_PATH"
  echo ""
  if [ "$KEY_NAME" == "$OBF_KEY_NAME" ]; then
      echo "5. !!! ВАЖНО: Для этого ключа ('$KEY_NAME') ОБЯЗАТЕЛЬНО поставь галочку 'Allow write access'/'Права на запись' !!!"
  else
      echo "5. Галочку 'Allow write access'/'Права на запись' ставить НЕ НУЖНО (для клонирования)."
  fi
  echo "6. Нажми 'Add key'."
  echo "---"
done

echo ""
echo "=========================================================================="
read -p ">>> Пожалуйста, подтвердите, что ОБА ключа были добавлены на $GIT_SSH_HOST с правильными правами. Нажмите Enter для продолжения..."
echo "=========================================================================="
echo ""
echo "Продолжаем настройку..."


# === ЧАСТЬ 3: Настройка SSH Config ===
echo ""
echo "--- ШАГ 3.3: Настройка файла $SSH_CONFIG_FILE ---"
mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
touch "$SSH_CONFIG_FILE"
chmod 600 "$SSH_CONFIG_FILE"

CONFIG_APPEND=""

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}"
  KEY_PATH="$SSH_BASE_DIR/$KEY_NAME/$KEY_NAME"
  # Алиас оставляем прежним для совместимости/простоты
  HOST_ALIAS="github.com-$KEY_NAME"

  if [ ! -f "$KEY_PATH" ]; then
    echo "!!! Ошибка: Приватный ключ $KEY_PATH не найден после генерации. Что-то пошло не так."
    exit 1
  fi

  CURRENT_BLOCK=$(cat <<EOF
# Конфигурация для ключа '$KEY_NAME' (репозиторий: $REPO_NAME)
Host $HOST_ALIAS
    HostName $GIT_SSH_HOST
    User $GIT_SSH_USER
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
)
  if grep -q -E "^\s*Host\s+$HOST_ALIAS\s*$" "$SSH_CONFIG_FILE"; then
    echo "Предупреждение: Конфигурация для 'Host $HOST_ALIAS' уже существует. Пропускаем добавление."
  else
    CONFIG_APPEND+="\n$CURRENT_BLOCK\n"
    echo "Подготовлен блок конфигурации для '$HOST_ALIAS' (HostName: $GIT_SSH_HOST, User: $GIT_SSH_USER)."
  fi
done

if [ -n "$CONFIG_APPEND" ]; then
  echo -e "$CONFIG_APPEND" >> "$SSH_CONFIG_FILE"
  echo "Конфигурационные блоки добавлены в $SSH_CONFIG_FILE"
fi


# === ЧАСТЬ 4: Клонирование / Обновление репозиториев ===
echo ""
echo "--- ШАГ 3.4: Клонирование / Обновление репозиториев в $WORK_DIR ---"
mkdir -p "$WORK_DIR"

for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}"
  HOST_ALIAS="github.com-$KEY_NAME"

  REPO_DIR_NAME=$(basename "$REPO_NAME")
  TARGET_DIR="$WORK_DIR/$REPO_DIR_NAME"
  CLONE_URL="$GIT_SSH_USER@$HOST_ALIAS:$REPO_NAME.git"
  ORIGINAL_URL_INFO="${GIT_SSH_USER}@${GIT_SSH_HOST}:${REPO_NAME}.git"

  echo "---"
  echo "Обработка репозитория '$REPO_NAME' (ключ: '$KEY_NAME')..."
  echo "Целевая директория: $TARGET_DIR"

  SSH_TEST_COMMAND="ssh -T ${GIT_SSH_USER}@${HOST_ALIAS}"
  echo "Проверка SSH соединения командой: ${SSH_TEST_COMMAND}"

  if timeout 15s ${SSH_TEST_COMMAND} 2>&1 | grep -qi "successfully authenticated"; then # -i для игнорирования регистра
    echo "[OK] SSH соединение для '$HOST_ALIAS' успешно подтверждено (аутентификация прошла)."

    if [ -d "$TARGET_DIR/.git" ]; then
        echo "Директория '$TARGET_DIR' уже является Git репозиторием. Выполняем git pull..."
        (cd "$TARGET_DIR" && git pull) || echo "[ПРЕДУПРЕЖДЕНИЕ] Не удалось выполнить git pull в $TARGET_DIR."
    elif [ -e "$TARGET_DIR" ]; then
        echo "[ПРЕДУПРЕЖДЕНИЕ] Путь '$TARGET_DIR' существует, но не является Git репозиторием. Пропускаем клонирование."
    else
        echo "Клонирование (через '$CLONE_URL') в '$TARGET_DIR'..."
        if git clone --quiet "$CLONE_URL" "$TARGET_DIR"; then # Добавлен --quiet для чистоты вывода
          echo "[OK] Репозиторий успешно склонирован в '$TARGET_DIR'."
        else
          echo "!!! Ошибка: Не удалось склонировать репозиторий $ORIGINAL_URL_INFO. Проверь вывод git clone (если запустить без --quiet) и права доступа ключа."
          # exit 1 # Можно раскомментировать для остановки при ошибке клонирования
        fi
    fi
  else
    echo "!!! Ошибка: Не удалось подтвердить успешную аутентификацию для '$HOST_ALIAS' после добавления ключей."
    echo "   Убедись, что ключи были ТОЧНО добавлены на '$GIT_SSH_HOST' с нужными правами,"
    echo "   и что хост '$GIT_SSH_HOST' доступен."
    echo "   Попробуй проверить вручную: ssh -vT ${GIT_SSH_USER}@${HOST_ALIAS}"
    # exit 1 # Можно раскомментировать для остановки при ошибке соединения
  fi
  echo "---"
done

echo ""
echo ">>> Этап 3 (Комбинированный: Настройка SSH и Клонирование) завершен!"
echo ">>> Репозитории должны находиться (или быть обновлены) в $WORK_DIR"
echo ">>> Теперь можно запускать скрипт сборки: 05_build_and_push.sh"

exit 0