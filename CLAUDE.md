# Notinhas — guia para agentes de IA

App nativo de notas adesivas para macOS 14+: cada nota é uma janela sem borda que fica no desktop, com markdown ao vivo, cor, opacidade, alfinete (flutua por cima de tudo) e modo recolhido. Não tem ícone no Dock nem barra de menus (`LSUIElement`); abre pelo Spotlight. Swift 6 (modo de linguagem 5) + AppKit, **sem dependências externas**, compilado só com as Command Line Tools.

Detalhes de arquitetura, ciclo de vida e formato dos dados: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Comandos

```sh
swift build                       # build debug
./scripts/test.sh                 # testes (Swift Testing) do NotinhasCore — use em vez de `swift test`
./scripts/build-app.sh            # build.noindex/Notinhas.app — release, universal (arm64 + x86_64), assinatura ad-hoc
./scripts/install-dev.sh          # compila, substitui /Applications/Notinhas.app e abre
./scripts/screenshots.sh          # regenera docs/images (imagens do README) renderizando as views reais
./scripts/release.sh              # testa, builda, cria a tag da próxima versão e a GitHub Release com Notinhas.zip
./scripts/next-version.sh         # só mostra qual seria a próxima versão
```

Com só as Command Line Tools, o `swift test` puro falha de forma intermitente com `plugin for module 'TestingMacros' not found`. O `scripts/test.sh` passa o `-plugin-path` certo, e `--build-system native` não acha o módulo `Testing`. O aviso `ld: warning: search path '.../Developer/Library/Frameworks' not found` é inofensivo.

## Mapa do código

| Arquivo | Responsabilidade |
| --- | --- |
| `Sources/NotinhasCore/Note.swift` | Modelo `Note` + `NoteColor`. Decodificação tolerante (campo novo precisa de default no `init(from:)`). |
| `Sources/NotinhasCore/NoteStore.swift` | Um JSON por nota em `~/Library/Application Support/Notinhas/notes/`. |
| `Sources/NotinhasCore/NotePlacement.swift` | Para onde cada nota vai quando um monitor sai ou volta. Pura e testada. |
| `Sources/NotinhasCore/HotCorner.swift` | Geometria do canto inferior direito (qual tela, monitores vizinhos). Pura e testada. |
| `Sources/NotinhasCore/MarkdownEditing.swift` | **Toda** edição de texto por comando: negrito, listas, Enter/Backspace/Tab em listas, checkbox. Funções puras que devolvem `TextEdit`. |
| `Sources/Notinhas/AppDelegate.swift` | Ciclo de vida: abrir notas, reabrir pelo Spotlight, login, atalho global, salvar, excluir, posição de nota nova. |
| `Sources/Notinhas/NoteWindowController.swift` | Uma nota: monta as views, aplica cor/alfinete/recolher, menu `⋯`, salvamento com debounce. |
| `Sources/Notinhas/NoteViews.swift` | `NoteWindow` (sem borda), fundo/header, arrastar, `IconButton`, alça de redimensionar. |
| `Sources/Notinhas/MarkdownTextView.swift` | Editor (TextKit 1 montado à mão), comandos de formatação, clique no checkbox, ⌘-clique em link; `NoteLayoutManager` desenha checkbox e bolinha. |
| `Sources/Notinhas/MarkdownStyler.swift` | Estilização ao vivo: só atributos, nunca caracteres. |
| `Sources/Notinhas/MainMenu.swift` | Menu principal invisível — é ele que faz ⌘C/⌘V/⌘Z/⌘B funcionarem. |
| `Sources/Notinhas/ColorPicker.swift` | Paleta das 7 cores e o popover de cor/opacidade. |
| `Sources/Notinhas/HotKey.swift` / `LoginItem.swift` | ⌃⌥N (nova nota) e ⌃⌥M (mostrar as notas) globais, via Carbon / abrir ao iniciar (`SMAppService`). |
| `Sources/Notinhas/CornerTab.swift` | Aba no canto inferior direito, como a Nota Rápida: monitor global de mouse + `NSPanel` que não ativa o app. |
| `Sources/Notinhas/Snapshot.swift` | Ferramenta de dev: renderiza as imagens do README fora da tela. |
| `install.sh` | Instalador de um comando para usuários finais (baixa a última Release). |

## Decisões de produto — não mudar sem perguntar ao dono

- Sem Dock, sem barra de menus, sem ⌘Tab. Abrir o app de novo (Spotlight/Finder) **traz todas as notas para frente**; sem notas, cria uma.
- ⌘Q **esconde** as notas (`NSApp.hide`) em vez de sair, para a aba do canto e o ⌃⌥N continuarem funcionando. É uma opção ligada por padrão no `⋯` ("⌘Q esconde as notas em vez de sair", chave `quitKeyHides`); desligada, o ⌘Q fecha o app. "Sair do Notinhas" no `⋯` sempre fecha.
- Aba do canto (menu `⋯` › "Abrir pelo canto da tela") vem **desligada**, porque o macOS já põe a Nota Rápida nesse canto. Encostar o mouse só mostra a aba; as notas vêm para frente ao **clicar**, para não roubar o foco de quem está digitando.
- Monitor desconectado: as notas dele esperam em cascata na tela do mouse e voltam para o lugar quando ele volta. Arrastar ou redimensionar uma nota que está esperando faz do lugar novo a casa dela.
- Nota nova é amarela "marca-texto". Header pequeno: `+`, cor, alfinete, `⋯`.
- Nota **sem** alfinete é janela normal: as outras janelas passam por cima. **Com** alfinete: `.floating` em todas as mesas e sobre apps em tela cheia.
- Markdown fica como texto puro (portável); a sintaxe é só esmaecida, exceto marcadores de lista, desenhados como bolinha/checkbox.
- Sem CI/CD (nada de GitHub Actions): testes e releases rodam localmente, com `scripts/test.sh` e `scripts/release.sh`.
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
- `bringAllToFront()` faz as notas subirem com fade (`NoteWindowController.rise`). Animar o frame dispara `windowDidMove`, por isso `isRising` ignora esses movimentos: senão, só mostrar as notas salvaria posições intermediárias e mudaria o `updatedAt`.
- O ⌘Q chama `AppDelegate.quitOrHide`, que olha `MainMenu.quitKeyHides`. Não recuse `terminate` em `applicationShouldTerminate`: logout e desligar o Mac mandam o app sair por ali. O painel da aba tem `canHide = false` para continuar aparecendo com as notas escondidas, e `bringAllToFront`/`createNote` chamam `NSApp.unhide`.
- `note.frame` é a **casa** da nota. `frameDidChange` só grava posição nova quando o mouse está pressionado (arrastar, redimensionar) ou quando a janela continua sobre a casa. Mover sem mouse para longe dela é o macOS ou `placeNotesOnScreens` abrindo espaço para um monitor que saiu, e aí só o tamanho é gravado. `placeNotesOnScreens` roda ao abrir e em `applicationDidChangeScreenParameters`.
- `HotKey`: todo handler Carbon recebe todo atalho apertado, então cada instância tem um id e devolve `eventNotHandledErr` para os dos outros.
- Recolher desativa `bodyBottom` e trava a altura com `minSize`/`maxSize`; `expandedHeight` guarda a altura para restaurar.
- O salvamento tem debounce de 0,4 s. `close()` cancela o save pendente antes de excluir (senão a nota "ressuscita"). SIGTERM vira `NSApp.terminate` para salvar o pendente (os scripts usam `pkill`).
- Se o app abriu no login (Apple Event `keyAELaunchedAsLogInItem`), ele não cria nota nem rouba o foco.
- A saída do build fica em `build.noindex/`, não `build/`: o sufixo `.noindex` impede o Spotlight de mostrar um segundo "Notinhas" ao lado do de `/Applications`.

## Verificando uma mudança

Este ambiente não tem Xcode, e o terminal não tem permissão de Gravação de Tela nem de Acessibilidade: não dá para tirar print nem clicar na UI.

1. `./scripts/test.sh` para a lógica.
2. `./scripts/screenshots.sh` e **olhe** os PNGs em `docs/images/` para qualquer mudança visual. Para cenas novas, edite `Snapshot.swift`.
3. `./scripts/install-dev.sh` e confira o comportamento com `pgrep -x Notinhas`, `lsappinfo info -only name "$(lsappinfo front)"` (app da frente), `ls ~/Library/Application\ Support/Notinhas/notes` e `sfltool dumpbtm | grep -A6 -i notinhas` (login item).
4. O que exige mãos humanas: digitar, ⌘B, Enter em lista, clicar no checkbox, arrastar, redimensionar, recolher, cor/opacidade, alfinete sobre outro app, ⌃⌥N e ⌃⌥M de outro app, aba do canto inferior direito, tirar e pôr o cabo de um monitor. Peça ao usuário para testar e diga isso explicitamente.

## Release e distribuição

Rode `./scripts/release.sh` com tudo commitado: ele testa, calcula a versão com `scripts/next-version.sh`, builda, cria a tag `vX.Y.Z` e publica a GitHub Release com `Notinhas.zip` e os títulos dos commits desde a tag anterior como notas. A versão sobe o patch; `[minor]` ou `[major]` no título (primeira linha) de um commit desde a última tag sobe essa parte. Para escolher na hora: `./scripts/release.sh minor "notas"`. O projeto não tem CI/CD (decisão do dono): release é sempre local.

A tag é a fonte da versão: **não** edite `CFBundleShortVersionString` no `Info.plist` (é placeholder). O `build-app.sh` grava `$VERSION` (ou a última tag) e o número do build (quantidade de commits) no app.

O app é assinado ad-hoc e **não é notarizado** (exigiria Apple Developer ID, US$ 99/ano). Por isso o `install.sh` remove o atributo de quarentena, e o README explica o caminho manual pelo Gatekeeper. Para notarizar no futuro: `codesign` com Developer ID + `xcrun notarytool` (que precisa do Xcode).

## Referências

- [NSTextStorageDelegate](https://developer.apple.com/documentation/appkit/nstextstoragedelegate) · [NSLayoutManager](https://developer.apple.com/documentation/appkit/nslayoutmanager) · [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow) (níveis e `collectionBehavior`) · [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) (login item)
- [Swift Testing](https://developer.apple.com/documentation/testing) · [Swift Package Manager](https://www.swift.org/documentation/package-manager/)
- [Notarização](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Abrir app de desenvolvedor não identificado](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
- [CommonMark](https://spec.commonmark.org/) (referência da sintaxe; o estilizador cobre um subconjunto)
