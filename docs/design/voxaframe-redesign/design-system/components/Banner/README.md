Баннер: символ, короткое сообщение и действие или закрытие — без вытеснения рабочего контента.

Контракт `VF/Banner`. Символ статуса + короткое сообщение + действие и/или dismiss; `surface` с `border`.

## Варианты и состояния

- **Варианты:** `info`, `warning`, `error`, `success`
- **Состояния:** `visible`, `dismissed`, `actionable` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты info, warning, error, success — символ и текст, не только цвет.
- Ошибка не стирает контент и не повторяет запрос бесконечно; actionable-ошибки остаются до решения.
- Объявляется вежливо (polite), не перехватывает фокус; не зависит от короткого таймера.
- Поведение (контракт): Do not erase content or auto-retry indefinitely; actionable errors persist.

## Доступность

- Polite announcements; no focus stealing; accessible dismiss.

## Что передаёт потребитель

Тон (info/warning/error/success), сообщение, необязательное действие, dismissible.

## Не делать

- Не скрывать ошибку автоматически через несколько секунд.
- Не накрывать список баннером.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+ErrorOverlays.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
