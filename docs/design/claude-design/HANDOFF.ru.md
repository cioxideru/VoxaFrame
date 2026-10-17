# Как импортировать дизайн систему VoxaFrame в Claude Design

Нужно создать и сохранить в Claude Design систему **VoxaFrame / Apple 27** для
видеоприложения VoxaFrame (SmartTube): iPhone, iPad, Mac Catalyst и Apple TV.
После этого её можно использовать для новых экранов приложения.

## Где лежат файлы

Общий каталог на исходном Mac:

```text
/Volumes/Work4TB/Users/ibaranov/Documents/SmartTubeIOS/docs/design/claude-design/
```

Если общий диск у вас подключён иначе, найдите в проекте папку
`docs/design/claude-design`. Файлы в ней уже распакованы. Архив
`VoxaFrame-Claude-Design.zip` нужен только для переноса на другой компьютер.
Для быстрого просмотра откройте [визуальный PDF](VoxaFrame-Design-System.pdf)
или [preview.html](preview.html) в браузере.

## Порядок импорта

1. Откройте Claude в аккаунте, где доступен Design, и начните новый диалог создания
   дизайн-системы.
2. Прикрепите три файла: [CLAUDE_IMPORT.md](CLAUDE_IMPORT.md),
   [VoxaFrame-Design-System.pdf](VoxaFrame-Design-System.pdf) и
   [assets/voxaframe-icon.png](assets/voxaframe-icon.png).
3. Если интерфейс принимает JSON, добавьте [light.tokens.json](tokens/light.tokens.json),
   [dark.tokens.json](tokens/dark.tokens.json), [components.json](components.json)
   и [platforms.json](platforms.json). Основные правила и значения есть и в Markdown.
4. Откройте [IMPORT_PROMPT.txt](IMPORT_PROMPT.txt), скопируйте весь текст в сообщение
   Claude и отправьте его вместе с вложениями.
5. Проверьте результат по списку ниже и сохраните систему под именем
   **VoxaFrame / Apple 27**. Найдите её в **Settings → Design systems** и выберите
   для следующего проекта.
6. В новом проекте попросите: «Используй VoxaFrame / Apple 27. Создай главный экран
   для iPhone, iPad, Mac Catalyst и Apple TV, затем экран плеера и офлайн-библиотеку.
   Соблюдай поведение и ограничения из CLAUDE_IMPORT.md».

Если используется отдельный интерфейс `claude.ai/design`, загрузите те же материалы
при настройке дизайн-системы организации. Названия действий могут зависеть от
интерфейса и прав аккаунта; ориентир — [инструкция Anthropic](https://support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design).
ZIP передавайте как архив файлов: автоматический импорт ZIP в готовую библиотеку
не проверен. Если Markdown нельзя прикрепить, вставьте его содержимое в диалог.

## Что проверить

- Сохранены название VoxaFrame, приложенная иконка и пять разделов: Home, Search,
  Library, Offline videos, Settings.
- Есть отдельные композиции для четырёх платформ, светлая и тёмная темы;
  на Apple TV виден фокус, на Mac работает клавиатурная навигация.
- Есть состояния без входа, пустого списка, загрузки, ошибки и отсутствия сети.
- В плеере предусмотрены качество, скорость, оригинальная и дублированная дорожки,
  перевод и очередь; для удаления офлайн-файлов — подтверждение.
- Учтены крупный текст, Reduce Motion и Reduce Transparency; текст остаётся читаемым.
- Система сохранена и доступна для выбора в новом проекте. Макеты из пакета служат
  визуальным ориентиром; нативную реализацию SwiftUI нужно выполнять отдельно.

После импорта передайте владельцу проекта имя сохранённой системы, четыре примера
главного экрана и список оставшихся расхождений. Публичная публикация не требуется.
Подробные правила и происхождение данных: [README.md](README.md) и
[CLAUDE_IMPORT.md](CLAUDE_IMPORT.md).
