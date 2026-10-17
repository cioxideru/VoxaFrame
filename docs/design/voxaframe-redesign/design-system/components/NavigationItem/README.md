Пункт основной навигации: символ, подпись, маркер выбора и необязательный бейдж.

Контракт `VF/NavigationItem`. SF Symbol + подпись + маркер выбора + опциональный бейдж.

## Варианты и состояния

- **Варианты:** `tab`, `sidebar`, `TV-tab`
- **Состояния:** `default`, `selected`, `focused`, `disabled` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: tab (iPhone), sidebar (iPad/Mac), TV-tab (верхние tabs, без символа, высота `tvTarget`).
- Selected — `action` на `surface` (в sidebar — на `elevated`); focused — кольцо `focus`. Это разные состояния: фокус не меняет выбор до активации.
- Бейдж — число на `action`/`onAction`, озвучивается VoiceOver.
- Поведение (контракт): Focus does not change selection until activation.

## Доступность

- Announce label, badge and selected state; no color-only cue.

## Что передаёт потребитель

ID раздела (home/search/library/offline/settings), подпись RU/EN, имя символа из AppSymbol, selected, disabled, необязательное число бейджа.

## Не делать

- Не обозначать выбор только цветом — есть фон-маркер и `aria-current`/selected trait.
- Не переименовывать внутренние AppSection-значения вместе с подписью.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/RootView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [131:70029](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=131-70029)
- Происхождение: voxaframe-proposal over current product behavior
