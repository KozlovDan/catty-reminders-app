# Лабораторная работа 2: GitHub Actions

## Что сделано

Лаба 2 продолжает lab1 и заменяет самописный GitHub webhook на GitHub Actions pipeline.

- Добавлен CI workflow: `.github/workflows/ci.yaml`.
- Добавлен CD workflow: `.github/workflows/deploy.yaml`.
- FRP example обновлен под lab2: приложение остается на `8181`, вместо webhook добавлен SSH-проброс.
- Деплой переиспользует `scripts/deploy.sh` из lab1 и Mac restart-скрипт `scripts/restart-catty-app-macos.sh`.
- Код приложения в `app/*` не меняется.

## CI

CI запускается на `push` в `lab2` и на `pull_request`.

Pipeline:

1. забирает репозиторий через `actions/checkout`;
2. ставит Python 3.12 через `actions/setup-python`;
3. устанавливает зависимости из `requirements.txt`;
4. запускает `pytest tests/test_unit.py`;
5. загружает artifact с именем `test_result`.

## CD

CD запускается при публикации GitHub Release и вручную через `workflow_dispatch`.

Pipeline:

1. собирает и тестирует проект на GitHub Runner;
2. подключается к Mac по SSH через FRP;
3. запускает `scripts/deploy.sh lab2 <sha>`;
4. `deploy.sh` обновляет код, зависимости, тесты, `.env` с `DEPLOY_REF` и перезапускает приложение;
5. workflow проверяет `http://app.kozlov.course.prafdin.ru/login`.

## Настройка Mac для CD

Включить SSH:

```bash
sudo systemsetup -setremotelogin on
```

Создать SSH ключ для GitHub Actions:

```bash
ssh-keygen -t rsa -C "github-actions" -f ~/.ssh/github_actions -N ""
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
cat ~/.ssh/github_actions
```

Приватный ключ из `cat ~/.ssh/github_actions` добавить в GitHub repository secret:

```text
SSH_PRIVATE_KEY
```

Опциональные secrets, если значения отличаются от дефолтов workflow:

```text
SSH_USER=a1234
DEPLOY_PATH=/Users/a1234/Documents/uni/devops/danila/catty-reminders-app
```

## Настройка FRP для lab2

Для локального Mac используется `deploy/frpc.lab2.local.toml` (не коммитится).

Публичные адреса:

- `http://app.kozlov.course.prafdin.ru` -> `localhost:8181`
- `course.prafdin.ru:3147` -> `localhost:22`

Запуск:

```bash
frpc -c deploy/frpc.lab2.local.toml
```

Проверка SSH через FRP:

```bash
ssh -p 3147 a1234@course.prafdin.ru
```

## GitHub Release

Для запуска CD создать release на GitHub из ветки `lab2`. После публикации release workflow `.github/workflows/deploy.yaml` должен выполнить деплой.

## Контрольные вопросы

1. GitHub Actions дает встроенные логи, secrets, artifacts и стандартные runners. Webhook проще локально, но требует свой сервер, безопасность и мониторинг.
2. Workflow состоит из событий запуска, jobs и steps. Steps могут быть shell-командами или готовыми actions.
3. Workflow могут запускать `push`, `pull_request`, `release`, `workflow_dispatch`, `schedule` и другие события.
4. Secrets нужны для чувствительных данных: приватные ключи и токены. Variables подходят для несекретной конфигурации.
5. GitHub-hosted runner управляется GitHub и быстро поднимается. Self-hosted runner полезен, если нужен доступ к локальной инфраструктуре или специфичное окружение.
6. FRP нужен, чтобы GitHub Runner мог достучаться до Mac за NAT через публичный адрес и TCP-порт.
7. CI проверяет код и тесты. CD доставляет проверенный код в окружение и перезапускает приложение.
8. Разделение сборки, тестов и деплоя упрощает диагностику и не дает деплоить непроверенный код.
9. `push` запускается на новый коммит в ветку, `pull_request` - на изменения в PR и удобен для проверки перед merge.
10. Откат можно сделать новым release на предыдущий commit/tag или вручную выполнить `git reset --hard <old_sha>` на хосте и перезапустить приложение.
