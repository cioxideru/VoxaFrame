Мини-плеер: обложка, название, play/pause, закрытие и раскрытие в полный плеер.

Контракт `VF/MiniPlayer`. Обложка + название + канал · состояние + play/pause + close; нажатие на текст раскрывает плеер. Поверхность `elevated`, граница `border`.

## Варианты и состояния

- **Варианты:** `compact`, `regular`
- **Состояния:** `playing`, `paused`, `buffering` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Над нижней навигацией (iPhone) или внизу области контента (iPad/Mac); место зарезервировано, контент не перекрывается.
- Close завершает mini presentation и не открывает full screen повторно.
- Высота растёт с текстом; каждая кнопка ≥ 44 pt и отдельно названа.
- Поведение (контракт): Separate close, play/pause and expand; reserve layout height.

## Доступность

- Each control independently named; no overlapping hit regions.

## Что передаёт потребитель

Обложка, название, канал, состояние (playing/paused/buffering), обработчики play/pause, close, expand.

## Не делать

- Не перекрывать системную навигацию.
- Не допускать пересечения областей нажатия.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/MiniPlayerView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
