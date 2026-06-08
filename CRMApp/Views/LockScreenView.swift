// MARK: - LockScreenView.swift
// 锁屏界面 — Face ID 自动触发 + PIN 手动输入

import SwiftUI

struct LockScreenView: View {

    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var store: DataStore

    @State private var pinInput: String = ""
    @State private var showPINEntry = false

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color(.systemIndigo), Color(.systemBlue).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {

                // App 图标占位
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .foregroundStyle(.white)

                Text("私域 CRM")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                // 错误提示
                if let error = lockManager.lastAuthError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Face ID 按钮（若设备支持且已开启）
                if store.settings.biometricLockEnabled {
                    Button {
                        lockManager.attemptUnlock()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                                .font(.title2)
                            Text(lockManager.biometricType + " 解锁")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: 240)
                        .padding()
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                }

                // PIN 输入区域
                if store.settings.appPINEnabled {
                    VStack(spacing: 16) {
                        if showPINEntry {
                            SecureField("输入密码", text: $pinInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                                .keyboardType(.numberPad)

                            Button("确认") {
                                lockManager.attemptUnlock(pin: pinInput)
                                pinInput = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.9))
                            .foregroundStyle(Color(.systemIndigo))
                        } else {
                            Button {
                                showPINEntry = true
                            } label: {
                                Text("使用密码")
                                    .foregroundStyle(.white.opacity(0.8))
                                    .underline()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        // App 首次进入时自动触发 Face ID
        .onAppear {
            if store.settings.biometricLockEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    lockManager.attemptUnlock()
                }
            }
        }
    }
}
