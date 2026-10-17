# VoxaFrame / Apple 27 — design system specification

Версия 1.0 · 2026-10-17 · язык пояснений: русский; имена токенов и компонентов: English.
Этот документ самодостаточен для начального импорта. [Инструкция](README.md).

## 1. Продукт и границы

VoxaFrame — нативный Swift/SwiftUI-видеоклиент, форк SmartTubeIOS. Люди находят видео,
смотрят их, выбирают язык и качество, подписываются на каналы и сохраняют материалы
для просмотра без сети. Основной объект — видео, основное действие — воспроизведение.
Образ бренда: две реплики формируют Play; коралл + кремовый на глубоком сливовом фоне.
Выбранную иконку не перерисовывать и не заменять знаком YouTube.

Целевой визуальный язык: iOS/iPadOS 27 и соответствующие нативные Mac/TV-паттерны.
Текущий проект поддерживает iOS/iPadOS 17+, Mac Catalyst на macOS 14+, tvOS 17+.
Версия Xcode 27.0 не равна минимальной версии ОС. Новый дизайн не меняет deployment target.
Системные эффекты применять с проверкой доступности; для прежних ОС сохранять нативный
читабельный вариант. Настоящий native macOS target не является частью этого задания.

### Текущее поведение, которое сохраняем

| Область | Обязательный контракт |
|---|---|
| Навигация | Home, Search, Library, Offline videos, Settings; порядок и назначения стабильны |
| Главная | Вложенные категории и подборки; Subscriptions/Shorts/History не превращать молча в новые основные вкладки |
| Аккаунт | Гостевой просмотр разрешён; персональные данные могут требовать входа; локальные подписки доступны без Google |
| Плеер | Play/Pause, seek, previous/next, quality, speed, audio, captions, queue, Fit/Fill; доступность зависит от контента/платформы |
| Аудио | Оригинальная и дублированная дорожки отделены от Yandex-перевода; перевод имеет состояния подготовки и ошибки |
| Настройки | Сохранённое качество, независимая скорость Shorts, тема System/Light/Dark, выбранный акцент, отключение Liquid Glass |
| Офлайн | Библиотека + задания загрузки; варианты видео/аудио/перевода, прогресс и ошибки; удаление с точным описанием последствий |
| Продолжение | История, очередь, мини-плеер, возврат к контенту без неожиданного перезапуска видео |

Рекламные обещания, платёжные экраны, social feed, новые логины, автоматическое включение
микрофона или новые функции AI не добавлять. В макетах использовать вымышленные названия,
каналы и аватары. Не включать токены OAuth, email, реальные аккаунты или приватные медиаданные.

## 2. Принципы

- Контент занимает главный слой; навигация и короткие управляющие элементы — отдельный слой.
- Liquid Glass использовать для системной навигации и групп управления, где это уместно.
  Списки, длинные описания, субтитры и карточки контента не покрывать стеклом.
- Предпочитать TabView, NavigationSplitView, List, Menu, sheet, Toggle, Slider, native focus.
  Макеты показывают намерение; нельзя воспроизводить системные элементы набором фиксированных пикселей.
- Один набор семантических ролей, разные композиции и плотность на каждой платформе.
- Виден только один главный призыв к действию в текущем контексте.
- Ошибка объясняет ситуацию и доступное действие. Ошибка загрузки не обнуляет список или очередь.
- Выбранная пользователем тема и цвет имеют приоритет над демонстрационным коралловым акцентом.

## 3. Токены

Файлы light/dark используют `$type`/`$value` по DTCG 2025.10. Для переносимости размеры
в JSON записаны как `px`: при переводе в SwiftUI это логические points (pt), не физические
пиксели Retina. Масштаб дисплея не умножает отступы, высоту строки или радиусы.
Все числовые значения ниже — дизайн-спецификация, не замена измерения системных safe areas.

### Цвет

| Роль | Light | Dark | Происхождение / применение |
|---|---|---|---|
| color.brand.coral | #FF6B57 | #FF6B57 | Предложение VoxaFrame по иконке; декоративный, не мелкий текст на белом |
| color.brand.plum | #260724 | #260724 | Бренд; обложка/иконка, не обязательный фон всего приложения |
| color.brand.ivory | #FFF4DE | #FFF4DE | Бренд; декоративные акценты |
| color.background | #FFFFFF | #000000 | Figma Backgrounds/Primary; в приложении systemBackground |
| color.surface | #F2F2F7 | #1C1C1E | Figma Backgrounds/Secondary; secondarySystemBackground |
| color.elevated | #FFFFFF | #2C2C2E | Предложение: контент на поднятой поверхности |
| color.text | #000000 | #FFFFFF | Figma Labels/Primary; primary |
| color.secondary | #61616B | #B8B8C2 | Непрозрачный fallback для макетов; в native secondary |
| color.action | #B83829 | #FF9988 | Контрастный коралловый для действий, авторское предложение |
| color.onAction | #FFFFFF | #260724 | Текст на action; проверять парой с фоном |
| color.border | #C6C6C8 | #38383A | Figma Separators/Opaque; декоративный разделитель, не единственный индикатор контроля |
| color.focus | #B83829 | #FFD9D2 | Клавиатурный контур; native TV focus остаётся системным |
| color.success | #236A3C | #82D99E | Подпись + check, не только зелёный |
| color.warning | #805300 | #F7CE7D | Подпись + предупреждение; не бледный жёлтый текст |
| color.danger | #B42318 | #FFB4A9 | Ошибка/удаление; отличать от обычного brand action подписью и role |
| color.scrim | #000000 @ 72% | #000000 @ 72% | Только поверх произвольного видео под белыми контролами |
| color.onMedia | #FFFFFF | #FFFFFF | Текст на scrim; проверять на самом светлом кадре |

Сырые iOS-цвета и alpha из источника сохранены в `figma-reference.json`. Системные цвета
динамические: не подменять `Color.primary`, `Color.secondary` и системные поверхности
фиксированными hex в приложении. Для AppKit/macOS нужны соответствующие semantic NSColor,
для Catalyst — UIKit. Веб-прототип использует явные fallback-значения.

### Типографика

Системный шрифт SF Pro через `.system`; в HTML `-apple-system, BlinkMacSystemFont, system-ui`.
Файлы шрифтов не вложены. Иконки в приложении — имена SF Symbols из AppSymbol, не glyph codes.

| Стиль | Размер / интерлиньяж iOS, pt | Вес | Применение |
|---|---|---|---|
| largeTitle | 34 / 41 | Bold | Заголовок компактного экрана |
| title1 | 28 / 34 | Bold | Раздел, заголовок на iPad |
| title2 | 22 / 28 | Bold | Полка, карточка крупного блока |
| title3 | 20 / 25 | Semibold | Название открытого видео |
| headline | 17 / 22 | Semibold | Кнопки и важные строки |
| body | 17 / 22 | Regular | Основной текст |
| callout | 16 / 21 | Regular | Вторичный абзац |
| subheadline | 15 / 20 | Regular | Карточка видео |
| footnote | 13 / 18 | Regular | Канал, дата, метаданные |
| caption1 | 12 / 16 | Regular | Длительность / короткая подпись |
| caption2 | 11 / 13 | Regular | Необязательная компактная метка |

Это базовый Large Dynamic Type из Figma, не TV-scale. В реализации использовать
семантические text styles и системное масштабирование. При accessibility-размерах
переходить в одну колонку, переносить кнопки, давать тексту расти по высоте.
Не ограничивать Dynamic Type ради совпадения с PNG.
Mac: system body/control styles; при custom-макете body 14/20 как предложение плотности.
TV: предлагаемая стартовая шкала title 48/58, heading 36/44, body 29/36, metadata 23/30;
оценить с дистанции просмотра. Она не извлечена из iOS-kit и не объявлена стандартом Apple.

### Пространство, форма, движение

| Набор | Значения | Правило |
|---|---|---|
| spacing | 4, 8, 12, 16, 20, 24, 32, 48, 64 | Один ритм; не фиксирует высоту динамического текста |
| content margin | iPhone 16, iPad 20, Mac 24, TV 80 по горизонтали / 60 по вертикали | Первые два подтверждены переменной Margin в Figma; Mac/TV — стартовые размеры макета |
| radius | card 16, small 8, panel 24, pill 999 | Авторские content-токены; sheets/windows/buttons округляет ОС |
| hit target | touch минимум проекта 44×44, Mac цель 28×28, TV цель 66×66 | Видимый значок может быть меньше; соседние цели не пересекаются |
| thumbnails | video 16:9, Shorts 9:16, channel 1:1 | Кроп только обложки; само видео Fit/Fill по выбору пользователя |
| motion | fast 120 ms, standard 220 ms, layout 320 ms | Предложение для custom-элементов; native motion не переопределять |
| reduced motion | 0 ms spatial movement | Отключить масштабирование/parallax; возможна короткая смена opacity |

Figma Sheet Top Radius 38/32 (iPhone/iPad) и статусные высоты — параметры конкретного
макета из источника. Не переносить их в safe-area padding и не фиксировать геометрию sheet.
Прогресс видео и состояние проигрывания не меняются от декоративной анимации.

## 4. Информационная архитектура

| ID | Подпись RU / EN | SF Symbol из текущего AppSymbol | Содержимое |
|---|---|---|---|
| home | Главная / Home | house.fill | Лента, категории, подписки, Shorts, продолжение |
| search | Поиск / Search | magnifyingglass | Запрос, подсказки, фильтры, результаты |
| library | Медиатека / Library | square.stack.fill | История, плейлисты, очередь и сохранённые разделы |
| offline | Офлайн / Offline videos | arrow.down.to.line | Сохранённые файлы и задания загрузки |
| settings | Настройки / Settings | gearshape.fill | Воспроизведение, язык, внешний вид, интеграции |

Короткая RU-подпись «Офлайн» — предложение локализации; существующие внутренние значения
AppSection и accessibility IDs не переименовывать вместе с видимым текстом.
Сохранять состояние каждого раздела и позицию списка. При возврате с плеера возвращать
фокус к запущенной карточке. Мини-плеер не перекрывает содержимое или системную навигацию.

## 5. Компоненты и состояния

Полная машиночитаемая спецификация: `components.json`. Все компоненты имеют устойчивые
имена `VF/...`. Общие состояния только там, где применимы: default, pressed, disabled,
selected, loading, error; hover на pointer-платформах; focused на клавиатуре/TV.
Не нужно создавать бессмысленное декартово произведение всех вариантов.

| Семейство | Анатомия и обязательные варианты | Правило поведения |
|---|---|---|
| VF/AppShell | Native navigation + content + optional mini player | Compact tabs; regular sidebar; TV top tabs |
| VF/NavigationItem | Symbol, label, selected marker, optional badge | Selected отличается от focused; бейдж читается VoiceOver |
| VF/Button | label, optional symbol, busy indicator | primary/secondary/plain/destructive/icon; 44pt touch; loading сохраняет ширину |
| VF/FilterChip | label, selected indication | Категории не дублируют основную навигацию; horizontal scroll доступен без swipe-only |
| VF/VideoCard | 16:9 thumb, duration, title, channel, date, progress, menu | grid/list; regular/live/upcoming/watched; меню отдельно от запуска видео |
| VF/ShortsCard | 9:16 cover, title, channel | Свой ряд/экран; скорость Shorts независима; не менять скорость обычного видео |
| VF/ChannelRow | avatar, name, subscription state, menu | Локальная и account-подписка различимы; pending/failed не имитируют успех |
| VF/SearchField | prompt, query, clear, submit, optional filter | query сохраняется; Enter ищет; Escape закрывает transient UI без потери результатов |
| VF/Player | media, transport, timeline, quick controls, overflow | inline/fullscreen/mini/audioOnly; hidden/showing controls; ready/buffering/error/ended |
| VF/Transport | previous, back, play/pause, forward, next | Интервалы из пользовательских настроек, не из нарисованного числа |
| VF/Timeline | elapsed, track, buffered, thumb, remaining | seek с клавиатуры/VoiceOver/remote; live без DVR не показывает ложный seek |
| VF/PlaybackOptions | quality/speed/audio/captions/Fit-Fill/queue/sleep | Выбор качества — намерение пользователя; активный fallback показывать отдельно |
| VF/TranslationStatus | off/requesting/preparing/ready/failed | Язык и статус названы текстом; повтор по запросу; не раскрывать OAuth |
| VF/MiniPlayer | thumb, title, play/pause, close, open | Close завершает mini presentation; не открывает full screen повторно |
| VF/QueueRow | position, title, channel, current marker, menu | Reorder через доступные команды, не только drag; удалить из очереди ≠ удалить файл |
| VF/DownloadRow | thumb, title, selected assets, progress, status, actions | queued/resolving/downloading/paused/completed/failed; честно отображать runtime-state |
| VF/OfflineAssetRow | quality/audio/language, size, state, delete | Удаление варианта и всего видео имеют разные подтверждения |
| VF/SettingsRow | label, explanation, value, native accessory | navigation/toggle/picker/action; длинные RU/EN строки переносятся |
| VF/StatusPanel | symbol, title, explanation, action | signedOut/empty/noResults/offline/error/loading; не объединять разные причины |
| VF/Banner | icon, short message, action/dismiss | Ошибка не скрывает рабочий контент; не полагаться на короткий таймер |
| VF/Sheet | title, native close, content, optional primary action | detents на iPhone; anchored popover или sheet на iPad/Mac; TV-native presentation |
| VF/ConfirmDeletion | title, exact scope, cancel, destructive action | Данные удаляются только после ясного подтверждения |
| VF/FocusTreatment | system focus + accessible name | Видимый, непрерывный путь; корректное восстановление после меню/плеера |

### Поведение ключевых сценариев

1. **Главная → видео → назад.** Карточка запускает видео один раз. Фокус и позиция ленты
   возвращаются к источнику. Mini-player занимает зарезервированное место.
2. **Качество → следующий ролик.** Показывать сохранённый выбор отдельно от текущего
   доступного разрешения; отсутствие варианта не превращает выбранное качество в Auto.
3. **Перевод.** Пользователь выбирает язык/перевод; интерфейс различает подготовку,
   синхронное воспроизведение, недоступность и ошибку. Нет обещаний мгновенного перевода.
4. **Загрузка → офлайн.** Выбор доступных video/audio/translation assets, очередь,
   прогресс, сохранённая библиотека. При временной уступке ресурсов плееру не показывать failure.
   Текст паузы допустим только если состояние получено от сервиса.
5. **Удаление.** «Удалить дорожку» перечисляет одну дорожку; «Удалить видео и файлы»
   предупреждает о видео, аудио, переводах и связанных заданиях. Cancel выбран безопасно.
6. **Вход.** На персональной ленте объяснить необходимость входа, сохранив переход
   к поиску, локальным подпискам и доступному гостевому контенту.

## 6. Платформы

Все размеры — тестовые viewport-пресеты, не перечень моделей устройств. Layout выбирается
по доступному окну/size class, а не по названию iPad. Реальные safe areas и системная
геометрия имеют приоритет над числами макета. JSON: `platforms.json`.

### iPhone

- Основной макет 393×852 pt; дополнительно 320×568, 430×932 и landscape 852×393.
- 5 native tabs, один NavigationStack в каждой ветке. На narrow — одна колонка карточек.
- Большой title при наличии места; фильтры под заголовком, scroll без второго уровня tabs.
- Плеер: отдельная landscape-композиция с safe-area controls, поворот и Fit/Fill.
- Меню качества/языка — sheet/menu; клавиатура не скрывает поиск и подтверждение.
- Mini-player над нижней навигацией, высота растёт с текстом; не хардкодить tab-bar height.

### iPad

- Основной макет 1194×834; также 834×1194 и окно 600×834.
- Regular: sidebar/tab adaptation нативным компонентом, content grid. Предлагаемая
  ширина sidebar 240–300 pt. Compact окно возвращается к одной колонке/compact navigation.
- Базово 2–3 колонки, учитывать пользовательскую настройку количества колонок (в коде 1…3).
  Минимальная ширина карточки 240 pt — предложение; если не помещается, уменьшить число колонок.
- Player + optional queue/description beside it только если обе области остаются читаемыми.
- Меню привязано к кнопке; popover не перекрывает собой собственный trigger и не уходит за окно.
- Touch, pointer, keyboard; key focus и selected navigation не сливать в одно состояние.

### macOS / Mac Catalyst

- Основной макет 1440×900; также 1024×768 и узкое окно 800×600.
- Предлагается sidebar + content + optional inspector. Сейчас `#if os(macOS)` sidebar
  сам по себе не доказывает sidebar в Catalyst: Catalyst компилируется как iOS.
  Поэтому Mac-пример — целевой дизайн, не скриншот реализованного desktop-shell.
- Native toolbar/titlebar, системные window controls; не рисовать свой Chrome-подобный browser shell.
- Keyboard shortcuts как предложения: Command-F поиск, Space play/pause вне поля ввода,
  Escape dismiss, стрелки seek при фокусе плеера. Проверить конфликты перед реализацией.
- Hover только дополняет доступные кнопки; context menu имеет эквивалент через меню/клавиатуру.
- На узком окне скрывать secondary pane; не объявлять новый minimum window size без проверки.

### Apple TV / tvOS

- Основной canvas 1920×1080 logical units. Предлагаемые margins 80/60; сверять с
  tvOS safe areas и фактическим экраном, не путать со scale 4K.
- Верхние native tabs; крупные горизонтальные полки. На старте 3–4 карточки в ряду;
  размер контента и фокус важнее совпадения с количеством колонок iPad.
- Focus ведётся системой. Selected tab, focused item и currently playing — разные состояния.
- На макете явный ring/lift, достаточный зазор между соседями; увеличение не обрезается контейнером.
- Remote Select активирует, Play/Pause управляет видео; Back закрывает верхний слой,
  затем возвращает назад. Фокус возвращается к исходной карточке/кнопке.
- Никаких touch-only swipe actions, маленьких hover menus и нижнего iPhone tab bar.
- Клавиатура/поиск системные; тексты и субтитры проверять с расстояния. Не показывать
  AirPlay/PiP/скачивание в состоянии enabled без проверки реальной поддержки на платформе.

## 7. Доступность и локализация

- Проектная цель контраста: обычный текст ≥4.5:1, крупный текст/значимые иконки/фокус ≥3:1.
  Замерять текст на конечной поверхности после alpha-compositing, в обеих темах.
- У обычного действия и удаления разные подписи, роль и смысл; цвет не единственный маркер.
- VoiceOver: имя, состояние и действие; карточка не озвучивает duration трижды.
  Отдельная кнопка меню остаётся доступной, порядок чтения совпадает с визуальным.
- Dynamic Type до AX5/доступных системных категорий. Длинные заголовки и RU-переводы
  переносятся; при большом тексте полные названия доступны в деталях и accessibility label.
- Reduce Motion отключает крупное движение и focus-scale в custom preview.
  Reduce Transparency/настройка Disable Liquid Glass дают непрозрачный читаемый фон.
  Increase Contrast усиливает границы/выделение; Bold Text не ломает строки.
- Timeline имеет accessibility adjustable action; seek не требует точного drag.
- RTL: logical leading/trailing; media transport не зеркалить механически вместе с текстом.
- Не помещать смысл только в звук; состояния воспроизведения и ошибки имеют визуальные подписи.
- Время auto-hide controls берётся из PlaybackTuning/настроек. При assistive interaction
  проверить, что controls не исчезают до завершения действия; не вводить второй timeout в UI.

### Микротексты для макетов

| Ситуация | RU | EN |
|---|---|---|
| Вход | Войдите, чтобы увидеть свою ленту | Sign in to see your feed |
| Гостевой путь | Открыть поиск | Open search |
| Нет результатов | Ничего не найдено. Попробуйте другой запрос. | No results. Try another search. |
| Нет сети | Нет подключения. Сохранённые видео доступны в разделе «Офлайн». | You're offline. Saved videos are available in Offline. |
| Перевод готовится | Готовим перевод… | Preparing translation… |
| Перевод недоступен | Перевод пока недоступен. Можно слушать оригинал. | Translation isn't available yet. You can play the original audio. |
| Повтор | Попробовать ещё раз | Try again |
| Удаление | Удалить видео и все сохранённые дорожки? | Delete this video and all saved tracks? |

Это предлагаемые тексты. При реализации использовать существующий каталог локализации
и проверить соответствие реальным service states; не менять ключи автоматически.

## 8. Связь с реализацией

| Паттерн | Текущие владельцы в репозитории |
|---|---|
| Navigation / AppSection | SmartTubeIOS/Sources/SmartTubeIOS/Views/RootView.swift |
| SF Symbols | SmartTubeIOS/Sources/SmartTubeIOS/Views/ViewHelpers.swift — AppSymbol |
| Cards | SmartTubeIOS/Sources/SmartTubeIOS/Views/Browse/VideoCardView.swift, ShortsCardView.swift |
| Playback | SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/; PlaybackViewModel, PlaybackTuning |
| Downloads | SmartTubeIOS/Sources/SmartTubeIOS/Views/Common/OfflineVideosView.swift; OfflineCoordinator |
| Theme / accent / quality | SmartTubeIOS/Sources/SmartTubeIOSCore/AppSettings.swift; SettingsStore |
| Stable UI-test identifiers | AccessibilityID — найти существующее определение, переиспользовать |

В текущей задаче Swift-код не изменён. В будущем использовать Swift 6, @MainActor @Observable,
без новых Combine/DispatchQueue/ObservableObject. Core остаётся Foundation-only.
Не править project.pbxproj вручную. Не создавать второй источник истины для symbols,
accessibility IDs, таймаутов и сохранённых настроек. JSON здесь — дизайн-спецификация,
не runtime store. Изменение layout не должно менять очередь, аудио, подписки или файлы.

## 9. Источники и происхождение

Проверено 17 октября 2026. Различать три вида данных:

- **source-fact**: прочитано из предоставленного файла Figma или текущих исходников.
- **platform-guidance**: рекомендации Apple, интерпретированные для приложения.
- **voxaframe-proposal**: выбранные здесь brand/action colors, размеры content-компонентов,
  композиции Mac/TV и предлагаемые shortcuts. Они ещё не внедрены в приложение.

Figma: [iOS and iPadOS 27 — Community](https://www.figma.com/design/DuO7Y7LtPFaGhcPKDVfNfQ/iOS-and-iPadOS-27--Community-).
Найдены 47 страниц, 6 collections, 299 variables, 34 text styles, 50 paint styles.
Зафиксированы 63 color variables, 34 text-style metrics, 41 dimension variables и
каталог 12 релевантных страниц компонентов. Это не полный экспорт 299 переменных
или всех node trees. Source file не изменялся. В Tab Bars чтение property definitions
одного набора возвращает ошибку источника; сохранены доступные IDs, имена и размеры.

| Источник | Роль |
|---|---|
| [Apple Design Resources](https://developer.apple.com/design/resources/) | Официальные UI kits для iOS/iPadOS и macOS 27; отдельные ресурсы TV |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | Навигационный слой Liquid Glass и системные materials |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Адаптация к окну, safe areas и окружению |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Текст, контраст, размеры, альтернативные способы взаимодействия |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Оконная композиция и keyboard/pointer |
| [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos) | Focus, remote и расстояние просмотра |
| [Anthropic: design system setup](https://support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design) | Загрузка материалов и создание reusable system |
| [DTCG format](https://www.designtokens.org/tr/2025.10/format/), [color](https://www.designtokens.org/tr/2025.10/color/) | Формат файлов токенов |

Community-copy содержит страницу Apple License и Getting Started с copyright Apple;
идентичность этой копии последней официальной библиотеке не доказана. Для нового native
контрола приоритет имеет текущий SDK и официальные ресурсы. iOS-kit не является Mac/TV-kit.
Шрифты, SF Symbol artwork, Apple component vectors и изображения примеров Apple в архив
не перенесены. Их лицензии действуют отдельно. Иконка VoxaFrame — существующий оригинал
проекта; приложение сохраняет upstream attribution/GPLv3.

## 10. Приёмка импортированной системы

1. Claude создал foundations, light/dark tokens, компоненты и отдельные platform patterns.
2. Значения action/onAction и text/background не перепутаны; system colors остаются semantic.
3. Главная нарисована для iPhone, iPad, Mac, TV; на TV виден focus и нет mobile tab bar.
4. Есть player, mini-player, quality/audio/translation selectors и offline library.
5. Для одной карточки показаны default, selected, focused, disabled и loading/error где применимо.
6. Guest/no-results/offline/error различимы; есть полезный следующий шаг.
7. Светлая/тёмная тема, большой текст, RU/EN и Reduce Motion/Transparency проверены отдельно.
8. Макеты используют выбранную иконку и вымышленный контент, не заявляют готовность native-кода.

### Следующие запросы после создания системы

**Главная:** «Используй VoxaFrame / Apple 27. Создай Home для четырёх платформ по
platforms.json: лента, фильтры, продолжить просмотр и мини-плеер. Сохрани все основные
разделы и покажи светлую/тёмную тему. Подпиши предлагаемые изменения текущего UI».

**Плеер:** «Создай Player с quality/audio/captions/translation/queue и состояниями
buffering/error/ready. Покажи iPhone landscape, iPad side-by-side, Mac window и tvOS
remote focus. Учитывай сохранённое качество и независимую скорость Shorts».

**Офлайн:** «Создай Offline library, download queue и asset detail. Покажи выбор качества,
аудио и перевода, недоступный вариант, прогресс, ошибку и два разных подтверждения:
удаление дорожки и удаление всего видео. Не придумывай состояния сервиса».

**Перед разработкой:** «Сопоставь результат с RootView/AppSection, AppSymbol,
AccessibilityID, AppSettings и существующими Views. Подготовь список минимальных изменений
SwiftUI, отмечая новые design proposals и платформенные проверки. Не изменяй runtime behavior».
