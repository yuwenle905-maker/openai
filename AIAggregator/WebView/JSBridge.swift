import Foundation

/// JS 注入脚本构建器
enum JSBridge {
    typealias Platform = AIPlatform

    // MARK: - 1. 页面就绪检测脚本（导航完成后注入，诊断用）

    /// 检查输入框与发送按钮是否在 DOM 中存在，结果回传 {handler}_ready 通道。
    /// isReady = false 时在控制台打印所有 input/textarea/contenteditable 元素供排查。
    static func pageReadyCheckScript(platform: AIPlatform) -> String {
        let readyHandler = "\(platform.messageHandler)_ready"

        switch platform {
        case .deepSeek:
            return """
            (function() {
                var input = document.querySelector('textarea[placeholder]')
                         || document.querySelector('#chat-input')
                         || document.querySelector('textarea');
                var btn   = document.querySelector('button[type="submit"]')
                         || document.querySelector('[data-testid="send-button"]')
                         || document.querySelector('#send-button');
                var isReady = !!(input && btn);

                window.webkit.messageHandlers.\(readyHandler)
                    .postMessage(isReady ? "true" : "false");

                if (!isReady) {
                    var all = document.querySelectorAll('input, textarea, [contenteditable="true"]');
                    var info = '[DeepSeek ready=false] 共找到 ' + all.length + ' 个输入元素：';
                    all.forEach(function(el) {
                        info += el.tagName
                             + '(type=' + (el.type || '-')
                             + ' ce=' + (el.getAttribute('contenteditable') || '-')
                             + ' cls=' + el.className.substring(0, 40) + ') | ';
                    });
                    console.warn(info);
                }
            })();
            """

        case .gemini:
            return """
            (function() {
                var input = document.querySelector('rich-textarea p')
                         || document.querySelector('[contenteditable="true"]')
                         || document.querySelector('textarea');
                var btn   = document.querySelector('button[aria-label*="Send"]')
                         || document.querySelector('button[data-mat-icon-name="send"]')
                         || document.querySelector('button[jsname="Qx7uuf"]');
                var isReady = !!(input && btn);

                window.webkit.messageHandlers.\(readyHandler)
                    .postMessage(isReady ? "true" : "false");

                if (!isReady) {
                    var all = document.querySelectorAll('input, textarea, [contenteditable="true"]');
                    var info = '[Gemini ready=false] 共找到 ' + all.length + ' 个输入元素：';
                    all.forEach(function(el) {
                        info += el.tagName
                             + '(type=' + (el.type || '-')
                             + ' ce=' + (el.getAttribute('contenteditable') || '-')
                             + ' cls=' + el.className.substring(0, 40) + ') | ';
                    });
                    console.warn(info);
                }
            })();
            """
        }
    }

    // MARK: - 2. 全局回复监听脚本（WKUserScript，atDocumentEnd 注入）

    static func globalListenerScript(platform: AIPlatform) -> String {
        let handler = platform.messageHandler

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
                        var msgs = document.querySelectorAll(
                            '[class*="message-content"], [class*="ds-markdown"]'
                        );
                        var last = msgs[msgs.length - 1];
                        if (!last || last.innerText.length < 5) return;
                        var text = last.innerText.trim();
                        var streaming = !!document.querySelector(
                            '[class*="thinking"], [class*="loading"], .ds-cursor'
                        );
                        if (!streaming && !text.endsWith('\\u25cb')) {
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
                        var msgs = document.querySelectorAll(
                            'model-response, message-content, [class*="response-content"]'
                        );
                        var last = msgs[msgs.length - 1];
                        if (!last || last.innerText.length < 5) return;
                        var thinking = document.querySelector(
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
    }

    // MARK: - 3. 输入 + 发送脚本（核心注入）

    static func buildInputScript(query: String, platform: AIPlatform) -> String {
        let escaped = escapeForJS(query)

        switch platform {
        case .deepSeek:
            return """
            (function() {
                // ── 步骤1：定位输入框 ─────────────────────────────────────
                var input = document.querySelector('textarea[placeholder]')
                         || document.querySelector('#chat-input')
                         || document.querySelector('textarea');

                if (!input) {
                    window.webkit.messageHandlers.deepSeekReply_error
                        .postMessage('input_not_found');
                    return;
                }

                // ── 步骤2：通过 React nativeSetter 写入 value ─────────────
                // 直接赋值 input.value 不会触发 React 的 onChange，
                // 必须劫持原型链上的 setter 才能让 React 感知变化。
                var nativeSetter = Object.getOwnPropertyDescriptor(
                    window.HTMLTextAreaElement.prototype, 'value'
                );
                nativeSetter.set.call(input, `\(escaped)`);

                // ── 步骤3：派发 InputEvent（React 监听此事件更新 state）──
                input.dispatchEvent(new InputEvent('input', {
                    bubbles: true,
                    cancelable: true,
                    inputType: 'insertText',
                    data: `\(escaped)`
                }));
                // 兼容部分框架同时监听 change 事件
                input.dispatchEvent(new Event('change', { bubbles: true }));

                // ── 步骤4：注册回复监听器 ─────────────────────────────────
                if (typeof window.__startDSListener === 'function') {
                    window.__startDSListener();
                }

                // ── 步骤5：显式调用发送按钮 .click()（不模拟回车）────────
                setTimeout(function() {
                    var btn = document.querySelector('button[type="submit"]')
                           || document.querySelector('[data-testid="send-button"]')
                           || document.querySelector('#send-button');
                    if (btn && !btn.disabled) {
                        btn.click();
                    } else {
                        window.webkit.messageHandlers.deepSeekReply_error
                            .postMessage('send_btn_not_found_or_disabled');
                    }
                }, 400);
            })();
            """

        case .gemini:
            return """
            (function() {
                // ── 步骤1：定位输入框（Gemini 使用 contenteditable rich-textarea）
                var input = document.querySelector('rich-textarea p')
                         || document.querySelector('[contenteditable="true"]')
                         || document.querySelector('textarea');

                if (!input) {
                    window.webkit.messageHandlers.geminiReply_error
                        .postMessage('input_not_found');
                    return;
                }

                input.focus();

                // ── 步骤2 & 3：写入内容 + 派发 InputEvent ─────────────────
                if (input.isContentEditable) {
                    // contenteditable：先全选再 insertText
                    document.execCommand('selectAll', false, null);
                    document.execCommand('insertText', false, `\(escaped)`);
                    input.dispatchEvent(new InputEvent('input', {
                        bubbles: true,
                        cancelable: true,
                        inputType: 'insertText',
                        data: `\(escaped)`
                    }));
                } else {
                    // textarea fallback
                    var nativeSetter = Object.getOwnPropertyDescriptor(
                        window.HTMLTextAreaElement.prototype, 'value'
                    );
                    nativeSetter.set.call(input, `\(escaped)`);
                    input.dispatchEvent(new InputEvent('input', {
                        bubbles: true,
                        cancelable: true,
                        inputType: 'insertText',
                        data: `\(escaped)`
                    }));
                }
                input.dispatchEvent(new Event('change', { bubbles: true }));

                // ── 步骤4：注册回复监听器 ─────────────────────────────────
                if (typeof window.__startGMListener === 'function') {
                    window.__startGMListener();
                }

                // ── 步骤5：显式调用发送按钮 .click() ─────────────────────
                setTimeout(function() {
                    var btn = document.querySelector('button[aria-label*="Send"]')
                           || document.querySelector('button[data-mat-icon-name="send"]')
                           || document.querySelector('button[jsname="Qx7uuf"]');
                    if (btn && !btn.disabled) {
                        btn.click();
                    } else {
                        window.webkit.messageHandlers.geminiReply_error
                            .postMessage('send_btn_not_found_or_disabled');
                    }
                }, 500);
            })();
            """
        }
    }

    // MARK: - 4. 整合脚本

    static func buildMergeScript(deepSeekAnswer: String, geminiAnswer: String) -> String {
        let mergeQuery = """
        以下是两个 AI 对同一问题的回答，请整合两者精华，给出简洁、准确、完整的最终答案：

        【DeepSeek 回答】
        \(deepSeekAnswer)

        【Gemini 回答】
        \(geminiAnswer)
        """
        return buildInputScript(query: mergeQuery, platform: .gemini)
    }

    // MARK: - 私有辅助

    /// 对用户文本做 JS 模板字符串转义（防止注入 `` ` ``、`\`、`$`）
    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "$",  with: "\\$")
    }
}
