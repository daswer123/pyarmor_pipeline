#!/bin/bash
# Устанавливает Python, Git, PyArmor и настраивает Git

# Exit immediately if a command exits with a non-zero status.
set -e

ENV_FILE="/root/.env"

# --- Функция загрузки .env ---
load_env() {
    if [ -f "$1" ]; then
        echo ">>> Загрузка переменных из $1..."
        set -a # Automatically export all variables subsequent defined or modified
        # shellcheck disable=SC1090 # Ignore SC1090 warning about sourcing non-constant path
        source "$1"
        set +a # Stop automatically exporting variables
    else
        echo "!!! Ошибка: Файл конфигурации $1 не найден."
        exit 1
    fi
    # Проверка обязательных переменных для этого скрипта
    if [ -z "$PYTHON_VERSION" ] || [ -z "$PYARMOR_VERSION" ] || [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
       echo "!!! Ошибка: Переменные PYTHON_VERSION, PYARMOR_VERSION, GIT_USER_NAME, GIT_USER_EMAIL должны быть установлены в $ENV_FILE"
       exit 1
    fi
    echo ">>> Переменные загружены."
}

# --- Загрузка .env ---
load_env "$ENV_FILE"

# Приоритет для update-alternatives (выше = предпочтительнее)
PYTHON_PRIORITY=100

# --- Обновление и установка зависимостей ---
echo ">>> Обновление списка пакетов..."
sudo apt update

echo ">>> Установка необходимых пакетов (software-properties-common, curl, git)..."
sudo apt install -y software-properties-common curl git

# --- Добавление PPA deadsnakes ---
echo ">>> Добавление PPA deadsnakes для получения свежих версий Python..."
# Проверяем, существует ли PPA, чтобы не добавлять повторно
if ! grep -q "^deb .*deadsnakes" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    echo ">>> Повторное обновление списка пакетов после добавления PPA..."
    sudo apt update
else
    echo ">>> PPA deadsnakes уже добавлен."
fi

# --- Установка Python ---
echo ">>> Установка Python ${PYTHON_VERSION} и связанных пакетов (dev, venv, distutils)..."
sudo apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-distutils

# --- Настройка python -> pythonX.Y через update-alternatives ---
echo ">>> Настройка команды 'python' для вызова 'python${PYTHON_VERSION}'..."
sudo update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} ${PYTHON_PRIORITY} --slave /usr/bin/pip pip /usr/bin/pip${PYTHON_VERSION%.*} || echo "Предупреждение: Не удалось настроить /usr/bin/pip как slave (возможно, pip${PYTHON_VERSION%.*} не существует)"


echo ">>> Проверка: команда 'python' теперь должна указывать на Python ${PYTHON_VERSION}."
python --version || echo "Ошибка при вызове 'python --version'."


# --- Установка pip (если update-alternatives не справился) ---
echo ">>> Проверка и установка pip для текущей версии 'python'..."
if ! python -m pip --version &> /dev/null; then
    echo ">>> pip не найден для текущего python, установка через get-pip.py..."
    curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
    sudo python /tmp/get-pip.py
    rm /tmp/get-pip.py
else
    echo ">>> pip уже доступен."
fi
echo ">>> Проверка версии pip:"
python -m pip --version

# --- Установка PyArmor ---
echo ">>> Установка/обновление PyArmor до версии ${PYARMOR_VERSION}..."
sudo python -m pip install --upgrade pip # Обновим pip
sudo python -m pip install pyarmor=="${PYARMOR_VERSION}" # Используем точную версию

# --- Проверка установки PyArmor ---
echo ">>> Проверка установки и версии PyArmor..."
if python -m pyarmor --version &> /dev/null; then
    echo "PyArmor установлен успешно. Версия:"
    python -m pyarmor --version
else
    echo "Не удалось выполнить 'python -m pyarmor --version'. Проверка через pip show:"
    python -m pip show pyarmor || echo "PyArmor не найден через pip show."
fi

# --- Настройка Git ---
echo ">>> Настройка глобальных параметров Git..."
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"
echo ">>> Имя пользователя Git установлено: $(git config --global user.name)"
echo ">>> Email пользователя Git установлен: $(git config --global user.email)"


echo ">>> Этап 1 (Установка зависимостей) завершен!"
echo "---"
echo "ВАЖНО: Пакеты Python были установлены глобально с помощью sudo."
echo "Для изоляции проектов рекомендуется использовать виртуальные окружения."
echo "---"

exit 0