Строка очереди: позиция, название, канал, маркер текущего и меню.

Контракт `VF/QueueRow`. Позиция/маркер + обложка + название + канал + ручка перестановки + меню.

## Варианты и состояния

- **Варианты:** `current`, `upNext`
- **Состояния:** `default`, `focused`, `reordering` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты current (маркер «Now playing», `action`) и upNext.
- Перестановка — через доступные команды (Move up/down), а не только drag.
- Удалить из очереди ≠ удалить офлайн-файл: формулировки и действия разные.
- Поведение (контракт): Removing from queue never means deleting an offline asset.

## Доступность

- Accessible reorder commands; announce current item.

## Что передаёт потребитель

Позиция, обложка, название, канал, признак текущего, обработчики move/remove/menu.

## Не делать

- Не называть «Удалить» действие, которое лишь убирает из очереди.
- Не делать drag единственным способом перестановки.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [550:50430](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=550-50430)
- Происхождение: voxaframe-proposal over current product behavior
