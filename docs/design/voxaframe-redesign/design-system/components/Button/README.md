Кнопка одного действия: подпись, необязательный символ и индикатор занятости.

Контракт `VF/Button`. Подпись + опциональный SF Symbol + busy-индикатор. Капсула `radius-pill`, высота ≥ `touchTarget` (44).

## Варианты и состояния

- **Варианты:** `primary`, `secondary`, `plain`, `destructive`, `icon`
- **Состояния:** `default`, `pressed`, `focused`, `hover`, `disabled`, `loading` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- primary — заливка `action`, текст `onAction`; один primary в текущем контексте.
- secondary — `surface` + `text`; plain — прозрачная, текст `action`; destructive — `surface` + `danger`, подпись называет объём удаления; icon — 44×44, только символ + обязательный accessibility label.
- loading сохраняет ширину и блокирует повторное нажатие; disabled — 40% непрозрачности и причина рядом.
- Focus — кольцо `focus` 3px с отступом 4px; hover только на Mac/iPad с pointer.
- Поведение (контракт): One action; busy state keeps size and prevents repeated submission.

## Доступность

- Icon-only actions need labels; disabled reason is available nearby.

## Что передаёт потребитель

Подпись, роль (primary/secondary/plain/destructive/icon), необязательный символ, состояние (disabled/loading), action; для icon — accessibility label.

## Не делать

- Не ставить два primary рядом.
- Не отличать удаление от действия только цветом.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/ViewHelpers.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [40:58696](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=40-58696)
- Происхождение: voxaframe-proposal over current product behavior
