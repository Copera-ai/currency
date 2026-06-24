# Copera Currency

A native macOS menu-bar app showing live currency & crypto pair rates (Fawaz fiat + Coinbase crypto) — iStat-Menus style, one menu-bar item per tracked pair — with a converter popover and a Settings window. Apple Silicon (M1+), macOS 14+.

## Prerequisites

- macOS 14.0+ (Apple Silicon, arm64 only)
- Xcode 26+ (the full IDE, not just the Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

---

## Desenvolvimento

> Esta seção é a referência pessoal do dono do projeto. Se você vem de React Native + Node, leia o "Conceito-chave" primeiro — o fluxo é bem diferente.

### Conceito-chave (vindo de React Native / Node)

App nativo é **compilado** e **não tem hot reload**. O app que está rodando continua executando o **código antigo** até você **parar e rodar de novo** (⌘R no Xcode). Salvar o arquivo `.swift` não muda nada no app que já está aberto.

- Não é como **Fast Refresh** do React Native (que recarrega a tela ao salvar).
- Não é como **nodemon** do Node (que reinicia o processo ao salvar).
- O ciclo aqui é: **editar → parar → buildar → rodar de novo**.

A boa notícia: build incremental é rápido, então o ciclo Stop → ⌘R leva poucos segundos depois do primeiro build.

> Existe uma exceção para iterar **só o visual**: o **Canvas / `#Preview`** do Xcode (veja mais abaixo). Esse é o mais perto de um "hot reload" que você tem aqui — mas só pra renderizar uma view isolada, não pra rodar o app inteiro.

### Xcode é a ferramenta principal

O **Xcode** é onde você compila, roda, debuga e faz preview visual. É o equivalente do "tudo em um" aqui.

Você **pode** editar arquivos `.swift` no VS Code / Cursor (e é confortável vindo de RN/Node), mas **build, run e debug são no Xcode**. Na prática, muita gente edita no editor que prefere e mantém o Xcode aberto só pra dar ⌘R e ver os logs.

### Abrir o projeto

```bash
cd /Users/christiancuri/workspace/copera/copera-currency
open CoperaCurrency.xcodeproj
```

Se o `CoperaCurrency.xcodeproj` **não existir** (ou você adicionou/removeu arquivos), gere ele antes:

```bash
xcodegen generate
```

O `.xcodeproj` é **gerado** a partir do `project.yml` e não é versionado (gitignored) — por isso pode não estar lá num clone novo.

### Rodar (⌘R)

No Xcode, na barra de cima:

1. Confira que o **scheme** selecionado é **CoperaCurrency**.
2. Confira que o **destino** é **My Mac**.
3. Aperte **⌘R** (Build + Run).

O app **aparece na barra de menu** (canto superior direito da tela), perto do relógio. Ele **não tem ícone no Dock** e **não abre janela** ao iniciar — isso é de propósito: é um app de barra de menu (menu-bar app). Clique no item da barra pra abrir o popover.

### Parar (⌘.)

Pare com **⌘.** ou o botão **⏹ Stop** no Xcode.

> AVISO IMPORTANTE: se você não parar pelo Stop e rodar de novo, fica uma **instância antiga** ainda viva na barra de menu — e você acaba olhando pra "versão velha" achando que sua mudança não funcionou. Sempre **Stop antes de rodar de novo**.

Pra matar qualquer instância presa na barra de menu:

```bash
killall "Copera Currency"
```

### O ciclo do dia a dia

```
mudou código  →  Stop (⌘.)  →  ⌘R  →  testa  →  repete
```

Build incremental é rápido, então esse loop é curto.

### Logs e debug

- **`⌘⇧Y`** abre a **Debug Area** (o console). Tudo que você `print(...)` no Swift aparece aí.
- Clique na **margem esquerda** de uma linha de código pra colocar um **breakpoint**. Quando a execução chegar nele, o app pausa e você consegue **inspecionar as variáveis** na Debug Area.

### Rodar os testes

No Xcode: **⌘U**.

Ou pela linha de comando:

```bash
xcodebuild test -project CoperaCurrency.xcodeproj -scheme CoperaCurrency -destination 'platform=macOS,arch=arm64'
```

### `#Preview` / Canvas — o "hot reload" do visual

O Xcode tem o **Canvas**: você abre um arquivo de view e ele mostra a view **renderizada ao vivo**, atualizando **enquanto você digita**, **sem rodar o app inteiro**. É o recurso mais parecido com hot reload que existe aqui — ótimo pra iterar layout, cores e espaçamentos rápido.

- Atalho pra mostrar/esconder: **Editor → Canvas** (**⌥⌘↩**).
- Pra funcionar, a view precisa de um bloco **`#Preview { ... }`** com dados de exemplo. É um trecho que diz ao Xcode como instanciar a view isolada.

Exemplo genérico de como é um `#Preview`:

```swift
#Preview {
    MinhaView(/* dados de exemplo */)
}
```

> No momento as views **ainda não têm** blocos `#Preview`. Eles podem ser adicionados por view conforme você quiser iterar o visual no Canvas (um `#Preview` por arquivo de view). _Não precisa adicionar agora — isto é só o conceito._

### Build pela linha de comando (alternativa ao Xcode)

Dá pra buildar e abrir o app sem o Xcode:

```bash
xcodebuild -project CoperaCurrency.xcodeproj -scheme CoperaCurrency -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Copera Currency.app"
```

A pasta `build/` é descartável (gitignored). No dia a dia, o jeito recomendado é rodar pelo **Xcode com ⌘R** — você ganha logs, breakpoints e o ciclo Stop/Run integrado.

### XcodeGen (de onde vem o `.xcodeproj`)

O `CoperaCurrency.xcodeproj` é **gerado** a partir do `project.yml` (e é gitignored). Você normalmente **não edita** o `.xcodeproj` na mão.

- Editar arquivos `.swift` **já existentes** e dar **⌘R** funciona direto, sem regenerar nada.
- Só rode `xcodegen generate` quando você **adicionar ou remover arquivos**, ou **mudar build settings** no `project.yml`.

```bash
xcodegen generate
```

Os arquivos `.swift` são pegos por globbing da pasta `CoperaCurrency/`, então arquivo novo só precisa de um `xcodegen generate` pra entrar no projeto.

### Mapa das pastas (`CoperaCurrency/`)

```
CoperaCurrency/
  App/           Entrada do app + AppDelegate
  MenuBar/       Itens da barra de menu + controller do popover
  UI/
    Popover/     PopoverView (o conversor que abre ao clicar)
    Settings/    SettingsRoot + as 4 abas
  Components/    Botões / toggles / badges reutilizáveis
  Theme/         Theme.swift = todas as cores (claro/escuro)
  Models/        Modelos de moeda / par / cotação
  Networking/    Providers de cotação (Fawaz fiat, Coinbase crypto)
  Store/         Dados e lógica — RatesStore.swift é o "cérebro"
```

Bons arquivos pra começar a mexer **no visual**:

- `CoperaCurrency/UI/Popover/PopoverView.swift`
- `CoperaCurrency/UI/Settings/Settings*Tab.swift`
- `CoperaCurrency/Theme/Theme.swift`

### Assinatura / distribuição

Hoje o app roda como **build de desenvolvimento** (não assinado para distribuição). Assinatura **Developer ID** + **notarização** + **auto-update (Sparkle)** virão numa fase posterior.

---

## Referência rápida (atalhos do Xcode)

| Ação | Atalho |
| --- | --- |
| Build + Run | ⌘R |
| Stop | ⌘. |
| Rodar testes | ⌘U |
| Debug Area (console) | ⌘⇧Y |
| Mostrar/esconder Canvas | ⌥⌘↩ |

## Project facts

- **Scheme:** `CoperaCurrency`
- **Product name:** `Copera Currency`
- **Bundle id:** `ai.copera.currency`
- **Deployment target:** macOS 14.0 (arm64 only)
