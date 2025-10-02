// Version: ASM-F Template 1.0
// Architecture: ASM-F (ActorStream MVVM with Factories & SharedDependencies)
import SwiftUI
import Combine

// MARK: - 1. 汎用的な状態管理（LoadState）
/// 任意の型に対応できる汎用的な読み込み状態
enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

// MARK: - 2. 共通サービス層（Shared Service Protocols）
/// 共通機能のプロトコル層
protocol AuthServiceProtocol: Sendable {
    func isAuthenticated() async throws -> Bool
    func login() async throws
}

// MARK: - 3. 共通サービス実装（Shared Service Implementations）
///認証サービスのダミー実装
struct AuthService: AuthServiceProtocol {
    func isAuthenticated() async throws -> Bool {
        // ダミー実装
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
        return true
    }
    
    func login() async throws {
        // 実際のログイン処理
        print("Logging in...")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
        print("Logged in successfully.")
    }
}

// MARK: - 4. 共通マネージャー層（Shared Managers - Actor + AsuncStream）
// 認証状態を管理する共通マネージャー
actor AuthManager {
    typealias State = LoadState<Bool> // 認証状態（true/false）
    
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    
    private let service: AuthServiceProtocol
    
    init(service: AuthServiceProtocol) {
        self.service = service
        // 初期状態を非同期で設定
//        Task { await checkAuthStatus() }
    }
    
    func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { continuation in
            self.continuations[id] = continuation
            continuation.yield(currentState) // 初期状態を即時配信
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
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
    
    func checkAuthStatus() async {
        currentState = .loading
        yieldToAll(currentState)
        do {
            let authenticated = try await service.isAuthenticated()
            currentState = .success(authenticated)
            yieldToAll(currentState)
        } catch {
            currentState = .failure(error)
            yieldToAll(currentState)
        }
    }
    
    func login() async {
        currentState = .loading
        yieldToAll(currentState)
        do {
            try await service.login()
            currentState = .success(true) // ログイン成功
            yieldToAll(currentState)
        } catch {
            currentState = .failure(error)
            yieldToAll(currentState)
        }
    }
}

// MARK: - 5. 共通IDコンテナ（SharedDependencies）
/// アプリ間で共有される依存関係を管理
@MainActor
final class SharedDependencies {
    static let shared = SharedDependencies(authService: AuthService())
    let authManager: AuthManager
//    lazy var authManager: AuthManager = AuthManager(
//        service: AuthService()
//    )
//     他の共通サービスやマネージャー（BillingManager, AdManagerなど）を追加
     private init(
        authService: AuthServiceProtocol
    ) {
        self.authManager = AuthManager(service: authService)
    }
        // テスト用のイニシャライザ
    static func mock(authService: AuthServiceProtocol) -> SharedDependencies {
        SharedDependencies(authService: authService)
    }
}

// MARK: - 6. アプリ固有サービス層（App-Specific Service Protocols）
protocol StringServiceProtocol: Sendable {
    func fetchString() async throws -> String
}

// MARK: - 7. アプリ固有サービス実装（App-Specific Service Implementations）
struct StringService: StringServiceProtocol {
    func fetchString() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
        return "こんにちは、ASM-Fの世界！"
    }
}

// MARK: - 8. アプリ固有マネージャー層（App-Specific Managers - Actor + AsyncStream）
actor StringManager {
    typealias State = LoadState<String>
    
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    
    private let service: StringServiceProtocol
    
//    init(service: StringServiceProtocol = StringService()) {
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
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
    
    func fetchString() async {
        currentState = .loading
        yieldToAll(currentState)
        do {
            let fetchedString = try await service.fetchString()
            currentState = .success(fetchedString)
            yieldToAll(currentState)
        } catch {
            currentState = .failure(error)
            yieldToAll(currentState)
        }
    }
}

// MARK: - 9. アプリ固有ViewModel層（App-Specific ViewModels - ObservableObject）
@MainActor
final class StringViewModel: ObservableObject {
    @Published var displayString: String = "Press the button to fetch string."
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    
    private let stringManager: StringManager
    private let authManager: AuthManager // 共通のAuthManager
    
    private var stringStreamID: UUID?
    private var authStreamID: UUID?
    private var observeTask: [Task<Void, Never>] = []
 
    init(stringManager: StringManager, authManager: AuthManager) {
        self.stringManager = stringManager
        self.authManager = authManager
        startObserving()
    }
    
    deinit {
        observeTask.forEach { $0.cancel() }
    }
    
    private func startObserving() {
        // StringManagerの状態を監視
        observeTask.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await self.stringManager.createStream()
            self.stringStreamID = id
            for await state in stream {
                if Task.isCancelled { break }
                self.updateStringUI(with: state)
            }
        })
            
        // AuthManagerの監視
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
        case .success(let str):
            isLoading = false
            displayString = str
            errorMessage = nil
            case .failure(let error):
            isLoading = false
            errorMessage = mapErrorToMessage(error)
        }
    }
    
    private func updateAuthUI(with state: LoadState<Bool>) {
        switch state {
        case .idle, .loading:
            // 認証状態の読み込み中は特に表示を変えない
            break
        case .success(let authenticated):
            isAuthenticated = authenticated
        case .failure(let error):
            print("Auth error: \(error)") // 認証エラーはログに出すなど
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
        Task {
            await stringManager.fetchString()
        }
    }
    
    func login() {
        Task {
            await authManager.login()
        }
    }
}

// MARK: - 10. アプリ固有View層（App-Specific Views - SwiftUI Views）

struct ContentView: View {
    @StateObject private var viewModel: StringViewModel
    
    init(viewModel: StringViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("認証状態: \(viewModel.isAuthenticated ? "認証済み" : "未認証")")
                .font(.headline)
                .foregroundStyle(viewModel.isAuthenticated ? .green : .red)
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
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
            
            Button("Login") {
                viewModel.login()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
        .navigationBarTitle(Text("ASM-F Example"))
        .padding()
    }
    
    // MARK: - 11. アプリ固有DIコンテナ(AppDependencis - Factory)
    /// アプリ固有の依存関係を管理しSharedDependenciesも利用
    @MainActor
    final class AppDependencies {
        // アプリ固有のManager
        let stringManager: StringManager
        
        // 共通の依存関係
        let shared: SharedDependencies
        
        init() {
            self.stringManager = StringManager(service: StringService())
            self.shared = SharedDependencies.shared
        }
        
        // ViewModelを生成するファクトリーメソッド
        func makeStringViewModel() -> StringViewModel {
            StringViewModel(
                stringManager: stringManager,
                authManager: shared.authManager // SharedDependenciesからAuthManagerを注入
            )
        }
    }
    
    // 他のビューモデルが必要になったらここに追加
    // func makeAnotherViewModel() -> AnotherViewModel { ...
    
    // MARK: - 12. App Entry Point (for SwiftUI App struct)
    @main
    struct StringApp: App {
        // アプリ固有のDIコンテナを生成
        //SharedDependenciesはAppDependencies内で自動的に.sharedが使われる
        let dependencies = AppDependencies()
        
        var body: some Scene {
            WindowGroup {
                NavigationStack {
                    // AppDependenciesからViewModelを生成してViewに注入
                    ContentView(viewModel: dependencies.makeStringViewModel())
                }
            }
        }
    }
}
