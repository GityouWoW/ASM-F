# ASM-F プロンプト

## 概要
ASM-F (ActorStream MVVM with Factories & SharedDependencies) は、Swift 6の並行性機能を活用した12層のアーキテクチャです。`actor`と`AsyncStream`による状態管理、DIコンテナによる依存性注入、共有依存関係の効率的な管理を特徴とします。

## レイヤー構造（12層）

### 1. 汎用的な状態管理 (LoadState)
**役割**: アプリ全体で利用される、データ読み込み状態を表現する汎用Enum

```swift
enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

特徴:
ジェネリック型で任意のデータ型に対応
全てのManagerで統一的に使用
ViewModelでのUI状態管理を簡潔にする

2. 共通サービス層 (Shared Service Protocols)
役割: 複数アプリで再利用可能な共通機能のプロトコル定義
swift

protocol AuthServiceProtocol: Sendable {
    func isAuthenticated() async throws -> Bool
    func login() async throws
}
設計原則:
Sendable準拠必須（Swift 6並行性対応）
async throwsで非同期エラー処理
テスト可能性を考慮したプロトコル駆動設計
例: AuthService, BillingService, AdService, AnalyticsService

3. 共通サービス実装 (Shared Service Implementations)
役割: 共通サービスプロトコルの具体的な実装
swift

struct AuthService: AuthServiceProtocol {
    func isAuthenticated() async throws -> Bool {
        // 実装
    }
    
    func login() async throws {
        // 実装
    }
}
設計原則:
プロトコルに準拠した具体的な実装
外部API、データベース、ファイルシステムとの通信を担当
ビジネスロジックは含まず、純粋なデータ取得・操作のみ

4. 共通マネージャー層 (Shared Managers - Actor + AsyncStream)
役割: 共通サービスを利用し、AsyncStreamで状態を配信するactor
swift

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
}
設計原則:
actorで状態の排他制御を保証
AsyncStreamで複数のViewModelに状態を配信
continuations辞書でストリームのライフサイクル管理
yieldToAllで全リスナーに一斉配信

5. 共通DIコンテナ (SharedDependencies)
役割: アプリ間で共有される共通マネージャーのインスタンスを管理するシングルトン
swift

@MainActor
final class SharedDependencies {
    static let shared = SharedDependencies(authService: AuthService())
    
    let authManager: AuthManager
    // 他の共通マネージャー（BillingManager, AdManagerなど）
    
    private init(authService: AuthServiceProtocol) {
        self.authManager = AuthManager(service: authService)
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
シングルトンパターン（.shared）
@MainActorで初期化を保証
private initでインスタンス生成を制御
テスト用のmockメソッド提供

6. アプリ固有サービス層 (App-Specific Service Protocols)
役割: 特定のアプリに特化した機能のプロトコル定義
swift

protocol StringServiceProtocol: Sendable {
    func fetchString() async throws -> String
}
設計原則:
共通サービス層と同じ設計原則
アプリ固有のビジネスロジックに対応

7. アプリ固有サービス実装 (App-Specific Service Implementations)
役割: アプリ固有サービスプロトコルの具体的な実装
swift

struct StringService: StringServiceProtocol {
    func fetchString() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "こんにちは、ASM-Fの世界！"
    }
}
設計原則:
共通サービス実装と同じ設計原則
アプリ固有のデータ取得・操作を実装

8. アプリ固有マネージャー層 (App-Specific Managers - Actor + AsyncStream)
役割: アプリ固有サービスを利用し、AsyncStreamで状態を配信するactor
swift

actor StringManager {
    typealias State = LoadState<String>
    
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: StringServiceProtocol
    
    // 共通マネージャー層と同じパターンで実装
}
設計原則:
共通マネージャー層と同じ設計原則
アプリ固有の状態管理を担当

9. アプリ固有ViewModel層 (@MainActor)
役割: Viewに表示するデータを管理し、Managerからの状態変化を@PublishedでViewに通知する@MainActorクラス
swift

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
        observeTask.forEach { \$0.cancel() }
    }
    
    private func startObserving() {
        observeTask.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await stringManager.createStream()
            self.stringStreamID = id
            for await state in stream {
                if Task.isCancelled { break }
                self.updateStringUI(with: state)
            }
        })
        
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
    
    private func mapErrorToMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "処理がキャンセルされました"
        }
        return "データの取得に失敗しました: \(error.localizedDescription)"
    }
    
    func fetchString() {
        Task {
            await stringManager.fetchString()
        }
    }
}
設計原則:
@MainActorでUI更新の安全性を保証
@PublishedでViewへの自動通知
複数のManagerを注入可能（アプリ固有 + 共有）
TaskでAsyncStreamを監視
deinitで必ずTaskをキャンセル
[weak self]でメモリリーク防止
エラーハンドリング: mapErrorToMessageでユーザー向けメッセージに変換
CancellationErrorを含む全エラーを適切に処理

10. アプリ固有View層
役割: SwiftUIのViewで、ViewModelの@Publishedプロパティを監視し、UIを構築・更新する
swift

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
@StateObjectでViewModelを保持
初期化: init(viewModel:)で受け取り、_viewModel = StateObject(wrappedValue:)で初期化
UI更新のみを担当、ビジネスロジックは持たない
ViewModelの状態に応じた宣言的UI構築

11. アプリ固有DIコンテナ (AppDependencies - Factory)
役割: アプリ固有のマネージャーやViewModelの生成を管理し、SharedDependenciesも利用する
swift

@MainActor
final class AppDependencies {
    let stringManager: StringManager
    let shared: SharedDependencies
    
    init() {
        self.stringManager = StringManager(service: StringService())
        self.shared = SharedDependencies.shared
    }
    
    // ViewModelを生成するファクトリーメソッド
    func makeStringViewModel() -> StringViewModel {
        StringViewModel(
            stringManager: stringManager,
            authManager: shared.authManager
        )
    }
}
設計原則:
@MainActorで初期化を保証
アプリ固有Managerを保持
SharedDependencies.sharedを参照
ファクトリーメソッド（makeXXXViewModel()）でViewModel生成
依存関係の注入を一元管理

12. App Entry Point
役割: アプリケーションのエントリーポイント。AppDependenciesを初期化し、ルートViewにViewModelを注入する
swift

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
AppDependenciesを生成
ViewにViewModelを注入: ContentView(viewModel: dependencies.makeStringViewModel())
アプリ全体の依存関係グラフのルート

状態の流れ

Service → Manager → AsyncStream → ViewModel → @Published → View
重要な設計原則

並行性
Swift 6 strict concurrency準拠
actorで状態の排他制御
@MainActorでUI更新の安全性
actor内でselfの初期化順序に注意
エラー処理
CancellationErrorを含む全エラーをUI層で適切に表示
mapErrorToMessageでユーザー向けメッセージに変換
エラー状態もLoadStateで統一的に管理
テスタビリティ
Protocol駆動設計
DIコンテナでモック注入可能
SharedDependencies.mockでテスト用インスタンス生成
メモリ管理
[weak self]でメモリリーク防止
deinitでTaskをキャンセル
onTerminationでストリームのクリーンアップ

使用例

新しい機能を追加する場合の手順:
Protocol定義 (Layer 6): NewFeatureServiceProtocol
Service実装 (Layer 7): NewFeatureService
Manager実装 (Layer 8): NewFeatureManager
AppDependenciesに追加 (Layer 11): let newFeatureManager: NewFeatureManager
ViewModel作成 (Layer 9): NewFeatureViewModel
ファクトリーメソッド追加 (Layer 11): func makeNewFeatureViewModel() -> NewFeatureViewModel
View作成 (Layer 10): NewFeatureView
App Entry Pointで使用 (Layer 12): NewFeatureView(viewModel: dependencies.makeNewFeatureViewModel())
共有機能を追加する場合は、Layer 2-5を使用し、SharedDependenciesに追加します。

# AIがコード生成時にチェック漏れを起こしたエラーリスト
https://github.com/GityouWoW/AIPrompt/blob/main/errorAvoidance



### 旧アーキテクチャプロンプト:
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

エラー参考: https://docs.swift.org/compiler/documentation/diagnostics/actor-isolated-call/
Type alias cannot be declared public because its underlying type uses an internal type
