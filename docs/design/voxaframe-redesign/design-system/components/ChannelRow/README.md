Строка канала: аватар, имя, состояние подписки и меню.

Контракт `VF/ChannelRow`. Аватар 1:1 + имя + подпись состояния + кнопка подписки + меню.

## Варианты и состояния

- **Варианты:** `local`, `account`
- **Состояния:** `default`, `subscribed`, `pending`, `failed`, `focused` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты local и account различимы подписью: «Локальная подписка» доступна без Google.
- pending показывает «Подписываем…», failed — ошибку и повтор; ни одно не имитирует успех.
- Показывается подтверждённый результат, а не оптимистичный.
- Поведение (контракт): Distinguish local from account subscriptions; show confirmed result.

## Доступность

- Readable subscribe/unsubscribe action and pending state.

## Что передаёт потребитель

Аватар, имя канала, тип подписки (local/account), состояние (default/subscribed/pending/failed), обработчики подписки и меню.

## Не делать

- Не смешивать локальную и account-подписку без подписи.
- Не показывать «Подписаны» до подтверждения.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Channel/ChannelListView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [550:50430](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=550-50430)
- Происхождение: voxaframe-proposal over current product behavior
