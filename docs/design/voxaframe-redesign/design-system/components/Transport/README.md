Группа транспорта: предыдущее, назад, play/pause, вперёд, следующее.

Контракт `VF/Transport`. previous · back N s · play/pause · forward N s · next; кнопки на `scrim`, символы `onMedia`; цели ≥ 44 pt (TV — 66).

## Варианты и состояния

- **Варианты:** `compact`, `full`, `TV`
- **Состояния:** `playing`, `paused`, `buffering`, `unavailable` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Интервалы перемотки берутся из пользовательских настроек, а не из нарисованного числа.
- Недоступные previous/next — disabled, а не скрыты молча.
- buffering — индикатор вместо play/pause без потери позиции; unavailable — весь транспорт недоступен с причиной.
- Поведение (контракт): Seek increments come from settings; disable unsupported previous/next.

## Доступность

- Named play/pause state, readable seek interval and 44pt touch targets.

## Что передаёт потребитель

Состояние (playing/paused/buffering/unavailable), интервалы назад/вперёд из настроек, доступность previous/next, обработчики.

## Не делать

- Не зеркалить транспорт механически в RTL.
- Не хардкодить «10» в символе — интервал из настроек.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+ControlElements.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [5473:21667](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=5473-21667)
- Происхождение: voxaframe-proposal over current product behavior
