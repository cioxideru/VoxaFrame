Выбор параметров воспроизведения: качество, скорость, аудио, субтитры, Fit/Fill, очередь и таймер сна.

Контракт `VF/PlaybackOptions`. Список вариантов в `VF/Sheet`/menu: подпись, пояснение, галочка выбранного; недоступные — `secondary` с причиной.

## Варианты и состояния

- **Варианты:** `quality`, `speed`, `audio`, `captions`, `scale`, `queue`, `sleep`
- **Состояния:** `default`, `selected`, `unavailable`, `loading`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Выбор качества — намерение пользователя: сохранённое значение показано отдельно от активного fallback.
- Отсутствие варианта не превращает выбор в Auto; неподдерживаемые варианты не активны.
- Выбранное отмечено галочкой и подписью, не только оттенком.
- Скорость Shorts независима от скорости обычных видео.
- Поведение (контракт): Separate requested quality from actual fallback; no unsupported options enabled.

## Доступность

- Named selected value; checkmark and label, not just tint.

## Что передаёт потребитель

Тип настройки, список вариантов с доступностью и причиной, сохранённый выбор, фактическое значение, обработчик выбора.

## Не делать

- Не включать варианты, которые платформа или контент не поддерживают.
- Не скрывать фактический fallback.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [5908:6487](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=5908-6487)
- Происхождение: voxaframe-proposal over current product behavior
