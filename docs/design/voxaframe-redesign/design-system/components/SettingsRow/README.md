Строка настроек: подпись, пояснение, значение и нативный аксессуар.

Контракт `VF/SettingsRow`. Подпись + многострочное пояснение + значение + аксессуар (chevron / Toggle / picker / действие).

## Варианты и состояния

- **Варианты:** `navigation`, `toggle`, `picker`, `action`
- **Состояния:** `default`, `focused`, `disabled`, `error` — только там, где применимо; без декартова произведения.
- **Платформы:** iPhone, iPad, нативный macOS, Apple TV

## Правила

- Варианты: navigation, toggle, picker, action; состояния default, focused, disabled, error.
- Сохраняет пользовательские тему, акцент и Liquid Glass — без принудительных значений по умолчанию.
- Длинные RU/EN строки переносятся; пояснение показывается целиком.
- Поведение (контракт): Preserve user theme/accent/Liquid Glass settings; no forced defaults.

## Доступность

- Full multiline description and state; native controls.

## Что передаёт потребитель

Подпись, пояснение, текущее значение, тип аксессуара, disabled-причина, сообщение об ошибке, обработчик.

## Не делать

- Не сбрасывать выбранный пользователем акцент в коралловый.
- Не обрезать пояснения многоточием.

## Связь с кодом и источниками

- Владелец: `SmartTubeIOS/Sources/SmartTubeIOS/Views/Settings/SettingsView.swift`
- Токены: `text`, `secondary`, `action`, `space-16`, `radius-card`
- Figma (нативный референс, не компонент VoxaFrame): [29:56814](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ?node-id=29-56814)
- Происхождение: voxaframe-proposal over current product behavior
