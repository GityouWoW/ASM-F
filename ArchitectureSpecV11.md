# ASM-F アーキテクチャ仕様書（清書）

[バージョン] ASM-F Layer12 v1.1  
[最終更新] 2025-10-10

## 概要
ASM-F (ActorStream MVVM with Factories & SharedDependencies) は、Swift 6 の並行性機能を活用した 12 層アーキテクチャです。actor と AsyncStream による状態管理、DI コンテナによる依存性注入、共有依存関係の効率的な管理を特徴とします。

## レイヤー構造（12層）

### Layer 1: 汎用的な状態管理 (LoadState)
役割: アプリ全体で利用される、データ読み込み状態を表現する汎用 Enum

enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

特徴:
- ジェネリック型で任意のデータ型に対応
- 全ての Manager で統一的に使用
- ViewModel での UI 状態管理を簡潔にする

---

### Layer 2: 共通サービス層 (Shared Service Protocols)
役割: 複数アプリで再利用可能な共通機能のプロトコル定義

protocol AuthServiceProtocol: Sendable {
    func isAuthenticated() async throws -> Bool
    func login() async throws
}

設計原則:
- Sendable 準拠必須（Swift 6 並行性対応）
- async throws で非同期エラー処理
- テスト容易性を考慮したプロトコル駆動設計
例: AuthService, BillingService, AdService, AnalyticsService

---

### Layer 3: 共通サービス実装 (Shared Service Implementations)
役割: 共通サービスプロトコルの具体的な実装

struct AuthService: AuthServiceProtocol {
    func isAuthenticated() async throws -> Bool {
        // 実装
    }
    func login() async throws {
        // 実装
    }
}

設計原則:
- プロトコルに準拠した具体的な実装
- 外部 API、データベース、ファイルシステムとの通信を担当
- ビジネスロジックは含まず、純粋なデータ取得・操作のみ

---

### Layer 4: 共通マネージャー層 (Shared Managers - Actor + AsyncStream)
役割: 共通サービスを利用し、AsyncStream で状態を配信する actor

actor AuthManager {
    typealias State = LoadState<Bool>
    
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: AuthServiceProtocol
    
    init(service: AuthServiceProtocol) {
        self.service = service
    }
    
    func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { continuation in
            self.continuations[id] = continuation
            continuation.yield(currentState)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
        return (id, stream)
    }
    
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
    
    private func yieldToAll(_ state: State) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
    
    func login() async {
        yieldToAll(.loading)
        do {
            try await service.login()
            yieldToAll(.success(true))
        } catch {
            yieldToAll(.failure(error))
        }
    }

    // 例: 認証状態チェック
    func checkAuthStatus() async {
        yieldToAll(.loading)
        do {
            let ok = try await service.isAuthenticated()
            yieldToAll(.success(ok))
        } catch {
            yieldToAll(.failure(error))
        }
    }
}

設計原則:
- actor で状態の排他制御を保証
- AsyncStream で複数の ViewModel に状態を配信
- continuations 辞書でストリームのライフサイクル管理
- yieldToAll で全リスナーに一斉配信
- init 中に actor 隔離されたメソッド呼び出しを行わない（Swift 6 制約）

---

### Layer 5: 共通 DI コンテナ (SharedDependencies)
役割: アプリ間で共有される共通マネージャーのインスタンスを管理するシングルトン

@MainActor
final class SharedDependencies {
    static let shared = SharedDependencies(authService: AuthService())
    
    let authManager: AuthManager
    // 他の共通マネージャー（BillingManager, AdManager など）
    
    private init(authService: AuthServiceProtocol) {
        self.authManager = AuthManager(service: authService)
        // 注意: actor の init 内で actor-isolated メソッドを呼ばない
        Task {
            await authManager.checkAuthStatus()
        }
    }
    
    // テスト用のイニシャライザ
    static func mock(authService: AuthServiceProtocol) -> SharedDependencies {
        SharedDependencies(authService: authService)
    }
}

設計原則:
- シングルトンパターン（.shared）
- @MainActor で初期化を保証
- private init でインスタンス生成を制御
- テスト用の mock メソッド提供

---

### Layer 6: アプリ固有サービス層 (App-Specific Service Protocols)
役割: 特定のアプリに特化した機能のプロトコル定義

protocol StringServiceProtocol: Sendable {
    func fetchString() async throws -> String
}

設計原則:
- 共通サービス層と同じ設計原則
- アプリ固有のビジネスロジックに対応

---

### Layer 7: アプリ固有サービス実装 (App-Specific Service Implementations)
役割: アプリ固有サービスプロトコルの具体的な実装

struct StringService: StringServiceProtocol {
    func fetchString() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "こんにちは、ASM-Fの世界！"
    }
}

設計原則:
- 共通サービス実装と同じ設計原則
- アプリ固有のデータ取得・操作を実装

---

### Layer 8: アプリ固有マネージャー層 (App-Specific Managers - Actor + AsyncStream)
役割: アプリ固有サービスを利用し、AsyncStream で状態を配信する actor

actor StringManager {
    typealias State = LoadState<String>
    
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: StringServiceProtocol
    
    init(service: StringServiceProtocol) {
        self.service = service
    }
    
    func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { continuation in
            self.continuations[id] = continuation
            continuation.yield(currentState)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
        return (id, stream)
    }
    
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
    
    private func yieldToAll(_ state: State) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
    
    func fetchString() async {
        yieldToAll(.loading)
        do {
            let text = try await service.fetchString()
            yieldToAll(.success(text))
        } catch {
            yieldToAll(.failure(error))
        }
    }
}

設計原則:
- 共通マネージャー層と同じパターン
- アプリ固有の状態管理を担当

---

### Layer 9: アプリ固有 ViewModel 層 (@MainActor)
役割: View に表示するデータを管理し、Manager からの状態変化を @Published で View に通知する @MainActor クラス

@MainActor
final class StringViewModel: ObservableObject {
    @Published var displayString: String = "Press the button to fetch string."
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    
    private let stringManager: StringManager
    private let authManager: AuthManager
    private var stringStreamID: UUID?
    private var authStreamID: UUID?
    private var observeTask: [Task<Void, Never>] = []
    
    init(
        stringManager: StringManager,
        authManager: AuthManager
    ) {
        self.stringManager = stringManager
        self.authManager = authManager
        startObserving()
    }
    
    deinit {
        observeTask.forEach { $0.cancel() }
    }
    
    private func startObserving() {
        // String stream
        observeTask.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await stringManager.createStream()
            self.stringStreamID = id
            for await state in stream {
                if Task.isCancelled { break }
                self.updateStringUI(with: state)
            }
        })
        
        // Auth stream
        observeTask.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await self.authManager.createStream()
            self.authStreamID = id
            for await state in stream {
                if Task.isCancelled { break }
                self.updateAuthUI(with: state)
            }
        })
    }
    
    private func updateStringUI(with state: LoadState<String>) {
        switch state {
        case .idle:
            isLoading = false
            errorMessage = nil
        case .loading:
            isLoading = true
            errorMessage = nil
        case .success(let value):
            isLoading = false
            displayString = value
            errorMessage = nil
        case .failure(let error):
            isLoading = false
            errorMessage = mapErrorToMessage(error)
        }
    }
    
    private func updateAuthUI(with state: LoadState<Bool>) {
        switch state {
        case .success(let value):
            isAuthenticated = value
        case .idle, .loading:
            // UI 要件に応じて必要なら反映
            break
        case .failure:
            isAuthenticated = false
        }
    }
    
    private func mapErrorToMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "処理がキャンセルされました"
        }
        return "データの取得に失敗しました: \(error.localizedDescription)"
    }
    
    func fetchString() {
        Task { await stringManager.fetchString() }
    }
}

設計原則:
- @MainActor で UI 更新の安全性を保証
- @Published で View への自動通知
- 複数の Manager を注入可能（アプリ固有 + 共有）
- Task で AsyncStream を監視
- deinit で必ず Task をキャンセル
- [weak self] でメモリリーク防止
- エラーハンドリングを mapErrorToMessage で統一

---

### Layer 10: アプリ固有 View 層
役割: SwiftUI の View で、ViewModel の @Published プロパティを監視し、UI を構築・更新する

struct ContentView: View {
    @StateObject private var viewModel: StringViewModel
    
    init(viewModel: StringViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("認証状態: \(viewModel.isAuthenticated ? "認証済み" : "未認証")")
                .font(.headline)
                .foregroundColor(viewModel.isAuthenticated ? .green : .red)
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else {
                Text(viewModel.displayString)
                    .font(.largeTitle)
                    .padding()
            }
            
            Button("Fetch String") {
                viewModel.fetchString()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .navigationBarTitle(Text("ASM-F Example"))
        .padding()
    }
}

設計原則:
- @StateObject で ViewModel を保持
- init(viewModel:) で受け取り、_viewModel = StateObject(wrappedValue:) で初期化
- UI 更新のみを担当、ビジネスロジックは持たない
- ViewModel の状態に応じた宣言的 UI 構築

---

### Layer 11: アプリ固有 DI コンテナ (AppDependencies - Factory)
役割: アプリ固有のマネージャーや ViewModel の生成を管理し、SharedDependencies も利用する

@MainActor
final class AppDependencies {
    let stringManager: StringManager
    let shared: SharedDependencies
    
    init() {
        self.stringManager = StringManager(service: StringService())
        self.shared = SharedDependencies.shared
    }
    
    // ViewModel を生成するファクトリーメソッド
    func makeStringViewModel() -> StringViewModel {
        StringViewModel(
            stringManager: stringManager,
            authManager: shared.authManager
        )
    }
}

設計原則:
- @MainActor で初期化を保証
- アプリ固有 Manager を保持
- SharedDependencies.shared を参照
- ファクトリーメソッド（makeXXXViewModel()）で ViewModel 生成
- 依存関係の注入を一元管理

---

### Layer 12: App Entry Point
役割: アプリケーションのエントリーポイント。AppDependencies を初期化し、ルート View に ViewModel を注入する

@main
struct StringApp: App {
    let dependencies = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(viewModel: dependencies.makeStringViewModel())
            }
        }
    }
}

設計原則:
- AppDependencies を生成
- View に ViewModel を注入: ContentView(viewModel: dependencies.makeStringViewModel())
- アプリ全体の依存関係グラフのルート

---

## 状態の流れ
Service → Manager → AsyncStream → ViewModel → @Published → View

---

## 重要な設計原則（要点）
- LoadState は必ず実装
- Service 層は必ず実装
- Swift 6 strict concurrency 準拠
- actor で状態の排他制御
- @MainActor で UI 更新の安全性
- actor 内で self の初期化順序に注意（init 中に actor-isolated メソッドを呼ばない）

---

## エラー処理
- CancellationError を含む全エラーを UI 層で適切に表示
- mapErrorToMessage でユーザー向けメッセージに変換
- エラー状態も LoadState で統一的に管理

---

## テスタビリティ
- Protocol 駆動設計
- DI コンテナでモック注入可能
- SharedDependencies.mock でテスト用インスタンス生成

---

## メモリ管理
- [weak self] でメモリリーク防止
- deinit で Task をキャンセル
- AsyncStream.onTermination でストリームのクリーンアップ

---

## 使用例（新機能追加の手順）
1. Protocol 定義 (Layer 6): NewFeatureServiceProtocol
2. Service 実装 (Layer 7): NewFeatureService
3. Manager 実装 (Layer 8): NewFeatureManager
4. AppDependencies に追加 (Layer 11): let newFeatureManager: NewFeatureManager
5. ViewModel 作成 (Layer 9): NewFeatureViewModel
6. ファクトリーメソッド追加 (Layer 11): func makeNewFeatureViewModel() -> NewFeatureViewModel
7. View 作成 (Layer 10): NewFeatureView
8. App Entry Point で使用 (Layer 12): NewFeatureView(viewModel: dependencies.makeNewFeatureViewModel())

共有機能を追加する場合は、Layer 2-5 を使用し、SharedDependencies に追加します。

---

## SwiftData
- ModelContext の扱い:
  - ViewModel が保持しない。ViewModel に都度引数で渡す
  - メイン UI 操作は @MainActor で行う
  - バックグラウンド処理は new ModelContext を生成

---

## よくあるエラー／注意点（生成時チェック）
- Text("\(Int(minutes))分") の文字列補間をエスケープしない（"\\(" にならない）
- ViewModel の初期化方法に注意（@StateObject のみで保持、@ObservedObject と混在させない）
- .onScrollGeometryChange の呼び出しで Missing arguments for parameters 'for', 'action' in call
- 'self' used in method call '' before all stored properties are initialized
- Swift 6 の strict concurrency checks
- Swift 6 では、actor の init 中は self がまだ actor に隔離されておらず、actor-isolated なメソッド呼び出し禁止
- Reference to generic type 'ScrollViewReader' requires arguments in <...>
- sendMessage の replyHandler を使う場合、受信側で didReceiveMessage:replyHandler: を必ず実装（未実装だと受信失敗）

次回このプロジェクトを生成・改修するときは、以下を必ず満たしてください(例:タイマーアプリ):

- タイマーのtickerタスクは Task キャンセルを厳密に尊重すること
  - ループは `while !Task.isCancelled`
  - `Task.sleep` は `do/catch` で `CancellationError` を受け、即 `break`
  - `stop`/`stopInternal` では `tickTask?.cancel()` 後に `await tickTask?.value` で終了を待機
- スナップショット保存の頻度を約1秒にスロットルすること
  - 毎tickや高頻度で UserDefaults へ書き込まない
  - 可能ならイベントドリブン（開始/一時停止/再開/終了/設定変更）も併用
- スリープ間隔（現在値）は変更しないこと（「2以外を実装」要求の厳守）
- 目的: 高CPU使用率の抑制（キャンセル後の高速スピン防止＋書き込み頻度削減）
- 既存のポモドーロ遷移/通知挙動は変更しない（後方互換を維持）
- Swift 6 strict concurrency に準拠。タイマー制御は actor で排他・直列化
- 必要に応じて、意図を示すコメント（キャンセル尊重・スロットリング理由）をコード内に付与

受け入れ基準:
- キャンセル後に ticker が回り続けない（Time Profilerでスピンが消える）
- スナップショット保存が1秒程度以下の頻度に抑制される
- スリープ間隔の数値は一切変更されていない
- 既存の通知・自動遷移仕様が保持される

   // PERMANENT NOTE:
            // - Do NOT use `while true` + `try? await Task.sleep(...)`. When the task is cancelled,
            //   `Task.sleep` throws CancellationError immediately; swallowing it causes a tight spin
            //   (100% CPU) and continuous allocations. Always check cancellation and break on error.
            // - Keep polling at ~1Hz. Sub-second polling forces constant re-layout and animation,
            //   increasing CPU usage and memory churn over time.
            // - Do NOT animate periodic state updates (avoid `withAnimation` here). Animate only on
            //   user-driven interactions. This prevents constant implicit animation transactions.

---

## 避けるべきアンチパターン
- 二重の状態管理: @StateObject と @ObservedObject の同時使用など
- 不適切な状態変更: onAppear での状態代入や ObservableObject 内での @ObservedObject 使用
- 過度な階層化: 不要な中間 ViewModel や複雑な依存関係チェーン

---

## 実装ガイダンス
- ObservableObject 間の関係: 別の ObservableObject 内での使用時の制限と回避（依存は Manager/Service 経由で）
- コード全体を提示する場合はじめにバージョンを付与

---

## 参考資料
- Swift 6 エラー診断（actor-isolated call）: https://docs.swift.org/compiler/documentation/diagnostics/actor-isolated-call/
- ASM-F GitHub: https://github.com/GityouWoW/ASM-F/tree/ASM-FLayer12v1
- エラー回避リスト: https://github.com/GityouWoW/AIPrompt/blob/main/errorAvoidance
