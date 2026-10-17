Корневой каркас приложения: нативная навигация по пяти разделам, область контента и опциональный мини-плеер.

Контракт `VF/AppShell`. Нативная навигация (tabs / sidebar / верхние tabs) + контент + опциональный мини-плеер.

## Варианты и состояния

- **Варианты:** `tabs`, `sidebar`, `topTabs`
- **Состояния:** `guest`, `signedIn`, `compact`, `regular` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Compact (iPhone, узкое окно iPad) — 5 нативных tabs внизу; regular (iPad, Mac) — sidebar 240–300 pt; Apple TV — верхние tabs, без нижнего tab bar.
- Сохраняет пять разделов, их порядок и состояние стека каждого раздела.
- Резервирует место под мини-плеер над навигацией; высоту tab bar не хардкодить.
- Гостевой режим разрешён: персональные разделы объясняют вход, остальные работают.
- Поведение (контракт): Preserve five destinations and each stack state; reserve mini-player space.

## Доступность

- Navigation has names, selected state and stable focus order.

## Что передаёт потребитель

Выбранный раздел, признак guest/signedIn, size class (compact/regular), наличие активного воспроизведения для мини-плеера, контент раздела.

## Не делать

- Не добавлять Subscriptions/Shorts/History как новые основные вкладки.
- Не рисовать нижний tab bar на TV и свой browser-chrome на Mac.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/RootView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [3:70967](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=3-70967)
- Происхождение: voxaframe-proposal over current product behavior
