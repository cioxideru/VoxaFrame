Поле поиска: подсказка, запрос, очистка, отправка и необязательный фильтр.

Контракт `VF/SearchField`. Символ поиска + prompt/запрос + кнопка очистки + submit (Enter) + опциональный фильтр.

## Варианты и состояния

- **Варианты:** `compact`, `toolbar`, `sidebar`
- **Состояния:** `empty`, `editing`, `submitting`, `results`, `noResults`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: compact (iPhone), toolbar (Mac, ⌘F), sidebar (iPad).
- Запрос сохраняется; очистка — явная кнопка; Enter ищет; Escape закрывает transient UI без потери результатов.
- Состояния empty / editing / submitting / results / noResults / error; noResults и error — через `VF/StatusPanel` с полезным шагом.
- Поведение (контракт): Preserve query; clear is explicit; Enter submits.

## Доступность

- Persistent label, clear action, keyboard focus and result announcement.

## Что передаёт потребитель

Текущий запрос, prompt, подсказки, состояние запроса, обработчики submit/clear, опциональные фильтры (`VF/FilterChip`).

## Не делать

- Не очищать результаты при закрытии клавиатуры.
- Не убирать постоянный label у поля.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Search/SearchView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [553:23047](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=553-23047)
- Происхождение: voxaframe-proposal over current product behavior
