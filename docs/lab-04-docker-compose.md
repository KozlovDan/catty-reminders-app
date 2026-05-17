# Лабораторная работа 4: Docker Compose

## Что требовалось

Лабораторная продолжает работу 3. Нужно перейти от запуска одного Docker-контейнера к Docker Compose:

- описать приложение в `docker-compose.yaml`;
- сделать приложение мультиконтейнерным;
- добавить персистентный слой, данные которого не теряются при пересоздании стека;
- в CD перейти на деплой через `docker compose up`;
- запускать приложение из заранее собранного Docker image, без bind mount исходного кода.

## Что сделано

- Добавлен `docker-compose.yaml` со стеком `app + db`.
- `app` запускается из image `IMAGE`, по умолчанию `catty-reminders-app:local`.
- `db` использует `mysql:8.4`.
- Данные MySQL хранятся в named volume `catty_mysql_data`.
- Приложение умеет работать с MySQL через `STORAGE_BACKEND=mysql`.
- Обычный локальный запуск без compose оставлен на TinyDB, чтобы не ломать старые сценарии.
- CI для `lab4` собирает и публикует image в GHCR, затем поднимает compose-стек и проверяет `/login`.
- CD при release собирает image и на хосте запускает обновление через `scripts/deploy.sh`, который вызывает `docker compose up -d --remove-orphans`.

## Локальный запуск через Compose

Сначала собрать image:

```bash
docker build -t catty-reminders-app:local .
```

Затем поднять стек:

```bash
IMAGE=catty-reminders-app:local \
DEPLOY_REF=local-compose \
docker compose up -d
```

Проверка:

```bash
curl http://127.0.0.1:8181/login
```

Остановка стека:

```bash
docker compose down
```

Если нужно удалить и данные базы:

```bash
docker compose down -v
```

## Настройка на хосте курса

По найденным параметрам:

```text
ID=popov
PROXY=http://course.prafdin.ru
TOKEN=devops
SSH_PORT=3156
```

FRP должен пробрасывать:

- `app.popov.course.prafdin.ru` на локальный порт `8181`;
- SSH на порт `3156`.

Пример находится в `deploy/frpc.example.toml`. В нем нужно заменить:

- `YOUR_ID` на `popov`;
- `tokentoken` на `devops`.

На хосте должен быть установлен Docker Compose:

```bash
docker compose version
```

Для GitHub Actions нужно настроить secrets:

```text
SSH_USERNAME
SSH_PRIVATE_KEY
APP_DIR
```

`APP_DIR` - путь к клону репозитория на хосте. Если secret не задан, workflow использует `$HOME/catty-reminders-app`.

## Проверки

Ожидаемое поведение после release:

1. GitHub Actions собирает image `ghcr.io/<owner>/<repo>:<sha>`.
2. По SSH запускается `scripts/deploy.sh lab4 <sha>`.
3. Скрипт обновляет репозиторий на хосте.
4. Скрипт делает `docker compose pull`.
5. Скрипт делает `docker compose up -d --remove-orphans`.
6. Приложение открывается на `http://app.popov.course.prafdin.ru/login`.
7. В HTML страницы логина есть `meta name="deployref"` со значением SHA релизного коммита.

## Контрольные вопросы

1. Docker Compose управляет мультиконтейнерным приложением через один YAML-файл: описывает сервисы, сети, volumes, переменные окружения и правила запуска.
2. Порядок запуска задается через `depends_on`. Это нужно, когда один сервис зависит от другого, например приложение должно стартовать после готовности базы данных.
3. Сервис Docker Compose - это описание компонента приложения. Контейнер - конкретный запущенный экземпляр этого сервиса.
4. Volume управляется Docker и подходит для постоянных данных контейнеров. Bind mount подключает конкретную директорию хоста и сильнее привязывает запуск к структуре файловой системы хоста.
5. Масштабирование делается командой `docker compose up --scale frontend=3`, если у сервиса нет конфликтующих фиксированных host ports.
6. `pull_policy` задает, когда Compose должен скачивать image: например всегда, только если image отсутствует локально, или никогда.
7. Контейнеры в одном Compose-стеке видят друг друга по именам сервисов благодаря общей Docker network и встроенному DNS Docker.
