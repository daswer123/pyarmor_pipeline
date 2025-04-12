#!/bin/bash
# Генерирует SSH ключи для репозиториев и выводит инструкции

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
    if [ -z "$SOURCE_REPO_NAME" ] || [ -z "$OBF_REPO_NAME" ]; then
       echo "!!! Ошибка: Переменные SOURCE_REPO_NAME и OBF_REPO_NAME должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# --- Конфигурация ---
KEY_NAMES=("source" "obf") # Соответствует SOURCE_REPO_NAME и OBF_REPO_NAME
REPO_NAMES=("$SOURCE_REPO_NAME" "$OBF_REPO_NAME")
SSH_BASE_DIR="$HOME/ssh" # Используем $HOME (обычно /root для root)
GITHUB_URL_BASE="https://github.com"
# --- Конец Конфигурации ---

echo ">>> Этап 3: Генерация SSH ключей ==="

# Создаем базовую директорию, если её нет
mkdir -p "$SSH_BASE_DIR"
echo "Базовая директория для ключей: $SSH_BASE_DIR"

# Генерируем ключи
for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  KEY_DIR="$SSH_BASE_DIR/$KEY_NAME"
  KEY_PATH="$KEY_DIR/$KEY_NAME"
  REPO_NAME="${REPO_NAMES[$i]}" # Берем из загруженного .env

  echo "---"
  echo "Обработка ключа для '$KEY_NAME' (Репозиторий: $REPO_NAME)..."

  mkdir -p "$KEY_DIR"
  echo "Создана директория: $KEY_DIR"

  # Генерируем ключ ed25519 без пароля (-N ''), перезаписываем (-f), добавляем комментарий (-C)
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N '' -C "key_${KEY_NAME}_${REPO_NAME//\//_}_$(date +%Y%m%d)" < /dev/null
  echo "Сгенерирован ключ: $KEY_PATH и $KEY_PATH.pub"

  chmod 600 "$KEY_PATH"
  chmod 644 "$KEY_PATH.pub"
  echo "Установлены права 600 для приватного ключа: $KEY_PATH"
done

echo ""
echo "================ ВАЖНО: Следующий шаг - ручной! ================"
echo "Необходимо добавить ПУБЛИЧНЫЕ ключи (.pub) как 'Deploy Keys' на GitHub:"

# Выводим публичные ключи и инструкции
for i in "${!KEY_NAMES[@]}"; do
  KEY_NAME="${KEY_NAMES[$i]}"
  KEY_DIR="$SSH_BASE_DIR/$KEY_NAME"
  PUB_KEY_PATH="$KEY_DIR/$KEY_NAME.pub"
  REPO_NAME="${REPO_NAMES[$i]}"
  REPO_URL="$GITHUB_URL_BASE/$REPO_NAME"
  SETTINGS_URL="$REPO_URL/settings/keys"

  echo ""
  echo "--- Ключ для репозитория: $REPO_NAME ($KEY_NAME) ---"
  echo "1. Перейди в настройки Deploy Keys этого репозитория:"
  echo "   $SETTINGS_URL"
  echo "2. Нажми 'Add deploy key'."
  echo "3. Дай ключу имя (например, 'build_pipeline_${KEY_NAME}')."
  echo "4. Скопируй и вставь ВЕСЬ следующий публичный ключ:"
  echo ""
  cat "$PUB_KEY_PATH"
  echo ""
  # ВАЖНОЕ УТОЧНЕНИЕ ПРО ПРАВА НА ЗАПИСЬ
  if [ "$KEY_NAME" == "obf" ]; then
      echo "5. !!! ВАЖНО: Для этого ключа ('$KEY_NAME') ОБЯЗАТЕЛЬНО поставь галочку 'Allow write access', иначе скрипт сборки не сможет пушить изменения !!!"
  else
      echo "5. Галочку 'Allow write access' ставить НЕ НУЖНО (если нужен только клон)."
  fi
  echo "6. Нажми 'Add key'."
  echo "---"
done

echo ""
echo "=================================================================="
echo ">>> Этап 3 (Генерация ключей) завершен!"
echo ">>> После того как добавишь ОБА ключа на GitHub с правильными правами, запускай следующий скрипт: 04_configure_ssh_and_clone.sh"
echo "=================================================================="

exit 0