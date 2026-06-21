import Foundation

/// JS 注入脚本构建器 — 为不同平台生成对应的自动化操作脚本
enum JSBridge {
    // Platform 类型由 WebViewManager.swift 中的 AIPlatform 统一定义，
    // 此处保留 typealias 保持向后兼容
    typealias Platform = AIPlatform

    /// 页面导航完成后自动注入的全局监听脚本（由 WebViewManager 注册为 UserScript）
    /// 监听流式输出结束事件，避免每次查询重复 observe
    static func globalListenerScript(platform: AIPlatform) -> String {
        let handler    = platform.messageHandler
        let errHandler = "\(handler)_error"

        switch platform {
        case .deepSeek:
            return """
            (function() {
                if (window.__dsListenerActive) return;
                window.__dsListenerActive = true;
                window.__dsObserver = null;

                window.__startDSListener = function() {
                    if (window.__dsObserver) window.__dsObserver.disconnect();
                    window.__dsObserver = new MutationObserver(function() {
                        const msgs = document.querySelectorAll(
                            '[class*="message-content"], [class*="ds-markdown"]'
                        );
                        const last = msgs[msgs.length - 1];
                        if (!last || last.innerText.length < 5) return;
                        const text = last.innerText.trim();
                        const isStreaming = !!document.querySelector(
                            '[class*="thinking"], [class*="loading"], .ds-cursor'
                        );
                        if (!isStreaming && !text.endsWith('▋')) {
                            window.__dsObserver.disconnect();
                            window.webkit.messageHandlers.\(handler).postMessage(text);
                        }
                    });
                    window.__dsObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });
                };
            })();
            """

        case .gemini:
            return """
            (function() {
                if (window.__gmListenerActive) return;
                window.__gmListenerActive = true;
                window.__gmObserver = null;

                window.__startGMListener = function() {
                    if (window.__gmObserver) window.__gmObserver.disconnect();
                    window.__gmObserver = new MutationObserver(function() {
                        const msgs = document.querySelectorAll(
                            'model-response, message-content, [class*="response-content"]'
                        );
                        const last = msgs[msgs.length - 1];
                        if (!last || last.innerText.length < 5) return;
                        const thinking = document.querySelector(
                            '[aria-label="Gemini is thinking"], [class*="loading-indicator"]'
                        );
                        if (!thinking) {
                            window.__gmObserver.disconnect();
                            window.webkit.messageHandlers.\(handler).postMessage(
                                last.innerText.trim()
                            );
                        }
                    });
                    window.__gmObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });
                };
            })();
            """
        }
        _ = errHandler // suppress unused warning
    }

    /// 构建"填充输入框 + 点击发送 + 监听回复"的完整 JS 脚本
    static func buildInputScript(query: String, platform: AIPlatform) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "$",  with: "\\$")

        switch platform {
        case .deepSeek:
            return """
            (function() {
                const input = document.querySelector('textarea[placeholder]') ||
                              document.querySelector('#chat-input') ||
                              document.querySelector('textarea');
                if (!input) {
                    window.webkit.messageHandlers.deepSeekReply_error
                        .postMessage('input_not_found');
                    return;
                }
                // React 受控输入：通过 nativeInputValueSetter 触发 onChange
                const nativeSetter = Object.getOwnPropertyDescriptor(
                    window.HTMLTextAreaElement.prototype, 'value'
                );
                nativeSetter.set.call(input, `\(escaped)`);
                input.dispatchEvent(new Event('input', { bubbles: true }));
                // 启动全局监听器（由 UserScript 注入），再点击发送
                if (typeof window.__startDSListener === 'function') {
                    window.__startDSListener();
                }
                setTimeout(() => {
                    const btn = document.querySelector(
                        'button[type="submit"], ' +
                        'button[data-testid="send-button"], ' +
                        '#send-button'
                    );
                    if (btn && !btn.disabled) btn.click();
                }, 300);
            })();
            """

        case .gemini:
            return """
            (function() {
                const input = document.querySelector('rich-textarea p') ||
                              document.querySelector('[contenteditable="true"]') ||
                              document.querySelector('textarea');
                if (!input) {
                    window.webkit.messageHandlers.geminiReply_error
                        .postMessage('input_not_found');
                    return;
                }
                input.focus();
                // contenteditable 需要 execCommand
                if (input.isContentEditable) {
                    document.execCommand('selectAll', false, null);
                    document.execCommand('insertText', false, `\(escaped)`);
                } else {
                    const nativeSetter = Object.getOwnPropertyDescriptor(
                        window.HTMLTextAreaElement.prototype, 'value'
                    );
                    nativeSetter.set.call(input, `\(escaped)`);
                }
                input.dispatchEvent(new Event('input', { bubbles: true }));
                if (typeof window.__startGMListener === 'function') {
                    window.__startGMListener();
                }
                setTimeout(() => {
                    const btn = document.querySelector(
                        'button[aria-label*="Send"], ' +
                        'button[data-mat-icon-name="send"], ' +
                        'button[jsname="Qx7uuf"]'
                    );
                    if (btn) btn.click();
                }, 400);
            })();
            """
        }
    }

    /// 注入用于整合的二次提问脚本（Gemini 侧）
    static func buildMergeScript(deepSeekAnswer: String, geminiAnswer: String) -> String {
        let mergeQuery = """
        以下是两个 AI 对同一问题的回答，请你整合两者的精华，给出一个简洁、准确、完整的最终答案：

        【DeepSeek 回答】
        \(deepSeekAnswer)

        【Gemini 回答】
        \(geminiAnswer)
        """
        return buildInputScript(query: mergeQuery, platform: .gemini)
    }
}
