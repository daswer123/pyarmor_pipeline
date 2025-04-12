# Гайд: Настройка SSH Deploy Keys для CI/CD Пайплайна

Этот документ описывает шаги для настройки доступа по SSH с сервера сборки/развертывания (CI/CD машины) к трем репозиториям на GitHub с использованием **Deploy Keys**. Каждый репозиторий будет использовать свой собственный SSH ключ.

**Целевые репозитории и предполагаемые права доступа:**

1.  `organization/pipeline-repository` (Чтение / Read-Only) - Для получения скриптов пайплайна.
2.  `organization/source-code-repository` (Чтение / Read-Only) - Для получения исходного кода.
3.  `organization/obfuscated-code-repository` (Чтение и Запись / Read-Write) - Для сохранения обфусцированного кода.

**Важно:** Если вам нужны другие права доступа (например, запись в `pipeline` репозиторий), измените соответствующие настройки на Шаге 2.

---

## Шаг 1: Генерация SSH Ключей на Сервере Пайплайна

Нам нужно создать три отдельные пары SSH ключей (приватный и публичный) для каждого репозитория. Ключи будут храниться в стандартной директории `~/.ssh/`.

1.  **Создайте директорию `.ssh` (если ее нет) и установите права:**
    ```bash
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cd ~/.ssh
    ```

2.  **Сгенерируйте ключи:**
    * Используйте `ssh-keygen`.
    * Укажите уникальное имя файла для каждого ключа с помощью опции `-f`.
    * **Не устанавливайте пароль (passphrase)**, нажав Enter дважды на запрос пароля, иначе автоматизация не сможет использовать ключ.
    * Опция `-C` добавляет комментарий к ключу (полезно для идентификации).

    ```bash
    # Ключ для репозитория pipeline (Read-Only)
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/pipeline_ro_key -N "" -C "pipeline_deploy_key_ro_$(date +%Y-%m-%d)"

    # Ключ для репозитория исходников (Read-Only)
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/source_ro_key -N "" -C "source_deploy_key_ro_$(date +%Y-%m-%d)"

    # Ключ для репозитория с обфусцированным кодом (Read-Write)
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/obf_rw_key -N "" -C "obf_deploy_key_rw_$(date +%Y-%m-%d)"
    ```
    *После выполнения этих команд у вас появятся файлы:*
    * `pipeline_ro_key` (приватный) и `pipeline_ro_key.pub` (публичный)
    * `source_ro_key` (приватный) и `source_ro_key.pub` (публичный)
    * `obf_rw_key` (приватный) и `obf_rw_key.pub` (публичный)

3.  **Установите правильные права на приватные ключи:**
    Это критически важно для безопасности и работы SSH.
    ```bash
    chmod 600 ~/.ssh/pipeline_ro_key
    chmod 600 ~/.ssh/source_ro_key
    chmod 600 ~/.ssh/obf_rw_key
    ```

4.  **Просмотрите публичные ключи:**
    Их содержимое понадобится на следующем шаге.
    ```bash
    cat ~/.ssh/pipeline_ro_key.pub
    cat ~/.ssh/source_ro_key.pub
    cat ~/.ssh/obf_rw_key.pub
    ```
    Скопируйте содержимое каждого ключа (строку, начинающуюся с `ssh-rsa ...`).

## Шаг 2: Добавление Публичных Ключей в GitHub (Deploy Keys)

Теперь нужно добавить **публичные** части ключей (`.pub`) в настройки соответствующих репозиториев на GitHub.

**Для каждого из трех репозиториев:**

1.  Перейдите на страницу репозитория на GitHub (например, `https://github.com/organization/pipeline-repository`).
2.  Нажмите на вкладку `Settings` (Настройки).
3.  В меню слева выберите `Deploy keys` (Ключи развертывания).
4.  Нажмите кнопку `Add deploy key` (Добавить ключ развертывания).
5.  **Title:** Введите понятное название ключа, например, `CICD Server Pipeline Access (RO)` или `CICD Server Obf Access (RW)`.
6.  **Key:** Вставьте полное содержимое **публичного** ключа (скопированное на Шаге 1, п.4) для *этого* репозитория.
7.  **Allow write access:**
    * Для `organization/pipeline-repository`: **Оставьте галочку снятой** (только чтение).
    * Для `organization/source-code-repository`: **Оставьте галочку снятой** (только чтение).
    * Для `organization/obfuscated-code-repository`: **Поставьте галочку** (разрешить запись).
8.  Нажмите `Add key` (Добавить ключ).

**Повторите эти 8 пунктов для всех трех репозиториев**, используя соответствующий публичный ключ и устанавливая правильный флажок `Allow write access`.

## Шаг 3: Настройка SSH Клиента на Сервере Пайплайна (`~/.ssh/config`)

Чтобы `git` и `ssh` знали, какой приватный ключ использовать для какого репозитория, создадим конфигурационный файл.

1.  **Создайте или откройте файл `~/.ssh/config`:**
    ```bash
    nano ~/.ssh/config
    ```

2.  **Добавьте следующий текст в файл**, используя имена приватных ключей, созданных на Шаге 1:

    ```config
    # ~/.ssh/config

    # Pipeline Repo (Read-Only access)
    Host github.com-pipeline-ro
        HostName github.com
        User git
        IdentityFile ~/.ssh/pipeline_ro_key # Путь к приватному ключу pipeline
        IdentitiesOnly yes

    # Source Repo (Read-Only access)
    Host github.com-source-ro
        HostName github.com
        User git
        IdentityFile ~/.ssh/source_ro_key  # Путь к приватному ключу source
        IdentitiesOnly yes

    # Obfuscated Repo (Read-Write access)
    Host github.com-obf-rw
        HostName github.com
        User git
        IdentityFile ~/.ssh/obf_rw_key     # Путь к приватному ключу obf
        IdentitiesOnly yes
    ```
    * `Host github.com-pipeline-ro`: Уникальный псевдоним (алиас) для подключения. Мы будем использовать его в командах `git`.
    * `IdentityFile ~/.ssh/pipeline_ro_key`: Указывает на **приватный** ключ.
    * `IdentitiesOnly yes`: Говорит SSH использовать только указанный ключ.

3.  **Сохраните файл и выйдите из редактора** (в `nano` это `Ctrl+X`, затем `Y`, затем `Enter`).

4.  **Установите права на файл конфигурации:**
    ```bash
    chmod 644 ~/.ssh/config
    ```

## Шаг 4: Проверка Доступа и Использование

1.  **Проверьте SSH соединение для каждого алиаса:**
    Вы должны увидеть приветственное сообщение от GitHub, подтверждающее аутентификацию.
    ```bash
    ssh -T git@github.com-pipeline-ro
    ssh -T git@github.com-source-ro
    ssh -T git@github.com-obf-rw
    ```
    *Ожидаемый ответ (примерно):*
    `Hi organization/pipeline-repository! You've successfully authenticated, but GitHub does not provide shell access.`
    *(Имя репозитория в ответе может отличаться, главное - сообщение об успешной аутентификации)*

2.  **Клонируйте репозитории, используя алиасы:**
    Теперь вы можете использовать `git clone`, `git pull`, `git push` (где разрешено), используя алиасы из `~/.ssh/config`:

    ```bash
    # Клонировать репозиторий пайплайна
    git clone git@github.com-pipeline-ro:organization/pipeline-repository.git

    # Клонировать репозиторий исходников
    git clone git@github.com-source-ro:organization/source-code-repository.git

    # Клонировать репозиторий с обфусцированным кодом
    git clone git@github.com-obf-rw:organization/obfuscated-code-repository.git

    # Пример пуша в репозиторий с правом записи (после коммита)
    # cd obfuscated-code-repository
    # ... внести изменения, добавить, закоммитить ...
    # git push origin <branch_name>
    ```

---

**Готово!** Теперь ваша машина настроена для безопасного взаимодействия с указанными репозиториями GitHub с использованием отдельных SSH Deploy Keys.