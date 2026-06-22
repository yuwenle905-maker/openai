import Foundation

/// JS 注入脚本构建器
enum JSBridge {
    typealias Platform = AIPlatform

    // MARK: - 1. 页面就绪检测脚本

    static func pageReadyCheckScript(platform: AIPlatform) -> String {
        let readyHandler = "\(platform.messageHandler)_ready"

        switch platform {
        case .deepSeek:
            return """
            (function() {
                var input = document.querySelector('textarea#chat-input')
                         || document.querySelector('textarea[placeholder]')
                         || document.querySelector('textarea');
                var btn   = document.querySelector('button[type="submit"]')
                         || document.querySelector('[data-testid="send-button"]')
                         || document.querySelector('#send-button');
                var isReady = !!(input && btn);
                console.log('[DSReady] input=' + !!input + ' btn=' + !!btn);
                window.webkit.messageHandlers.\(readyHandler).postMessage(isReady ? "true" : "false");
                if (!isReady) {
                    var all = document.querySelectorAll('input, textarea, [contenteditable]');
                    var info = '[DeepSeek ready=false] inputs:' + all.length + ' ';
                    all.forEach(function(el) {
                        info += el.tagName + '(' + (el.type||'-') + '/' + el.className.substring(0,30) + ') ';
                    });
                    console.warn(info);
                }
            })();
            """

        case .gemini:
            return """
            (function() {
                var input = document.querySelector('rich-textarea .ql-editor')
                         || document.querySelector('rich-textarea p')
                         || document.querySelector('[contenteditable="true"]')
                         || document.querySelector('textarea');
                var btn   = document.querySelector('button[aria-label*="Send"]')
                         || document.querySelector('button[data-mat-icon-name="send"]')
                         || document.querySelector('button[jsname="Qx7uuf"]')
                         || document.querySelector('.send-button');
                var isReady = !!(input && btn);
                console.log('[GMReady] input=' + !!input + ' btn=' + !!btn);
                window.webkit.messageHandlers.\(readyHandler).postMessage(isReady ? "true" : "false");
                if (!isReady) {
                    var all = document.querySelectorAll('input, textarea, [contenteditable]');
                    var info = '[Gemini ready=false] inputs:' + all.length + ' ';
                    all.forEach(function(el) {
                        info += el.tagName + '(' + (el.getAttribute('contenteditable')||'-') + '/' + el.className.substring(0,30) + ') ';
                    });
                    console.warn(info);
                }
            })();
            """
        }
    }

    // MARK: - 2. 全局回复监听脚本（WKUserScript，atDocumentEnd 注入）
    //
    // 核心策略：防抖（debounce）而非 CSS class 检测
    // 原因：流式输出结束无法依赖特定 CSS class（版本迭代后 class 名会变），
    // 但"1.5 秒内没有新 DOM 变化"是平台无关的可靠信号。

    static func globalListenerScript(platform: AIPlatform) -> String {
        let handler = platform.messageHandler

        switch platform {
        case .deepSeek:
            return """
            (function() {
                if (window.__dsListenerActive) return;
                window.__dsListenerActive = true;

                window.__startDSListener = function() {
                    // 清理上一次的状态
                    if (window.__dsObserver)  { window.__dsObserver.disconnect(); }
                    clearTimeout(window.__dsDebounce);
                    clearTimeout(window.__dsMaxTimer);
                    window.__dsSent = false;

                    function getReply() {
                        // 广谱选择器：取页面内所有 markdown/回复容器的最后一个
                        var candidates = document.querySelectorAll(
                            '[class*="ds-markdown"], [class*="markdown"], ' +
                            '[class*="message-content"], [class*="assistant"], ' +
                            '[class*="response"], [class*="reply"]'
                        );
                        var last = candidates[candidates.length - 1];
                        return last ? last.innerText.trim() : '';
                    }

                    function tryPost() {
                        if (window.__dsSent) return;
                        var text = getReply();
                        if (text.length < 5) {
                            console.log('[DSListener] 内容过短（' + text.length + '），继续等待');
                            return;
                        }
                        window.__dsSent = true;
                        if (window.__dsObserver) window.__dsObserver.disconnect();
                        clearTimeout(window.__dsMaxTimer);
                        console.log('[DSListener] 防抖触发，回复长度=' + text.length + '，发送');
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__dsObserver = new MutationObserver(function() {
                        // 每次 DOM 变化重置 1.5 秒计时器
                        clearTimeout(window.__dsDebounce);
                        window.__dsDebounce = setTimeout(tryPost, 1500);
                    });
                    window.__dsObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });

                    // 90 秒硬超时兜底，防止永久卡住
                    window.__dsMaxTimer = setTimeout(function() {
                        if (!window.__dsSent) {
                            console.log('[DSListener] 90s 硬超时，强制发送');
                            tryPost();
                        }
                    }, 90000);

                    console.log('[DSListener] 开始监听（防抖模式），等待回复...');
                };
            })();
            """

        case .gemini:
            return """
            (function() {
                if (window.__gmListenerActive) return;
                window.__gmListenerActive = true;

                window.__startGMListener = function() {
                    if (window.__gmObserver)  { window.__gmObserver.disconnect(); }
                    clearTimeout(window.__gmDebounce);
                    clearTimeout(window.__gmMaxTimer);
                    window.__gmSent = false;

                    function getReply() {
                        var candidates = document.querySelectorAll(
                            'model-response, message-content, ' +
                            '[class*="response-content"], [class*="model-response"], ' +
                            '[class*="assistant"], .response-container'
                        );
                        var last = candidates[candidates.length - 1];
                        return last ? last.innerText.trim() : '';
                    }

                    function tryPost() {
                        if (window.__gmSent) return;
                        var text = getReply();
                        if (text.length < 5) {
                            console.log('[GMListener] 内容过短（' + text.length + '），继续等待');
                            return;
                        }
                        window.__gmSent = true;
                        if (window.__gmObserver) window.__gmObserver.disconnect();
                        clearTimeout(window.__gmMaxTimer);
                        console.log('[GMListener] 防抖触发，回复长度=' + text.length + '，发送');
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__gmObserver = new MutationObserver(function() {
                        clearTimeout(window.__gmDebounce);
                        window.__gmDebounce = setTimeout(tryPost, 1500);
                    });
                    window.__gmObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });

                    window.__gmMaxTimer = setTimeout(function() {
                        if (!window.__gmSent) {
                            console.log('[GMListener] 90s 硬超时，强制发送');
                            tryPost();
                        }
                    }, 90000);

                    console.log('[GMListener] 开始监听（防抖模式），等待回复...');
                };
            })();
            """
        }
    }

    // MARK: - 3. 输入 + 发送脚本

    static func buildInputScript(query: String, platform: AIPlatform) -> String {
        let escaped = escapeForJS(query)

        switch platform {
        case .deepSeek:
            return """
            (function() {
                console.log('[DSInject] 开始注入，文本长度=' + \(query.count));

                // ── 找输入框 ────────────────────────────────────────────────
                var input = document.querySelector('textarea#chat-input')
                         || document.querySelector('textarea[placeholder]')
                         || document.querySelector('textarea');

                if (!input) {
                    console.error('[DSInject] 找不到输入框');
                    window.webkit.messageHandlers.deepSeekReply_error.postMessage('input_not_found');
                    return;
                }
                console.log('[DSInject] 找到输入框: ' + input.tagName + ' placeholder=' + input.placeholder);

                // ── React nativeSetter 写入 value ─────────────────────────
                var descriptor = Object.getOwnPropertyDescriptor(
                    window.HTMLTextAreaElement.prototype, 'value'
                );
                if (descriptor && descriptor.set) {
                    descriptor.set.call(input, `\(escaped)`);
                } else {
                    input.value = `\(escaped)`;
                }

                // ── 触发 React 事件链 ─────────────────────────────────────
                input.focus();
                input.dispatchEvent(new Event('focus', { bubbles: true }));
                input.dispatchEvent(new InputEvent('input', {
                    bubbles: true, cancelable: true,
                    inputType: 'insertText', data: `\(escaped)`
                }));
                input.dispatchEvent(new Event('change', { bubbles: true }));

                console.log('[DSInject] 事件已触发，value长度=' + input.value.length);

                // ── 启动回复监听 ──────────────────────────────────────────
                if (typeof window.__startDSListener === 'function') {
                    window.__startDSListener();
                } else {
                    console.warn('[DSInject] __startDSListener 未定义');
                }

                // ── 重试点击发送按钮（每 200ms 重试，最多 10 次）─────────
                var attempts = 0;
                function tryClickSend() {
                    attempts++;
                    var btn = document.querySelector('button[type="submit"]:not([disabled])')
                           || document.querySelector('[data-testid="send-button"]:not([disabled])')
                           || document.querySelector('#send-button:not([disabled])');

                    // 兜底：遍历所有按钮，找到离输入框最近的可用提交按钮
                    if (!btn) {
                        var allBtns = document.querySelectorAll('button:not([disabled])');
                        for (var i = 0; i < allBtns.length; i++) {
                            var b = allBtns[i];
                            if (b.type === 'submit' || b.getAttribute('aria-label') === 'Send'
                                || b.textContent.trim() === '' && b.querySelector('svg')) {
                                btn = b;
                                break;
                            }
                        }
                    }

                    if (btn) {
                        console.log('[DSInject] 第' + attempts + '次，找到可用按钮，点击');
                        btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                        btn.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                        btn.click();
                    } else if (attempts < 10) {
                        console.log('[DSInject] 第' + attempts + '次，按钮未就绪，200ms后重试');
                        setTimeout(tryClickSend, 200);
                    } else {
                        console.error('[DSInject] 超过最大重试次数，发送失败');
                        window.webkit.messageHandlers.deepSeekReply_error.postMessage('send_btn_timeout');

                        // 最后兜底：尝试 Enter 键
                        input.dispatchEvent(new KeyboardEvent('keydown', {
                            bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13
                        }));
                    }
                }
                setTimeout(tryClickSend, 300);
            })();
            """

        case .gemini:
            return """
            (function() {
                console.log('[GMInject] 开始注入，文本长度=' + \(query.count));

                // ── 找输入框（Gemini 使用 contenteditable rich-textarea）────
                var editor = document.querySelector('rich-textarea .ql-editor')
                          || document.querySelector('rich-textarea [contenteditable="true"]')
                          || document.querySelector('[contenteditable="true"]')
                          || document.querySelector('textarea');

                if (!editor) {
                    console.error('[GMInject] 找不到输入框');
                    window.webkit.messageHandlers.geminiReply_error.postMessage('input_not_found');
                    return;
                }
                console.log('[GMInject] 找到输入框: ' + editor.tagName + ' ce=' + editor.getAttribute('contenteditable'));

                editor.focus();

                // ── 写入内容 ──────────────────────────────────────────────
                if (editor.isContentEditable) {
                    // 清空现有内容
                    editor.innerHTML = '';
                    // 方法1: execCommand insertText（主流浏览器仍支持）
                    var success = document.execCommand('insertText', false, `\(escaped)`);
                    if (!success || editor.innerText.trim().length === 0) {
                        // 方法2: 直接操作 innerHTML + TextNode
                        console.log('[GMInject] execCommand失败，使用innerHTML方法');
                        var p = document.createElement('p');
                        p.textContent = `\(escaped)`;
                        editor.innerHTML = '';
                        editor.appendChild(p);
                        // 把光标移到末尾
                        var range = document.createRange();
                        range.selectNodeContents(editor);
                        range.collapse(false);
                        var sel = window.getSelection();
                        if (sel) { sel.removeAllRanges(); sel.addRange(range); }
                    }
                } else {
                    // textarea fallback
                    var descriptor = Object.getOwnPropertyDescriptor(
                        window.HTMLTextAreaElement.prototype, 'value'
                    );
                    if (descriptor && descriptor.set) {
                        descriptor.set.call(editor, `\(escaped)`);
                    } else {
                        editor.value = `\(escaped)`;
                    }
                }

                // ── 触发事件让框架感知内容变化 ───────────────────────────
                editor.dispatchEvent(new InputEvent('input', {
                    bubbles: true, cancelable: true,
                    inputType: 'insertText', data: `\(escaped)`
                }));
                editor.dispatchEvent(new Event('change', { bubbles: true }));

                console.log('[GMInject] 内容已写入: ' + (editor.innerText || editor.value || '').substring(0, 30));

                // ── 启动回复监听 ──────────────────────────────────────────
                if (typeof window.__startGMListener === 'function') {
                    window.__startGMListener();
                } else {
                    console.warn('[GMInject] __startGMListener 未定义');
                }

                // ── 重试点击发送按钮（每 200ms 重试，最多 10 次）─────────
                var attempts = 0;
                function tryClickSend() {
                    attempts++;
                    var btn = document.querySelector('button[aria-label*="Send"]:not([disabled])')
                           || document.querySelector('button[data-mat-icon-name="send"]:not([disabled])')
                           || document.querySelector('button[jsname="Qx7uuf"]:not([disabled])')
                           || document.querySelector('.send-button:not([disabled])');

                    // 兜底：找所有可用按钮里包含 send 语义的
                    if (!btn) {
                        var allBtns = document.querySelectorAll('button:not([disabled])');
                        for (var i = 0; i < allBtns.length; i++) {
                            var b = allBtns[i];
                            var label = (b.getAttribute('aria-label') || '').toLowerCase();
                            if (label.includes('send') || label.includes('submit')) {
                                btn = b;
                                break;
                            }
                        }
                    }

                    if (btn) {
                        console.log('[GMInject] 第' + attempts + '次，找到可用按钮，点击');
                        btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                        btn.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                        btn.click();
                    } else if (attempts < 10) {
                        console.log('[GMInject] 第' + attempts + '次，按钮未就绪，200ms后重试');
                        setTimeout(tryClickSend, 200);
                    } else {
                        console.error('[GMInject] 超过最大重试次数，发送失败');
                        window.webkit.messageHandlers.geminiReply_error.postMessage('send_btn_timeout');

                        // 最后兜底：Enter 键
                        editor.dispatchEvent(new KeyboardEvent('keydown', {
                            bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13
                        }));
                    }
                }
                setTimeout(tryClickSend, 400);
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

    /// 对用户文本做 JS 模板字符串转义
    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "$",  with: "\\$")
    }
}
