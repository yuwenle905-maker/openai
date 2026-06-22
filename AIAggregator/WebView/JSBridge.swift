import Foundation

/// JS 注入脚本构建器
enum JSBridge {
    typealias Platform = AIPlatform

    // MARK: - 1. DOM 结构探测脚本（页面加载后调用，结果显示在 debugLabel）

    static func domProbeScript(platform: AIPlatform) -> String {
        let dbg = "\(platform.messageHandler)_debug"
        return """
        (function() {
            var report = '[DOM探测-\(platform.messageHandler)]\n';

            // ── 输入框 ────────────────────────────────────────────────
            var inputs = document.querySelectorAll('textarea, input[type="text"], input:not([type]), [contenteditable="true"]');
            report += '输入框(' + inputs.length + '):\n';
            inputs.forEach(function(el, i) {
                if (i >= 6) return;
                report += '  ' + el.tagName
                    + ' id=' + (el.id || '-')
                    + ' ce=' + (el.getAttribute('contenteditable') || '-')
                    + ' ph=' + (el.placeholder || '-').substring(0,20)
                    + ' cls=' + (el.className || '').substring(0,30) + '\n';
            });

            // ── 按钮 ──────────────────────────────────────────────────
            var btns = document.querySelectorAll('button');
            report += '按钮(' + btns.length + '):\n';
            var shownBtns = 0;
            btns.forEach(function(b) {
                if (shownBtns >= 10) return;
                var label = b.getAttribute('aria-label') || '';
                var txt   = (b.textContent || '').trim().substring(0, 20);
                var typ   = b.type || '-';
                var dis   = b.disabled ? '[禁]' : '[可]';
                var hasSvg= b.querySelector('svg') ? '有SVG' : '无SVG';
                var cls   = (b.className || '').substring(0, 30);
                report += '  ' + dis + ' type=' + typ
                    + ' aria="' + label.substring(0,20) + '"'
                    + ' txt="' + txt + '"'
                    + ' ' + hasSvg
                    + ' cls=' + cls + '\n';
                shownBtns++;
            });

            // ── 回复容器候选 ──────────────────────────────────────────
            var replyCands = document.querySelectorAll(
                'model-response, message-content, response-text,' +
                '[class*="markdown"],[class*="response"],[class*="assistant"],[class*="model"],' +
                '[data-message-author-role="model"]'
            );
            report += '回复容器候选(' + replyCands.length + '):\n';
            replyCands.forEach(function(el, i) {
                if (i >= 5) return;
                var txt = (el.innerText || '').trim().substring(0, 40);
                report += '  ' + el.tagName + ' cls=' + (el.className || '').substring(0,30)
                    + ' len=' + (el.innerText||'').trim().length
                    + ' preview="' + txt + '"\n';
            });

            try { window.webkit.messageHandlers.\(dbg).postMessage(report); } catch(e) {}
        })();
        """
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

                window.__startDSListener = function() {
                    if (window.__dsObserver)  { window.__dsObserver.disconnect(); }
                    clearTimeout(window.__dsDebounce);
                    clearTimeout(window.__dsMaxTimer);
                    clearInterval(window.__dsPolling);
                    window.__dsSent = false;
                    window.__dsPrevPollLen = -1;
                    window.__dsNoChangeCount = 0;
                    window.__dsPollCount = 0;

                    function getReply() {
                        var candidates = document.querySelectorAll(
                            '[class*="ds-markdown"], [class*="markdown"], ' +
                            '[class*="message-content"], [class*="assistant"], ' +
                            '[class*="response"], [class*="reply"]'
                        );
                        var last = candidates[candidates.length - 1];
                        return last ? last.innerText.trim() : '';
                    }

                    function tryPost(reason) {
                        if (window.__dsSent) return;
                        var text = getReply();
                        if (text.length < 5) {
                            console.log('[DSListener] 内容过短(' + text.length + ')，继续等待');
                            return;
                        }
                        window.__dsSent = true;
                        if (window.__dsObserver) window.__dsObserver.disconnect();
                        clearTimeout(window.__dsMaxTimer);
                        clearInterval(window.__dsPolling);
                        console.log('[DSListener] 触发原因=' + reason + '，回复长度=' + text.length);
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__dsObserver = new MutationObserver(function() {
                        var currentLen = getReply().length;
                        console.log('[WVM-Debug] DOM changed, DS text length: ' + currentLen);
                        clearTimeout(window.__dsDebounce);
                        window.__dsDebounce = setTimeout(function() { tryPost('debounce-1.5s'); }, 1500);
                    });
                    window.__dsObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });

                    window.__dsPolling = setInterval(function() {
                        if (window.__dsSent) { clearInterval(window.__dsPolling); return; }
                        window.__dsPollCount++;
                        var currentLen = getReply().length;
                        console.log('[WVM-Debug] DS轮询 len=' + currentLen + ' prev=' + window.__dsPrevPollLen + ' noChg=' + window.__dsNoChangeCount);
                        if (currentLen === 0 && window.__dsPollCount === 5) {
                            var cands = document.querySelectorAll('[class*="ds-markdown"],[class*="markdown"],[class*="message-content"],[class*="assistant"],[class*="response"],[class*="reply"]').length;
                            var msg = 'DS选择器5s未命中，候选容器=' + cands + '。可能AI未响应或选择器失效';
                            try { window.webkit.messageHandlers.\(handler)_debug.postMessage(msg); } catch(e) {}
                        }
                        if (currentLen >= 5 && currentLen === window.__dsPrevPollLen) {
                            window.__dsNoChangeCount++;
                            if (window.__dsNoChangeCount >= 3) {
                                clearInterval(window.__dsPolling);
                                tryPost('polling-3s-no-change');
                            }
                        } else {
                            window.__dsNoChangeCount = 0;
                        }
                        window.__dsPrevPollLen = currentLen;
                    }, 1000);

                    window.__dsMaxTimer = setTimeout(function() {
                        if (!window.__dsSent) tryPost('timeout-90s');
                    }, 90000);

                    console.log('[DSListener] 监听启动（防抖+轮询）');
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
                    clearInterval(window.__gmPolling);
                    window.__gmSent = false;
                    window.__gmPrevPollLen = -1;
                    window.__gmNoChangeCount = 0;
                    window.__gmPollCount = 0;

                    function getReply() {
                        // 阶段1：Gemini 专属自定义元素（最稳定）
                        var phase1 = document.querySelectorAll(
                            'model-response, message-content, response-text, ' +
                            '[data-message-author-role="model"]'
                        );
                        if (phase1.length > 0) {
                            var t1 = phase1[phase1.length - 1].innerText.trim();
                            if (t1.length > 5) return t1;
                        }
                        // 阶段2：class 名匹配
                        var phase2 = document.querySelectorAll(
                            '[class*="response-content"], [class*="model-response"], ' +
                            '[class*="markdown"], [class*="assistant"], ' +
                            '[class*="gemini"], [class*="bard"]'
                        );
                        if (phase2.length > 0) {
                            var t2 = phase2[phase2.length - 1].innerText.trim();
                            if (t2.length > 5) return t2;
                        }
                        // 阶段3：role 属性
                        var phase3 = document.querySelectorAll('[role="article"], [role="region"]');
                        if (phase3.length > 0) {
                            var t3 = phase3[phase3.length - 1].innerText.trim();
                            if (t3.length > 5) return t3;
                        }
                        // 阶段4：全页面最后一段大文本块（兜底）
                        var main = document.querySelector('main') || document.body;
                        var paras = main.querySelectorAll('p, [class*="text"]');
                        for (var i = paras.length - 1; i >= 0; i--) {
                            var t4 = paras[i].innerText ? paras[i].innerText.trim() : '';
                            if (t4.length > 30) return t4;
                        }
                        return '';
                    }

                    function tryPost(reason) {
                        if (window.__gmSent) return;
                        var text = getReply();
                        if (text.length < 5) {
                            console.log('[GMListener] 内容过短(' + text.length + ')，继续等待');
                            return;
                        }
                        window.__gmSent = true;
                        if (window.__gmObserver) window.__gmObserver.disconnect();
                        clearTimeout(window.__gmMaxTimer);
                        clearInterval(window.__gmPolling);
                        console.log('[GMListener] 触发原因=' + reason + '，回复长度=' + text.length);
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__gmObserver = new MutationObserver(function() {
                        var currentLen = getReply().length;
                        console.log('[WVM-Debug] DOM changed, GM text length: ' + currentLen);
                        clearTimeout(window.__gmDebounce);
                        window.__gmDebounce = setTimeout(function() { tryPost('debounce-1.5s'); }, 1500);
                    });
                    window.__gmObserver.observe(document.body, {
                        childList: true, subtree: true, characterData: true
                    });

                    window.__gmPolling = setInterval(function() {
                        if (window.__gmSent) { clearInterval(window.__gmPolling); return; }
                        window.__gmPollCount++;
                        var currentLen = getReply().length;
                        console.log('[WVM-Debug] GM轮询 len=' + currentLen + ' prev=' + window.__gmPrevPollLen + ' noChg=' + window.__gmNoChangeCount);
                        if (currentLen === 0 && window.__gmPollCount === 5) {
                            var cands = document.querySelectorAll('model-response,message-content,[class*="response-content"],[class*="model-response"],[class*="markdown"],[class*="assistant"],.response-container').length;
                            var msg = 'GM选择器5s未命中，候选容器=' + cands;
                            try { window.webkit.messageHandlers.\(handler)_debug.postMessage(msg); } catch(e) {}
                        }
                        if (currentLen >= 5 && currentLen === window.__gmPrevPollLen) {
                            window.__gmNoChangeCount++;
                            if (window.__gmNoChangeCount >= 3) {
                                clearInterval(window.__gmPolling);
                                tryPost('polling-3s-no-change');
                            }
                        } else {
                            window.__gmNoChangeCount = 0;
                        }
                        window.__gmPrevPollLen = currentLen;
                    }, 1000);

                    window.__gmMaxTimer = setTimeout(function() {
                        if (!window.__gmSent) tryPost('timeout-90s');
                    }, 90000);

                    console.log('[GMListener] 监听启动（防抖+轮询）');
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
                console.log('[DSInject] 开始注入，文本长度=\(query.count)');

                // ── 全页面找输入框（广谱，不依赖硬编码 class）────────────
                function findInput() {
                    return document.querySelector('textarea#chat-input')
                        || document.querySelector('textarea[placeholder]')
                        || document.querySelector('textarea');
                }
                var input = findInput();
                if (!input) {
                    // 最后兜底：取所有 textarea 中最后一个
                    var all = document.querySelectorAll('textarea');
                    if (all.length > 0) input = all[all.length - 1];
                }
                if (!input) {
                    var msg = '找不到任何输入框，页面输入元素=' + document.querySelectorAll('input,textarea,[contenteditable]').length;
                    console.error('[DSInject] ' + msg);
                    try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage(msg); } catch(e) {}
                    window.webkit.messageHandlers.deepSeekReply_error.postMessage('input_not_found');
                    return;
                }
                console.log('[DSInject] 找到输入框: ' + input.tagName + ' placeholder=' + (input.placeholder||'-'));

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

                // ── 全页面评分找最佳发送按钮 ─────────────────────────────
                // 不依赖特定选择器，对所有按钮打分，取分最高且可点击的那个
                function findBestButton() {
                    var best = null, bestScore = -1;
                    document.querySelectorAll('button').forEach(function(b) {
                        if (b.disabled) return;
                        var score = 0;
                        var aria  = (b.getAttribute('aria-label') || '').toLowerCase();
                        var cls   = (b.className || '').toLowerCase();
                        var txt   = (b.textContent || '').trim().toLowerCase();
                        var typ   = (b.type || '').toLowerCase();
                        if (typ === 'submit') score += 10;
                        if (aria.includes('send') || aria.includes('发送') || aria.includes('submit')) score += 8;
                        if (txt === '发送' || txt === 'send') score += 7;
                        if (cls.includes('send') || cls.includes('submit')) score += 6;
                        if (b.querySelector('svg') && txt.length < 3) score += 4;
                        if (score > bestScore) { bestScore = score; best = b; }
                    });
                    return bestScore > 0 ? best : null;
                }

                var attempts = 0;
                function tryClickSend() {
                    attempts++;
                    var btn = findBestButton();
                    if (btn) {
                        var btnInfo = 'type=' + (btn.type||'-') + ' aria="' + (btn.getAttribute('aria-label')||'') + '" txt="' + (btn.textContent||'').trim().substring(0,15) + '"';
                        console.log('[DSInject] 第' + attempts + '次，点击按钮: ' + btnInfo);
                        btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                        btn.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                        btn.click();

                        // 500ms：检查是否清空
                        setTimeout(function() {
                            var ci = findInput();
                            var remaining = ci ? ci.value.trim().length : 0;
                            if (remaining > 0) {
                                var msg = '500ms后输入框仍有 ' + remaining + ' 字，发送可能未触达';
                                console.warn('[DSInject] ' + msg);
                                try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage(msg); } catch(e) {}
                            } else {
                                try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage('✓ 发送成功，输入框已清空'); } catch(e) {}
                            }
                        }, 500);

                        // 3s：仍有内容则再次点击
                        setTimeout(function() {
                            var ci = findInput();
                            if (!ci || ci.value.trim().length === 0) { return; }
                            var msg = '⚠️ 3s强制重试：输入框未清空，再次点击';
                            try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage(msg); } catch(e) {}
                            var rb = findBestButton();
                            if (rb) {
                                rb.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                                rb.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                                rb.click();
                                try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage('⚠️ 3s强制重试点击已执行'); } catch(e) {}
                            } else {
                                ci.dispatchEvent(new KeyboardEvent('keydown', {
                                    bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13
                                }));
                                try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage('⚠️ 3s强制重试：用Enter键兜底'); } catch(e) {}
                            }
                        }, 3000);

                    } else if (attempts < 15) {
                        console.log('[DSInject] 第' + attempts + '次未找到可用按钮，200ms后重试');
                        setTimeout(tryClickSend, 200);
                    } else {
                        // 穷举失败：用 Enter 键
                        var failMsg = '⚠️ 15次重试后仍无可用按钮，页面按钮总数=' + document.querySelectorAll('button').length + '（含禁用=' + document.querySelectorAll('button[disabled]').length + '）';
                        console.error('[DSInject] ' + failMsg);
                        try { window.webkit.messageHandlers.deepSeekReply_debug.postMessage(failMsg); } catch(e) {}
                        window.webkit.messageHandlers.deepSeekReply_error.postMessage('send_btn_timeout');
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
                console.log('[GMInject] 开始注入，文本长度=\(query.count)');

                // ── 全页面找输入框（多阶段，含回退）────────────────────
                function findEditor() {
                    return document.querySelector('rich-textarea .ql-editor')
                        || document.querySelector('rich-textarea [contenteditable="true"]')
                        || document.querySelector('[contenteditable="true"][role="textbox"]')
                        || document.querySelector('[contenteditable="true"]')
                        || document.querySelector('textarea');
                }
                var editor = findEditor();
                if (!editor) {
                    // 最终兜底：取所有 contenteditable 中最后一个
                    var allCE = document.querySelectorAll('[contenteditable]');
                    if (allCE.length > 0) editor = allCE[allCE.length - 1];
                }
                if (!editor) {
                    var msg = '找不到任何输入框，可编辑元素=' + document.querySelectorAll('[contenteditable],textarea,input').length;
                    console.error('[GMInject] ' + msg);
                    try { window.webkit.messageHandlers.geminiReply_debug.postMessage(msg); } catch(e) {}
                    window.webkit.messageHandlers.geminiReply_error.postMessage('input_not_found');
                    return;
                }
                console.log('[GMInject] 找到输入框: ' + editor.tagName + ' ce=' + editor.getAttribute('contenteditable'));

                editor.focus();

                // ── 写入内容 ──────────────────────────────────────────────
                if (editor.isContentEditable) {
                    editor.innerHTML = '';
                    var success = document.execCommand('insertText', false, `\(escaped)`);
                    if (!success || editor.innerText.trim().length === 0) {
                        console.log('[GMInject] execCommand失败，用innerHTML写入');
                        var p = document.createElement('p');
                        p.textContent = `\(escaped)`;
                        editor.innerHTML = '';
                        editor.appendChild(p);
                        var range = document.createRange();
                        range.selectNodeContents(editor);
                        range.collapse(false);
                        var sel = window.getSelection();
                        if (sel) { sel.removeAllRanges(); sel.addRange(range); }
                    }
                } else {
                    var desc = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
                    if (desc && desc.set) { desc.set.call(editor, `\(escaped)`); }
                    else { editor.value = `\(escaped)`; }
                }

                editor.dispatchEvent(new InputEvent('input', {
                    bubbles: true, cancelable: true, inputType: 'insertText', data: `\(escaped)`
                }));
                editor.dispatchEvent(new Event('change', { bubbles: true }));
                console.log('[GMInject] 内容已写入: ' + (editor.innerText || editor.value || '').substring(0, 30));

                // ── 启动回复监听 ──────────────────────────────────────────
                if (typeof window.__startGMListener === 'function') {
                    window.__startGMListener();
                } else {
                    console.warn('[GMInject] __startGMListener 未定义');
                }

                // ── 全页面评分找最佳发送按钮 ─────────────────────────────
                function findBestGMButton() {
                    var best = null, bestScore = -1;
                    document.querySelectorAll('button').forEach(function(b) {
                        if (b.disabled) return;
                        var score = 0;
                        var aria = (b.getAttribute('aria-label') || '').toLowerCase();
                        var cls  = (b.className || '').toLowerCase();
                        var txt  = (b.textContent || '').trim().toLowerCase();
                        var jsn  = (b.getAttribute('jsname') || '').toLowerCase();
                        if (aria.includes('send') || aria.includes('发送') || aria.includes('submit')) score += 10;
                        if (jsn === 'qx7uuf') score += 9;
                        if (txt === 'send' || txt === '发送') score += 8;
                        if (cls.includes('send') || cls.includes('submit')) score += 6;
                        if (b.querySelector('svg') && txt.length < 3) score += 3;
                        if (score > bestScore) { bestScore = score; best = b; }
                    });
                    return bestScore > 0 ? best : null;
                }

                var attempts = 0;
                function tryClickSend() {
                    attempts++;
                    var btn = findBestGMButton();
                    if (btn) {
                        var btnInfo = 'aria="' + (btn.getAttribute('aria-label')||'') + '" jsname=' + (btn.getAttribute('jsname')||'-');
                        console.log('[GMInject] 第' + attempts + '次，点击按钮: ' + btnInfo);
                        btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                        btn.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                        btn.click();

                        // 500ms：检查是否清空
                        setTimeout(function() {
                            var ce = findEditor();
                            var remaining = ce ? ce.innerText.trim().length : 0;
                            if (remaining > 0) {
                                var msg = '500ms后输入框仍有 ' + remaining + ' 字，发送可能未触达';
                                console.warn('[GMInject] ' + msg);
                                try { window.webkit.messageHandlers.geminiReply_debug.postMessage(msg); } catch(e) {}
                            } else {
                                try { window.webkit.messageHandlers.geminiReply_debug.postMessage('✓ 发送成功，输入框已清空'); } catch(e) {}
                            }
                        }, 500);

                        // 3s：仍有内容则再次点击
                        setTimeout(function() {
                            var ce = findEditor();
                            if (!ce || ce.innerText.trim().length === 0) { return; }
                            var msg = '⚠️ 3s强制重试：输入框未清空，再次点击';
                            try { window.webkit.messageHandlers.geminiReply_debug.postMessage(msg); } catch(e) {}
                            var rb = findBestGMButton();
                            if (rb) {
                                rb.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                                rb.dispatchEvent(new MouseEvent('mouseup',   { bubbles: true, cancelable: true }));
                                rb.click();
                                try { window.webkit.messageHandlers.geminiReply_debug.postMessage('⚠️ 3s强制重试点击已执行'); } catch(e) {}
                            } else {
                                editor.dispatchEvent(new KeyboardEvent('keydown', {
                                    bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13
                                }));
                                try { window.webkit.messageHandlers.geminiReply_debug.postMessage('⚠️ 3s强制重试：用Enter键兜底'); } catch(e) {}
                            }
                        }, 3000);

                    } else if (attempts < 15) {
                        console.log('[GMInject] 第' + attempts + '次未找到可用按钮，200ms后重试');
                        setTimeout(tryClickSend, 200);
                    } else {
                        var failMsg = '⚠️ GM 15次重试无按钮，页面按钮总数=' + document.querySelectorAll('button').length;
                        console.error('[GMInject] ' + failMsg);
                        try { window.webkit.messageHandlers.geminiReply_debug.postMessage(failMsg); } catch(e) {}
                        window.webkit.messageHandlers.geminiReply_error.postMessage('send_btn_timeout');
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

    // MARK: - 5. 页面就绪检测脚本

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
            })();
            """

        case .gemini:
            return """
            (function() {
                var input = document.querySelector('rich-textarea .ql-editor')
                         || document.querySelector('[contenteditable="true"]')
                         || document.querySelector('textarea');
                var btn   = document.querySelector('button[aria-label*="Send"]')
                         || document.querySelector('button[jsname="Qx7uuf"]');
                var isReady = !!(input && btn);
                console.log('[GMReady] input=' + !!input + ' btn=' + !!btn);
                window.webkit.messageHandlers.\(readyHandler).postMessage(isReady ? "true" : "false");
            })();
            """
        }
    }

    // MARK: - 私有辅助

    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "$",  with: "\\$")
    }
}
