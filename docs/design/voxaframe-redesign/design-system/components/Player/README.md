Плеер: медиа, транспорт, шкала, быстрые настройки и overflow — в режимах inline, fullscreen, mini и audioOnly.

Контракт `VF/Player`. Медиа + `VF/Transport` + `VF/Timeline` + быстрые настройки (`VF/PlaybackOptions`) + overflow; контролы на `scrim`, текст `onMedia`.

## Варианты и состояния

- **Варианты:** `inline`, `fullscreen`, `mini`, `audioOnly`
- **Состояния:** `ready`, `playing`, `paused`, `buffering`, `error`, `ended` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Состояния: ready, playing, paused, buffering, error, ended; контролы hidden/showing по времени из PlaybackTuning.
- Открытие панелей не перезапускает воспроизведение и не меняет очередь или аудио.
- Запрошенное качество и фактический fallback показаны отдельно: «Requested: 1080p · Playing: 720p».
- iPhone landscape — полноэкранная композиция; iPad — очередь/описание рядом только если обе области читаемы; TV — фокус пульта.
- Поведение (контракт): Keep media and transport state; do not restart playback when panels open.

## Доступность

- Transport remains usable with VoiceOver/keyboard/remote; captions legible.

## Что передаёт потребитель

Медиа-источник, состояние воспроизведения, позиция/длительность/буфер, доступные дорожки и качества, текущий выбор, очередь.

## Не делать

- Не закрывать субтитры и длинный текст стеклом.
- Не вводить второй таймаут автоскрытия в UI.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma: нет прямого референса
- Происхождение: voxaframe-proposal over current product behavior
