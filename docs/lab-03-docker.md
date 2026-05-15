# Лабораторная работа 3: Docker

## Что сделано

Лаба 3 продолжает lab2 и переводит деплой приложения на Docker.

- Добавлен `Dockerfile` для FastAPI-приложения.
- Добавлен `.dockerignore`.
- CI workflow собирает и публикует Docker image в GitHub Container Registry.
- CD workflow по release собирает image, публикует его в GHCR и на Mac запускает контейнер на порту `8181`.
- Лишняя инфраструктура старых лабораторных убрана из lab3: webhook-сервер, systemd unit-файлы и webhook env не нужны.

## Dockerfile

Образ основан на `python:3.12-slim`.

Сборка:

```bash
docker build -t catty-reminders-app:local .
```

Запуск:

```bash
docker run --rm -p 8181:8181 -e DEPLOY_REF=local-test catty-reminders-app:local
```

Проверка:

```bash
curl http://127.0.0.1:8181/login
```

## CI

Workflow `.github/workflows/ci.yaml` запускается на ветках:

- `lab3`
- `lab3_autotests*`

CI выполняет:

1. установку Python-зависимостей;
2. запуск тестов;
3. загрузку artifact `test_result`;
4. lint Dockerfile через Hadolint с `continue-on-error`;
5. сборку и публикацию image в `ghcr.io`.

## CD

Workflow `.github/workflows/deploy.yaml` запускается при публикации release.

CD выполняет:

1. тесты на GitHub Runner;
2. сборку Docker image;
3. публикацию image в GitHub Container Registry;
4. SSH-подключение к Mac через FRP;
5. `docker pull`;
6. пересоздание контейнера `catty-reminders-app`;
7. проверку `http://app.kozlov.course.prafdin.ru/login`.

Для SSH используются те же secrets, что в lab2:

```text
SSH_PRIVATE_KEY
SSH_USER
```

На Mac должен быть установлен и запущен Docker Desktop.

## Контрольные вопросы

1. Docker запускает приложение в контейнере, который использует ядро хоста. VM запускает отдельную гостевую ОС.
2. Dockerfile - инструкция сборки image. Основные инструкции: `FROM`, `RUN`, `WORKDIR`, `COPY`, `EXPOSE`, `CMD`, `ENTRYPOINT`.
3. Жизненный цикл: написать Dockerfile, собрать image, опубликовать в registry, скачать image на целевой машине, запустить container.
4. Registry нужен как общее хранилище image между CI runner и сервером деплоя.
5. Доступ снаружи дается через публикацию порта: `docker run -p host_port:container_port`.
6. Сборка и деплой на одной машине ПОРНО допустимы в учебных или маленьких проектах, но хуже масштабируются и смешивают ответственности.
7. Тестовые зависимости увеличивают image и расширяют поверхность атаки, поэтому в production обычно делают отдельные build/test stages.
8. Из GHCR image можно скачать `docker pull ghcr.io/owner/repo:tag`, затем отправить в DockerHub через `docker tag` и `docker push`.
9. Без registry image можно перенести через `docker save`, `scp`, `docker load`.
10. Cache нежелателен, если нужно гарантированно подтянуть свежие системные пакеты или пересобрать слой с внешними mutable dependencies.
11. Secrets можно передавать через env, Docker secrets, mounted files или внешние secret managers.
12. `CMD` задает команду по умолчанию, `ENTRYPOINT` задает основной executable контейнера.
13. Ресурсы контейнера смотрят через `docker stats`.
14. Лимиты задаются флагами `--memory`, `--cpus`. При превышении памяти контейнер может быть остановлен OOM killer.
