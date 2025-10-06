// ASM-F Layer12 V1.0

import SwiftUI
import Combine

// 1. 汎用的な状態管理
/// ジェネリックな読み込み状態。アプリ全体で共通利用。
public enum LoadState<Value>: Sendable {
    case idle
    case loading
    case success(Value)
    case failure(Error)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// 2. 共通サービス層: SharedServiceProtocol
/// Sendable 準拠、async throws で Swift 6 並行性対応。
public protocol AuthServiceProtocol: Sendable {
    func isAuthenticated() async throws -> Bool
    func login() async throws
    func logout() async throws
}

// 3. 共通サービス実装: SharedService
/// サンプル実装。実サービス置換容易に。
public struct AuthService: AuthServiceProtocol {
    public init() {}

    public func isAuthenticated() async throws -> Bool {
        // TODO: 実装に置換（Keychain/Server など）
        return false
    }

    public func login() async throws {
        // TODO: 実装に置換
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    public func logout() async throws {
        // TODO: 実装に置換
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}

// 4. 共通マネージャー層
/// actor で排他、AsyncStream で配信。continuation 管理を厳密化。
public actor AuthManager {
    public typealias State = LoadState<Bool>

    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: AuthServiceProtocol

    public init(service: AuthServiceProtocol) {
        self.service = service
        // init 中は actor 隔離されていないため、actor-isolated メソッド呼び出し禁止。
        // ここでは非同期開始をしない。呼び出し側が start() する。
    }

    // 変更点: 起動時に認証状態を流すための明示的 start メソッド
    public func start() async {
        await refreshAuthStatus()
    }

    public func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { [weakSelf = self] continuation in
            // actor 内だが、AsyncStream クロージャは @Sendable 文脈。循環参照/終了処理に注意。
            Task { [weak weakSelf] in
                guard let self = weakSelf else { return }
                await self.addContinuation(id: id, continuation: continuation)
            }
        }
        return (id, stream)
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<State>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentState)
        continuation.onTermination = { [weakSelf = self] _ in
            Task { [weak weakSelf] in
                guard let self = weakSelf else { return }
                await self.removeContinuation(id: id)
            }
        }
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

    public func refreshAuthStatus() async {
        yieldToAll(.loading)
        do {
            let ok = try await service.isAuthenticated()
            yieldToAll(.success(ok))
        } catch {
            yieldToAll(.failure(error))
        }
    }

    public func login() async {
        yieldToAll(.loading)
        do {
            try await service.login()
            yieldToAll(.success(true))
        } catch {
            yieldToAll(.failure(error))
        }
    }

    public func logout() async {
        yieldToAll(.loading)
        do {
            try await service.logout()
            yieldToAll(.success(false))
        } catch {
            yieldToAll(.failure(error))
        }
    }
}

// 5. 共通DIYコンテナ
/// @MainActor で UI スレッド初期化安全性を担保。
/// init 中に actor メソッドを呼ばず、作成後に Task で start() を指示。
@MainActor
public final class SharedDependencies {
    public static let shared = SharedDependencies(authService: AuthService())

    public let authManager: AuthManager

    private init(authService: AuthServiceProtocol) {
        self.authManager = AuthManager(service: authService)
        Task { await authManager.start() } // 初期状態配信を開始
    }

    // テスト/プレビュー用
    public static func mock(authService: AuthServiceProtocol) -> SharedDependencies {
        SharedDependencies(authService: authService)
    }
}


import Foundation
import SwiftUI
import Combine

// 6. アプリ固有サービス層
public protocol StringServiceProtocol: Sendable {
    func fetchString() async throws -> String
}

// 7. アプリ固有サービス実装
public struct StringService: StringServiceProtocol {
    public init() {}
    public func fetchString() async throws -> String {
        try await Task.sleep(nanoseconds: 600_000_000)
        return "こんにちは、ASM-Fの世界！"
    }
}

// 8. アプリ固有マネージャー層
public actor StringManager {
    public typealias State = LoadState<String>

    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: StringServiceProtocol

    public init(service: StringServiceProtocol) {
        self.service = service
    }

    public func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { [weakSelf = self] continuation in
            Task { [weak weakSelf] in
                guard let self = weakSelf else { return }
                await self.addContinuation(id: id, continuation: continuation)
            }
        }
        return (id, stream)
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<State>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentState)
        continuation.onTermination = { [weakSelf = self] _ in
            Task { [weak weakSelf] in
                guard let self = weakSelf else { return }
                await self.removeContinuation(id: id)
            }
        }
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

    public func fetchString() async {
        yieldToAll(.loading)
        do {
            let value = try await service.fetchString()
            yieldToAll(.success(value))
        } catch {
            yieldToAll(.failure(error))
        }
    }
}

// 9. アプリ固有UI層ViewModel層
/// init 中で actor-isolated メソッドを呼ばず、startObserving() は自分自身(@MainActor)のメソッドなのでOK。
/// strict concurrency: UI 更新は @MainActor 上で実行。
@MainActor
public final class StringViewModel: ObservableObject {
    @Published public private(set) var displayString: String = "Press the button to fetch string."
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isAuthenticated: Bool = false

    private let stringManager: StringManager
    private let authManager: AuthManager
    private var tasks: [Task<Void, Never>] = []

    public init(stringManager: StringManager, authManager: AuthManager) {
        self.stringManager = stringManager
        self.authManager = authManager
        startObserving() // self は @MainActor 上。actor 呼び出しは Task 内で await。
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    private func startObserving() {
        // String stream
        tasks.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await self.stringManager.createStream()
            _ = id // id を保持したい場合はプロパティを追加
            for await state in stream {
                if Task.isCancelled { break }
                await self.updateStringUI(with: state)
            }
        })

        // Auth stream
        tasks.append(Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await self.authManager.createStream()
            _ = id
            for await state in stream {
                if Task.isCancelled { break }
                await self.updateAuthUI(with: state)
            }
        })
    }

    private func updateStringUI(with state: LoadState<String>) async {
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

    private func updateAuthUI(with state: LoadState<Bool>) async {
        switch state {
        case .idle:
            // 初期は未知、UI 表示上は未認証扱いでも可
            isAuthenticated = false
        case .loading:
            // ローディング中の見せ方はアプリ要件で調整
            break
        case .success(let ok):
            isAuthenticated = ok
        case .failure:
            isAuthenticated = false
        }
    }

    private func mapErrorToMessage(_ error: Error) -> String {
        if error is CancellationError { return "処理がキャンセルされました" }
        return "データの取得に失敗しました: \(error.localizedDescription)"
    }

    public func fetchString() {
        Task { await stringManager.fetchString() }
    }

    public func login() {
        Task { await authManager.login() }
    }

    public func logout() {
        Task { await authManager.logout() }
    }
}

import SwiftUI

// 10. アプリView層
///  ViewModel は @StateObject。init で渡し、_viewModel = StateObject(wrappedValue:) で初期化。
/// Text の文字列補間は \\ を使わない（エスケープ不具合回避）。
public struct ContentView: View {
    @StateObject private var viewModel: StringViewModel

    public init(viewModel: StringViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("認証状態: \(viewModel.isAuthenticated ? "認証済み" : "未認証")")
                .font(.headline)
                .foregroundColor(viewModel.isAuthenticated ? .green : .red)

            Group {
                if viewModel.isLoading {
                    ProgressView().scaleEffect(1.4)
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                } else {
                    Text(viewModel.displayString)
                        .font(.title2)
                        .padding(.vertical, 4)
                }
            }

            HStack {
                Button("Fetch String") { viewModel.fetchString() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)

                if viewModel.isAuthenticated {
                    Button("Logout") { viewModel.logout() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Login") { viewModel.login() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .navigationTitle("ASM-F Example")
    }
}

import Foundation

// 11. アプリ固有DIコンテナ
/// App 固有 Manager と Shared を束ね、ViewModel の生成専用メソッドを提供。
@MainActor
public final class AppDependencies {
    public let stringManager: StringManager
    public let shared: SharedDependencies

    public init() {
        self.stringManager = StringManager(service: StringService())
        self.shared = SharedDependencies.shared
    }

    public func makeStringViewModel() -> StringViewModel {
        StringViewModel(
            stringManager: stringManager,
            authManager: shared.authManager
        )
    }
}

import SwiftUI

// 12. エントリーポイント
@main
struct StringApp: App {
    // 変更点: App 起動時に依存を構築し、ViewModel を注入
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(viewModel: dependencies.makeStringViewModel())
            }
        }
    }
}

