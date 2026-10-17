Статус закадрового перевода: язык и состояние называются текстом, повтор и оригинал доступны.

Контракт `VF/TranslationStatus`. Символ + язык и состояние (текст) + пояснение + действие (повтор / слушать оригинал).

## Варианты и состояния

- **Варианты:** `off`, `original`, `translated`
- **Состояния:** `off`, `requesting`, `preparing`, `ready`, `failed` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Состояния off, requesting, preparing, ready, failed; варианты off / original / translated.
- Перевод (Yandex) отделён от доступной дублированной дорожки.
- Повтор — по запросу; оригинальное аудио всегда доступно как запасной путь.
- Никогда не показывать OAuth и учётные данные.
- Поведение (контракт): Translation is distinct from an available dubbed track; never show credentials.

## Доступность

- State and target language in text; explicit retry and original-audio fallback.

## Что передаёт потребитель

Целевой язык, состояние, сообщение об ошибке, обработчики повтора и переключения на оригинал.

## Не делать

- Не обещать мгновенный перевод.
- Не выдавать дубляж за перевод.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerAudioTrackPicker.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [9:55875](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=9-55875)
- Происхождение: voxaframe-proposal over current product behavior
