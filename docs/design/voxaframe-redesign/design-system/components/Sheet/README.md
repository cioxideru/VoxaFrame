Контейнер для выбора и деталей: заголовок, нативное закрытие, содержимое и необязательное главное действие.

Контракт `VF/Sheet`. Grabber (iPhone) + заголовок + нативная кнопка закрытия + содержимое + опциональное primary-действие.

## Варианты и состояния

- **Варианты:** `bottomSheet`, `popover`, `dialog`, `TV-panel`
- **Состояния:** `opening`, `ready`, `busy`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: bottomSheet с detents (iPhone), popover, привязанный к кнопке (iPad/Mac), dialog, TV-panel (нативная презентация tvOS).
- Состояния opening, ready, busy, error.
- Нативный контейнер и адаптивный размер; вызвавший контрол остаётся видимым; popover не закрывает свой trigger и не уходит за окно.
- Фокус входит в содержимое и возвращается к trigger после закрытия.
- Поведение (контракт): Use native container and adaptive sizing; keep invoking control in view.

## Доступность

- Focus enters content and returns to trigger; clear dismiss action.

## Что передаёт потребитель

Заголовок, содержимое (обычно `VF/PlaybackOptions` или детали), необязательное главное действие, тип презентации, обработчик закрытия.

## Не делать

- Не фиксировать геометрию sheet по Figma (top radius 38/32 — параметр макета).
- Не рисовать свой контейнер вместо нативного.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+PickerOverlays.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [10525:1632](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=10525-1632)
- Происхождение: voxaframe-proposal over current product behavior
