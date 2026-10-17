Обработка фокуса: системный фокус плюс доступное имя; фокус, выбор и воспроизведение — три разных состояния.

Контракт `VF/FocusTreatment`. Системный фокус (tvOS focus engine / keyboard focus ring) + доступное имя элемента.

## Варианты и состояния

- **Варианты:** `keyboard`, `TV`
- **Состояния:** `focused`, `unfocused` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Клавиатура (iPad/Mac): кольцо `focus` 3 px с отступом 4 px; на TV — системный фокус, в макете кольцо 5 px с отступом 7 px и подъём, не обрезанный контейнером.
- Selected tab, focused item и currently playing различимы одновременно.
- Путь фокуса видимый и непрерывный; после меню или плеера фокус восстанавливается на исходный элемент.
- Кольцо сохраняется при Reduce Motion и Increase Contrast; при Reduce Motion отключается только масштаб.
- Поведение (контракт): Use native focus engine; keep focus, selection and playback distinct.

## Доступность

- Visible ring survives Reduce Motion and high contrast; no clipped lift.

## Что передаёт потребитель

Фокусируемый элемент с accessibility label; точку восстановления фокуса после закрытия слоя.

## Не делать

- Не путать focused и selected.
- Не убирать outline без замены.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/VideoCardView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
