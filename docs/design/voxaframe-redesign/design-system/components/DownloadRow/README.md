Строка задания загрузки: обложка, название, выбранные дорожки, прогресс, статус и действия.

Контракт `VF/DownloadRow`. Обложка + название + выбранные дорожки (видео / аудио / перевод) + прогресс с числом + статус (символ + текст) + действия.

## Варианты и состояния

- **Варианты:** `video`, `audio`, `translation`
- **Состояния:** `queued`, `resolving`, `downloading`, `paused`, `completed`, `failed` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Состояния: queued, resolving, downloading, paused, completed, failed — только те, что реально отдаёт сервис.
- Прогресс имеет числовое значение («64% · 128 MB of 200 MB»).
- Ошибка остаётся видимой до решения и предлагает повтор; временная уступка ресурсов плееру — не failure.
- «Paused» показывается только если состояние пришло от сервиса.
- Поведение (контракт): Map only states exposed by service; expose exact assets, progress and retry.

## Доступность

- Progress has numeric/text value; retain error message until resolved.

## Что передаёт потребитель

Обложка, название, список дорожек, состояние сервиса, прогресс и размер, сообщение об ошибке, обработчики retry/cancel/open.

## Не делать

- Не придумывать состояния, которых нет у сервиса.
- Не скрывать ошибку по таймеру.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Common/OfflineVideosView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [9:55875](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=9-55875)
- Происхождение: voxaframe-proposal over current product behavior
