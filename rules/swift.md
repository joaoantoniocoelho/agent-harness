# Swift (iOS/macOS, Xcode)

> Em repo existente, as convenções e configs do repo prevalecem. Os **defaults** abaixo valem para projetos novos.

## Defaults de projeto novo
- Projeto Xcode; build e testes via `xcodebuild`.
- **SwiftLint** (`--strict`) e **swift-format** (`swift format lint --strict`).
- Configs base: `~/Developer/agent-harness/templates/lint/swift/`.
- **Swift 6** com strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`).

## Arquitetura
- **SwiftUI** + **Observation** (`@Observable`); não usar `ObservableObject`/`@Published` em código novo.
- Estado de UI no `@MainActor`; trabalho pesado fora da main via `async`/`await` e actors.
- Sem `DispatchQueue`/completion handlers em código novo; use Swift Concurrency.
- Organização por feature (`Features/<Feature>/{Views,Models,Services}`).

## Segurança de tipos
- Sem force unwrap (`!`) nem force cast (`as!`). Use `guard let` e early return.
- `struct` e `let` por padrão; `class` só quando precisar de identidade/referência.
- Erros esperados com `throws` tipado ou `Result`, seguindo o repo.

## Testes
- Swift Testing (`@Test`, `#expect`) em código novo; XCTest se o repo já usa.
- Não desabilite testes (`.disabled`, `XCTSkip`) sem aprovação.
