Строка сохранённой дорожки видео: качество / аудио / язык, размер, состояние и удаление.

Контракт `VF/OfflineAssetRow`. Тип (видео / аудио / перевод) + качество или язык + размер + состояние + удаление дорожки.

## Варианты и состояния

- **Варианты:** `video`, `audio`, `translation`
- **Состояния:** `available`, `inProgress`, `unavailable`, `failed` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты video, audio, translation; состояния available, inProgress, unavailable, failed.
- Удаление одной дорожки и удаление всего видео — разные действия с разными подтверждениями (`VF/ConfirmDeletion`).
- Недоступный вариант показан с причиной, не скрыт.
- Поведение (контракт): Choose and delete individual variants; whole-video deletion has separate scope.

## Доступность

- Asset name, quality/language, size, availability, destructive scope.

## Что передаёт потребитель

Тип дорожки, качество/язык, размер, состояние, обработчик удаления дорожки.

## Не делать

- Не называть удаление дорожки «удалить видео».
- Не скрывать размер.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Common/OfflineVideosView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [550:50430](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=550-50430)
- Происхождение: voxaframe-proposal over current product behavior
