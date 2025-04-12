#!/bin/bash
# Применяет глобальные настройки PyArmor

# Exit immediately if a command exits with a non-zero status.
set -e

echo ">>> Этап 2: Настройка глобальных параметров PyArmor..."

# Используем 'python -m pyarmor' для надежности
echo ">>> Установка mix.str:includes (пример, замените на вашу регулярку при необходимости)..."
pyarmor cfg mix.str:includes "/regular expression/" || echo "Предупреждение: Не удалось установить mix.str:includes"

echo ">>> Установка mix_argnames=1..."
pyarmor cfg mix_argnames=1 || echo "Предупреждение: Не удалось установить mix_argnames"

echo ">>> Установка optimize=2..."
pyarmor cfg optimize=2 || echo "Предупреждение: Не удалось установить optimize"

echo ">>> Проверка текущих настроек PyArmor:"
pyarmor cfg

echo ">>> Этап 2 (Настройка PyArmor) завершен!"

exit 0