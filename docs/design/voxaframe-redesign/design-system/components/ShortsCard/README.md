Карточка Shorts: вертикальная обложка 9:16, название и канал, в собственном ряду или экране.

Контракт `VF/ShortsCard`. Обложка 9:16 (`radius-card`) + название (2 строки) + канал.

## Варианты и состояния

- **Варианты:** `shelf`, `player`
- **Состояния:** `default`, `focused`, `loading`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: shelf (ряд на Home) и player (отдельный экран Shorts).
- Скорость Shorts независима и не меняет скорость обычных видео.
- Помимо swipe есть явные действия: кнопки, клавиатура, пульт.
- Поведение (контракт): Use 9:16 artwork; preserve independent Shorts speed.

## Доступность

- Named content and explicit actions beyond swipe.

## Что передаёт потребитель

Вертикальная обложка, название, канал, обработчик открытия, состояние loading/error.

## Не делать

- Не смешивать Shorts с 16:9 карточками в одной сетке.
- Не полагаться только на swipe-навигацию.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/ShortsCardView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
