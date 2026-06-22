import Foundation

/// JS 注入脚本构建器
enum JSBridge {
    typealias Platform = AIPlatform

    // MARK: - 1. DOM 结构探测脚本

    static func domProbeScript(platform: AIPlatform) -> String {
        let dbg = "\(platform.messageHandler)_debug"
        return """
        (function() {
            var report = '[DOM探测-\(platform.messageHandler)] UA=' + navigator.userAgent.substring(0,60) + '\\n';

            var inputs = document.querySelectorAll('textarea, input[type="text"], input:not([type]), [contenteditable="true"]');
            report += '输入框(' + inputs.length + '):\\n';
            inputs.forEach(function(el, i) {
                if (i >= 6) return;
                report += '  ' + el.tagName
                    + ' id=' + (el.id || '-')
                    + ' ph=' + (el.placeholder || '-').substring(0,20)
                    + ' cls=' + (el.className || '').substring(0,30) + '\\n';
            });

            // button + role=button + input[type=submit
            var btns = document.querySelectorAll('button, [role="button"], input[type="submit"]');
            report += '可点击元素(' + btns.length + ') [button=' + document.querySelectorAll('button').length + ' role-btn=' + document.querySelectorAll('[role="button"]').length + ']:\\n';
            var n = 0;
            btns.forEach(function(b) {
                if (n++ >= 10) return;
                var dis = (b.disabled || b.getAttribute('aria-disabled')==='true') ? '[禁]' : '[可]';
                report += '  ' + dis
                    + ' ' + b.tagName
                    + ' role=' + (b.getAttribute('role')||'-')
                    + ' type=' + (b.type||'-')
                    + ' aria="' + (b.getAttribute('aria-label')||'').substring(0,20) + '"'
                    + ' txt="' + (b.textContent||'').trim().substring(0,15) + '"'
                    + ' svg=' + !!b.querySelector('svg') + '\\n';
            });

            var replyCands = document.querySelectorAll(
                'model-response, message-content, response-text,' +
                '[class*="markdown"],[class*="response"],[class*="assistant"],[class*="model"],' +
                '[data-message-author-role="model"]'
            );
            report += '回复容器(' + replyCands.length + '):\\n';
            replyCands.forEach(function(el, i) {
                if (i >= 4) return;
                report += '  ' + el.tagName
                    + ' cls=' + (el.className||'').substring(0,30)
                    + ' len=' + (el.innerText||'').trim().length + '\\n';
            });

            report += 'DOM总元素=' + document.querySelectorAll('*').length
                + ' title=' + document.title.substring(0,30);

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
                        if (text.length < 5) { return; }
                        window.__dsSent = true;
                        if (window.__dsObserver) window.__dsObserver.disconnect();
                        clearTimeout(window.__dsMaxTimer);
                        clearInterval(window.__dsPolling);
                        console.log('[DSListener] 触发=' + reason + ' len=' + text.length);
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__dsObserver = new MutationObserver(function() {
                        var len = getReply().length;
                        console.log('[DS-DOM] changed len=' + len);
                        clearTimeout(window.__dsDebounce);
                        window.__dsDebounce = setTimeout(function() { tryPost('debounce'); }, 1500);
                    });
                    window.__dsObserver.observe(document.body, { childList: true, subtree: true, characterData: true });

                    window.__dsPolling = setInterval(function() {
                        if (window.__dsSent) { clearInterval(window.__dsPolling); return; }
                        window.__dsPollCount++;
                        var len = getReply().length;
                        if (len === 0 && window.__dsPollCount === 5) {
                            var c = document.querySelectorAll('[class*="ds-markdown"],[class*="markdown"],[class*="message-content"],[class*="assistant"],[class*="response"]').length;
                            try { window.webkit.messageHandlers.\(handler)_debug.postMessage('DS 5s仍空，候选容器=' + c); } catch(e) {}
                        }
                        if (len >= 5 && len === window.__dsPrevPollLen) {
                            if (++window.__dsNoChangeCount >= 3) { clearInterval(window.__dsPolling); tryPost('poll-3s'); }
                        } else { window.__dsNoChangeCount = 0; }
                        window.__dsPrevPollLen = len;
                    }, 1000);

                    window.__dsMaxTimer = setTimeout(function() {
                        if (!window.__dsSent) tryPost('timeout-90s');
                    }, 90000);

                    console.log('[DSListener] 监听启动');
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
                        var p1 = document.querySelectorAll('model-response, message-content, response-text, [data-message-author-role="model"]');
                        if (p1.length > 0) { var t = p1[p1.length-1].innerText.trim(); if (t.length > 5) return t; }
                        var p2 = document.querySelectorAll('[class*="response-content"],[class*="model-response"],[class*="markdown"],[class*="assistant"],[class*="gemini"],[class*="bard"]');
                        if (p2.length > 0) { var t2 = p2[p2.length-1].innerText.trim(); if (t2.length > 5) return t2; }
                        var p3 = document.querySelectorAll('[role="article"],[role="region"]');
                        if (p3.length > 0) { var t3 = p3[p3.length-1].innerText.trim(); if (t3.length > 5) return t3; }
                        var main = document.querySelector('main') || document.body;
                        var paras = main.querySelectorAll('p,[class*="text"]');
                        for (var i = paras.length-1; i >= 0; i--) {
                            var t4 = paras[i].innerText ? paras[i].innerText.trim() : '';
                            if (t4.length > 30) return t4;
                        }
                        return '';
                    }

                    function tryPost(reason) {
                        if (window.__gmSent) return;
                        var text = getReply();
                        if (text.length < 5) { return; }
                        window.__gmSent = true;
                        if (window.__gmObserver) window.__gmObserver.disconnect();
                        clearTimeout(window.__gmMaxTimer);
                        clearInterval(window.__gmPolling);
                        console.log('[GMListener] 触发=' + reason + ' len=' + text.length);
                        window.webkit.messageHandlers.\(handler).postMessage(text);
                    }

                    window.__gmObserver = new MutationObserver(function() {
                        var len = getReply().length;
                        console.log('[GM-DOM] changed len=' + len);
                        clearTimeout(window.__gmDebounce);
                        window.__gmDebounce = setTimeout(function() { tryPost('debounce'); }, 1500);
                    });
                    window.__gmObserver.observe(document.body, { childList: true, subtree: true, characterData: true });

                    window.__gmPolling = setInterval(function() {
                        if (window.__gmSent) { clearInterval(window.__gmPolling); return; }
                        window.__gmPollCount++;
                        var len = getReply().length;
                        if (len === 0 && window.__gmPollCount === 5) {
                            var c = document.querySelectorAll('model-response,message-content,[class*="response-content"],[class*="model-response"],[class*="markdown"],[class*="assistant"]').length;
                            try { window.webkit.messageHandlers.\(handler)_debug.postMessage('GM 5s仍空，候选容器=' + c); } catch(e) {}
                        }
                        if (len >= 5 && len === window.__gmPrevPollLen) {
                            if (++window.__gmNoChangeCount >= 3) { clearInterval(window.__gmPolling); tryPost('poll-3s'); }
                        } else { window.__gmNoChangeCount = 0; }
                        window.__gmPrevPollLen = len;
                    }, 1000);

                    window.__gmMaxTimer = setTimeout(function() {
                        if (!window.__gmSent) tryPost('timeout-90s');
                    }, 90000);

                    console.log('[GMListener] 监听启动');
                };
            })();
            """
        }
    }

    // MARK: - 3. 输入 + 发送脚本
    //
    // 发送策略优先级（彻底不依赖 querySelector 按钮）：
    //  1. Enter键（keydown/keypress/keyup）→ 发送到输入框 + document.body
    //  2. 全页面按钮评分（如果有按钮则点）
    //  3. 坐标点击（模拟人工点击发送区域）
    //  500ms 后检查输入框是否清空来判断是否成功

    static func buildInputScript(query: String, platform: AIPlatform) -> String {
        let escaped = escapeForJS(query)

        switch platform {
        case .deepSeek:
            return """
            (function() {
                var DBG = 'deepSeekReply_debug';
                var ERR = 'deepSeekReply_error';
                function post(ch, msg) { try { window.webkit.messageHandlers[ch].postMessage(msg); } catch(e) {} }

                console.log('[DSInject] 开始，文本长度=\(query.count)');

                // ── Step1：找输入框 ──────────────────────────────────
                function findInput() {
                    return document.querySelector('textarea#chat-input')
                        || document.querySelector('textarea[placeholder]')
                        || document.querySelector('textarea')
                        || (document.activeElement && document.activeElement.tagName !== 'BODY'
                            ? document.activeElement : null);
                }

                var input = findInput();

                if (!input) {
                    // 没有输入框：坐标点击页面底部中央唤醒焦点，再重试
                    var cx = window.innerWidth / 2;
                    var cy = window.innerHeight * 0.82;
                    var el = document.elementFromPoint(cx, cy);
                    post(DBG, '无输入框，坐标唤醒(' + Math.round(cx) + ',' + Math.round(cy) + ')→' + (el ? el.tagName : 'null'));
                    if (el) {
                        el.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true, clientX:cx, clientY:cy }));
                        el.dispatchEvent(new MouseEvent('mouseup',   { bubbles:true, cancelable:true, clientX:cx, clientY:cy }));
                        el.click();
                    }
                    setTimeout(function() {
                        input = document.querySelector('textarea') || document.activeElement;
                        if (input && input.tagName !== 'BODY' && input.tagName !== 'HTML') {
                            post(DBG, '二次找到: ' + input.tagName);
                            doInject(input);
                        } else {
                            var total = document.querySelectorAll('*').length;
                            post(DBG, '❌ 二次仍无输入框，DOM元素总数=' + total + '，title=' + document.title.substring(0,30));
                            post(ERR, 'input_not_found');
                        }
                    }, 800);
                    return;
                }

                post(DBG, '输入框: ' + input.tagName + ' id=' + (input.id||'-') + ' ph=' + (input.placeholder||'-').substring(0,20));
                doInject(input);

                // ── Step2：写入文本 ─────────────────────────────────
                function doInject(el) {
                    el.focus();
                    el.dispatchEvent(new Event('focus', { bubbles: true }));

                    var desc = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
                    if (desc && desc.set) {
                        desc.set.call(el, `\(escaped)`);
                    } else {
                        el.value = `\(escaped)`;
                    }

                    el.dispatchEvent(new InputEvent('input', { bubbles:true, cancelable:true, inputType:'insertText', data:`\(escaped)` }));
                    el.dispatchEvent(new Event('change', { bubbles:true }));

                    var written = (el.value || '').length;
                    post(DBG, '文本已写入，实际长度=' + written);
                    console.log('[DSInject] value长度=' + written);

                    // 启动回复监听
                    if (typeof window.__startDSListener === 'function') {
                        window.__startDSListener();
                    }

                    // Step3：发送（延迟300ms等React状态稳定）
                    setTimeout(function() { trySend(el, 1); }, 300);
                }

                // ── Step3：多策略发送，最多4轮 ──────────────────────
                function trySend(el, round) {
                    var vw = window.innerWidth, vh = window.innerHeight;

                    // ── 策略A：确保焦点在输入框，光标在末尾 ──────────
                    el.focus();
                    if (el.setSelectionRange) {
                        el.setSelectionRange(el.value.length, el.value.length);
                    }

                    // ── 策略B：Enter键（keydown + keypress + keyup）──
                    function fireEnter(target) {
                        var o = { bubbles:true, cancelable:true, key:'Enter', code:'Enter', keyCode:13, which:13, composed:true };
                        target.dispatchEvent(new KeyboardEvent('keydown',  o));
                        target.dispatchEvent(new KeyboardEvent('keypress', o));
                        target.dispatchEvent(new KeyboardEvent('keyup',    o));
                    }
                    fireEnter(el);

                    // ── 策略C：Form submit（最可靠，绕过按钮查找）────
                    var form = (typeof el.closest === 'function') ? el.closest('form') : null;
                    if (form) {
                        if (typeof form.requestSubmit === 'function') {
                            form.requestSubmit();
                            post(DBG, '第' + round + '轮 form.requestSubmit()');
                        } else {
                            form.dispatchEvent(new Event('submit', { bubbles:true, cancelable:true }));
                        }
                    } else {
                        post(DBG, '第' + round + '轮 无form，vw=' + vw + ' vh=' + vh);
                    }

                    // ── 策略D：广谱可点击元素评分（包括 role=button/div/span）
                    var best = null, bestScore = -1;
                    var selector = 'button, [role="button"], input[type="submit"], ' +
                                   '[class*="send"], [class*="Send"], [class*="submit"]';
                    document.querySelectorAll(selector).forEach(function(b) {
                        if (b.disabled || b.getAttribute('aria-disabled') === 'true') return;
                        var s = 0;
                        var aria = (b.getAttribute('aria-label') || '').toLowerCase();
                        var cls  = (b.className || '').toLowerCase();
                        var txt  = (b.textContent || '').trim().toLowerCase();
                        var typ  = (b.type || b.getAttribute('type') || '').toLowerCase();
                        if (typ === 'submit') s += 10;
                        if (aria.includes('send') || aria.includes('发送')) s += 8;
                        if (txt === '发送' || txt === 'send') s += 7;
                        if (cls.includes('send') || cls.includes('submit')) s += 6;
                        if (b.querySelector('svg') && txt.length < 3) s += 4;
                        if (s > bestScore) { bestScore = s; best = b; }
                    });
                    if (best) {
                        best.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true }));
                        best.dispatchEvent(new MouseEvent('mouseup',   { bubbles:true, cancelable:true }));
                        best.click();
                        post(DBG, '第' + round + '轮元素点击: tag=' + best.tagName + ' role=' + (best.getAttribute('role')||'-') + ' aria="' + (best.getAttribute('aria-label')||'').substring(0,20) + '"');
                    } else {
                        // 上报页面里所有 role=button 元素数，帮助调试
                        var rolebtns = document.querySelectorAll('[role="button"]').length;
                        var allbtns  = document.querySelectorAll('button').length;
                        post(DBG, '第' + round + '轮无可点击元素: button=' + allbtns + ' role-button=' + rolebtns);
                    }

                    // ── 策略E：坐标点击（依赖 vw/vh 非零）────────────
                    if (vw > 0 && vh > 0) {
                        function clickAt(x, y) {
                            var t = document.elementFromPoint(x, y);
                            if (!t) return;
                            t.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                            t.dispatchEvent(new MouseEvent('mouseup',   { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                            t.dispatchEvent(new MouseEvent('click',     { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                        }
                        clickAt(vw - 44, vh - 88);
                        clickAt(vw - 44, vh - 130);
                    }

                    // 500ms后检查是否清空
                    setTimeout(function() {
                        var remaining = (el.value || '').trim().length;
                        if (remaining === 0) {
                            post(DBG, '✓ 第' + round + '轮发送成功，输入框已清空');
                        } else if (round < 4) {
                            post(DBG, '第' + round + '轮后仍有 ' + remaining + ' 字，600ms后重试');
                            setTimeout(function() { trySend(el, round + 1); }, 600);
                        } else {
                            post(DBG, '⚠️ ' + round + '轮后仍未清空，发送可能失败');
                            post(ERR, 'send_failed');
                        }
                    }, 500);
                }
            })();
            """

        case .gemini:
            return """
            (function() {
                var DBG = 'geminiReply_debug';
                var ERR = 'geminiReply_error';
                function post(ch, msg) { try { window.webkit.messageHandlers[ch].postMessage(msg); } catch(e) {} }

                console.log('[GMInject] 开始，文本长度=\(query.count)');

                // ── Step1：找输入框 ──────────────────────────────────
                function findEditor() {
                    return document.querySelector('rich-textarea .ql-editor')
                        || document.querySelector('rich-textarea [contenteditable="true"]')
                        || document.querySelector('[contenteditable="true"][role="textbox"]')
                        || document.querySelector('[contenteditable="true"]')
                        || document.querySelector('textarea')
                        || (document.activeElement && document.activeElement !== document.body
                            ? document.activeElement : null);
                }

                var editor = findEditor();

                if (!editor) {
                    var cx = window.innerWidth / 2;
                    var cy = window.innerHeight * 0.82;
                    var el = document.elementFromPoint(cx, cy);
                    post(DBG, 'GM 无输入框，坐标唤醒(' + Math.round(cx) + ',' + Math.round(cy) + ')→' + (el ? el.tagName : 'null'));
                    if (el) {
                        el.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true, clientX:cx, clientY:cy }));
                        el.click();
                    }
                    setTimeout(function() {
                        editor = findEditor() || document.activeElement;
                        if (editor && editor.tagName !== 'BODY') {
                            post(DBG, 'GM 二次找到: ' + editor.tagName);
                            doInject(editor);
                        } else {
                            post(DBG, 'GM ❌ 二次仍无输入框，DOM总=' + document.querySelectorAll('*').length);
                            post(ERR, 'input_not_found');
                        }
                    }, 800);
                    return;
                }

                post(DBG, 'GM 输入框: ' + editor.tagName + ' ce=' + (editor.getAttribute('contenteditable')||'-'));
                doInject(editor);

                // ── Step2：写入文本 ─────────────────────────────────
                function doInject(el) {
                    el.focus();
                    el.dispatchEvent(new Event('focus', { bubbles: true }));

                    if (el.isContentEditable) {
                        el.innerHTML = '';
                        var ok = document.execCommand('insertText', false, `\(escaped)`);
                        if (!ok || el.innerText.trim().length === 0) {
                            var p = document.createElement('p');
                            p.textContent = `\(escaped)`;
                            el.innerHTML = '';
                            el.appendChild(p);
                            var range = document.createRange();
                            range.selectNodeContents(el);
                            range.collapse(false);
                            var sel = window.getSelection();
                            if (sel) { sel.removeAllRanges(); sel.addRange(range); }
                        }
                    } else {
                        var desc = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
                        if (desc && desc.set) { desc.set.call(el, `\(escaped)`); }
                        else { el.value = `\(escaped)`; }
                    }

                    el.dispatchEvent(new InputEvent('input', { bubbles:true, cancelable:true, inputType:'insertText', data:`\(escaped)` }));
                    el.dispatchEvent(new Event('change', { bubbles:true }));

                    var written = (el.innerText || el.value || '').trim().length;
                    post(DBG, 'GM 文本已写入，实际长度=' + written);

                    if (typeof window.__startGMListener === 'function') {
                        window.__startGMListener();
                    }

                    setTimeout(function() { trySend(el, 1); }, 400);
                }

                // ── Step3：多策略发送 ────────────────────────────────
                function trySend(el, round) {
                    var vw = window.innerWidth, vh = window.innerHeight;

                    // 策略A：Enter键
                    function fireEnter(target) {
                        var o = { bubbles:true, cancelable:true, key:'Enter', code:'Enter', keyCode:13, which:13 };
                        target.dispatchEvent(new KeyboardEvent('keydown',  o));
                        target.dispatchEvent(new KeyboardEvent('keypress', o));
                        target.dispatchEvent(new KeyboardEvent('keyup',    o));
                    }
                    fireEnter(el);
                    fireEnter(document.body);

                    // 策略B：按钮评分
                    var best = null, bestScore = -1;
                    document.querySelectorAll('button').forEach(function(b) {
                        if (b.disabled) return;
                        var s = 0;
                        var aria = (b.getAttribute('aria-label')||'').toLowerCase();
                        var jsn  = (b.getAttribute('jsname')||'').toLowerCase();
                        var cls  = (b.className||'').toLowerCase();
                        var txt  = (b.textContent||'').trim().toLowerCase();
                        if (aria.includes('send') || aria.includes('发送')) s += 10;
                        if (jsn === 'qx7uuf') s += 9;
                        if (txt === 'send' || txt === '发送') s += 8;
                        if (cls.includes('send') || cls.includes('submit')) s += 6;
                        if (b.querySelector('svg') && txt.length < 3) s += 3;
                        if (s > bestScore) { bestScore = s; best = b; }
                    });
                    if (best) {
                        best.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true }));
                        best.dispatchEvent(new MouseEvent('mouseup',   { bubbles:true, cancelable:true }));
                        best.click();
                        post(DBG, 'GM 第' + round + '轮按钮: ' + (best.getAttribute('aria-label')||'').substring(0,20));
                    }

                    // 策略C：坐标点击
                    function clickAt(x, y) {
                        var t = document.elementFromPoint(x, y);
                        if (!t) return;
                        t.dispatchEvent(new MouseEvent('mousedown', { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                        t.dispatchEvent(new MouseEvent('mouseup',   { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                        t.dispatchEvent(new MouseEvent('click',     { bubbles:true, cancelable:true, clientX:x, clientY:y, view:window }));
                    }
                    clickAt(vw - 44, vh - 88);
                    clickAt(vw - 44, vh - 130);

                    // 500ms后检查
                    setTimeout(function() {
                        var remaining = (el.innerText || el.value || '').trim().length;
                        if (remaining === 0) {
                            post(DBG, 'GM ✓ 第' + round + '轮发送成功');
                        } else if (round < 4) {
                            post(DBG, 'GM 第' + round + '轮后仍有 ' + remaining + ' 字，重试');
                            setTimeout(function() { trySend(el, round + 1); }, 600);
                        } else {
                            post(DBG, 'GM ⚠️ ' + round + '轮后仍未清空');
                            post(ERR, 'send_failed');
                        }
                    }, 500);
                }
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
        return """
        (function() {
            var input = document.querySelector('textarea') || document.querySelector('[contenteditable="true"]');
            var btn   = document.querySelector('button[type="submit"]')
                     || document.querySelector('button[aria-label*="Send"]')
                     || document.querySelector('button[jsname="Qx7uuf"]');
            var isReady = !!(input && btn);
            console.log('[\(platform.messageHandler)-Ready] input=' + !!input + ' btn=' + !!btn + ' totalBtn=' + document.querySelectorAll('button').length);
            window.webkit.messageHandlers.\(readyHandler).postMessage(isReady ? "true" : "false");
        })();
        """
    }

    // MARK: - 私有辅助

    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "$",  with: "\\$")
    }
}
