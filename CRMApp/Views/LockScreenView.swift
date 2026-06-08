// MARK: - LockScreenView.swift
// 锁屏界面 — Face ID 自动触发 + PIN 手动输入（iOS 15 兼容）

import SwiftUI

struct LockScreenView: View {

    @EnvironmentObject var lockManager: LockManager
    @EnvironmentObject var store: DataStore

    @State private var pinInput: String = ""
    @State private var showPINEntry = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemIndigo), Color(.systemBlue).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {

                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .foregroundColor(.white)

                Text("私域 CRM")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                if let error = lockManager.lastAuthError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if store.settings.biometricLockEnabled {
                    Button {
                        lockManager.attemptUnlock()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid").font(.title2)
                            Text(lockManager.biometricType + " 解锁").fontWeight(.semibold)
                        }
                        .frame(maxWidth: 240)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .foregroundColor(.white)
                    }
                }

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
                            .tint(Color.white.opacity(0.9))
                            .foregroundColor(Color(.systemIndigo))
                        } else {
                            Button {
                                showPINEntry = true
                            } label: {
                                // iOS 15 兼容：用 overlay underline 代替 .underline() modifier
                                Text("使用密码")
                                    .foregroundColor(.white.opacity(0.8))
                                    .overlay(
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(.white.opacity(0.8)),
                                        alignment: .bottom
                                    )
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if store.settings.biometricLockEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    lockManager.attemptUnlock()
                }
            }
        }
    }
}
