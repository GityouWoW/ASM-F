# ASM-F アーキテクチャ仕様（中規模・初期開発用）

私は SwiftUI アプリを **ASM-F (ActorStream MVVM with Factories & SharedDependencies)** というアーキテクチャで構築しています。

## 基本構造: ActorStream MVVM (ASM)
- **actor + AsyncStream** で状態管理
- **@MainActor ViewModel** が **@Published** に反映
- **View** は **@StateObject** で ViewModel を監視

## Factory パターン
- 各アプリごとに独立した **AppDependencies** を持つ
- Service / Manager / ViewModel を生成して注入

## SharedDependencies
- 共通で使う認証、課金、広告、設定などをまとめる
- 各アプリの AppDependencies から注入して利用

## 設計方針
- 中規模プロジェクトでも見通し良く拡張できる
- テスト容易性（モック差し替え可能）を重視
- Swift 6 の strict concurrency に準拠
- protocolも規模に応じて利用

## 参考
- エラー対応: https://docs.swift.org/compiler/documentation/diagnostics/actor-isolated-call/
- 詳細仕様: https://raw.githubusercontent.com/GityouWoW/ASM-F/1d0bc65ce4f819eed99c6b39f05504f79b2ef144/ASM-Fv1Architecture-spec.md
