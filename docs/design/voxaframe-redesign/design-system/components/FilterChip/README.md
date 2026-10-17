Чип категории ленты или фильтра поиска с явным признаком выбора.

Контракт `VF/FilterChip`. Подпись + признак выбора. Капсула 40 pt, `surface`; выбранная — заливка `text`, подпись `background`.

## Варианты и состояния

- **Варианты:** `category`, `toggle`
- **Состояния:** `default`, `selected`, `focused`, `disabled` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- category — один выбранный в ряду (For you, Subscriptions, Shorts, History); toggle — независимые фильтры.
- Выбор категории хранится отдельно от основной навигации и не дублирует её.
- Ряд прокручивается горизонтально и доступен без swipe-only: клавиатура, VoiceOver, фокус.
- Поведение (контракт): Maintain feed category selection separately from main navigation.

## Доступность

- Selected trait; horizontal list accessible without gesture-only control.

## Что передаёт потребитель

Подпись, selected, disabled, обработчик; для ряда — список категорий и текущая.

## Не делать

- Не превращать чипы во второй уровень tabs.
- Не обозначать выбор только оттенком — используйте контраст заливки и selected trait.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Home/HomeView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [5502:6049](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=5502-6049)
- Происхождение: voxaframe-proposal over current product behavior
