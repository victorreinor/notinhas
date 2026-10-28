# Notinhas — guia para agentes de IA

App nativo de notas adesivas para macOS 14+: cada nota é uma janela sem borda que fica no desktop, com markdown ao vivo, cor, opacidade, alfinete (flutua por cima de tudo) e modo recolhido. Não tem ícone no Dock nem barra de menus (`LSUIElement`); abre pelo Spotlight. Swift 6 (modo de linguagem 5) + AppKit, **sem dependências externas**, compilado só com as Command Line Tools.

Detalhes de arquitetura, ciclo de vida e formato dos dados: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Comandos

```sh
swift build                       # build debug
swift test                        # testes (Swift Testing) do NotinhasCore
./scripts/build-app.sh            # build/Notinhas.app — release, universal (arm64 + x86_64), assinatura ad-hoc
./scripts/install-dev.sh          # compila, substitui /Applications/Notinhas.app e abre
./scripts/screenshots.sh          # regenera docs/images (imagens do README) renderizando as views reais
./scripts/release.sh "notas"      # testa, builda, cria tag vX.Y.Z e GitHub Release com Notinhas.zip
```

O aviso `ld: warning: search path '.../Developer/Library/Frameworks' not found` no `swift test` é inofensivo.

## Mapa do código

| Arquivo | Responsabilidade |
| --- | --- |
| `Sources/NotinhasCore/Note.swift` | Modelo `Note` + `NoteColor`. Decodificação tolerante (campo novo precisa de default no `init(from:)`). |
| `Sources/NotinhasCore/NoteStore.swift` | Um JSON por nota em `~/Library/Application Support/Notinhas/notes/`. |
| `Sources/NotinhasCore/MarkdownEditing.swift` | **Toda** edição de texto por comando: negrito, listas, Enter/Backspace/Tab em listas, checkbox. Funções puras que devolvem `TextEdit`. |
| `Sources/Notinhas/AppDelegate.swift` | Ciclo de vida: abrir notas, reabrir pelo Spotlight, login, atalho global, salvar, excluir, posição de nota nova. |
| `Sources/Notinhas/NoteWindowController.swift` | Uma nota: monta as views, aplica cor/alfinete/recolher, menu `⋯`, salvamento com debounce. |
| `Sources/Notinhas/NoteViews.swift` | `NoteWindow` (sem borda), fundo/header, arrastar, `IconButton`, alça de redimensionar. |
| `Sources/Notinhas/MarkdownTextView.swift` | Editor (TextKit 1 montado à mão), comandos de formatação, clique no checkbox, ⌘-clique em link; `NoteLayoutManager` desenha checkbox e bolinha. |
| `Sources/Notinhas/MarkdownStyler.swift` | Estilização ao vivo: só atributos, nunca caracteres. |
| `Sources/Notinhas/MainMenu.swift` | Menu principal invisível — é ele que faz ⌘C/⌘V/⌘Z/⌘B funcionarem. |
| `Sources/Notinhas/ColorPicker.swift` | Paleta das 7 cores e o popover de cor/opacidade. |
| `Sources/Notinhas/HotKey.swift` / `LoginItem.swift` | ⌃⌥N global (Carbon) / abrir ao iniciar (`SMAppService`). |
| `Sources/Notinhas/Snapshot.swift` | Ferramenta de dev: renderiza as imagens do README fora da tela. |
| `install.sh` | Instalador de um comando para usuários finais (baixa a última Release). |

## Decisões de produto — não mudar sem perguntar ao dono

- Sem Dock, sem barra de menus, sem ⌘Tab. Abrir o app de novo (Spotlight/Finder) **traz todas as notas para frente**; sem notas, cria uma.
- Nota nova é amarela "marca-texto". Header pequeno: `+`, cor, alfinete, `⋯`.
- Nota **sem** alfinete é janela normal: as outras janelas passam por cima. **Com** alfinete: `.floating` em todas as mesas e sobre apps em tela cheia.
- Markdown fica como texto puro (portável); a sintaxe é só esmaecida, exceto marcadores de lista, desenhados como bolinha/checkbox.
- Textos da interface em português (pt-BR); código, comentários e logs em inglês.
- Não mudar o bundle id `dev.victorreinor.notinhas` nem a pasta `Notinhas` (preferências, login item e notas dos usuários dependem deles). Não mudar o nome do asset `Notinhas.zip` (o `install.sh` baixa `releases/latest/download/Notinhas.zip`).

## Armadilhas

- **TextKit 1 é obrigatório.** `MarkdownTextView.init` monta storage → layout manager → container à mão porque `NoteLayoutManager.drawGlyphs` só existe no TextKit 1. Não use `NSTextView.scrollableTextView()` nem APIs de TextKit 2. A view guarda `ownedStorage` porque nada mais retém o `NSTextStorage`.
- **Estilizar só em `willProcessEditing`** e só atributos. Pular quando `hasMarkedText()` (acentos com tecla morta, ´ + a).
- Marcadores de lista ficam com cor `.clear` e o `NoteLayoutManager` desenha por cima; o clique no checkbox é detectado pelo atributo `.noteCheckbox`. O `x` de `[x]` recebe `kern` para alinhar com `[ ]`.
- Links usam o atributo próprio `.noteLink` (abre com ⌘-clique). `.link` abriria a cada clique e atrapalharia a edição.
- **Nova formatação:** escreva a função pura em `MarkdownEditing` com teste, e chame via `MarkdownTextView.apply(_:)`, que passa por `shouldChangeText`/`didChangeText` (desfazer + salvar). Não altere `textStorage` direto.
- **Novo atalho de teclado:** adicione no `MainMenu` (app `LSUIElement` sem menu principal não recebe key equivalents). Shift + número gera símbolo (⇧8 = `*`), por isso ⇧⌘8 é tratado por `keyCode` em `MarkdownTextView.performKeyEquivalent`.
- Janela sem borda: `canBecomeKey` sobrescrito; arrastar pelo `NoteHeaderView.performDrag`; redimensionar pela `ResizeGrip`. O fundo é desenhado em `draw(_:)` (não em propriedades de layer) para o snapshot funcionar. Chame `invalidateShadow()` depois de mudar forma ou tamanho.
- Recolher desativa `bodyBottom` e trava a altura com `minSize`/`maxSize`; `expandedHeight` guarda a altura para restaurar.
- O salvamento tem debounce de 0,4 s. `close()` cancela o save pendente antes de excluir (senão a nota "ressuscita"). SIGTERM vira `NSApp.terminate` para salvar o pendente (os scripts usam `pkill`).
- Se o app abriu no login (Apple Event `keyAELaunchedAsLogInItem`), ele não cria nota nem rouba o foco.

## Verificando uma mudança

Este ambiente não tem Xcode, e o terminal não tem permissão de Gravação de Tela nem de Acessibilidade: não dá para tirar print nem clicar na UI.

1. `swift test` para a lógica.
2. `./scripts/screenshots.sh` e **olhe** os PNGs em `docs/images/` para qualquer mudança visual. Para cenas novas, edite `Snapshot.swift`.
3. `./scripts/install-dev.sh` e confira o comportamento com `pgrep -x Notinhas`, `lsappinfo info -only name "$(lsappinfo front)"` (app da frente), `ls ~/Library/Application\ Support/Notinhas/notes` e `sfltool dumpbtm | grep -A6 -i notinhas` (login item).
4. O que exige mãos humanas: digitar, ⌘B, Enter em lista, clicar no checkbox, arrastar, redimensionar, recolher, cor/opacidade, alfinete sobre outro app, ⌃⌥N de outro app. Peça ao usuário para testar e diga isso explicitamente.

## Release e distribuição

Suba `CFBundleShortVersionString` em `Resources/Info.plist`, faça commit e rode `./scripts/release.sh "o que mudou"`. O app é assinado ad-hoc e **não é notarizado** (exigiria Apple Developer ID, US$ 99/ano). Por isso o `install.sh` remove o atributo de quarentena, e o README explica o caminho manual pelo Gatekeeper. Para notarizar no futuro: `codesign` com Developer ID + `xcrun notarytool` (que precisa do Xcode).

## Referências

- [NSTextStorageDelegate](https://developer.apple.com/documentation/appkit/nstextstoragedelegate) · [NSLayoutManager](https://developer.apple.com/documentation/appkit/nslayoutmanager) · [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow) (níveis e `collectionBehavior`) · [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) (login item)
- [Swift Testing](https://developer.apple.com/documentation/testing) · [Swift Package Manager](https://www.swift.org/documentation/package-manager/)
- [Notarização](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Abrir app de desenvolvedor não identificado](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
- [CommonMark](https://spec.commonmark.org/) (referência da sintaxe; o estilizador cobre um subconjunto)
