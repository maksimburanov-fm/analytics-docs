# Amplitude User Properties

## Общее описание

В Amplitude для пользователей Freedom Media передаются user properties — свойства пользователя, которые описывают его текущий статус, тип профиля, провайдера, язык интерфейса и активные пакеты.

Свойства отправляются через GTM-теги Amplitude Browser SDK. Для user properties используется метод Amplitude:

```text
identify
```

В GTM это настроено через параметры:

```text
type = identify
userPropertyOperations.command = set
```

Отдельно пользовательский идентификатор отправляется через метод:

```text
setUserId
```

Это не user property, а основной идентификатор пользователя в Amplitude.

---

## Инициализация Amplitude

Основной тег инициализации:

```text
Amplitude
```

Метод отправки:

```text
type = init
```

В теге включены:

```text
detPageView = true
detSession = true
defaultEventTracking = true
pageHistoryTracking = all
detAttribution = true
```

Это означает, что Amplitude SDK инициализируется через GTM и дополнительно собирает системные события просмотра страниц и сессий.

---

## User ID

### `user_id`

Тег:

```text
AM - user_id
```

Метод отправки:

```text
type = setUserId
```

Значение:

```text
aaa{{union}}
```

Источник значения:

```text
{{union}}
```

`union` — GTM-переменная, которая читает cookie `union`.

Cookie `union` устанавливается HTML-тегом `auth_user_id`. Этот тег делает запрос к API:

```text
/v2/users/self
```

Если в ответе есть `data.id`, значение записывается в cookie `union`, после чего в `dataLayer` отправляется событие:

```text
set_userid
```

На это событие срабатывает тег `AM - user_id`.

Важно: `user_id` не является user property. Это идентификатор пользователя в Amplitude.

---

## Список user properties

| User property  | GTM tag             | Метод отправки     | Значение           | Источник значения                   | Описание                             |
| -------------- | ------------------- | ------------------ | ------------------ | ----------------------------------- | ------------------------------------ |
| `lang`         | `AM - lang`         | `identify` / `set` | `{{lang}}`         | `localStorage.i18nextLng`           | Язык интерфейса пользователя         |
| `profile_type` | `AM - profile_type` | `identify` / `set` | `{{profile_type}}` | `localStorage.profile.profile.role` | Тип активного профиля пользователя   |
| `is_logged`    | `AM - auth`         | `identify` / `set` | `{{authType}}`     | cookie `isLogged`                   | Признак авторизации пользователя     |
| `provider_id`  | `AM - pid`          | `identify` / `set` | `{{pid}}`          | cookie `pid`                        | ID провайдера пользователя           |
| `packets_list` | `AM - packets`      | `identify` / `set` | `{{packets}}`      | `window.packets_list_array`         | Список активных пакетов пользователя |

---

## Описание свойств

### `lang`

Тег отправки:

```text
AM - lang
```

Метод отправки:

```text
identify
```

Значение:

```text
{{lang}}
```

Переменная `lang` получает значение из:

```text
localStorage.getItem('i18nextLng')
```

Свойство показывает текущий язык интерфейса пользователя.

Тег срабатывает на All Pages и имеет режим firing:

```text
UNLIMITED
```

---

### `profile_type`

Тег отправки:

```text
AM - profile_type
```

Метод отправки:

```text
identify
```

Значение:

```text
{{profile_type}}
```

Переменная `profile_type` читает данные из:

```text
localStorage.profile
```

Далее переменная пытается получить:

```text
parsedData.profile.role
```

Возможные значения:

| Значение    | Описание                                                    |
| ----------- | ----------------------------------------------------------- |
| `adult`     | Взрослый профиль                                            |
| `child`     | Детский профиль                                             |
| `undefined` | Неавторизованная зона или тип профиля не удалось определить |

Тег срабатывает:

```text
All Pages
change_profile
```

Это значит, что свойство обновляется при загрузке страницы и после смены профиля.

---

### `is_logged`

Тег отправки:

```text
AM - auth
```

Метод отправки:

```text
identify
```

Значение:

```text
{{authType}}
```

Переменная `authType` читает cookie:

```text
isLogged
```

Свойство показывает, авторизован пользователь или нет.

Основное значение:

```text
1 = пользователь авторизован
```

Тег срабатывает после события:

```text
set_userid
```

Это событие отправляется в `dataLayer` после успешного получения user id через API `/v2/users/self`.

---

### `provider_id`

Тег отправки:

```text
AM - pid
```

Метод отправки:

```text
identify
```

Значение:

```text
{{pid}}
```

Переменная `pid` читает cookie:

```text
pid
```

Cookie `pid` устанавливается HTML-тегом `auth_user_id` после запроса к API:

```text
/v2/users/self
```

Если в ответе есть:

```text
data.provider.id
```

значение записывается в cookie `pid`.

Важно: в текущем GTM-контейнере в Amplitude отправляется именно свойство:

```text
provider_id
```

Свойство `provider` как название провайдера в текущей конфигурации не найдено. Если в Amplitude нужен человекочитаемый провайдер, нужно добавить отдельную переменную и отдельный identify-тег или изменить текущую логику.

---

### `packets_list`

Тег отправки:

```text
AM - packets
```

Метод отправки:

```text
identify
```

Значение:

```text
{{packets}}
```

Переменная `packets` читает значение из JavaScript-переменной:

```text
window.packets_list_array
```

Эта переменная заполняется HTML-тегом:

```text
packets_list
```

Тег `packets_list` делает запрос к API:

```text
/v2/purchasepackets
```

Далее из ответа собирается массив активных пакетов. В список попадают только те пакеты, у которых есть:

```text
packet.subscription.start_at != null
```

После этого список записывается в:

```text
window.packets_list_array
```

и также сохраняется в cookie:

```text
packets_list
```

Если список пустой, это означает, что у пользователя нет активных пакетов или список пакетов не удалось определить.

Тег `AM - packets` срабатывает после события:

```text
set_userid
```

---

## Вспомогательные события для установки user properties

### `token_ready`

Событие `token_ready` создается HTML-тегом:

```text
token_ready_push
```

Тег срабатывает на событие `gtm.load` и через 2 секунды отправляет в `dataLayer`:

```text
event = token_ready
```

После `token_ready` запускаются теги, которые получают данные пользователя и пакетов:

```text
auth_user_id
packets_list
```

---

### `set_userid`

Событие `set_userid` отправляется HTML-тегом:

```text
auth_user_id
```

после успешного запроса к API `/v2/users/self`.

На событие `set_userid` срабатывают теги:

```text
AM - user_id
AM - auth
AM - pid
AM - packets
```

То есть после получения user id GTM обновляет идентификатор пользователя и связанные user properties в Amplitude.

---

## Итоговая логика отправки

Общая логика выглядит так:

```text
gtm.load
  → token_ready_push
  → dataLayer event: token_ready
  → auth_user_id
  → request /v2/users/self
  → set cookie union
  → set cookie pid
  → dataLayer event: set_userid
  → AM - user_id
  → AM - auth
  → AM - pid
  → AM - packets
```

Для пакетов:

```text
token_ready / after_auth
  → packets_list
  → request /v2/purchasepackets
  → window.packets_list_array
  → AM - packets
```

Для профиля:

```text
All Pages / change_profile
  → AM - profile_type
  → identify profile_type
```

Для языка:

```text
All Pages
  → AM - lang
  → identify lang
```

---

## Важные замечания

1. `user_id` отправляется через `setUserId`, а не через user property.

2. В текущем контейнере отправляется `provider_id`, а не `provider`.

3. `packets_list` зависит от успешного запроса `/v2/purchasepackets`.

4. `is_logged`, `provider_id` и `packets_list` обновляются после события `set_userid`.

5. `profile_type` обновляется на загрузке страницы и после смены профиля.

6. `lang` обновляется на загрузке страницы.

7. Если пользователь не авторизован, часть свойств может быть пустой или иметь значение `undefined`.
