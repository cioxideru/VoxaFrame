# Реализация

Компоненты `VF/*` — контракты поведения для SwiftUI-реализации. HTML-превью здесь схематичны: в продакшене используйте нативные контролы, семантические цвета, safe areas и доступность платформы. React-библиотеки у системы нет, и выдавать превью за неё не нужно.

## Владельцы в репозитории SmartTubeIOS

| Паттерн | Текущий владелец |
|---|---|
| Навигация / AppSection | `SmartTubeIOS/Sources/SmartTubeIOS/Views/RootView.swift` |
| SF Symbols | `SmartTubeIOS/Sources/SmartTubeIOS/Views/ViewHelpers.swift` — `AppSymbol` |
| Карточки | `Views/Browse/VideoCardView.swift`, `ShortsCardView.swift` |
| Воспроизведение | `Views/Player/`; `PlaybackViewModel`, `PlaybackTuning` |
| Загрузки | `Views/Common/OfflineVideosView.swift`; `OfflineCoordinator` |
| Тема / акцент / качество | `SmartTubeIOS/Sources/SmartTubeIOSCore/AppSettings.swift`; `SettingsStore` |
| Идентификаторы UI-тестов | `AccessibilityID`: найдите существующее определение и переиспользуйте его |

## Правила для кода

- Swift 6, `@MainActor @Observable`. Не добавляйте новые Combine, DispatchQueue и ObservableObject. Core остаётся Foundation-only.
- `project.pbxproj` вручную не правьте.
- Второй источник истины для symbols, accessibility IDs, таймаутов и сохранённых настроек не создавайте. Токены здесь — дизайн-спецификация, а не runtime store.
- Изменение layout не меняет очередь, аудио, подписки или файлы.
- Внутренние значения `AppSection` и accessibility IDs не переименовывайте вместе с видимым текстом. Например, «Офлайн» — только предложение локализации. Используйте существующий каталог локализации, ключи автоматически не меняйте.

## Происхождение данных

- **source-fact** — прочитано из Figma-копии «iOS and iPadOS 27 — Community» или текущих исходников: системные цвета, метрики text styles, поля iPhone/iPad.
- **platform-guidance** — Apple HIG (Materials, Layout, Accessibility, macOS, tvOS), интерпретированные для приложения.
- **voxaframe-proposal** — бренд- и action-цвета, размеры контент-компонентов, композиции Mac/TV, шкала TV и сочетания клавиш. В приложении их ещё нет.

Сырые iOS-цвета, alpha и ссылки на узлы Figma лежат в `figma-reference.json` исходного пакета. Шрифты, SF Symbols, векторы компонентов Apple и примеры изображений Apple в систему не перенесены, их лицензии действуют отдельно. Приложение сохраняет upstream attribution и GPLv3.

## Приёмка нового макета

1. Главная нарисована для iPhone, iPad, Mac и TV. На TV виден фокус и нет мобильного tab bar.
2. Есть плеер, мини-плеер, выбор качества, аудио и перевода и офлайн-библиотека.
3. Для карточки показаны default, selected, focused, disabled и loading/error, где применимо.
4. Guest, no-results, offline и error различимы, и у каждого есть полезный следующий шаг.
5. Отдельно проверены светлая и тёмная тема, крупный текст, RU/EN и Reduce Motion/Transparency.
6. Используется выбранная иконка и вымышленный контент. Готовность native-кода макет не заявляет.
