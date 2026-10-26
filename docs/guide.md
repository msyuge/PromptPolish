# PromptPolish user guide

**English** · [Русский](guide.ru.md) · [← README](../README.md)

PromptPolish lives in the macOS menu bar and turns a short idea typed into an AI chat's input field into a detailed, structured prompt tailored to that chat. The model runs right on your Mac.

The app's interface is in Russian; the English meaning of each button is given in parentheses.

- [1. Installation](#1-installation)
- [2. Accessibility permission](#2-accessibility-permission)
- [3. Model](#3-model)
- [4. Your first prompt](#4-your-first-prompt)
- [5. Writing a good idea](#5-writing-a-good-idea)
- [6. Settings](#6-settings)
- [7. Troubleshooting](#7-troubleshooting)
- [8. Uninstalling](#8-uninstalling)

## 1. Installation

1. Open [Releases](https://github.com/msyuge/PromptPolish/releases/latest) and download `PromptPolish-<version>.dmg`.
2. Open the DMG and drag **PromptPolish** onto the **Applications** shortcut.
3. Launch PromptPolish from **Applications**. No window opens: a magic wand icon appears on the right side of the menu bar. Click it to open the menu.

The app is signed and notarized by Apple, so there is no "unidentified developer" warning.

You need macOS 14 or later and an Apple Silicon Mac (M1 or newer). The app does not run on Intel Macs.

## 2. Accessibility permission

Without this permission PromptPolish can't read text from another app or replace it.

1. On first launch macOS shows a prompt — click **Open System Settings**. If it didn't appear, choose **Выдать доступ к Accessibility…** (Grant Accessibility access) in the PromptPolish menu.
2. In **System Settings → Privacy & Security → Accessibility**, turn on **PromptPolish**. macOS asks for your password or Touch ID.
3. Go back to the PromptPolish menu: the permission item disappears and **Улучшить промт** (Improve prompt) becomes active. No restart needed.

## 3. Model

**The default is Qwen3.5 2B**: a 1.75 GB model that takes about 2 GB of memory while loaded. On the first ⌥⌘P PromptPolish looks for a model in this order:

1. **LM Studio.** If you already downloaded an MLX model in LM Studio, PromptPolish loads it from LM Studio's folder. No second copy is made and LM Studio doesn't have to be running.
2. **Hugging Face cache** (`~/.cache/huggingface/hub`).
3. **Download.** If no model is found, PromptPolish downloads Qwen3.5 2B, about 1.75 GB. Progress is shown in the menu ("Скачивание модели: 42%") and in Settings. Downloads survive dropped connections, and after that no internet is needed.

To save memory while you aren't using it, the model is loaded on the first ⌥⌘P and unloaded after 5 idle minutes. While it's not loaded the menu says **Модель загрузится при ⌥⌘P** (Model loads on ⌥⌘P), and the next prompt starts 2–4 seconds later. While it's loaded the menu says **Модель готова** (Model ready) and offers **Выгрузить модель из памяти** (Unload model from memory).

**Choosing another model.** Menu → **Модель** (Model) → pick an item:

- **На диске** (On disk) — models you already have;
- **Скачать с Hugging Face** (Download from Hugging Face) — models you can download. Only models that fit your Mac's memory are listed.

| Model | When to choose it |
|---|---|
| Qwen3.5 2B | default: balance of size and quality |
| Qwen3.5 0.8B | when disk space or memory is very tight; noticeably weaker prompts |
| Qwen3.5 4B | best quality, but 3 GB and more of memory |
| Gemma 4 E2B | alternative from Google |
| Apple Intelligence (experimental) | built into macOS 26+, nothing to download; often wrong in Russian |

The choice is remembered and the previous model is unloaded from memory.

## 4. Your first prompt

1. Open any AI chat: claude.ai, chatgpt.com or perplexity.ai in a browser, or the Claude or ChatGPT desktop app.
2. Type an idea into the input field, for example: `explain swift closures to a beginner`.
3. Select the text. You can skip this — then the whole field is used.
4. Press **⌥⌘P** (Option + Command + P).
5. A panel appears next to the text. Its title shows which chat the prompt is for ("Промт для Claude"), and the text streams in below. This usually takes 10–30 seconds.
6. If the model needs more details, it asks 2–3 questions. Type your answers in the field below them and press **Ответить** (Answer) or **⌘↩**.
7. When the prompt is ready you can edit it in the panel. Then:
   - **Заменить** (Replace) or **Return** — the prompt replaces the text in the chat's field;
   - **Копировать** (Copy) or **⇧⌘C** — the prompt goes to the clipboard;
   - **Отмена** (Cancel) or **Esc** — close the panel without changes.
8. Send the prompt in the chat as usual.

Replacing does not touch your clipboard: whatever you copied before stays there.

## 5. Writing a good idea

PromptPolish adds structure, but it can't guess facts. The more specific the idea, the fewer questions and the more precise the prompt.

- Say **what you want**: a post, a plan, a comparison, code, an explanation.
- Add **who it's for and why**: "for my manager", "for a beginner", "for a coffee Telegram channel".
- Mention **constraints** if any: length, tone, format, deadlines, language.
- No need to write "make a prompt for…" — PromptPolish knows you want a prompt. The exception is prompts for image, video and music generators (Midjourney, Stable Diffusion, Suno): write those as you normally would.
- The prompt is written in the same language as your idea.

Example: instead of `plan`, write `a one-month plan to learn swift from scratch, one hour a day`.

## 6. Settings

Menu → **Настройки…** (Settings…), or ⌘, while the menu is open.

**Основные** (General):

- **Горячая клавиша** (Hotkey) — click the field and press a new shortcut.
- **Разрешения** (Permissions) — Accessibility status.
- **Модель** (Model) — model choice, loading state and location. **Обновить** (Refresh) rescans the disk, for example after downloading in LM Studio.
- **Выгружать из памяти** (Unload from memory) — how many idle minutes before memory is freed (5 minutes by default; "никогда" — never, keep it loaded).
- **Загружать модель при запуске** (Load model at launch) — the model is ready immediately, but takes memory even when unused.
- **Лицензии** (Licenses) — third-party license texts.

**Системные инструкции** (System instructions) — the rules the model follows when writing a prompt for each chat:

- pick a chat on the left and edit the text on the right; the **Русский / English** switch picks the instruction set — Russian is used for ideas written in Cyrillic, English for all others;
- **Сохранить** (Save, ⌘S) — the change applies from the next ⌥⌘P;
- **Отменить изменения** (Discard changes) — go back to the saved version;
- **Сбросить к стандартной** (Reset to default) — restore the instruction shipped with the app;
- **Показать файл в Finder** (Show file in Finder) — edits are plain text files in `~/Library/Application Support/PromptPolish/SystemPrompts/`.

A dot next to a chat means its instruction is customized; a pencil means unsaved edits.

## 7. Troubleshooting

**⌥⌘P does nothing, or you hear an error sound.**

- Make sure the menu doesn't show **Выдать доступ к Accessibility…** (see section 2).
- The cursor must be in an input field that contains text.
- Password fields are skipped on purpose.
- If another app has secure input on (for example, **Terminal → Secure Keyboard Entry**), macOS blocks PromptPolish — turn it off.
- The shortcut may be taken by another app — assign a different one in Settings.

**Permission is granted but PromptPolish says it isn't.** This can happen after updating the app. In **Accessibility**, select PromptPolish, click **−**, then **+** and add the app from Applications again.

**The prompt was pasted in the wrong place, or the field wasn't replaced.** While the prompt is generating, don't switch windows or clear the selection in the field. If replacing still fails, the panel shows an error — click **Копировать** (Copy) and paste the prompt manually.

**"Ошибка модели" (model error) or the download doesn't start.** Check your internet connection and free disk space (about 3 GB), then click **Повторить загрузку модели** (Retry loading model) in the menu. An interrupted download resumes where it stopped.

**A model from LM Studio isn't listed.** Only **MLX** models are supported, not GGUF. In LM Studio pick the MLX variant when downloading, then choose **Модель → Обновить список** (Model → Refresh list).

**Everything is slow, the Mac lags.** A loaded model takes 2.5–3.4 GB of memory. In Settings make sure **Загружать модель при запуске** (Load model at launch) is off and **Выгружать из памяти** (Unload from memory) isn't set to never; you can unload the model right away from the menu. Don't keep another model loaded in LM Studio or Ollama, close heavy browser tabs, or switch to Qwen3.5 2B.

**The prompt is odd or inaccurate.** Small models sometimes get details wrong, and Qwen3.5 0.8B writes the weakest prompts. Fix the result in the panel before replacing, add more specifics to your idea, or pick a larger model — Qwen3.5 4B — in the menu. If prompts for a particular chat are consistently off, edit its system instruction.

**The model keeps asking questions.** It follows the rule "if the request is vague, ask first". Add who the result is for and what format you need, or remove that rule from the system instruction.

**Seeing what happened.** PromptPolish keeps a technical log without prompt text:

```bash
/usr/bin/log show --last 30m --info --predicate 'subsystem == "com.alekseimaksimov.promptpolish"'
```

If the problem persists, [open an issue](https://github.com/msyuge/PromptPolish/issues) and attach the output of this command.

## 8. Uninstalling

1. Quit PromptPolish: menu → **Выход** (Quit).
2. Delete **PromptPolish** from Applications.
3. Optionally remove its data:
   - system instruction edits: `~/Library/Application Support/PromptPolish`;
   - settings: `defaults delete com.alekseimaksimov.promptpolish`;
   - models downloaded by PromptPolish: the `models--mlx-community--…` folders in `~/.cache/huggingface/hub` (LM Studio models are never touched).
4. In **Accessibility**, remove PromptPolish from the list with **−**.
