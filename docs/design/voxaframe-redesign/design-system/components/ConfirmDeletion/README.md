Подтверждение удаления с точным объёмом: одна дорожка или всё видео с файлами.

Контракт `VF/ConfirmDeletion`. Заголовок + точный объём (что удалится) + Cancel + destructive-действие.

## Варианты и состояния

- **Варианты:** `oneAsset`, `wholeVideo`
- **Состояния:** `confirming`, `busy`, `failed` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- oneAsset перечисляет одну дорожку; wholeVideo — видео, аудио, переводы и связанные задания.
- Начальный фокус и выбор по умолчанию — безопасный Cancel; destructive role нативная.
- busy — блокирует повтор; failed — ошибка и ничего не помечено удалённым.
- Поведение (контракт): Describe precise scope; cancel is safe; failure never pretends removal.

## Доступность

- Native destructive role; focus on safe action initially.

## Что передаёт потребитель

Объём удаления (список элементов и размер), обработчики cancel/confirm, состояние busy/failed.

## Не делать

- Не удалять до явного подтверждения.
- Не показывать «Удалено» при ошибке.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Common/OfflineVideosView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [507:24668](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=507-24668)
- Происхождение: voxaframe-proposal over current product behavior
