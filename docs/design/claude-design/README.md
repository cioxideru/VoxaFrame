# VoxaFrame — пакет для Claude Design

Версия 1.0 · 17 октября 2026 · задача DESIGN-0001.

Готовая основа дизайна VoxaFrame для iPhone, iPad, Mac Catalyst и Apple TV.
Это дизайн-система для нового интерфейса, а не изменение работающего приложения.

## Самый простой импорт

1. Распакуйте `VoxaFrame-Claude-Design.zip`.
2. В Claude прикрепите **[CLAUDE_IMPORT.md](CLAUDE_IMPORT.md)**,
   **[VoxaFrame-Design-System.pdf](VoxaFrame-Design-System.pdf)** и
   **[assets/voxaframe-icon.png](assets/voxaframe-icon.png)**.
3. Скопируйте целиком **[IMPORT_PROMPT.txt](IMPORT_PROMPT.txt)** в сообщение.
4. Попросите сохранить результат как дизайн-систему VoxaFrame. Управление системой:
   **Settings → Design systems**. Затем создавайте проекты с этой системой.

Для точного переноса значений дополнительно прикрепите
[tokens/light.tokens.json](tokens/light.tokens.json),
[tokens/dark.tokens.json](tokens/dark.tokens.json),
[components.json](components.json) и [platforms.json](platforms.json).
Архив служит контейнером для передачи: автоматический импорт ZIP как готовой библиотеки
Claude не подтверждён. Если интерфейс не принимает какой-либо тип файла, начните с Markdown,
PDF и PNG: основные правила и значения уже есть в них.

В отдельном интерфейсе `claude.ai/design` используйте загрузку brand/product assets при
настройке design system организации. Актуальный основной путь — обычный Claude с Design.
`/design-sync` уместен для уже существующей библиотеки React; этот пакет не выдаёт SwiftUI
или HTML-справочник за React-библиотеку.
Основание: [инструкция Anthropic](https://support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design).

## Что внутри

| Файл | Для чего |
|---|---|
| [CLAUDE_IMPORT.md](CLAUDE_IMPORT.md) | Единый документ: продукт, правила, компоненты, платформы, состояния, доступность, источники |
| [IMPORT_PROMPT.txt](IMPORT_PROMPT.txt) | Готовый запрос на создание системы; дальнейшие запросы есть в основном документе |
| [VoxaFrame-Design-System.pdf](VoxaFrame-Design-System.pdf) | Визуальные эталоны бренда, компонентов и четырёх платформ |
| [preview.html](preview.html) | Автономный справочник с переключением темы; работает без сети |
| [tokens/light.tokens.json](tokens/light.tokens.json), [tokens/dark.tokens.json](tokens/dark.tokens.json) | Токены по синтаксису DTCG 2025.10; отдельный файл на тему |
| [tokens/voxaframe.css](tokens/voxaframe.css) | CSS-представление тех же токенов для прототипов |
| [components.json](components.json) | Контракты компонентов: варианты, состояния, поведение, доступность, связь с кодом |
| [platforms.json](platforms.json) | Размеры макетов и адаптация для каждой платформы |
| [figma-reference.json](figma-reference.json) | Проверенные ссылки и факты из предоставленной Figma-копии |
| [provenance.json](provenance.json) | Происхождение данных, исходные файлы, границы достоверности |
| [assets/voxaframe-icon.png](assets/voxaframe-icon.png) | Выбранная пользователем иконка; оригинал без изменения |
| [checks.json](checks.json) | Результаты локальной проверки пакета |
| [manifest.json](manifest.json) | SHA-256 каждого файла пакета для проверки целостности |
| [verify.py](verify.py) | Повторная проверка JSON, ссылок, контраста и состава |

PNG-макеты лежат в `previews/`. Это предложения нового дизайна с вымышленным контентом.
Текущие пользовательские скриншоты, учётные данные и исходники приложения в архив не входят.

## Приоритеты для Claude

1. Поведение и ограничения VoxaFrame из `CLAUDE_IMPORT.md`.
2. Нативные компоненты и доступность соответствующей Apple-платформы.
3. Семантические токены и контракты из JSON.
4. Визуальные примеры как направление, а не фиксированная сетка для любого окна.

Коралловый акцент и новые композиции — предложение дизайн-системы; в текущем приложении
сохраняются пользовательский цвет, системная/светлая/тёмная тема и настройка Liquid Glass.
Макеты не подтверждают реализацию новых экранов или поддержку новых API.

## Проверка после импорта

Попросите Claude нарисовать главный экран на четырёх платформах, затем экран плеера и
состояние загрузки без сети. Проверьте 5 основных разделов, выбранную иконку, обе темы,
крупный текст, клавиатурный/TV-фокус и отсутствие стекла под длинным текстом.
Вход в Claude, загрузка и публикация системы в аккаунте пользователя в эту работу не входят.

Apple UI kit использован как источник ссылок и параметров. Пакет не содержит копии
библиотеки Apple, файлов SF Pro/SF Symbols или её векторных компонентов. Для использования
оригинальных ресурсов открывайте исходную Figma и её страницу License.

Полная спецификация для Claude: [CLAUDE_IMPORT.md](CLAUDE_IMPORT.md).
