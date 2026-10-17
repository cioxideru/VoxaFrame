Панель состояния экрана: символ, заголовок, объяснение причины и следующий шаг.

Контракт `VF/StatusPanel`. Декоративный символ (скрыт от VoiceOver) + заголовок + объяснение + действие.

## Варианты и состояния

- **Варианты:** `signedOut`, `empty`, `noResults`, `offline`, `error`, `loading`
- **Состояния:** `default`, `withAction` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты signedOut, empty, noResults, offline, error, loading — разные причины не объединяются.
- Гостевой путь остаётся доступным: при signedOut — «Открыть поиск».
- Текст из словаря микротекстов README; одно главное действие.
- Поведение (контракт): Explain actual reason and next action; guest access remains reachable.

## Доступность

- Meaningful title, text, action; decorative icon hidden from accessibility.

## Что передаёт потребитель

Причина (вариант), заголовок, объяснение, действие и его обработчик.

## Не делать

- Не показывать одну «Что-то пошло не так» для всех причин.
- Не прятать рабочий контент за ошибкой.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Common/SignInView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [5583:24408](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=5583-24408)
- Происхождение: voxaframe-proposal over current product behavior
