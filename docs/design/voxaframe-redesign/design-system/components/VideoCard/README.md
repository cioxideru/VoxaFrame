Карточка видео: обложка 16:9, длительность, название, канал, дата, прогресс и отдельное меню.

Контракт `VF/VideoCard`. Обложка 16:9 (`radius-card`) + длительность на `scrim` + название (`subheadline` semibold) + канал · дата (`footnote`, `secondary`) + прогресс просмотра + кнопка меню.

## Варианты и состояния

- **Варианты:** `grid`, `list`, `live`, `upcoming`, `watched`
- **Состояния:** `default`, `focused`, `hover`, `loading`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: grid / list, а также live / upcoming / watched — бейджем и прогрессом, не только цветом.
- Нажатие на карточку запускает видео один раз; меню — отдельное действие, доступное отдельно.
- После возврата из плеера фокус возвращается на карточку.
- Состояния: default, focused (кольцо `focus`; на TV — кольцо 5 px с отступом 7 px), hover (pointer), loading (скелет), error.
- Поведение (контракт): Play once; overflow menu is a distinct action; restore focus on return.

## Доступность

- Title, channel, duration, watched state; menu remains separately reachable.

## Что передаёт потребитель

Обложка, название, канал, дата/статус, длительность, доля просмотра, live/upcoming, обработчики play и menu.

## Не делать

- Не озвучивать длительность трижды.
- Не делать меню частью области запуска.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/VideoCardView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
