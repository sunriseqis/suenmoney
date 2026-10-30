//
//  LoginView.swift
//  SuenMoney
//
//  登录页。
//
//  与 Web 一致的三件事：
//    1. 服务器地址只在这里出现（多地址 + 顺序探活 + 4s 快失败）。
//    2. 错误按类型说人话：口令错就说口令错，别把 401 说成「网络不好」。
//    3. 只保留**一个**服务端输入口；多地址由用户在设置页自己增删（U11）。
//
//  ⚠ 不做「首次初始化」（U17）：建账号是 Web 的职责，客户端只登录。
//

import SwiftUI

public struct LoginView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthStore.self) private var auth

    @State private var username: String = ""
    @State private var password: String = ""
    /// 登录页只保留**一个**服务端输入口
    @State private var serverUrl: String = ""
    /// 连通状态："" 未测 / "ok" 通 / "bad" 不通
    @State private var probeState: String = ""
    @State private var probeText: String = ""
    @State private var errorText: String = ""
    @State private var busy: Bool = false

    @FocusState private var focus: Field?
    private enum Field { case username, password, server }

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                brandBlock
                cardHead
                inputs
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(css: tokens.danger))
                }
                loginButton
                Divider().overlay(Color(css: tokens.line))
                serverBlock
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(css: tokens.bg).ignoresSafeArea())
        .onAppear {
            serverUrl = ServerConfig.shared.baseUrl
        }
    }

    // MARK: 品牌块（Web LoginView.vue:113-119）：徽标 56 + 名称 + 英文副标

    private var brandBlock: some View {
        VStack(spacing: 8) {
            BrandMark(56)
            Text("SuenMoney")
                .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                .foregroundStyle(Color(css: tokens.ink))
            Text("FAMILY LEDGER · 单账本")
                .font(.custom(fontMonoOf(), size: 9.5))
                .tracking(1.6)
                .foregroundStyle(Color(css: tokens.ink3))
        }
        .frame(maxWidth: .infinity)
    }

    /// 「登录」标题**水平居中**（鸿蒙 Column 默认 HorizontalAlign.Center），
    /// 下面那句说明才是左对齐 —— 之前两行都左对齐，与基准版式不同。
    private var cardHead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("登录")
                .font(.custom(fontBodyOf(isCyber), size: 12))
                .foregroundStyle(Color(css: tokens.ink3))
                .frame(maxWidth: .infinity)
            Text("用你的账号进入账本。")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(css: tokens.ink3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputs: some View {
        VStack(spacing: 10) {
            fieldBox(focused: focus == .username) {
                TextField("登录名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(css: tokens.ink))
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .accessibilityIdentifier("login.username")
            }
            fieldBox(focused: focus == .password) {
                SecureField("口令", text: $password)
                    .focused($focus, equals: .password)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(css: tokens.ink))
                    .submitLabel(.go)
                    .onSubmit {
                        focus = nil
                        Task { await doLogin() }
                    }
                    .accessibilityIdentifier("login.password")
            }
        }
    }

    /// 输入框：cyber 用 surface2 底 + 1.5 描边；**聚焦时 2px #5DB8FF 焦点环**（鸿蒙 R35）。
    /// 之前只有光标、没有描边反馈，外接键盘/自动化时完全看不出焦点在哪。
    private func fieldBox<Content: View>(focused: Bool,
                                         @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                    .stroke(Color(css: focused ? focusRing : outlineStrongOf(isCyber)),
                            lineWidth: focused ? 2 : fieldBorderWOf(tokens.borderW, isCyber))
            )
    }

    private var loginButton: some View {
        Button {
            Task { await doLogin() }
        } label: {
            Text(busy ? "登录中…" : "登录")
                .font(.system(size: 16))
                .foregroundStyle(Color(css: tokens.accentInk))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(css: tokens.accent))
                // 鸿蒙 Button 默认是 ButtonType.Capsule（44 高即 22 圆角），
                // 不是 14 圆角矩形 —— 主 CTA 形状是首屏最显眼的差异之一。
                .clipShape(Capsule())
                .opacity(busy ? 0.4 : 1)
        }
        .disabled(busy)
        .accessibilityIdentifier("login.submit")
    }

    // MARK: 服务端（只保留一个输入口）

    private var serverBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("服务端")
                .font(.system(size: 11))
                .foregroundStyle(Color(css: tokens.ink3))

            HStack(spacing: 8) {
                // 连通指示：通=绿、不通=红、未测=灰
                Circle()
                    .fill(Color(css: probeState == "ok"
                                 ? tokens.ok
                                 : (probeState == "bad" ? tokens.danger : tokens.ink3)))
                    .frame(width: 8, height: 8)

                TextField("http://主机:端口", text: $serverUrl)
                    .font(.custom(fontMonoOf(), size: 12.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focus, equals: .server)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Color(css: fieldBgOf(tokens.surface2, tokens.surface3, isCyber)))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                            .stroke(Color(css: tokens.line2), lineWidth: isCyber ? 1.5 : tokens.borderW)
                    )

                smallButton("测试") {
                    Task { await testServer() }
                }
                smallButton("保存") {
                    Task { await saveServer() }
                }
            }

            if !probeText.isEmpty {
                Text(probeText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
        }
    }

    private func smallButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(css: tokens.ink2))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color(css: tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                        .stroke(Color(css: outlineStrongOf(isCyber)), lineWidth: fieldBorderWOf(tokens.borderW, isCyber))
                )
        }
    }

    // MARK: 动作

    private var filledServer: String {
        serverUrl.trimmingCharacters(in: .whitespaces)
    }

    /// 保存这一个地址（登录前手填的地址，作为候选列表首项）
    private func saveServer() async {
        let url = filledServer
        guard !url.isEmpty else { return }
        ServerConfig.shared.setServers([url], active: url)
        probeText = "已保存"
    }

    /// 探活这一个地址，点亮连通指示
    private func testServer() async {
        let url = filledServer
        guard !url.isEmpty else {
            probeText = "请先填地址"
            return
        }
        let r = await ServerRouter.probe(url)
        probeState = r.ok ? "ok" : "bad"
        probeText = r.ok ? "地址可用" : "连不上这个地址"
    }

    /// 登录：先选路（4s 快失败），再登录
    private func doLogin() async {
        errorText = ""
        guard !username.isEmpty, !password.isEmpty else {
            errorText = "请填写登录名与口令"
            return
        }
        let url = filledServer
        guard !url.isEmpty else {
            errorText = "请填写服务端地址"
            return
        }
        busy = true
        defer { busy = false }

        // 登录前把地址落库（作为候选列表首项），再用它选路
        ServerConfig.shared.setServers([url], active: url)
        let chosen = await ServerRouter.choose([url])
        guard !chosen.isEmpty else {
            errorText = "所有服务器地址都连不上"
            return
        }

        focus = nil
        do {
            try await auth.login(username: username, password: password)
            // 登录成功后立刻补一次同步（离线账在别的设备上要先落本地）
            Task { _ = await SyncEngine.shared.syncNow() }
        } catch let err as ApiError {
            switch err.kind {
            case .unauthorized:
                errorText = "登录名或口令不对"
            case .network:
                errorText = "连不上服务端（网络或地址有问题）"
            default:
                errorText = err.message.isEmpty ? "登录失败" : err.message
            }
        } catch {
            errorText = "登录失败"
        }
    }
}
