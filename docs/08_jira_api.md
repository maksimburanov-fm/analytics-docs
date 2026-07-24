# Jira REST API для проекта FMAP

## Короткий путь для нового чата

Jira в этом проекте подключена через REST API, а не через MCP-сервер.

1. Подключить корпоративный VPN.
2. Открыть репозиторий `analytics-docs` как текущий проект.
3. Запустить:

   ```powershell
   .\.codex\scripts\check-jira.cmd
   ```

4. Если preflight завершился успешно, выполнять запрос через
   `.codex\scripts\invoke-jira.ps1`, запуская его с обходом локальной
   PowerShell execution policy.

Параметры подключения:

- Jira: `https://project.ffin.kz`;
- проект по умолчанию: `FMAP`;
- версия REST API: `/rest/api/2`;
- токен: пользовательская переменная Windows `JIRA_PAT`.

Токен нельзя вставлять в чат, выводить в терминал, записывать в Git или
добавлять в конфигурационные файлы проекта.

## Однократная настройка токена

Создайте PAT в профиле Jira и сохраните его на уровне пользователя Windows:

```powershell
$jiraPat = (New-Object System.Net.NetworkCredential(
    "",
    (Read-Host "Вставьте Jira PAT" -AsSecureString)
)).Password

[Environment]::SetEnvironmentVariable("JIRA_PAT", $jiraPat, "User")
Remove-Variable jiraPat

[bool][Environment]::GetEnvironmentVariable("JIRA_PAT", "User")
```

Последняя команда должна вернуть `True`. Codex не нужно передавать значение
токена: скрипты читают свежую пользовательскую переменную при каждом запуске.

## Безопасная модель работы

- Поиск, скрининг и проверка задач выполняются только через `GET`.
- `POST`, `PUT` и `DELETE` в проектном wrapper-скрипте заблокированы без
  явного параметра `-AllowWrite`.
- Создание, изменение, переход статуса, комментарий или удаление выполняются
  только по явному запросу пользователя.
- Перед записью нужно получить актуальные create/edit metadata.
- Перед удалением нужно проверить точный ключ задачи. Формулировки «закрыть»,
  «отменить» и «убрать с доски» не означают удаление.
- После изменения нужно повторно прочитать задачу и сообщить итоговый ключ и
  статус.

## Чтение задачи

Чтобы не повторять параметры запуска в каждом запросе, в рабочем PowerShell
процессе можно определить функцию:

```powershell
function Invoke-ProjectJira {
    & powershell.exe `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File "$PWD\.codex\scripts\invoke-jira.ps1" `
      @args
}
```

Функция действует только в текущем PowerShell-процессе и не сохраняет токен.
Новый чат может определить её заново или вызвать `powershell.exe` с теми же
параметрами напрямую.

```powershell
Invoke-ProjectJira `
  -Path "/rest/api/2/issue/FMAP-447?fields=key,summary,status,assignee"
```

## Поиск по JQL

JQL нужно кодировать перед добавлением в URL:

```powershell
$jql = [uri]::EscapeDataString(
    'project = FMAP AND created >= "2026-01-01" ORDER BY created DESC'
)

Invoke-ProjectJira `
  -Path "/rest/api/2/search?jql=$jql&maxResults=100&fields=key,summary,status,assignee"
```

Для больших выборок использовать `startAt` и читать страницы, пока не будет
получено значение `total`. Не сохранять сырые пользовательские выгрузки в Git.

## Metadata перед созданием и изменением

Доступные типы задач:

```powershell
Invoke-ProjectJira `
  -Path "/rest/api/2/issue/createmeta/FMAP/issuetypes"
```

Поля для типа `Задача`:

```powershell
Invoke-ProjectJira `
  -Path "/rest/api/2/issue/createmeta/FMAP/issuetypes/10700"
```

Актуальные ID типов на момент проверки:

| Тип | ID |
|---|---:|
| Epic | `10000` |
| Задача | `10700` |
| Ошибка | `10805` |
| Oversprint | `13516` |

Перед использованием ID всё равно следует запросить metadata: конфигурация Jira
может измениться.

Поля, доступные для редактирования конкретной задачи:

```powershell
Invoke-ProjectJira `
  -Path "/rest/api/2/issue/FMAP-447/editmeta"
```

## Создание задачи

В текущей конфигурации Jira поле `reporter` обязательное. Его безопасно брать из
`/myself`, не выводя имя или токен:

```powershell
$self = (
    Invoke-ProjectJira -Path "/rest/api/2/myself"
) | ConvertFrom-Json

$body = @{
    fields = @{
        project = @{ key = "FMAP" }
        issuetype = @{ id = "10700" }
        reporter = @{ name = $self.name }
        summary = "Краткая тема задачи"
        description = "Описание, критерии готовности и ссылки"
    }
} | ConvertTo-Json -Depth 10

$bodyBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($body)
)

Invoke-ProjectJira `
  -Method POST `
  -Path "/rest/api/2/issue" `
  -BodyBase64 $bodyBase64 `
  -AllowWrite
```

Ответ содержит ключ созданной задачи. После создания нужно прочитать её через
`GET /rest/api/2/issue/{key}` и проверить поля.

## Изменение задачи

```powershell
$issueKey = "<exact_issue_key>"

$body = @{
    fields = @{
        summary = "Обновлённая тема"
        description = "Обновлённое описание"
    }
} | ConvertTo-Json -Depth 10

$bodyBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($body)
)

Invoke-ProjectJira `
  -Method PUT `
  -Path "/rest/api/2/issue/$issueKey" `
  -BodyBase64 $bodyBase64 `
  -AllowWrite
```

Перед обновлением использовать `editmeta` и отправлять только изменяемые поля.

## Переход статуса

Сначала получить допустимые переходы:

```powershell
$issueKey = "<exact_issue_key>"

Invoke-ProjectJira `
  -Path "/rest/api/2/issue/$issueKey/transitions"
```

Затем передать выбранный ID:

```powershell
$body = @{ transition = @{ id = "<transition_id>" } } |
  ConvertTo-Json -Depth 5

$bodyBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($body)
)

Invoke-ProjectJira `
  -Method POST `
  -Path "/rest/api/2/issue/$issueKey/transitions" `
  -BodyBase64 $bodyBase64 `
  -AllowWrite
```

## Удаление

Удаление необратимо и выполняется только при явном запросе с точным ключом:

```powershell
$issueKey = "<exact_issue_key>"

Invoke-ProjectJira `
  -Method DELETE `
  -Path "/rest/api/2/issue/$issueKey" `
  -AllowWrite
```

Если пользователь просит закрыть или отменить задачу, использовать переход
статуса, а не `DELETE`.

## Основные endpoints

| Назначение | Метод и endpoint |
|---|---|
| Текущий пользователь | `GET /rest/api/2/myself` |
| Права в FMAP | `GET /rest/api/2/mypermissions?projectKey=FMAP` |
| Поиск | `GET /rest/api/2/search?jql=...` |
| Чтение задачи | `GET /rest/api/2/issue/{key}` |
| Создание | `POST /rest/api/2/issue` |
| Изменение | `PUT /rest/api/2/issue/{key}` |
| Удаление | `DELETE /rest/api/2/issue/{key}` |
| Допустимые переходы | `GET /rest/api/2/issue/{key}/transitions` |
| Выполнение перехода | `POST /rest/api/2/issue/{key}/transitions` |
| Добавление комментария | `POST /rest/api/2/issue/{key}/comment` |

## Диагностика

| Симптом | Что проверить |
|---|---|
| `JIRA_PAT is not set` | Переменная должна быть создана с областью `User`, а не только через `$env:JIRA_PAT` в одном терминале |
| `401 Unauthorized` | Токен создан именно в Jira, не в Confluence; PAT не истёк |
| Нет HTTP-ответа | Корпоративный VPN и доступность `project.ffin.kz` |
| `403 Forbidden` | Права пользователя в FMAP и результат `check-jira.cmd` |
| `400 Bad Request` при создании | Запросить create metadata, проверить обязательные поля и тип задачи |
| `400 Bad Request` при изменении | Запросить `editmeta`, отправлять только поддерживаемые поля |

Preflight не создаёт и не изменяет задачи: он выполняет только GET-запросы.
