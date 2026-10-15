script_name('BP Tasks Dock')
script_author('claudenahuy')
script_description('bp-dock')
script_version('1.1')

local JS_SOURCE = [==[
(function () {
'use strict';
var VER = 5;
if (window.__bpq && window.__bpq.v === VER) return;
if (window.__bpq) { try { window.__bpq.destroy(); } catch (e) {} }
var KEYS = ['bp_mission_default', 'bp_mission_premium', 'bp_mission_premium_plus'];
var DOCK_ID = 'bpq-dock', PANEL_ID = 'bpq-panel', STYLE_ID = 'bpq-style';
var S = window.__bpq_keep || (window.__bpq_keep = {}); // \u0436\u0438\u0432\u0451\u0442 \u0442\u043e\u043b\u044c\u043a\u043e \u0432 \u043f\u0430\u043c\u044f\u0442\u0438 \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u044b
if (!S.bp) S.bp = {};
if (S.browserId === undefined) S.browserId = null;
var quests = null, questsKey = '', loading = false, retryAt = 0;
var ver = 0, lastKey = '', startedAt = Date.now(), timerId = 0, heartbeatId = 0, mo = null, rafScheduled = false, destroyed = false;
var selId = null, items = [], mode = 'off';
function log() {
try { console.log.apply(console, ['[bpq]'].concat([].slice.call(arguments))); } catch (e) {}
}
function esc(s) {
return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
});
}
function fmt(n) {
try { return new Intl.NumberFormat('ru-RU').format(n); } catch (e) { return String(n); }
}
/* ---------- \u043f\u0435\u0440\u0435\u0445\u0432\u0430\u0442 \u0434\u0430\u043d\u043d\u044b\u0445, \u043a\u043e\u0442\u043e\u0440\u044b\u0435 \u0438\u0433\u0440\u0430 \u0438 \u0442\u0430\u043a \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u044f\u0435\u0442 \u0432 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441 ---------- */
function parseArgs(raw) {
var s = (raw === undefined || raw === null) ? '[]' : String(raw);
try {
return JSON.parse(s.replace(/[\\]/g, '\\\\').replace(/[\/]/g, '\\/').replace(/[\b]/g, '\\b')
.replace(/[\f]/g, '\\f').replace(/[\n]/g, '\\n').replace(/[\r]/g, '\\r').replace(/[\t]/g, '\\t'));
} catch (e) {
try { return JSON.parse(s); } catch (e2) { return null; }
}
}
function onEvent(name, raw) {
if (name === 'event.battlePass.initializeBattlePassData') {
var d = parseArgs(raw);
var o = Array.isArray(d) ? d[0] : d;
if (o && typeof o === 'object') { S.bp = Object.assign({}, S.bp, o); ver++; }
} else if (name === 'event.battlePass.updateQuestsProgress') {
var p = parseArgs(raw);
var a = Array.isArray(p) ? (Array.isArray(p[0]) ? p[0] : p) : null;
if (a && a.length) { S.progress = a; ver++; }
}
}
var origExec = window.executeEvent;
function wrappedExec(name) {
try { onEvent(name, arguments[1]); } catch (e) {}
return origExec.apply(this, arguments);
}
if (typeof origExec === 'function') window.executeEvent = wrappedExec;
var XO = XMLHttpRequest.prototype;
var oOpen = XO.open, oSetHeader = XO.setRequestHeader;
function wrappedOpen(method, url) {
try { this.__bpqUrl = String(url); } catch (e) {}
return oOpen.apply(this, arguments);
}
function wrappedSetHeader(k, v) {
try {
if (this.__bpqUrl && /\/client\/json\/table\/get\?/.test(this.__bpqUrl) && /^authorization$/i.test(k)) {
if (!S.api) log('\u043f\u043e\u043b\u0443\u0447\u0435\u043d \u0434\u043e\u0441\u0442\u0443\u043f \u043a API');
S.api = { url: this.__bpqUrl, auth: v };
}
} catch (e) {}
return oSetHeader.apply(this, arguments);
}
XO.open = wrappedOpen;
XO.setRequestHeader = wrappedSetHeader;
var cefWrapped = null, cefOrig = null;
function hookCef() {
try {
var c = window.cef;
if (!c || typeof c.SendMessage !== 'function' || c.SendMessage === cefWrapped) return;
if (c.SendMessage.__bpq) return;
cefOrig = c.SendMessage;
cefWrapped = function (msg, id) {
if (id !== undefined && id !== null) S.browserId = id;
return cefOrig.apply(this, arguments);
};
cefWrapped.__bpq = true;
c.SendMessage = cefWrapped;
} catch (e) {}
}
function sendMsg(m) {
if (window.cef && typeof window.cef.SendMessage === 'function' && S.browserId !== null) {
window.cef.SendMessage(m, S.browserId);
} else { log('\u043d\u0435\u0442 browserId, \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435 \u043d\u0435 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e:', m); }
}
/* ---------- \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u043e\u043f\u0438\u0441\u0430\u043d\u0438\u0439 \u0437\u0430\u0434\u0430\u043d\u0438\u0439 (\u0442\u043e\u0442 \u0436\u0435 \u0437\u0430\u043f\u0440\u043e\u0441, \u0447\u0442\u043e \u0434\u0435\u043b\u0430\u0435\u0442 \u0441\u0430\u043c\u0430 \u0438\u0433\u0440\u0430) ---------- */
function loadQuests() {
if (!S.api || loading) return;
var key = KEYS[Math.min(S.bp.premium || 0, KEYS.length - 1)];
if (quests && questsKey === key) return;
if (Date.now() < retryAt) return;
loading = true;
var url = S.api.url.replace(/([?&]key=)[^&]*/, '$1' + key);
fetch(url, { headers: { Authorization: S.api.auth } }).then(function (r) {
if (!r.ok) throw new Error('HTTP ' + r.status);
return r.json();
}).then(function (data) {
if (!Array.isArray(data)) throw new Error('bad data');
quests = data; questsKey = key; loading = false; ver++;
}).catch(function (e) {
loading = false; retryAt = Date.now() + 5000; log('\u043e\u0448\u0438\u0431\u043a\u0430 \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438 \u0437\u0430\u0434\u0430\u043d\u0438\u0439', String(e));
});
}
/* ---------- \u0441\u0442\u0438\u043b\u0438 ---------- */
var U = 'var(--bpu)';
function c(n) { return 'calc(' + n + '*' + U + ')'; }
var CSS = [
/* \u0437\u0430\u0434\u0430\u043d\u0438\u044f \u0441\u043b\u0435\u0432\u0430 */
'#bpq-dock{position:fixed;z-index:2;display:none;flex-direction:column;box-sizing:border-box;color:#fff}',
'#bpq-dock.bpq-on{display:flex}',
'#bpq-dock .bpq-title{font-family:HeadingNowMedium;font-size:' + c(26) + ';line-height:1;text-transform:uppercase;',
'margin:' + c(2) + ' 0 ' + c(14) + ';padding-left:' + c(12) + ';border-left:' + c(4) + ' solid #fff600}',
'#bpq-dock .bpq-list{width:100%;height:auto;flex:1 1 auto;min-height:0;box-sizing:border-box;padding-right:' + c(14) + '}',
'#bpq-dock .battle-pass-quests__item{flex:0 0 auto;cursor:pointer;background:rgba(26,12,50,.62);',
'border:1px solid rgba(255,255,255,.1);box-sizing:border-box}',
'#bpq-dock .battle-pass-quests__item:hover{background:rgba(255,255,255,.2)}',
'#bpq-dock .battle-pass-quests__item.battle-pass-quests__item--active{background:rgba(255,255,255,.2);',
'border-color:#fff600;box-shadow:0 0 ' + c(14) + ' rgba(255,246,0,.28)}',
'#bpq-dock .bpq-msg{font-family:HeadingNowRegular;font-size:' + c(16) + ';line-height:1.35;',
'color:rgba(255,255,255,.8);padding:' + c(8) + ' 0}',
'#bpq-dock .bpq-foot{display:flex;gap:' + c(12) + ';margin-top:' + c(14) + '}',
'#bpq-dock .bpq-timer{flex:1 1 0;min-width:0;display:flex;align-items:center;gap:' + c(10) + ';',
'height:' + c(66) + ';padding:0 ' + c(14) + ';border-radius:' + c(14) + ';background:rgba(26,12,50,.62);',
'border:1px solid rgba(255,255,255,.1);box-sizing:border-box}',
'#bpq-dock .bpq-ico{color:#fff;font-size:' + c(30) + '}',
'#bpq-dock .bpq-cap{font-family:HeadingNowRegular;font-size:' + c(12) + ';white-space:nowrap}',
'#bpq-dock .bpq-val{font-family:HeadingNowBold;font-size:' + c(20) + ';color:#fff600;text-transform:uppercase;white-space:nowrap}',
'#bpq-dock .bpq-reload{flex:1 1 0;min-width:0;display:flex;align-items:center;justify-content:center;',
'height:' + c(66) + ';padding:0 ' + c(8) + ';border-radius:' + c(14) + ';background:#fff;color:#251e48;',
'font-family:HeadingNowMedium;font-size:' + c(16) + ';text-transform:uppercase;text-align:center;cursor:pointer;',
'box-sizing:border-box;transition:.14s ease-out;transition-property:background-color,color,box-shadow}',
'#bpq-dock .bpq-reload:hover{box-shadow:0 0 ' + c(20) + ' rgba(255,255,255,.5)}',
'#bpq-dock .bpq-reload:active{background:#979797;color:#fff}',
'#bpq-dock .bpq-reload.bpq-off{opacity:.35;pointer-events:none}',
'#bpq-dock.bpq-narrow .bpq-title{font-size:' + c(21) + '}',
'#bpq-dock.bpq-narrow .bpq-list{padding-right:' + c(10) + '}',
'#bpq-dock.bpq-narrow .battle-pass-quests__item{height:auto;min-height:' + c(96) + ';padding:' + c(12) + '}',
'#bpq-dock.bpq-narrow .battle-pass-quests__item-info{width:75%;height:auto;gap:' + c(6) + ';justify-content:flex-start}',
'#bpq-dock.bpq-narrow .battle-pass-quests__item-reward{width:' + c(62) + '}',
'#bpq-dock.bpq-narrow .battle-pass-quests__item-title{font-size:' + c(14) + '}',
'#bpq-dock.bpq-narrow .battle-pass-quests__item-description{font-size:' + c(11) + '}',
'#bpq-dock.bpq-narrow .bpq-cap{display:none}',
'#bpq-dock.bpq-narrow .bpq-timer,#bpq-dock.bpq-narrow .bpq-reload{height:' + c(52) + '}',
'#bpq-dock.bpq-narrow .bpq-reload{font-size:' + c(13) + '}',
/* \u043f\u0430\u043d\u0435\u043b\u044c \u0432\u044b\u0431\u0440\u0430\u043d\u043d\u043e\u0433\u043e \u0437\u0430\u0434\u0430\u043d\u0438\u044f */
'#bpq-panel{position:fixed;z-index:2;display:none;box-sizing:border-box;align-items:center;gap:' + c(28) + ';',
'padding:0 ' + c(28) + ';color:#fff;border-radius:' + c(18) + ';overflow:hidden;',
'background:linear-gradient(180deg,rgba(64,32,118,.62),rgba(34,16,70,.68));border:1px solid rgba(255,255,255,.14)}',
'#bpq-panel.bpq-on{display:flex}',
'#bpq-panel .bpq-p-main{flex:1.4 1 0;min-width:0}',
'#bpq-panel .bpq-p-title{font-family:HeadingNowBold;font-size:' + c(26) + ';line-height:1.1;margin-bottom:' + c(8) + '}',
'#bpq-panel .bpq-p-desc{font-family:HeadingNowRegular;font-size:' + c(16) + ';line-height:1.3;',
'max-height:' + c(62) + ';overflow:hidden;color:rgba(255,255,255,.92)}',
'#bpq-panel .bpq-p-mid{flex:1 1 0;min-width:0;display:flex;flex-direction:column;justify-content:center}',
'#bpq-panel .battle-pass-quests__details-progress-wrapper{margin-top:0}',
'#bpq-panel .bpq-help{margin-top:' + c(12) + ';min-height:' + c(46) + ';font-size:' + c(16) + ';cursor:pointer;',
'border-radius:' + c(12) + ';text-transform:uppercase}',
'#bpq-panel .bpq-p-rew{flex:0 0 auto}',
'#bpq-panel .bpq-p-cap{font-family:HeadingNowMedium;font-size:' + c(15) + ';margin-bottom:' + c(8) + '}',
'#bpq-panel .bpq-p-rlist{gap:' + c(16) + ';justify-content:flex-start}',
'#bpq-panel .battle-pass-quests__details-reward{gap:' + c(6) + '}',
'#bpq-panel .battle-pass-quests__details-reward-image-wrapper{width:' + c(58) + ';height:' + c(58) + ';border-radius:' + c(12) + ';overflow:hidden}',
'#bpq-panel .battle-pass-quests__details-reward-image{width:' + c(44) + '}',
'#bpq-panel .battle-pass-quests__details-reward-title{font-size:' + c(11) + ';line-height:1.15;text-align:center;max-width:' + c(88) + '}',
/* \u0432\u0435\u0442\u043a\u0430 \u043d\u0430\u0433\u0440\u0430\u0434: \u043f\u0440\u044f\u0447\u0435\u043c \u0440\u043e\u0434\u043d\u0443\u044e (\u043f\u043e\u0441\u0442\u0440\u0430\u043d\u0438\u0447\u043d\u0443\u044e) \u0438 \u043f\u043e\u043a\u0430\u0437\u044b\u0432\u0430\u0435\u043c \u0441\u0432\u043e\u044e \u0431\u0435\u0441\u043a\u043e\u043d\u0435\u0447\u043d\u0443\u044e \u043b\u0435\u043d\u0442\u0443 */
'.bpq-active .battle-pass-main__pagination{display:none!important}',
'.bpq-active .battle-pass-main__lines{display:none!important}',
'.bpq-active .battle-pass-main__premium-button-wrapper{position:fixed!important;bottom:auto!important;',
'left:var(--bpq-pl)!important;top:var(--bpq-pt)!important;width:var(--bpq-pw)!important;height:var(--bpq-ph)!important}',
'#bpq-strip{position:fixed;z-index:2;display:none;overflow:hidden;box-sizing:border-box}',
'#bpq-strip.bpq-on{display:block}',
'#bpq-strip-view{width:100%;height:100%;overflow:hidden;position:relative}',
'#bpq-strip-inner{padding:' + c(34) + ' ' + c(30) + ' 0 0;box-sizing:border-box;transform-origin:0 0;transform:scale(var(--bpq-strip-s,1))}',
/* \u0432 \u043e\u0440\u0438\u0433\u0438\u043d\u0430\u043b\u0435 .battle-pass-main__line \u0436\u0451\u0441\u0442\u043a\u043e \u043f\u043e\u0434 5 \u043a\u0430\u0440\u0442\u043e\u0447\u0435\u043a - \u0443 \u043d\u0430\u0441 \u0432 \u043d\u0435\u0439 100, \u0441\u043d\u0438\u043c\u0430\u0435\u043c \u043f\u043e\u0442\u043e\u043b\u043e\u043a, \u0438\u043d\u0430\u0447\u0435 \u043a\u0430\u0440\u0442\u043e\u0447\u043a\u0438 \u0441\u043f\u043b\u044e\u0449\u0438\u0442 */
'#bpq-strip .battle-pass-main__line{width:max-content!important}',
'#bpq-strip .battle-pass-main__reward{flex-shrink:0}',
/* \u0434\u043e\u0440\u043e\u0436\u043a\u0430 \u0443\u0440\u043e\u0432\u043d\u0435\u0439 \u0432 \u043e\u0440\u0438\u0433\u0438\u043d\u0430\u043b\u0435 \u0440\u0430\u0441\u0441\u0447\u0438\u0442\u0430\u043d\u0430 \u043d\u0430 5 \u043e\u0442\u043c\u0435\u0442\u043e\u043a - \u0440\u0430\u0441\u0442\u044f\u0433\u0438\u0432\u0430\u0435\u043c \u043d\u0430 \u0432\u0441\u044e \u043b\u0435\u043d\u0442\u0443 \u0438 \u043d\u0435 \u0434\u0430\u0451\u043c \u043e\u0442\u043c\u0435\u0442\u043a\u0430\u043c \u0441\u043f\u043b\u044e\u0449\u0438\u0442\u044c\u0441\u044f */
'#bpq-strip .battle-pass-main__experience{width:max-content}',
'#bpq-strip .battle-pass-main__experience-line{width:max-content}',
'#bpq-strip .battle-pass-main__experience-line-level-wrapper{flex-shrink:0}',
'#bpq-strip .battle-pass-main__reward{cursor:pointer}',
'#bpq-strip .battle-pass-main__experience-line-level-wrapper-button{cursor:pointer}',
'#bpq-strip .battle-pass-main__experience-line-reset{cursor:pointer}',
/* \u043f\u043e\u043b\u0437\u0443\u043d\u043e\u043a \u043f\u0440\u043e\u043a\u0440\u0443\u0442\u043a\u0438 \u043b\u0435\u043d\u0442\u044b */
'#bpq-slider{position:fixed;z-index:2;display:none;box-sizing:border-box}',
'#bpq-slider.bpq-on{display:block}',
'#bpq-slider-track{position:relative;width:100%;height:100%;border-radius:999px;box-sizing:border-box;',
'background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.14);cursor:pointer}',
'#bpq-slider-thumb{position:absolute;top:0;height:100%;min-width:' + c(40) + ';border-radius:999px;',
'background:linear-gradient(180deg,#fff,#d6d6de);cursor:grab;box-shadow:0 0 ' + c(10) + ' rgba(0,0,0,.45)}',
'#bpq-slider-thumb:hover{background:linear-gradient(180deg,#fff,#fff600)}',
'#bpq-slider-thumb:active{cursor:grabbing;background:#fff600}'
].join('');
function hideBroken(e) {
if (e.target && e.target.tagName === 'IMG') e.target.style.visibility = 'hidden';
}
function ensureStyle() {
if (document.getElementById(STYLE_ID)) return;
var st = document.createElement('style');
st.id = STYLE_ID; st.textContent = CSS;
(document.head || document.documentElement).appendChild(st);
}
function ensureDock(root) {
var d = document.getElementById(DOCK_ID);
if (d && d.parentNode === root) return d;
if (d && d.parentNode) d.parentNode.removeChild(d);
d = document.createElement('div');
d.id = DOCK_ID;
d.innerHTML = '<div class="bpq-title">\u0415\u0436\u0435\u0434\u043d\u0435\u0432\u043d\u044b\u0435 \u0437\u0430\u0434\u0430\u043d\u0438\u044f</div>' +
'<div class="battle-pass-quests__quests bpq-list"></div>' +
'<div class="bpq-foot"><div class="bpq-timer"><i class="bpq-ico icon-refresh-timer"></i>' +
'<div><div class="bpq-cap">\u0414\u043e \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f \u0437\u0430\u0434\u0430\u043d\u0438\u0439:</div><div class="bpq-val">--</div></div></div>' +
'<div class="bpq-reload">\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u0437\u0430\u0434\u0430\u043d\u0438\u044f</div></div>';
d.querySelector('.bpq-reload').addEventListener('click', function () {
sendMsg('battlePass.quests.reload');
});
d.querySelector('.bpq-list').addEventListener('click', function (e) {
var it = e.target.closest ? e.target.closest('.battle-pass-quests__item') : null;
if (!it) return;
selId = it.getAttribute('data-id');
markSelected(d);
renderPanel(root);
});
d.addEventListener('error', hideBroken, true);
lastKey = '';
root.appendChild(d);
return d;
}
function ensurePanel(root) {
var p = document.getElementById(PANEL_ID);
if (p && p.parentNode === root) return p;
if (p && p.parentNode) p.parentNode.removeChild(p);
p = document.createElement('div');
p.id = PANEL_ID;
p.addEventListener('click', function (e) {
var h = e.target.closest ? e.target.closest('.bpq-help') : null;
if (h) sendMsg('battlePass.quests.help|' + h.getAttribute('data-id'));
});
p.addEventListener('error', hideBroken, true);
panelKey = '';
root.appendChild(p);
return p;
}
/* ---------- \u0440\u0430\u0441\u043a\u043b\u0430\u0434\u043a\u0430: \u0441\u0447\u0438\u0442\u0430\u0435\u043c \u043f\u043e \u0440\u0435\u0430\u043b\u044c\u043d\u044b\u043c \u044d\u043b\u0435\u043c\u0435\u043d\u0442\u0430\u043c \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u044b, \u043f\u043e\u0434 \u043b\u044e\u0431\u043e\u0435 \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043d\u0438\u0435 ---------- */
/* ---------- \u0432\u0435\u0442\u043a\u0430 \u043d\u0430\u0433\u0440\u0430\u0434: \u0441\u0432\u043e\u044f \u0431\u0435\u0441\u043a\u043e\u043d\u0435\u0447\u043d\u0430\u044f \u043b\u0435\u043d\u0442\u0430 \u0432\u043c\u0435\u0441\u0442\u043e \u043f\u043e\u0441\u0442\u0440\u0430\u043d\u0438\u0447\u043d\u043e\u0439 \u0440\u043e\u0434\u043d\u043e\u0439 ---------- */
var branchCache = '', branchAt = 0;
function branchImgBase() {
if (branchCache && Date.now() - branchAt < 3000) return branchCache;
var re = /^(https?:\/\/[^?#]+\/projects\/[^\/?#]+\/systems\/battlepass\/[^\/?#]+)\//;
var native = [].filter.call(document.querySelectorAll('img[src]'), function (i) {
return !i.closest || !i.closest('#bpq-strip');
}).map(function (i) { return i.getAttribute('src') || ''; });
var base = '';
for (var i = native.length - 1; i >= 0; i--) { var m = re.exec(native[i]); if (m) { base = m[1]; break; } }
if (!base) {
try {
var entries = performance.getEntriesByType('resource');
for (var j = entries.length - 1; j >= 0; j--) { var m2 = re.exec(entries[j].name); if (m2) { base = m2[1]; break; } }
} catch (e) {}
}
if (!base) base = S.branchBaseGood || ''; // \u043f\u043e\u0441\u043b\u0435\u0434\u043d\u0438\u0439 \u0438\u0437\u0432\u0435\u0441\u0442\u043d\u044b\u0439 \u0432\u0435\u0440\u043d\u044b\u0439 \u0430\u0434\u0440\u0435\u0441, \u043f\u0435\u0440\u0435\u0436\u0438\u0432\u0430\u0435\u0442 \u043f\u0435\u0440\u0435\u043e\u0442\u043a\u0440\u044b\u0442\u0438\u044f \u0411\u041f
if (!base) return ''; // \u0430\u0434\u0440\u0435\u0441\u0430 \u0435\u0449\u0451 \u043d\u0438\u0433\u0434\u0435 \u043d\u0435\u0442 - \u043a\u0430\u0440\u0442\u0438\u043d\u043a\u0438 \u043f\u043e\u044f\u0432\u044f\u0442\u0441\u044f, \u043a\u0430\u043a \u0442\u043e\u043b\u044c\u043a\u043e \u0438\u0433\u0440\u0430 \u0443\u0441\u043f\u0435\u0435\u0442 \u0438\u0445 \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c
S.branchBaseGood = base;
branchCache = base + '/'; branchAt = Date.now();
return branchCache;
}
function iconSrc(name) {
if (S.icons && S.icons[name]) return S.icons[name];
return '';
}
function grabNativeIcons(root) {
if (S.icons) return;
S.icons = {};
var b = root.querySelector('.battle-pass-main__experience-line-level-wrapper-button-img');
var r = root.querySelector('.battle-pass-main__experience-line-reset-icon');
if (b) S.icons.thunder = b.getAttribute('src');
if (r) S.icons.reset = r.getAttribute('src');
}
var rewCommon = null, rewPremium = null, rewLoading = false, rewRetryAt = 0;
function loadBranchData() {
if (!S.api || rewLoading || (rewCommon && rewPremium) || Date.now() < rewRetryAt) return;
rewLoading = true;
var urlC = S.api.url.replace(/([?&]key=)[^&]*/, '$1battlepass_awards_default');
var urlP = S.api.url.replace(/([?&]key=)[^&]*/, '$1battlepass_awards_gold');
Promise.all([
fetch(urlC, { headers: { Authorization: S.api.auth } }).then(function (r) { return r.json(); }),
fetch(urlP, { headers: { Authorization: S.api.auth } }).then(function (r) { return r.json(); })
]).then(function (res) {
if (!Array.isArray(res[0]) || !Array.isArray(res[1])) throw new Error('bad data');
rewCommon = res[0]; rewPremium = res[1]; rewLoading = false; ver++;
}).catch(function (e) {
rewLoading = false; rewRetryAt = Date.now() + 5000; log('\u043e\u0448\u0438\u0431\u043a\u0430 \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438 \u043d\u0430\u0433\u0440\u0430\u0434 \u0432\u0435\u0442\u043a\u0438', String(e));
});
}
function calcDaysLeft() {
var ts = S.bp && S.bp.timestampTaskTime;
if (!ts) return 1;
return Math.max(0, Math.ceil((ts - Math.floor(Date.now() / 1000)) / 86400));
}
function claimed(level, idx) {
var a = S.bp && S.bp.availableToReceive && S.bp.availableToReceive[level - 1];
return !!(a && a[idx]);
}
function setClaimed(level, idx) {
if (!S.bp.availableToReceive) S.bp.availableToReceive = [];
if (!S.bp.availableToReceive[level - 1]) S.bp.availableToReceive[level - 1] = [0, 0];
S.bp.availableToReceive[level - 1][idx] = 1;
ver++;
}
function clickNative(sel) {
var el = document.querySelector(sel);
if (el) { el.click(); return true; }
return false;
}
function emptySlotHtml() {
return '<div class="battle-pass-main__reward" style="visibility:hidden"></div>';
}
function commonCardHtml(r, base) {
var lvl = r.level, locked = (S.bp.level || 0) < lvl, done = claimed(lvl, 0);
var img = (r.sysName && base) ? base + r.sysName : '';
var state;
if (locked) {
state = '<div class="battle-pass-main__lock-button" data-act="descr" data-t="common" data-lvl="' + lvl + '">' +
'<i class="battle-pass-main__lock-icon icon-lock-bp"></i><p class="battle-pass-main__lock-button-title">\u041e\u043f\u0438\u0441\u0430\u043d\u0438\u0435</p></div>';
} else if (done) {
state = '<div class="battle-pass-main__recived"><div class="battle-pass-main__recived-icon icon-check-circle"></div>' +
'<div class="battle-pass-main__recived-text">\u041f\u043e\u043b\u0443\u0447\u0435\u043d\u043e</div></div>';
} else {
state = '<div class="battle-pass-main__reward-button" data-act="get-common" data-lvl="' + lvl + '">\u041f\u043e\u043b\u0443\u0447\u0438\u0442\u044c</div>';
}
return '<div class="battle-pass-main__reward battle-pass-main__reward--common' + (locked ? ' battle-pass-main__reward--locked' : '') +
'" data-lvl="' + lvl + '" data-t="common">' +
'<div class="battle-pass-main__reward-title" data-act="descr" data-t="common" data-lvl="' + lvl + '">' + esc(r.title) + '</div>' +
'<div class="battle-pass-main__reward-image-wrapper" data-act="descr" data-t="common" data-lvl="' + lvl + '">' +
(img ? '<img class="battle-pass-main__reward-image" alt="reward-icon" style="width:100%;height:100%" src="' + esc(img) + '"/>' : '') + '</div>' +
(r.count > 0 ? '<div class="battle-pass-main__reward-count">' + esc(r.count) + ' \u0448\u0442.</div>' : '') +
state + '</div>';
}
function premiumCardHtml(r, base) {
var lvl = r.level, locked = (S.bp.level || 0) < lvl, done = claimed(lvl, 1), hasPrem = (S.bp.premium || 0) > 0;
var img = (r.sysName && base) ? base + r.sysName : '';
var state;
if (locked) {
state = '<div class="battle-pass-main__lock-button" data-act="descr" data-t="premium" data-lvl="' + lvl + '">' +
'<i class="battle-pass-main__lock-icon icon-lock-bp"></i><p class="battle-pass-main__lock-button-title">\u041e\u043f\u0438\u0441\u0430\u043d\u0438\u0435</p></div>';
} else if (done && hasPrem) {
state = '<div class="battle-pass-main__recived"><div class="battle-pass-main__recived-icon icon-check-circle"></div>' +
'<div class="battle-pass-main__recived-text">\u041f\u043e\u043b\u0443\u0447\u0435\u043d\u043e</div></div>';
} else {
var seasonOver = calcDaysLeft() <= 0;
var text = hasPrem ? '\u041f\u043e\u043b\u0443\u0447\u0438\u0442\u044c' : (seasonOver ? '\u041d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u043e' : '\u041a\u0443\u043f\u0438\u0442\u044c Premium');
var icon = hasPrem ? '' : '<i class="arizona-pass-premium-button__icon icon-lock-wide"></i>';
state = '<div class="battle-pass-main__reward-button battle-pass-main__reward-button--premium">' +
'<div class="arizona-pass-premium-button" data-act="get-premium" data-lvl="' + lvl + '">' + icon +
'<div class="arizona-pass-premium-button__text">' + text + '</div></div></div>';
}
return '<div class="battle-pass-main__reward battle-pass-main__reward--premium' + (locked ? ' battle-pass-main__reward--locked' : '') +
'" data-lvl="' + lvl + '" data-t="premium">' +
'<div class="battle-pass-main__reward-title" data-act="descr" data-t="premium" data-lvl="' + lvl + '">' + esc(r.title) + '</div>' +
'<div class="battle-pass-main__reward-image-wrapper" data-act="descr" data-t="premium" data-lvl="' + lvl + '">' +
(img ? '<img class="battle-pass-main__reward-image" alt="reward-icon" style="width:100%;height:100%" src="' + esc(img) + '"/>' : '') + '</div>' +
(r.count > 0 ? '<div class="battle-pass-main__reward-count">' + esc(r.count) + ' \u0448\u0442.</div>' : '') +
state + '</div>';
}
function levelMarkerHtml(lvl, cap) {
var cur = S.bp.level || 0;
var cls = 'battle-pass-main__experience-line-level-wrapper';
if (cur > lvl) cls += ' battle-pass-main__experience-line-level-wrapper--filled';
if (cur === lvl) cls += ' battle-pass-main__experience-line-level-wrapper--current';
if (lvl === 1) cls += ' battle-pass-main__experience-line-level-wrapper--first';
if (lvl === cap) cls += ' battle-pass-main__experience-line-level-wrapper--last';
var extra = '';
if (cur === lvl && lvl !== cap) {
var th = iconSrc('thunder');
extra += '<div class="battle-pass-main__experience-line-level-wrapper-button" data-act="buy-level">' +
(th ? '<img class="battle-pass-main__experience-line-level-wrapper-button-img" src="' + esc(th) + '" alt="thunder-img"/>' : '\u26a1') + '</div>';
}
if (lvl === cap) {
var rs = iconSrc('reset');
extra += '<div class="battle-pass-main__experience-line-reset" data-act="reset">' +
(rs ? '<img class="battle-pass-main__experience-line-reset-icon" src="' + esc(rs) + '" alt="reset"/>' : '\u21bb') + '</div>';
}
return '<div class="' + cls + '">' + extra +
'<div class="battle-pass-main__experience-line-level-value-wrapper">' +
'<div class="battle-pass-main__experience-line-level' + (lvl <= cur ? ' battle-pass-main__experience-line-level--red' : '') + '">' +
'<div class="battle-pass-main__experience-line-level-value">' + lvl + '</div></div></div></div>';
}
var stripKey = '', stripAutoScrolled = false;
function byLevel(arr) {
var map = {}, max = 0;
for (var i = 0; i < arr.length; i++) {
var lvl = arr[i] && (arr[i].level || arr[i].level === 0 ? arr[i].level : i + 1);
map[lvl] = arr[i];
if (lvl > max) max = lvl;
}
return { map: map, max: max };
}
function renderStrip(inner) {
if (!rewCommon || !rewPremium) return false;
var base = branchImgBase();
var c = byLevel(rewCommon), p2 = byLevel(rewPremium);
var cap = Math.max(c.max, p2.max) || 100;
var sig = (S.bp.level || 0) + '|' + (S.bp.premium || 0) + '|' + cap + '|' + base + '|' +
((S.bp.availableToReceive || []).map(function (a) { return a ? a[0] + '' + a[1] : '00'; }).join(''));
if (sig === stripKey) return false;
stripKey = sig;
var commonHtml = [], premHtml = [], markHtml = [];
for (var lvl = 1; lvl <= cap; lvl++) {
var rc = c.map[lvl], rp = p2.map[lvl];
commonHtml.push(rc ? commonCardHtml(rc, base) : emptySlotHtml());
premHtml.push(rp ? premiumCardHtml(rp, base) : emptySlotHtml());
markHtml.push(levelMarkerHtml(lvl, cap));
}
inner.innerHTML =
'<div class="battle-pass-main__line">' +
'<div class="battle-pass-main__lines-caption"><div class="battle-pass-main__lines-caption-text">\u041e\u0411\u042b\u0427\u041d\u042b\u0419</div></div>' +
commonHtml.join('') + '</div>' +
'<div class="battle-pass-main__experience"><div class="battle-pass-main__experience-line">' + markHtml.join('') + '</div></div>' +
'<div class="battle-pass-main__line">' +
'<div class="battle-pass-main__lines-caption"><div class="battle-pass-main__lines-caption-text">PREMIUM</div></div>' +
premHtml.join('') + '</div>';
return true;
}
function ensureStrip(root) {
var s = document.getElementById('bpq-strip');
if (s && s.parentNode === root) return s;
if (s && s.parentNode) s.parentNode.removeChild(s);
s = document.createElement('div');
s.id = 'bpq-strip';
stripKey = ''; stripAutoScrolled = false; // \u043d\u043e\u0432\u0430\u044f \u0440\u0430\u0437\u043c\u0435\u0442\u043a\u0430 \u043e\u0442 \u0438\u0433\u0440\u044b - \u043d\u0430\u043f\u043e\u043b\u043d\u044f\u0435\u043c \u0438 \u0446\u0435\u043d\u0442\u0440\u0438\u0440\u0443\u0435\u043c \u043d\u0430 \u0443\u0440\u043e\u0432\u043d\u0435 \u0437\u0430\u043d\u043e\u0432\u043e
s.innerHTML = '<div id="bpq-strip-view"><div id="bpq-strip-inner"></div></div>';
var view = s.querySelector('#bpq-strip-view');
view.addEventListener('click', function (e) {
var t = e.target.closest ? e.target.closest('[data-act]') : null;
if (!t) return;
var act = t.getAttribute('data-act'), lvl = t.getAttribute('data-lvl');
if (act === 'get-common') {
setClaimed(lvl, 0); sendMsg('battlePass.main.getCommonReward|' + lvl);
} else if (act === 'get-premium') {
if ((S.bp.premium || 0) > 0) { setClaimed(lvl, 1); sendMsg('battlePass.main.getPremiumReward|' + lvl); }
else if (!clickNative('.battle-pass-main__premium-button-wrapper .arizona-pass-premium-button')) clickNative('.battle-pass-main__premium-button-wrapper');
} else if (act === 'descr') {
sendMsg('battlePass.main.rewardDescriptionClick|' + t.getAttribute('data-t') + '|' + (lvl - 1));
} else if (act === 'buy-level') {
clickNative('.battle-pass-main__level-purchase-button');
} else if (act === 'reset') {
sendMsg('battlePass.main.getResetLevel');
}
}, true);
view.addEventListener('wheel', function (e) {
var d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
if (!d) return;
e.preventDefault();
view.scrollLeft += d; // scrollLeft \u0443\u0436\u0435 \u0432 \u044d\u043a\u0440\u0430\u043d\u043d\u044b\u0445 px (\u043f\u0440\u043e\u0432\u0435\u0440\u0435\u043d\u043e \u044d\u043c\u043f\u0438\u0440\u0438\u0447\u0435\u0441\u043a\u0438), \u043c\u0430\u0441\u0448\u0442\u0430\u0431 \u0442\u0443\u0442 \u043d\u0438 \u043f\u0440\u0438 \u0447\u0451\u043c
}, { passive: false });
view.addEventListener('scroll', updateSliderThumb, { passive: true });
root.appendChild(s);
return s;
}
/* ---------- \u043f\u043e\u043b\u0437\u0443\u043d\u043e\u043a \u043f\u0440\u043e\u043a\u0440\u0443\u0442\u043a\u0438 \u043f\u043e\u0434 \u043b\u0435\u043d\u0442\u043e\u0439: \u0442\u044f\u043d\u0435\u0442\u0441\u044f \u043c\u044b\u0448\u044c\u044e, \u043e\u0442\u0440\u0430\u0436\u0430\u0435\u0442 \u043f\u043e\u0437\u0438\u0446\u0438\u044e \u043b\u0435\u043d\u0442\u044b ---------- */
var sliderDragging = false, sliderStartX = 0, sliderStartScroll = 0;
function updateSliderThumb() {
var view = document.getElementById('bpq-strip-view');
var track = document.getElementById('bpq-slider-track');
var thumb = document.getElementById('bpq-slider-thumb');
if (!view || !track || !thumb) return;
var maxScroll = Math.max(0, view.scrollWidth - view.clientWidth);
var trackW = track.clientWidth;
var thumbW = Math.min(trackW, Math.max(40, trackW * (view.clientWidth / Math.max(1, view.scrollWidth))));
thumb.style.width = px(thumbW);
var free = Math.max(0, trackW - thumbW);
thumb.style.left = px(maxScroll > 0 ? (view.scrollLeft / maxScroll) * free : 0);
}
function ensureSlider(root) {
var s = document.getElementById('bpq-slider');
if (s && s.parentNode === root) return s;
if (s && s.parentNode) s.parentNode.removeChild(s);
s = document.createElement('div');
s.id = 'bpq-slider';
s.innerHTML = '<div id="bpq-slider-track"><div id="bpq-slider-thumb"></div></div>';
var track = s.querySelector('#bpq-slider-track'), thumb = s.querySelector('#bpq-slider-thumb');
thumb.addEventListener('mousedown', function (e) {
var view = document.getElementById('bpq-strip-view');
if (!view) return;
sliderDragging = true; sliderStartX = e.clientX; sliderStartScroll = view.scrollLeft;
e.preventDefault();
});
track.addEventListener('mousedown', function (e) {
if (e.target === thumb) return;
var view = document.getElementById('bpq-strip-view');
if (!view) return;
var tr = track.getBoundingClientRect(), tw = thumb.getBoundingClientRect().width;
var free = Math.max(1, tr.width - tw);
var ratio = (e.clientX - tr.left - tw / 2) / free;
var maxScroll = Math.max(0, view.scrollWidth - view.clientWidth);
view.scrollLeft = Math.max(0, Math.min(maxScroll, ratio * maxScroll));
});
document.addEventListener('mousemove', function (e) {
if (!sliderDragging) return;
var view = document.getElementById('bpq-strip-view');
if (!view) return;
var tr = track.getBoundingClientRect(), tw = thumb.getBoundingClientRect().width;
var maxScroll = Math.max(0, view.scrollWidth - view.clientWidth);
var free = Math.max(1, tr.width - tw);
var scale = maxScroll / free;
view.scrollLeft = Math.max(0, Math.min(maxScroll, sliderStartScroll + (e.clientX - sliderStartX) * scale));
});
document.addEventListener('mouseup', function () { sliderDragging = false; });
root.appendChild(s);
return s;
}
function scrollToCurrent(view, inner, cap, scale) {
var cur = Math.max(1, Math.min(cap, S.bp.level || 1));
var card = inner.querySelector('.battle-pass-main__reward--common[data-lvl="' + cur + '"]') ||
inner.querySelector('.battle-pass-main__experience-line-level-wrapper:nth-child(' + cur + ')');
log('\u0430\u0432\u0442\u043e\u043f\u0440\u043e\u043a\u0440\u0443\u0442\u043a\u0430: S.bp.level=' + S.bp.level + ', \u043a\u0430\u0440\u0442\u043e\u0447\u0435\u043a \u0432 \u0434\u0430\u043d\u043d\u044b\u0445 (cap)=' + cap +
', \u0446\u0435\u043b\u044c=' + cur + ', \u043a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u043d\u0430\u0439\u0434\u0435\u043d\u0430=' + !!card);
if (!card) return;
var s2 = scale || 1;
var visualCenter = (card.offsetLeft + card.offsetWidth / 2) * s2;
view.scrollLeft = Math.max(0, visualCenter - view.clientWidth / 2);
}
var cdnCache = '', cdnAt = 0;
function imgBase() {
if (cdnCache && Date.now() - cdnAt < 3000) return cdnCache;
var re = /^(https?:\/\/[^?#]+?\/projects\/[^\/?#]+)\/(?:systems|assets)\//;
var native = [].filter.call(document.querySelectorAll('img[src]'), function (i) {
return !i.closest || !(i.closest('#bpq-dock') || i.closest('#bpq-panel') || i.closest('#bpq-strip'));
}).map(function (i) { return i.getAttribute('src') || ''; });
var base = '';
for (var i = native.length - 1; i >= 0; i--) { var m = re.exec(native[i]); if (m) { base = m[1]; break; } }
if (!base) {
try {
var entries = performance.getEntriesByType('resource');
for (var j = entries.length - 1; j >= 0; j--) { var m2 = re.exec(entries[j].name); if (m2) { base = m2[1]; break; } }
} catch (e) {}
}
if (!base) base = S.cdnBaseGood || 'https://cdn.azresources.cloud/projects/arizona-rp';
S.cdnBaseGood = base;
cdnCache = base + '/assets/images/donate/'; cdnAt = Date.now();
return cdnCache;
}
function itemHtml(q, cur, base) {
var total = Number(q.totalProgress) || 1;
var done = cur >= total;
var pct = Math.floor(cur / total * 100);
var img = base ? base + '96500019.webp' : '';
return '<div class="battle-pass-quests__item' + (String(q.id) === String(selId) ? ' battle-pass-quests__item--active' : '') +
'" data-id="' + esc(q.id) + '"><div class="battle-pass-quests__item-info">' +
'<div class="battle-pass-quests__item-title">' + esc(q.title) + '</div>' +
'<div class="battle-pass-quests__item-description">' + esc(q.description) + '</div>' +
'<div class="battle-pass-quests__progress-wrapper">' +
'<div class="battle-pass-quests__progress-marks' + (done ? ' battle-pass-quests__progress-marks--complete' : '') + '">' +
'<div class="battle-pass-quests__progress-count"><div class="battle-pass-quests__progress-current">' +
fmt(Math.min(cur, total)) + '</div><div class="battle-pass-quests__progress-total"> / ' + fmt(total) + '</div></div>' +
'<div class="battle-pass-quests__progress-percents">' +
(done ? '<i class="battle-pass-quests__progress-check ui-check"></i><div class="battle-pass-quests__progress-total">\u0412\u044b\u043f\u043e\u043b\u043d\u0435\u043d\u043e</div>'
: pct + '%') + '</div></div>' +
'<div class="battle-pass-quests__progress-bar" style="--progress-percents:' + pct + '%">' +
'<div class="battle-pass-quests__progress-bar battle-pass-quests__progress-bar--current' +
(done ? ' battle-pass-quests__progress-bar--complete' : '') + '"></div></div></div></div>' +
'<div class="battle-pass-quests__item-reward"><div class="battle-pass-quests__item-reward-image-wrapper">' +
(img ? '<img src="' + esc(img) + '" alt="reward" class="battle-pass-quests__item-reward-image"/>' : '') +
'</div><div class="battle-pass-quests__item-reward-name">+' + esc(q.prizeValue) + ' \u0435\u0434.</div></div></div>';
}
function panelHtml(it, base) {
var q = it.q, cur = it.cur, total = Number(q.totalProgress) || 1;
var done = cur >= total, pct = Math.floor(cur / total * 100);
var rew = (q.rewards || []).map(function (r) {
return '<div class="battle-pass-quests__details-reward"><div class="battle-pass-quests__details-reward-image-wrapper">' +
(base ? '<img class="battle-pass-quests__details-reward-image" alt="reward" src="' + esc(base + r.item + '.webp') + '"/>' : '') +
'</div><div class="battle-pass-quests__details-reward-title">' + esc(r.name) + '</div></div>';
}).join('');
return '<div class="bpq-p-main"><div class="bpq-p-title">' + esc(q.title) + '</div>' +
'<div class="bpq-p-desc">' + esc(q.hint || q.description) + '</div></div>' +
'<div class="bpq-p-mid"><div class="battle-pass-quests__details-progress-wrapper" style="--details-progress-percents:' + pct + '%">' +
'<div class="battle-pass-quests__details-progress-marks' + (done ? ' battle-pass-quests__details-progress-marks--complete' : '') + '">' +
'<div class="battle-pass-quests__details-progress-count"><div class="battle-pass-quests__details-progress-current">' +
fmt(Math.min(cur, total)) + '</div><div class="battle-pass-quests__details-progress-total"> / ' + fmt(total) + '</div></div>' +
'<div class="battle-pass-quests__details-progress-percents">' +
(done ? '<i class="battle-pass-quests__details-progress-check ui-check"></i>\u0412\u044b\u043f\u043e\u043b\u043d\u0435\u043d\u043e' : pct + '%') + '</div></div>' +
'<div class="battle-pass-quests__details-progress-bar"><div class="battle-pass-quests__details-progress-bar ' +
'battle-pass-quests__details-progress-bar--current' + (done ? ' battle-pass-quests__details-progress-bar--complete' : '') +
'"></div></div></div>' +
(q.buttonNameInfo ? '<div class="battle-pass-quests__get-rewards-button bpq-help" data-id="' + esc(q.id) + '">' +
esc(q.buttonNameInfo) + '</div>' : '') + '</div>' +
'<div class="bpq-p-rew"><div class="bpq-p-cap">\u041d\u0430\u0433\u0440\u0430\u0434\u044b:</div>' +
'<div class="battle-pass-quests__details-rewards bpq-p-rlist">' + rew + '</div></div>';
}
function weight(it) {
var total = Number(it.q.totalProgress) || 0;
return it.cur > total ? 4 : (it.cur ? -1 : 1);
}
function markSelected(dock) {
[].forEach.call(dock.querySelectorAll('.battle-pass-quests__item'), function (el) {
el.classList.toggle('battle-pass-quests__item--active', el.getAttribute('data-id') === String(selId));
});
}
var panelKey = '';
function renderPanel(root) {
var p = document.getElementById(PANEL_ID);
if (!p) return;
var sel = null;
for (var i = 0; i < items.length; i++) if (String(items[i].q.id) === String(selId)) sel = items[i];
var key = sel ? sel.q.id + '|' + sel.cur + '|' + imgBase() : 'none';
if (key === panelKey) return;
panelKey = key;
p.innerHTML = sel ? panelHtml(sel, imgBase()) :
'<div class="bpq-p-main"><div class="bpq-p-desc">\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0437\u0430\u0434\u0430\u043d\u0438\u0435 \u0441\u043b\u0435\u0432\u0430.</div></div>';
}
function render(dock, root) {
var list = dock.querySelector('.bpq-list');
var html, key, build = null;
var waited = Date.now() - startedAt > 4000;
items = [];
if (!quests) {
key = S.api ? 'load' : 'noapi' + (waited ? 1 : 0);
html = S.api ? '<div class="bpq-msg">\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u0437\u0430\u0434\u0430\u043d\u0438\u0439\u2026</div>'
: '<div class="bpq-msg">\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435 \u0434\u0430\u043d\u043d\u044b\u0445 \u043e\u0442 \u0441\u0435\u0440\u0432\u0435\u0440\u0430\u2026' + (waited ?
'<br>\u0415\u0441\u043b\u0438 \u0441\u043f\u0438\u0441\u043e\u043a \u043d\u0435 \u043f\u043e\u044f\u0432\u0438\u043b\u0441\u044f: \u043e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u0432\u043a\u043b\u0430\u0434\u043a\u0443 \u00ab\u0417\u0430\u0434\u0430\u043d\u0438\u044f\u00bb \u043e\u0434\u0438\u043d \u0440\u0430\u0437 \u0438\u043b\u0438 \u043f\u0435\u0440\u0435\u0437\u0430\u0439\u0434\u0438\u0442\u0435 \u0432 \u0438\u0433\u0440\u0443 ' +
'(\u0441\u043a\u0440\u0438\u043f\u0442 \u0434\u043e\u043b\u0436\u0435\u043d \u0431\u044b\u0442\u044c \u0437\u0430\u043f\u0443\u0449\u0435\u043d \u0434\u043e \u043f\u0435\u0440\u0432\u043e\u0433\u043e \u043e\u0442\u043a\u0440\u044b\u0442\u0438\u044f \u0431\u0430\u0442\u0442\u043b\u043f\u0430\u0441\u0441\u0430).' : '') + '</div>';
} else if (!S.progress) {
key = 'noprog';
html = '<div class="bpq-msg">\u041f\u0440\u043e\u0433\u0440\u0435\u0441\u0441 \u0437\u0430\u0434\u0430\u043d\u0438\u0439 \u0435\u0449\u0451 \u043d\u0435 \u043f\u043e\u043b\u0443\u0447\u0435\u043d.<br>\u041e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u0432\u043a\u043b\u0430\u0434\u043a\u0443 \u00ab\u0417\u0430\u0434\u0430\u043d\u0438\u044f\u00bb \u043e\u0434\u0438\u043d \u0440\u0430\u0437, ' +
'\u043f\u043e\u0441\u043b\u0435 \u044d\u0442\u043e\u0433\u043e \u0441\u043f\u0438\u0441\u043e\u043a \u0437\u0430\u043f\u043e\u043b\u043d\u0438\u0442\u0441\u044f.</div>';
} else {
var map = {};
S.progress.forEach(function (p) {
if (p && (p.categoryId === undefined || p.categoryId === 'daily')) map[p.id] = p;
});
quests.forEach(function (q, i) {
var p = map[q.id];
if (p && p.visible) items.push({ q: q, cur: Number(p.progress) || 0, i: i });
});
items.sort(function (a, b) { return (weight(a) - weight(b)) || (a.i - b.i); });
var found = items.some(function (it) { return String(it.q.id) === String(selId); });
if (!found) selId = items.length ? items[0].q.id : null;
var base = imgBase();
var sig = items.map(function (it) { return it.q.id + ':' + it.cur; }).join(',');
key = 'ok|' + sig + '|' + selId + '|' + base;
if (!items.length) html = '<div class="bpq-msg">\u0421\u0435\u0439\u0447\u0430\u0441 \u043d\u0435\u0442 \u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b\u0445 \u0437\u0430\u0434\u0430\u043d\u0438\u0439.</div>';
else build = function () { return items.map(function (it) { return itemHtml(it.q, it.cur, base); }).join(''); };
}
if (key !== lastKey) {
if (build) html = build();
var st = list.scrollTop;
list.innerHTML = html;
list.scrollTop = st;
lastKey = key;
}
renderPanel(root);
}
function updateTimer(dock) {
var ts = S.bp && S.bp.timestampMissionTime;
var v = dock.querySelector('.bpq-val');
var txt = '--';
if (ts) {
var diff = Math.max(0, ts - Math.floor(Date.now() / 1000));
txt = Math.floor(diff / 3600) + ' \u0447 ' + Math.floor(diff % 3600 / 60) + ' \u043c\u0438\u043d';
}
if (v.textContent !== txt) v.textContent = txt;
dock.querySelector('.bpq-reload').classList.toggle('bpq-off', S.browserId === null);
}
/* ---------- \u0440\u0430\u0441\u043a\u043b\u0430\u0434\u043a\u0430: \u0434\u043e\u043a\u0430 \u0441\u043b\u0435\u0432\u0430, \u043b\u0435\u043d\u0442\u0430 \u043d\u0430\u0433\u0440\u0430\u0434 \u0441\u043f\u0440\u0430\u0432\u0430, \u043f\u0430\u043d\u0435\u043b\u044c \u0437\u0430\u0434\u0430\u043d\u0438\u044f \u043f\u043e\u0434 \u043d\u0435\u0439 ---------- */
function getU(root) {
var it = root.querySelector('.battle-pass__navigation-menu-item');
if (it) {
var h = it.getBoundingClientRect().height;
if (h > 0 && h / 48 > 0.3 && h / 48 < 3) return h / 48; // \u0432\u044b\u0441\u043e\u0442\u0430 \u043f\u0443\u043d\u043a\u0442\u0430 \u043c\u0435\u043d\u044e = 48 \u0443\u0441\u043b\u043e\u0432\u043d\u044b\u0445 px
}
var sc = parseFloat(getComputedStyle(document.body).getPropertyValue('--global-scale')) || 1;
return 0.0005 * sc * window.innerWidth + 0.04 * sc * sc;
}
function px(n) { return Math.round(n * 100) / 100 + 'px'; }
function plan(root) {
var nav = root.querySelector('.battle-pass__navigation-menu');
var head = root.querySelector('.battle-pass__header');
var buy = root.querySelector('.battle-pass-main__level-purchase-button');
if (!nav || !head || !buy) return null;
var u = getU(root), W = window.innerWidth, H = window.innerHeight;
var nr = nav.getBoundingClientRect(), hr = head.getBoundingClientRect(), br = buy.getBoundingClientRect();
var chip = root.querySelector('.battle-pass-main__pass-stats');
var cr = chip ? chip.getBoundingClientRect() : null;
var M = nr.left, B = 14 * u, gap = 14 * u, panelH = 150 * u;
var chipTop = cr ? cr.top : H - 90 * u;
var top = hr.bottom + 12 * u;
var prem = { l: br.left, t: br.bottom + 12 * u, w: br.width, h: br.height };
var stripTop = Math.max(top, prem.t + prem.h + 10 * u);
var dockW = Math.min(W - 2 * M - 380 * u, 640 * u);
if (dockW < 380 * u) dockW = Math.min(380 * u, (W - 2 * M) * 0.4);
var dockBottom = chipTop - gap; // \u0443 \u0441\u043f\u0438\u0441\u043a\u0430 \u0437\u0430\u0434\u0430\u043d\u0438\u0439 \u0441\u0432\u043e\u044f \u043a\u043e\u043b\u043e\u043d\u043a\u0430 - \u0435\u043c\u0443 \u043d\u0438 \u043a \u0447\u0435\u043c\u0443 \u0443\u0441\u0442\u0443\u043f\u0430\u0442\u044c \u043c\u0435\u0441\u0442\u043e \u043f\u0430\u043d\u0435\u043b\u0438 \u0441\u043f\u0440\u0430\u0432\u0430
var sliderH = 22 * u;
var showPanel = (chipTop - gap - stripTop - sliderH - gap - panelH - gap) >= 200 * u;
var bottom = showPanel ? chipTop - gap - panelH - gap : chipTop - gap;
var sliderBottom = bottom - (showPanel ? gap : 0);
var sliderTop = sliderBottom - sliderH;
var stripBottom = sliderTop - gap;
if (dockBottom - top < 240 * u || stripBottom - stripTop < 160 * u || W - 2 * M - dockW - gap < 300 * u) return null;
var right = { l: M + dockW + gap, w: W - M - (M + dockW + gap) };
return {
u: u, M: M, top: top, bottom: bottom, B: B, gap: gap, showPanel: showPanel, prem: prem,
dock: { l: M, t: top, w: dockW, h: dockBottom - top },
strip: { l: right.l, t: stripTop, w: right.w, h: stripBottom - stripTop },
slider: { l: right.l, t: sliderTop, w: right.w, h: sliderH },
panel: showPanel ? { l: right.l, t: bottom + gap, w: right.w, h: panelH } : null
};
}
function setTasksTab(root, hide) {
[].forEach.call(root.querySelectorAll('.battle-pass__navigation-menu-item'), function (el) {
if (/^\s*\u0437\u0430\u0434\u0430\u043d\u0438\u044f/i.test(el.textContent)) el.style.display = hide ? 'none' : '';
});
}
function deactivate(root, dock, panel, strip) {
mode = 'off';
if (root) { root.classList.remove('bpq-active'); setTasksTab(root, false); }
if (dock) dock.classList.remove('bpq-on');
if (panel) panel.classList.remove('bpq-on');
if (strip) strip.classList.remove('bpq-on');
var sl = document.getElementById('bpq-slider'); if (sl) sl.classList.remove('bpq-on');
}
function tick() {
if (destroyed) return;
var root = null, dock = null, panel = null, strip = null;
try {
hookCef();
root = document.querySelector('.battle-pass');
dock = document.getElementById(DOCK_ID);
panel = document.getElementById(PANEL_ID);
strip = document.getElementById('bpq-strip');
var onMain = false;
if (root && !root.classList.contains('battle-pass--preview') &&
root.querySelector('.battle-pass-main__lines-caption-text')) {
var ts = S.bp && S.bp.timestampTaskTime;
var off = ts && ts <= Math.floor(Date.now() / 1000);
onMain = !off && !root.querySelector('.battle-pass__navigation-menu-item--disabled');
}
if (!root) return;
if (!onMain) {
root.classList.remove('bpq-active');
if (dock) dock.classList.remove('bpq-on');
if (panel) panel.classList.remove('bpq-on');
if (strip) strip.classList.remove('bpq-on');
var sl2 = document.getElementById('bpq-slider'); if (sl2) sl2.classList.remove('bpq-on');
setTasksTab(root, false);
return;
}
ensureStyle();
dock = ensureDock(root);
panel = ensurePanel(root);
strip = ensureStrip(root);
var slider = ensureSlider(root);
grabNativeIcons(root);
root.classList.add('bpq-active');
var pl = plan(root);
if (!pl) { deactivate(root, dock, panel, strip); return; }
var rs = root.style;
rs.setProperty('--bpu', pl.u + 'px');
rs.setProperty('--bpq-pl', px(pl.prem.l)); rs.setProperty('--bpq-pt', px(pl.prem.t));
rs.setProperty('--bpq-pw', px(pl.prem.w)); rs.setProperty('--bpq-ph', px(pl.prem.h));
var s = dock.style;
s.setProperty('--bpu', pl.u + 'px');
s.left = px(pl.dock.l); s.top = px(pl.dock.t); s.width = px(pl.dock.w); s.height = px(pl.dock.h);
dock.classList.toggle('bpq-narrow', pl.dock.w < 470 * pl.u);
dock.classList.add('bpq-on');
var ps = panel.style;
if (pl.panel) {
ps.setProperty('--bpu', pl.u + 'px');
ps.left = px(pl.panel.l); ps.top = px(pl.panel.t); ps.width = px(pl.panel.w); ps.height = px(pl.panel.h);
}
panel.classList.toggle('bpq-on', !!pl.panel);
var ss = strip.style;
ss.left = px(pl.strip.l); ss.top = px(pl.strip.t); ss.width = px(pl.strip.w); ss.height = px(pl.strip.h);
strip.classList.add('bpq-on');
var sls = slider.style;
sls.left = px(pl.slider.l); sls.top = px(pl.slider.t); sls.width = px(pl.slider.w); sls.height = px(pl.slider.h);
slider.classList.add('bpq-on');
loadQuests();
loadBranchData();
render(dock, root);
updateTimer(dock);
var view = strip.querySelector('#bpq-strip-view'), inner = strip.querySelector('#bpq-strip-inner');
var rebuilt = renderStrip(inner);
var natH = inner.scrollHeight || inner.offsetHeight;
if (natH > 0) {
var scaleH = pl.strip.h / natH;
var scaleW = 1;
var cardsList = inner.querySelectorAll('.battle-pass-main__reward--common');
if (cardsList.length >= 2) {
var pitch = cardsList[1].offsetLeft - cardsList[0].offsetLeft;
if (pitch > 0) scaleW = pl.strip.w / (4.6 * pitch);
}
var scale = Math.min(1, scaleH, scaleW);
S.stripScale = scale;
rs.setProperty('--bpq-strip-s', String(scale));
if (rebuilt && !stripAutoScrolled) {
scrollToCurrent(view, inner, Math.max(rewCommon.length, rewPremium.length) || 100, scale);
stripAutoScrolled = true;
}
updateSliderThumb();
}
setTasksTab(root, true);
} catch (e) { log('tick', String(e)); }
}
function scheduleTick() {
if (rafScheduled) return;
rafScheduled = true;
requestAnimationFrame(function () { rafScheduled = false; tick(); });
}
function destroy() {
destroyed = true;
clearInterval(timerId);
clearInterval(heartbeatId);
if (mo) mo.disconnect();
window.removeEventListener('resize', scheduleTick);
if (window.executeEvent === wrappedExec) window.executeEvent = origExec;
if (XO.open === wrappedOpen) XO.open = oOpen;
if (XO.setRequestHeader === wrappedSetHeader) XO.setRequestHeader = oSetHeader;
try {
if (window.cef && window.cef.SendMessage === cefWrapped && cefOrig) window.cef.SendMessage = cefOrig;
} catch (e) {}
var root = document.querySelector('.battle-pass');
if (root) {
root.classList.remove('bpq-active');
root.style.removeProperty('--bpu'); root.style.removeProperty('--bpq-strip-s');
setTasksTab(root, false);
}
[DOCK_ID, PANEL_ID, STYLE_ID, 'bpq-strip', 'bpq-slider'].forEach(function (id) {
var el = document.getElementById(id); if (el && el.parentNode) el.parentNode.removeChild(el);
});
if (window.__bpq && window.__bpq.v === VER) delete window.__bpq;
log('\u0432\u044b\u0433\u0440\u0443\u0436\u0435\u043d');
}
window.__bpq = { v: VER, destroy: destroy };
window.addEventListener('resize', scheduleTick);
mo = new MutationObserver(scheduleTick);
mo.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
heartbeatId = setInterval(scheduleTick, 1000);
tick();
log('\u0437\u0430\u043f\u0443\u0449\u0435\u043d');
})();
]==]

local CHUNK = 2500          -- размер одной порции JS в символах (пакет ограничен по длине)
local enabled = true
local want_toggle = false

-- Выполнить JS-код в основном CEF-интерфейсе (тот же приём, что используют другие скрипты для Arizona)
local function evalcef(code)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 17)
    raknetBitStreamWriteInt32(bs, 0)
    raknetBitStreamWriteInt16(bs, #code)
    raknetBitStreamWriteInt8(bs, 0)
    raknetBitStreamWriteString(bs, code)
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
end

-- Экранирование куска кода, чтобы положить его в строку JS в одинарных кавычках
local function js_quote(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub("'", "\\'")
    s = s:gsub('\r', '')
    s = s:gsub('\n', '\\n')
    return s
end

-- Отправка кода порциями: собираем строку в window.__bpq_src и выполняем целиком.
-- Если код уже запущен и версия та же, JS сам ничего не делает (повторная отправка безопасна).
local function inject()
    evalcef("window.__bpq_src='';")
    local i = 1
    while i <= #JS_SOURCE do
        local part = JS_SOURCE:sub(i, i + CHUNK - 1)
        evalcef("window.__bpq_src+='" .. js_quote(part) .. "';")
        i = i + CHUNK
        wait(30)
    end
    evalcef("try{(0,eval)(window.__bpq_src);}catch(e){console.log('[bpq] '+e);}delete window.__bpq_src;")
end

local function remove()
    evalcef("try{window.__bpq&&window.__bpq.destroy();}catch(e){}")
end

local function cmd_toggle()
    want_toggle = true   -- сам вызов делаем в основном потоке (там разрешён wait)
end

function main()
    while not isSampAvailable() do wait(100) end
    wait(6000)           -- даём интерфейсу загрузиться

    if sampRegisterChatCommand then
        sampRegisterChatCommand('bpdock', cmd_toggle)
    end

    inject()
    local last = os.clock()

    while true do
        wait(100)
        if want_toggle then
            want_toggle = false
            enabled = not enabled
            if enabled then inject() else remove() end
            if sampAddChatMessage then
                sampAddChatMessage('[BP Dock] ' .. (enabled and 'enabled' or 'disabled'), 0xFFFFD700)
            end
            last = os.clock()
        end
        -- Раз в минуту переотправляем код: если страница интерфейса перезагрузилась, он вернётся;
        -- если всё работает, JS ничего не сделает.
        if enabled and os.clock() - last > 60 then
            inject()
            last = os.clock()
        end
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() and not quitGame then
        pcall(remove)    -- убрать список и вернуть перехваты на место
    end
end