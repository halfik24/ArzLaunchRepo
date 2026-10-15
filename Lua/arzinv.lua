script_name('ARZ inv')
script_author('joce')

local BOOTSTRAP_JS = ([=[
(() => {
    'use strict';
    const VERSION = '__VERSION__';

    if (window.__arzInvTheme) {
        if (window.__arzInvTheme.version === VERSION) {
            window.__arzInvTheme.sync();
            return;
        }
        window.__arzInvTheme.destroy();
    }

    const STYLE_ID = 'arz-theme-styles';
    const REGEX_SRC = /\/(\d+)\.(?:webp|png|jpe?g)/i;

    const getMatchState = () => localStorage.getItem('arz_item_match_active') === 'true';
    const setMatchState = (val) => localStorage.setItem('arz_item_match_active', String(val));

    const SVG_MATCH_ICON = `
        <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M 2.5 8.5 C 2.5 7.12 3.62 6 5 6 L 16.5 6 C 17.2 6 17.85 6.35 18.25 6.9 L 21.6 11.5 C 21.9 11.9 21.65 12.5 21.15 12.5 L 18.5 12.5 C 17.8 12.5 17.15 12.15 16.75 11.6 L 15.2 9.5 L 5 9.5 C 3.62 9.5 2.5 8.38 2.5 7 Z" fill="currentColor"/>
            <g transform="rotate(180 12 12)">
                <path d="M 2.5 8.5 C 2.5 7.12 3.62 6 5 6 L 16.5 6 C 17.2 6 17.85 6.35 18.25 6.9 L 21.6 11.5 C 21.9 11.9 21.65 12.5 21.15 12.5 L 18.5 12.5 C 17.8 12.5 17.15 12.15 16.75 11.6 L 15.2 9.5 L 5 9.5 C 3.62 9.5 2.5 8.38 2.5 7 Z" fill="currentColor"/>
            </g>
        </svg>
        <div class="arz-match-btn__tooltip">Подсветка предметов в лавке</div>
    `;

    const CSS_RULES = `
        .character-main {
            position: relative !important;
            z-index: 5 !important;
        }
        .character__tabs-navigation,
        .character__tab-navigation {
            position: absolute !important;
            right: 100% !important;
            left: auto !important;
            top: 70px !important;
            display: flex !important;
            flex-direction: column !important;
            gap: 6px !important;
            margin: 0 !important;
            padding: 0 !important;
            width: 44px !important;
            z-index: 10 !important;
            pointer-events: auto !important;
            transform: none !important;
        }
        .character__tab-navigation-item {
            position: relative !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            width: 44px !important;
            height: 44px !important;
            background: #111216 !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-right: none !important;
            border-radius: 12px 0 0 12px !important;
            color: #8c9099 !important;
            cursor: pointer !important;
            box-sizing: border-box !important;
            margin: 0 !important;
            left: 1px !important;
            transition: background 0.15s ease, color 0.15s ease !important;
        }
        .character__tab-navigation-item:hover {
            background: #16181f !important;
            color: #ffffff !important;
        }
        .character__tab-navigation-item--active {
            background: #090a0c !important;
            border-top: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-left: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-right: none !important;
            width: 45px !important;
            left: 2px !important;
            color: #ffffff !important;
            z-index: 15 !important;
        }
        .character__tab-navigation-item-icon {
            font-size: 16px !important;
        }
        .inventory-window,
        .inventory-trade,
        .inventory-store,
        .inventory-storage,
        .character-main,
        .character-guard,
        .warehouse {
            background: #090a0c !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            box-shadow: none !important;
            border-radius: 18px !important;
            box-sizing: border-box !important;
        }
        .inventory-window__header,
        .inventory-trade__header,
        .inventory-store__header,
        .character-guard__header,
        .warehouse__header {
            background: #101114 !important;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
        }
        .inventory-window__header-title-text,
        .inventory-trade__title,
        .character-guard__title,
        .warehouse__title,
        .inventory-store__title {
            color: #f5f5f5 !important;
            font-weight: 700 !important;
        }
        .inventory-window__header-controls {
            display: flex !important;
            align-items: center !important;
            gap: 12px !important;
        }
        .inventory-window__header-controls i,
        .inventory-window__header-controls div {
            color: #8c9099 !important;
        }
        .arz-match-btn {
            position: relative !important;
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            width: 24px !important;
            height: 24px !important;
            cursor: pointer !important;
            margin: 0 !important;
            padding: 0 !important;
            user-select: none !important;
            flex-shrink: 0 !important;
        }
        .arz-match-btn svg {
            width: 22px !important;
            height: 22px !important;
            display: block !important;
        }
        .arz-match-btn svg path {
            fill: #8c9099 !important;
            transition: fill 0.15s ease !important;
        }
        .arz-match-btn:hover svg path {
            fill: #ffffff !important;
        }
        .arz-match-btn--active svg path {
            fill: #2ed573 !important;
        }
        .arz-match-btn__tooltip {
            position: absolute !important;
            bottom: -32px !important;
            right: -10px !important;
            background: #0e0f13 !important;
            border: 1px solid rgba(255, 255, 255, 0.15) !important;
            border-radius: 6px !important;
            padding: 4px 10px !important;
            color: #ffffff !important;
            font-size: 11px !important;
            font-weight: 600 !important;
            white-space: nowrap !important;
            opacity: 0 !important;
            visibility: hidden !important;
            transform: translateY(-4px) !important;
            transition: opacity 0.15s ease, transform 0.15s ease !important;
            pointer-events: none !important;
            z-index: 100 !important;
        }
        .arz-match-btn:hover .arz-match-btn__tooltip {
            opacity: 1 !important;
            visibility: visible !important;
            transform: translateY(0) !important;
        }
        .inventory-item.arz-item--dimmed {
            opacity: 0.15 !important;
            filter: grayscale(100%) !important;
        }
        .inventory-grid__item-mock--lock,
        .inventory-grid__item-mock--locked,
        .inventory-item--locked,
        .inventory-item__lock-icon {
            display: none !important;
            pointer-events: none !important;
        }
        .inventory-grid__item-mock {
            background: #101114 !important;
            border: 1px solid rgba(255, 255, 255, 0.04) !important;
            border-radius: 18px !important;
            box-sizing: border-box !important;
            opacity: 0.6 !important;
        }
        .character-main__loadout,
        .character-main__skin,
        .character-main__skin-container,
        .character-main__loadout-buttons,
        .character-main__bottom-buttons,
        .character-guard__loadout {
            background: transparent !important;
            background-image: none !important;
            box-shadow: none !important;
        }
        .character-main__loadout::before,
        .character-main__loadout::after,
        .character-main__skin-container::before,
        .character-main__skin-container::after,
        .character-main__skin-glow,
        .character-guard__overlay {
            display: none !important;
        }
        .character-main__skin-image,
        .character-guard__loadout-image {
            filter: none !important;
        }
        .character-guard__stats {
            background: #111216 !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-radius: 12px !important;
            padding: 10px 14px !important;
            box-shadow: none !important;
            box-sizing: border-box !important;
        }
        .character-guard__stat-caption {
            color: #a0a4ab !important;
            font-size: 12px !important;
            font-weight: 600 !important;
        }
        .character-guard__stat-value {
            color: #ffffff !important;
            font-size: 13px !important;
            font-weight: 800 !important;
            text-shadow: none !important;
        }
        .character-guard__tabs {
            background: transparent !important;
            gap: 6px !important;
            margin-top: 10px !important;
        }
        .character-guard__tab-wrapper {
            position: relative !important;
            display: flex !important;
            align-items: center !important;
            width: 100% !important;
        }
        .character-guard__tab {
            position: relative !important;
            width: 100% !important;
            background: #111216 !important;
            border: 1.5px solid rgba(255, 255, 255, 0.12) !important;
            border-radius: 12px !important;
            box-shadow: none !important;
            box-sizing: border-box !important;
            padding: 10px 16px !important;
            transition: all 0.2s ease !important;
        }
        .character-guard__tab::before,
        .character-guard__tab::after {
            display: none !important;
        }
        .character-guard__tab:hover {
            background: #16181e !important;
            border-color: rgba(255, 255, 255, 0.3) !important;
            transform: translateY(-1px) !important;
        }
        .character-guard__tab--active {
            background: #161820 !important;
            border: 1.5px solid rgba(210, 57, 204, 0.8) !important;
            box-shadow: none !important;
        }
        .character-guard__tab-caption {
            color: #ffffff !important;
            font-weight: 700 !important;
            font-size: 13px !important;
            letter-spacing: 0.4px !important;
            text-align: center !important;
        }
        .character-guard__tab-state {
            position: absolute !important;
            right: 14px !important;
            top: 50% !important;
            transform: translateY(-50%) !important;
            border-radius: 50% !important;
            box-shadow: none !important;
            z-index: 2 !important;
        }
        .character-guard__menu-button {
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            height: 38px !important;
            background: #111216 !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-radius: 10px !important;
            color: #e5e5e5 !important;
            font-weight: 600 !important;
            cursor: pointer !important;
        }
        .character-guard__loadout-image-wrapper {
            background: #101115 !important;
            border: 2px solid var(--rarity-color, rgba(255, 255, 255, 0.15)) !important;
            border-radius: 18px !important;
            box-shadow: none !important;
            overflow: hidden !important;
        }
        .character-guard__loadout-rarity,
        .character-guard__loadout-level,
        .character-guard__loadout-exp {
            background: rgba(10, 11, 14, 0.8) !important;
            border: 1px solid rgba(255, 255, 255, 0.1) !important;
            border-radius: 8px !important;
            color: #ffffff !important;
            font-weight: 700 !important;
        }
        .inventory-button,
        .inventory-button--blue-red,
        .inventory-button--white-grey,
        .inventory-button--default {
            background: #111216 !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-radius: 10px !important;
            box-shadow: none !important;
            color: #e5e5e5 !important;
            transition: all 0.2s ease !important;
            outline: none !important;
        }
        .inventory-button::before,
        .inventory-button::after {
            display: none !important;
        }
        .inventory-button:hover {
            background: #16181d !important;
            border-color: rgba(255, 255, 255, 0.25) !important;
            transform: translateY(-1px) !important;
        }
        .inventory-button__text {
            color: #e5e5e5 !important;
            font-weight: 600 !important;
            letter-spacing: 0.3px !important;
        }
        .inventory-button--active {
            background: #1f222a !important;
            border-color: rgba(255, 255, 255, 0.35) !important;
            box-shadow: none !important;
        }
        .inventory-button--active .inventory-button__text {
            color: #ffffff !important;
            font-weight: 700 !important;
        }
        .inventory-search {
            width: 100% !important;
            margin-bottom: 8px !important;
            box-sizing: border-box !important;
        }
        .inventory-search__search {
            position: relative !important;
            width: 100% !important;
            background: #121216 !important;
            border: 1px solid rgba(255, 255, 255, 0.08) !important;
            border-radius: 8px !important;
            box-sizing: border-box !important;
            display: flex !important;
            align-items: center !important;
        }
        .inventory-search__search-field {
            width: 100% !important;
            height: 36px !important;
            background: transparent !important;
            border: none !important;
            outline: none !important;
            color: #f0f0f0 !important;
            font-size: 13px !important;
            padding: 0 36px 0 12px !important;
            box-sizing: border-box !important;
        }
        .inventory-search__search-field::placeholder {
            color: rgba(255, 255, 255, 0.35) !important;
            font-weight: 500 !important;
        }
        .inventory-search__search-icon,
        .inventory-search__search-close {
            position: absolute !important;
            right: 12px !important;
            color: rgba(255, 255, 255, 0.45) !important;
            font-size: 14px !important;
            pointer-events: none !important;
        }
        .inventory-grid__grid {
            gap: 6px !important;
        }
        .inventory-item {
            --item-accent: rgba(255, 255, 255, 0.18);
            position: relative !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            overflow: hidden !important;
            background-color: #121215 !important;
            background-image: none !important;
            border: 2px solid rgba(255, 255, 255, 0.12) !important;
            border-radius: 18px !important;
            box-sizing: border-box !important;
            transition: transform 0.15s ease !important;
            box-shadow: none !important;
        }
        .inventory-item[style*="rgba"],
        .inventory-item[style*="rgb("] {
            --item-accent: var(--bg);
            border-color: var(--bg) !important;
        }
        .inventory-item:hover {
            transform: translateY(-2px) !important;
            box-shadow: none !important;
        }
        .inventory-item::before,
        .inventory-item__background {
            content: '' !important;
            position: absolute !important;
            top: -2px !important;
            left: -2px !important;
            width: calc(100% + 4px) !important;
            height: calc(100% + 4px) !important;
            background-color: var(--item-accent) !important;
            background-image: none !important;
            border-radius: 0 !important;
            opacity: 0.35 !important;
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100' preserveAspectRatio='none'%3E%3Cpath d='M0,32 C12,58 38,78 95,100 L0,100 Z' fill='%23000'/%3E%3C/svg%3E") !important;
            -webkit-mask-size: 100% 100% !important;
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100' preserveAspectRatio='none'%3E%3Cpath d='M0,32 C12,58 38,78 95,100 L0,100 Z' fill='%23000'/%3E%3C/svg%3E") !important;
            mask-size: 100% 100% !important;
            pointer-events: none !important;
            z-index: 1 !important;
        }
        .inventory-item::after,
        .inventory-item__gradient {
            content: '' !important;
            display: block !important;
            position: absolute !important;
            top: -2px !important;
            left: -2px !important;
            width: calc(100% + 4px) !important;
            height: calc(100% + 4px) !important;
            background-color: var(--item-accent) !important;
            background-image: none !important;
            border-radius: 0 !important;
            opacity: 0.95 !important;
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100' preserveAspectRatio='none'%3E%3Cpath d='M0,58 C10,74 26,88 68,100 L0,100 Z' fill='%23000'/%3E%3C/svg%3E") !important;
            -webkit-mask-size: 100% 100% !important;
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100' preserveAspectRatio='none'%3E%3Cpath d='M0,58 C10,74 26,88 68,100 L0,100 Z' fill='%23000'/%3E%3C/svg%3E") !important;
            mask-size: 100% 100% !important;
            pointer-events: none !important;
            z-index: 2 !important;
        }
        .inventory-item__color {
            display: none !important;
        }
        .inventory-item__image {
            width: 100% !important;
            height: 100% !important;
            max-width: 76% !important;
            max-height: 76% !important;
            object-fit: contain !important;
            display: block !important;
            margin: auto !important;
            pointer-events: none !important;
            filter: none !important;
            z-index: 3 !important;
        }

        .inventory-item__amount {
            position: absolute !important;
            bottom: 3px !important;
            left: 50% !important;
            right: auto !important;
            transform: translateX(-50%) !important;
            padding: 1px 5px !important;
            min-width: 16px !important;
            width: max-content !important;
            max-width: 96% !important;
            box-sizing: border-box !important;
            white-space: nowrap !important;
            overflow: visible !important;
            text-align: center !important;
            background: #0d0e12 !important;
            border: 1px solid rgba(255, 255, 255, 0.22) !important;
            border-radius: 8px !important;
            color: #ffffff !important;
            font-size: 9px !important;
            font-weight: 800 !important;
            line-height: 1.2 !important;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.6) !important;
            z-index: 8 !important;
        }
        .inventory-item__amount:empty {
            display: none !important;
        }

        .splitted-item-money {
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            gap: 2px !important;
            margin: 0 !important;
            padding: 0 !important;
            max-width: 100% !important;
        }
        .splitted-item-money__icon {
            width: 9px !important;
            height: 9px !important;
            display: block !important;
            flex-shrink: 0 !important;
        }
        .splitted-item-money__value {
            margin: 0 !important;
            padding: 0 !important;
            color: #ffffff !important;
            font-size: 9px !important;
            font-weight: 800 !important;
            line-height: 1 !important;
            white-space: nowrap !important;
        }

        /* 100% ПЕРЕОПРЕДЕЛЕНИЕ: ИКОНКА СТРОГО СПРАВА ВВЕРХУ */
        html body .inventory-item > .inventory-item__activity-icon,
        html body .inventory-item > i[class*="icon-type-"],
        html body .inventory-item > [class*="activity-icon"],
        html body .inventory-item i.inventory-item__activity-icon {
            position: absolute !important;
            inset: 5px 6px auto auto !important;
            top: 5px !important;
            right: 6px !important;
            bottom: auto !important;
            left: auto !important;
            width: 16px !important;
            height: 16px !important;
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            font-size: 11px !important;
            color: #ffffff !important;
            filter: none !important;
            transform: none !important;
            margin: 0 !important;
            padding: 0 !important;
            z-index: 10 !important;
            pointer-events: none !important;
        }

        /* 100% ПЕРЕОПРЕДЕЛЕНИЕ: ТАЙМЕР СТРОГО СЛЕВА ВВЕРХУ */
        html body .inventory-item > .inventory-item__timer,
        html body .inventory-item > div.inventory-item__timer,
        html body .inventory-item .inventory-item__timer {
            position: absolute !important;
            inset: 4px auto auto 5px !important;
            top: 4px !important;
            left: 5px !important;
            right: auto !important;
            bottom: auto !important;
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            padding: 1px 4px !important;
            border-radius: 5px !important;
            background: rgba(13, 14, 18, 0.85) !important;
            border: 1px solid rgba(255, 255, 255, 0.15) !important;
            color: #e5e5e5 !important;
            font-size: 8.5px !important;
            font-weight: 700 !important;
            line-height: 1.1 !important;
            white-space: nowrap !important;
            text-shadow: none !important;
            transform: none !important;
            margin: 0 !important;
            z-index: 10 !important;
            pointer-events: none !important;
        }

        .inventory-item__placeholder {
            color: rgba(255, 255, 255, 0.4) !important;
        }
        .inventory-item__hover-overlay {
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            height: 100% !important;
            background: rgba(255, 255, 255, 0.04) !important;
            opacity: 0 !important;
            transition: opacity 0.15s ease !important;
            z-index: 7 !important;
        }
        .inventory-item:hover .inventory-item__hover-overlay {
            opacity: 1 !important;
        }
    `;

    const injectStyles = () => {
        let style = document.getElementById(STYLE_ID);
        if (!style) {
            style = document.createElement('style');
            style.id = STYLE_ID;
            document.head.appendChild(style);
        } else if (style.parentElement !== document.head) {
            document.head.appendChild(style);
        }
        // Всегда держим наш стиль последним в head
        if (document.head.lastElementChild !== style) {
            document.head.appendChild(style);
        }
        if (style.textContent !== CSS_RULES) {
            style.textContent = CSS_RULES;
        }
    };

    const getItemIdentifier = (el) => {
        if (!el) return null;

        const img = el.querySelector('.inventory-item__image');
        if (img) {
            const src = img.getAttribute('src') || '';
            const matchSrc = src.match(REGEX_SRC);
            if (matchSrc) return matchSrc[1];

            const alt = img.getAttribute('alt') || '';
            const digits = alt.replace(/\D/g, '');
            if (digits) return digits;
        }

        const spanId = el.querySelector('.inventory-item__item-id');
        if (spanId && spanId.textContent) {
            const digits = spanId.textContent.replace(/\D/g, '');
            if (digits) return digits;
        }

        if (el.dataset.id) return el.dataset.id;

        return null;
    };

    const formatPriceNumber = (n) => {
        if (n >= 1000000000) {
            const v = (n / 1000000000).toFixed(2).replace(/\.00$/, '').replace(/(\.[1-9])0$/, '$1');
            return `${v}ккк`;
        }
        if (n >= 1000000) {
            const v = (n / 1000000).toFixed(2).replace(/\.00$/, '').replace(/(\.[1-9])0$/, '$1');
            return `${v}кк`;
        }
        if (n >= 1000) {
            const v = (n / 1000).toFixed(1).replace(/\.0$/, '');
            return `${v}к`;
        }
        return String(n);
    };

    const formatStorePrices = (storeWin) => {
        const values = storeWin.querySelectorAll('.splitted-item-money__value');
        for (const el of values) {
            if (el.dataset.priceDone) continue;
            const raw = el.textContent.replace(/\s+/g, '');
            if (!/^\d+$/.test(raw)) continue;

            const num = parseInt(raw, 10);
            if (num >= 1000) {
                el.dataset.priceDone = 'true';
                el.textContent = formatPriceNumber(num);
            }
        }
    };

    const updateItemMatching = () => {
        const isMatchActive = getMatchState();
        const bag = document.querySelector('.inventory-window__header-title-icon.icon-bag');
        const allWins = document.querySelectorAll('.inventory-store, .inventory-trade, .inventory-window');
        const storeWindows = [];

        for (const w of allWins) {
            const titleEl = w.querySelector('.inventory-window__header-title-text, .inventory-trade__title, .inventory-store__title');
            const title = titleEl ? titleEl.textContent.toUpperCase() : '';
            if (title.includes('ЛАВКА') || title.includes('ТОРГОВ') || w.classList.contains('inventory-store')) {
                storeWindows.push(w);
                formatStorePrices(w);
            }
        }

        if (!isMatchActive || !bag || !storeWindows.length) {
            for (const item of document.querySelectorAll('.inventory-item.arz-item--dimmed')) {
                item.classList.remove('arz-item--dimmed');
            }
            return;
        }

        const myInvWin = bag.closest('.inventory-window');
        if (!myInvWin) return;

        const myItemIds = new Set();
        for (const item of myInvWin.querySelectorAll('.inventory-item')) {
            const id = getItemIdentifier(item);
            if (id) myItemIds.add(id);
        }

        if (myItemIds.size === 0) return;

        for (const w of storeWindows) {
            for (const item of w.querySelectorAll('.inventory-item')) {
                const id = getItemIdentifier(item);
                if (id) {
                    const shouldDim = !myItemIds.has(id);
                    const isDimmed = item.classList.contains('arz-item--dimmed');
                    if (isDimmed !== shouldDim) {
                        item.classList.toggle('arz-item--dimmed', shouldDim);
                    }
                }
            }
        }
    };

    const injectMatchButton = (headerControls) => {
        let btn = headerControls.querySelector('.arz-match-btn');
        const isActive = getMatchState();

        if (!btn) {
            btn = document.createElement('div');
            btn.className = 'arz-match-btn' + (isActive ? ' arz-match-btn--active' : '');
            btn.innerHTML = SVG_MATCH_ICON;

            const toggle = (e) => {
                e.preventDefault();
                e.stopPropagation();
                const nextState = !getMatchState();
                setMatchState(nextState);
                btn.classList.toggle('arz-match-btn--active', nextState);
                updateItemMatching();
            };

            btn.addEventListener('click', toggle);
            headerControls.prepend(btn);
        } else {
            btn.classList.toggle('arz-match-btn--active', isActive);
        }
    };

    const processDom = () => {
        injectStyles();
        const bag = document.querySelector('.inventory-window__header-title-icon.icon-bag');
        if (bag) {
            const win = bag.closest('.inventory-window');
            if (win) {
                const controls = win.querySelector('.inventory-window__header-controls');
                if (controls) injectMatchButton(controls);
            }
        }
        updateItemMatching();
    };

    injectStyles();

    let rafId = null;
    let isProcessing = false;

    const scheduleUpdate = () => {
        if (rafId || isProcessing) return;
        rafId = requestAnimationFrame(() => {
            rafId = null;
            isProcessing = true;
            try {
                processDom();
            } finally {
                isProcessing = false;
            }
        });
    };

    const observer = new MutationObserver((mutations) => {
        if (isProcessing) return;
        for (const m of mutations) {
            if (m.type === 'childList' || (m.type === 'attributes' && m.target && m.target.classList && m.target.classList.contains('inventory-item'))) {
                scheduleUpdate();
                break;
            }
        }
    });

    observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'src']
    });

    processDom();

    window.__arzInvTheme = {
        version: VERSION,
        sync: scheduleUpdate,
        destroy: () => {
            observer.disconnect();
            if (rafId) cancelAnimationFrame(rafId);
            const style = document.getElementById(STYLE_ID);
            if (style) style.remove();
            window.__arzInvTheme = null;
        }
    };
})();
]=]):gsub('__VERSION__', thisScript().version)

local function evalcef(code)
    if type(code) ~= 'string' or #code == 0 or #code > 32767 then return false end
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 17)
    raknetBitStreamWriteInt32(bs, 0)
    raknetBitStreamWriteInt16(bs, #code)
    raknetBitStreamWriteInt8(bs, 0)
    raknetBitStreamWriteString(bs, code)
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
    return true
end

function main()
    while not isSampAvailable() do wait(100) end

    sampAddChatMessage('{FFA500}[ARZ Global Theme]{FFFFFF} Модуль активен {5CC9FF}v' .. thisScript().version .. '{FFFFFF}.', -1)

    wait(1000)
    evalcef(BOOTSTRAP_JS)

    wait(-1)
end