// MARK: - LockManager.swift
// 生物识别 / PIN 密码锁管理（可在设置中自由开关）

import Foundation
import LocalAuthentication
import SwiftUI

// MARK: 锁定状态
enum LockState {
    case unlocked
    case locked
    case authenticating
}

// MARK: 锁管理器
class LockManager: ObservableObject {

    @Published var lockState: LockState = .locked
    @Published var lastAuthError: String?

    // 注入 settings 引用（避免重复读取）
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        // 若所有锁均关闭，直接解锁
        if !settings.biometricLockEnabled && !settings.appPINEnabled {
            lockState = .unlocked
        }
    }

    // MARK: 更新设置引用（设置页面修改后调用）
    func refresh(settings: AppSettings) {
        self.settings = settings
        if !settings.biometricLockEnabled && !settings.appPINEnabled {
            lockState = .unlocked
        }
    }

    // MARK: 尝试解锁（按优先级：Face ID → PIN）
    func attemptUnlock(pin: String? = nil) {
        lockState = .authenticating
        lastAuthError = nil

        // 若 Face ID 开启，优先走生物识别
        if settings.biometricLockEnabled {
            authenticateBiometric { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.lockState = .unlocked
                    } else {
                        // Face ID 失败 → 降级到 PIN（若开启）
                        if self?.settings.appPINEnabled == true {
                            self?.lockState = .locked
                            self?.lastAuthError = "生物识别失败，请输入密码"
                        } else {
                            self?.lockState = .locked
                            self?.lastAuthError = error ?? "认证失败"
                        }
                    }
                }
            }
            return
        }

        // 仅 PIN 模式
        if settings.appPINEnabled {
            guard let pin = pin else {
                lockState = .locked
                return
            }
            if pin == settings.appPIN {
                lockState = .unlocked
            } else {
                lockState = .locked
                lastAuthError = "密码错误，请重试"
            }
            return
        }

        // 所有锁关闭
        lockState = .unlocked
    }

    // MARK: 重新锁定（退到后台时调用）
    func lock() {
        if settings.biometricLockEnabled || settings.appPINEnabled {
            lockState = .locked
        }
    }

    // MARK: 检测设备是否支持生物识别
    var biometricType: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "不支持"
        }
        switch context.biometryType {
        case .faceID:    return "Face ID"
        case .touchID:   return "Touch ID"
        case .opticID:   return "Optic ID"
        default:         return "生物识别"
        }
    }

    // MARK: 私有：调用 LocalAuthentication
    private func authenticateBiometric(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        let reason  = "请验证身份以进入 CRM"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error?.localizedDescription ?? "设备不支持生物识别")
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, err in
            completion(success, err?.localizedDescription)
        }
    }
}
