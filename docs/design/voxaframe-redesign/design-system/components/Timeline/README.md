Шкала воспроизведения: прошедшее время, дорожка, буфер, ручка и оставшееся время.

Контракт `VF/Timeline`. elapsed + дорожка (played `onMedia`, buffered 50%) + ручка + remaining, на `scrim`.

## Варианты и состояния

- **Варианты:** `VOD`, `live`, `DVR`
- **Состояния:** `idle`, `scrubbing`, `buffering`, `disabled` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты VOD, live, DVR. Live без DVR не показывает ложный seek — только бейдж LIVE.
- Перемотка доступна с клавиатуры (стрелки при фокусе), VoiceOver (adjustable action) и пульта; точный drag не требуется.
- scrubbing увеличивает ручку; disabled — понижение непрозрачности и причина.
- Поведение (контракт): Show only valid seek range; unavailable live seek is explicit.

## Доступность

- Adjustable accessibility value; keyboard/remote alternative to drag.

## Что передаёт потребитель

Позиция, длительность, буфер, тип потока (VOD/live/DVR), допустимый диапазон, шаг перемотки, обработчик seek.

## Не делать

- Не показывать диапазон, куда нельзя перемотать.
- Не делать drag единственным способом перемотки.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView+ControlElements.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [7:53847](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=7-53847)
- Происхождение: voxaframe-proposal over current product behavior
