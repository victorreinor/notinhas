# Arquitetura

```
                     ┌──────────────────────────── Notinhas (app, AppKit) ───────────────────────────┐
 Spotlight / login ─▶│ AppDelegate ──open/create/delete──▶ NoteWindowController (1 por nota)         │
 ⌃⌥N (HotKey)      ─▶│   │  ▲ onChange(Note)                  ├─ NoteWindow (sem borda)              │
 Canto (CornerTab) ─▶│   │  │                                  ├─ NoteHeaderView  + ● 📌 ⋯            │
                     │   │  └────────────────────────────────  ├─ título (NSTextField)                │
                     │   ▼                                     ├─ MarkdownTextView ── MarkdownStyler  │
                     │ NoteStore ◀── NotinhasCore ──▶ MarkdownEditing   └─ NoteLayoutManager         │
                     └──────────────────────────────────────────────────────────────────────────────┘
```

`NotinhasCore` não importa AppKit: modelo, persistência e as transformações de texto são puras e testadas. `Notinhas` é a camada AppKit.

## Ciclo de vida

| Evento | O que acontece (`AppDelegate`) |
| --- | --- |
| Primeira abertura, sem notas | Cria uma nota amarela no canto superior direito da tela do mouse, com foco no corpo. |
| Abertura com notas salvas | Abre todas as janelas e traz para frente. |
| Abertura no login | Abre as janelas sem ativar o app. Sem notas, não cria nenhuma. |
| Abrir de novo com o app rodando | `applicationShouldHandleReopen` → `bringAllToFront()` (ou cria uma nota, se não houver nenhuma). As notas sobem 28 pt com fade, em cascata (`rise`). |
| ⌃⌥N em qualquer app | `HotKey` (Carbon `RegisterEventHotKey`, sem permissão de Acessibilidade) → nova nota. |
| Monitor conectado ou desconectado | `applicationDidChangeScreenParameters` → `placeNotesOnScreens()`: `NotePlacement.targets` manda as notas cuja casa sumiu para uma cascata na tela do mouse e devolve as outras para casa. Também roda ao abrir o app. |
| Mouse no canto inferior direito (se ligado no `⋯`) | `CornerTab`: monitor global de `.mouseMoved` (mouse não pede Acessibilidade, só teclado) → `HotCorner.screen` acha a tela → um `NSPanel` não ativante desliza a aba. Clique → `showNotes()`. A aba some quando o mouse sai dela e só volta depois que o mouse sai do canto. |
| `+` / ⌘N | Nota nova à direita da atual (ou à esquerda, ou em cascata, o que couber na tela). |
| ⌘Q | `quitOrHide`: por padrão `NSApp.hide` (as notas somem, mas o app segue rodando, com a aba do canto e o ⌃⌥N); com a opção desligada no `⋯`, sai. |
| Sair (`⋯`, logout) / SIGTERM | `applicationWillTerminate` → `flushPendingSave()` em todas as notas. |

Na primeira execução a partir de um `.app`, `LoginItem.enableOnFirstRun()` registra o login item uma vez (chave `loginItemConfigured` no UserDefaults). Depois disso, quem decide é o usuário, no menu `⋯` ou nos Ajustes do Sistema.

## A janela da nota

- `NoteWindow`: `[.borderless, .resizable]`, fundo transparente, sombra, aparência `.aqua` fixa (o papel é sempre claro, até no modo escuro).
- Alfinete ligado: `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. Desligado: `.normal` e `[]`.
- Opacidade: `window.alphaValue`.
- Recolher (duplo clique no header): esconde o corpo, a janela fica com a altura do header (28 pt) e o título aparece no header. Quando o título está vazio, usa a primeira linha do corpo (`MarkdownEditing.plainTitle`).
- A barra de formatação só aparece com a nota em foco (`windowDidBecomeKey`/`windowDidResignKey`).

## O editor

```
tecla / botão / menu
   │
   ├─ texto comum ─────────────▶ NSTextView ──┐
   │                                          │ edita o NSTextStorage
   └─ comando (⌘B, Enter em lista, clique ─▶ MarkdownEditing (puro) → TextEdit
      no checkbox, Tab…)                      → MarkdownTextView.apply (shouldChangeText → replace → didChangeText)
                                              │
                          NSTextStorage.processEditing
                                              │
                    MarkdownStyler.willProcessEditing: reestiliza o texto inteiro (só atributos)
                                              │
                    NoteLayoutManager.drawGlyphs: desenha checkbox/bolinha sobre os marcadores transparentes
```

- O texto salvo é sempre markdown puro. O estilizador aplica fonte, cor e tachado e esmaece a sintaxe (`**`, `_`, `~~`, `` ` ``, `#`, `[]()`).
- Suporta: títulos `#`…`###`, negrito, itálico (`*`/`_`), tachado, código inline, bloco de código cercado, link markdown e URL solta, lista `-`/`*`/`+`, lista numerada, checklist `- [ ]`/`- [x]`, citação `>`, linha horizontal.
- Cada edição reestiliza a nota inteira, o que é barato porque notas são curtas. Se um dia houver notas enormes, reestilize só os parágrafos tocados (`editedRange` expandido para linhas).

## Persistência

Um arquivo por nota em `~/Library/Application Support/Notinhas/notes/<UUID>.json`, gravado de forma atômica 0,4 s depois da última mudança:

```json
{
  "body" : "## Hoje\n- [ ] Comprar café",
  "collapsed" : false,
  "color" : "yellow",
  "createdAt" : "2026-10-28T16:05:36Z",
  "expandedHeight" : 240,
  "frame" : [[2842, 638], [260, 240]],
  "id" : "18F733E2-81B7-46F3-A3FC-367A802D89D9",
  "opacity" : 1,
  "pinned" : false,
  "title" : "Mercado",
  "updatedAt" : "2026-10-28T16:07:12Z"
}
```

`frame` está em coordenadas de tela, com origem no canto inferior esquerdo da tela principal. `frame` é a casa da nota: com o monitor dela desconectado, a janela espera em outra tela sem mexer no `frame` salvo (só o tamanho acompanha), e volta quando o monitor volta. Para adicionar campos, use `decodeIfPresent` com default em `Note.init(from:)`, assim notas antigas continuam abrindo.

## Distribuição

- `scripts/build-app.sh` monta o bundle à mão (sem Xcode): binário universal, `Info.plist`, ícone (`scripts/make-icon.swift` desenha o ícone e o `iconutil` gera o `.icns`) e `codesign --sign -`.
- `scripts/release.sh` (local, sem CI): `scripts/next-version.sh` sobe a última tag (patch, ou `[minor]`/`[major]` no título de um commit), `scripts/test.sh`, `build-app.sh` com `VERSION`, e publica `Notinhas.zip` (feito com `ditto`, que preserva a assinatura) numa GitHub Release `v<versão>`, com os commits desde a tag anterior como notas.
- `install.sh` baixa `releases/latest/download/Notinhas.zip`, instala em `/Applications` (ou `~/Applications`), remove a quarentena e abre o app. Sem notarização, o Gatekeeper bloquearia um app baixado pelo navegador. Arquivos baixados com `curl` não recebem quarentena, e o `xattr -dr` é uma garantia extra.
