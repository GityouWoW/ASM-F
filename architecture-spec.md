アーキテクチャプロンプト:
私は SwiftUI アプリを ASM-F (ActorStream MVVM with Factories & SharedDependencies) というアーキテクチャで構築しています。
基本構造: ActorStream MVVM (ASM)
actor + AsyncStream で状態管理
@MainActor ViewModel が @Published に反映
View は @StateObject で ViewModel を監視
Factory パターン:
各アプリごとに独立した AppDependencies を持つ
Service / Manager / ViewModel を生成して注入
SharedDependencies:
共通で使う認証、課金、広告、設定などをまとめる
各アプリの AppDependencies から注入して利用
方針:
中規模プロジェクトでも見通し良く拡張できる
テスト容易性（モック差し替え可能）を重視
Swift 6 の strict concurrency に準拠
