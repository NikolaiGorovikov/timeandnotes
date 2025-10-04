export function main() {
    "use strict";

    /* =========================
       State & constants
       ========================= */
    const DEFAULT_NOTE_TEXT = "New notes like $x^2 + y^2 \\leq 1$ will go here";
    const MAX_SIZE = 25;
    const MIN_SIZE = 8;

    const MAX_SIZE_NOTE = 9;
    const MIN_SIZE_NOTE = 3;
    const NUM_STEPS = 20;
    const INITIAL_STEPS = 0.2;

    const storage = {
        time: {
            size: undefined
        },
        notes: {
            list: []
        }
    }

    // Time state
    const timeState = {
        mode: "clock",          // "clock" | "countdown"
        offsetMs: 0,            // user adjustment offset vs system
        editing: false,         // editing segments with arrows
        editTarget: null,       // "hh" | "mm" | "ampm" | "ss"
        countdown: {
            byEndTime: true,
            endTimestamp: null,
            durationMs: 0,
            startedAt: null
        }
    };

    // Elements
    const board = document.getElementById("board");
    const timeBlock = document.getElementById("timeBlock");
    const timeWrap = document.getElementById("timeWrap");
    const timeDisplay = document.getElementById("timeDisplay");
    const hhEl = document.getElementById("hh");
    const mmEl = document.getElementById("mm");
    const ssEl = document.getElementById("ss");
    const ampmEl = document.getElementById("ampm");
    const modeToggle = document.getElementById("modeToggle");
    const cdEnd = document.getElementById("cdEnd");
    const cdDur = document.getElementById("cdDur");
    const notes = document.getElementById("notes");
    const hud = document.getElementById("hud");

    // NEW: resize handles
    const timeHandleBL = document.getElementById("timeHandleBL");
    const timeHandleBR = document.getElementById("timeHandleBR");
    const timeHandleBL2 = document.getElementById("timeHandleBL2");
    const timeHandleBR2 = document.getElementById("timeHandleBR2");
    const timeHandleBC = document.getElementById("timeHandleBC");

    // Keep a tick interval (250ms keeps seconds snappy and reduces drift)
    let tickHandle = null;

    // NEW: dragging state
    let timeResizing = false;
    const MIN_FONT_PX = 10; // floor to avoid vanishingly small text
    const initialTimeBaseStr = getComputedStyle(document.documentElement)
        .getPropertyValue("--time-base").trim() || "16vw";

    /* =========================
       Utilities
       ========================= */
    function pad2(n) { return String(n).padStart(2,"0"); }
    function nowMs() { return Date.now() + timeState.offsetMs; }

    function isPrintableKey(e) {
        if (e.ctrlKey || e.metaKey || e.altKey) return false;
        if (e.key.length === 1) return true;
        return false;
    }

    function placeCaretAtEnd(el) {
        el.focus({preventScroll:true});
        const range = document.createRange();
        range.selectNodeContents(el);
        range.collapse(false);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
    }

    function parseDuration(input) {
        if (!input) return null;
        const s = input.trim();
        if (!s) return null;
        if (/^\d+$/.test(s)) {
            const minutes = parseInt(s,10);
            return minutes * 60 * 1000;
        }
        const parts = s.split(":").map(x => x.trim());
        if (parts.some(p => p === "" || isNaN(p))) return null;
        let h=0,m=0,_s=0;
        if (parts.length === 2) { h = parseInt(parts[0],10); m = parseInt(parts[1],10); }
        else if (parts.length === 3) { h = parseInt(parts[0],10); m = parseInt(parts[1],10); _s = parseInt(parts[2],10); }
        else return null;
        if (m>59 || _s>59) return null;
        return ((h*60 + m)*60 + _s) * 1000;
    }

    function setAttrSelected(el, on) {
        el.setAttribute("aria-selected", on ? "true" : "false");
    }

    // NEW: helpers for CSS var parsing
    function readRootVar(name) {
        return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    }
    function parseNumberUnit(str) {
        const m = String(str).trim().match(/^(-?\d*\.?\d+)([a-z%]*)$/i);
        return { num: m ? parseFloat(m[1]) : 0, unit: m ? m[2] || "" : "" };
    }

    /* =========================
       Time rendering & logic
       ========================= */
    function renderClock(ts) {
        const d = new Date(ts);
        let h = d.getHours();
        const m = d.getMinutes();
        const s = d.getSeconds();
        const mer = (h >= 12) ? "PM" : "AM";
        h = h % 12; if (h === 0) h = 12;
        hhEl.textContent = pad2(h);
        mmEl.textContent = pad2(m);
        ssEl.textContent = ":"+pad2(s);
        ampmEl.textContent = mer;
    }

    function renderCountdown() {
        let remaining = 0;
        if (timeState.countdown.byEndTime && timeState.countdown.endTimestamp) {
            remaining = timeState.countdown.endTimestamp - nowMs();
        } else if (!timeState.countdown.byEndTime && timeState.countdown.durationMs) {
            remaining = (timeState.countdown.startedAt ?? nowMs()) + timeState.countdown.durationMs - nowMs();
        }
        if (remaining < 0) remaining = 0;
        const totalSec = Math.floor(remaining / 1000);
        const h = Math.floor(totalSec / 3600);
        const m = Math.floor((totalSec % 3600) / 60);
        const s = totalSec % 60;

        hhEl.textContent = pad2(h);
        mmEl.textContent = pad2(m % 60);
        ssEl.textContent = ":"+pad2(s);
        ampmEl.textContent = " "; // keep slot so layout is stable; label "LEFT" added via CSS
    }

    function tick() {
        if (timeState.mode === "clock") {
            renderClock(nowMs());
        } else {
            renderCountdown();
        }
    }

    function startTicking() {
        if (tickHandle) clearInterval(tickHandle);
        tickHandle = setInterval(tick, 250);
        tick(); // immediate
    }

    /* =========================
       Time controls (editing & modes)
       ========================= */
    function setTimeEditing(on) {
        timeState.editing = on;
        timeBlock.toggleAttribute("data-editing", on);
        if (on && !timeState.editTarget) {
            timeState.editTarget = "hh";
            setAttrSelected(hhEl, true);
        }
        if (!on) {
            setAttrSelected(hhEl, false);
            setAttrSelected(mmEl, false);
            setAttrSelected(ssEl, false);
            setAttrSelected(ampmEl, false);
            timeState.editTarget = null;
        }
    }

    function rotateTarget(dir) {
        const order = ["hh","mm","ampm","ss"];
        let idx = order.indexOf(timeState.editTarget || "hh");
        idx = (idx + (dir > 0 ? 1 : -1) + order.length) % order.length;
        timeState.editTarget = order[idx];
        setAttrSelected(hhEl, order[idx]==="hh");
        setAttrSelected(mmEl, order[idx]==="mm");
        setAttrSelected(ampmEl, order[idx]==="ampm");
        setAttrSelected(ssEl, order[idx]==="ss");
    }

    function adjustSegment(delta) {
        const base = new Date(nowMs());
        if (timeState.mode === "countdown") {
            let remain = 0;
            if (timeState.countdown.byEndTime && timeState.countdown.endTimestamp) {
                remain = timeState.countdown.endTimestamp - nowMs();
            } else {
                remain = (timeState.countdown.durationMs || 0);
            }
            if (timeState.editTarget === "hh") remain += delta * 3600_000;
            if (timeState.editTarget === "mm") remain += delta * 60_000;
            if (timeState.editTarget === "ss") remain += delta * 1000;
            remain = Math.max(0, remain);
            if (timeState.countdown.byEndTime) {
                timeState.countdown.endTimestamp = nowMs() + remain;
                timeState.countdown.startedAt = null;
            } else {
                timeState.countdown.durationMs = remain;
                timeState.countdown.startedAt = nowMs();
            }
            return;
        }

        const desired = new Date(base);
        if (timeState.editTarget === "hh") desired.setHours(desired.getHours() + delta);
        if (timeState.editTarget === "mm") desired.setMinutes(desired.getMinutes() + delta);
        if (timeState.editTarget === "ss") desired.setSeconds(desired.getSeconds() + delta);
        if (timeState.editTarget === "ampm") desired.setHours(desired.getHours() + (delta>0 ? 12 : -12));
        const systemNow = Date.now();
        timeState.offsetMs = desired.getTime() - systemNow;
    }

    function setCountdownFromInputs() {
        const byEnd = document.querySelector('input[name="cdmode"]:checked')?.value === "end";
        timeState.countdown.byEndTime = byEnd;

        if (byEnd) {
            const v = cdEnd.value; // "HH:MM" 24h
            if (!v) return;
            const [H,M] = v.split(":").map(x=>parseInt(x,10));
            const target = new Date(nowMs());
            target.setHours(H, M, 0, 0);
            if (target.getTime() <= nowMs()) target.setDate(target.getDate() + 1);
            timeState.countdown.endTimestamp = target.getTime();
            timeState.countdown.startedAt = null;
        } else {
            const durMs = parseDuration(cdDur.value);
            if (!durMs) return;
            timeState.countdown.durationMs = durMs;
            timeState.countdown.startedAt = nowMs();
        }
    }

    function toggleMode(countdownOn) {
        timeState.mode = countdownOn ? "countdown" : "clock";
        timeBlock.dataset.mode = timeState.mode;
        // cdInputs.hidden = !countdownOn;
        tick();
    }

    /* =========================
       Note block creation / behavior (unchanged)
       ========================= */
    function createNote({initialText = DEFAULT_NOTE_TEXT, isDefault = true, initial_progress = INITIAL_STEPS, first = false} = {}) {
        const article = document.createElement("article");
        article.className = "block note focusable";
        let current_size = MIN_SIZE_NOTE+(MAX_SIZE_NOTE-MIN_SIZE_NOTE)*initial_progress;

        article.style.setProperty("--note-base", current_size+"vw");

        storage.notes.list.push({
            article,
            text: "",
            size: current_size
        });

        if (isDefault) article.setAttribute("data-default", "true");

        const content = document.createElement("div");
        content.className = "content";
        content.contentEditable = "true";
        content.spellcheck = false;
        content.textContent = "";

        const controls = document.createElement("div");
        controls.className = "controls";
        controls.innerHTML = `
<div class="note-size-cover">

<div class="plus-minus-btns" title="Grad to change the font size">

<div class="range-line">
    <div class="range-line-progress"></div>
</div>
<div class="range-ball">
<div class="ball-hitbox"></div>
</div>

</div>

</div>
        <button class="btn danger delBtn" title="Delete this note">Delete</button>

`;

        article.appendChild(content);
        article.appendChild(controls);
        notes.appendChild(article);

        let current_left = (controls.querySelector(".range-line").getBoundingClientRect().width-controls.querySelector(".range-ball").getBoundingClientRect().width/2+controls.querySelector(".range-line").getBoundingClientRect().height/2)*initial_progress;
        controls.querySelector(".range-line-progress").style.width = current_left/(controls.querySelector(".range-line").getBoundingClientRect().width-controls.querySelector(".range-ball").getBoundingClientRect().width/2+controls.querySelector(".range-line").getBoundingClientRect().height/2) * controls.querySelector(".range-line").getBoundingClientRect().width+"px";
        article.style.setProperty("--note-base", current_left/(controls.querySelector(".range-line").getBoundingClientRect().width-controls.querySelector(".range-ball").getBoundingClientRect().width/2+controls.querySelector(".range-line").getBoundingClientRect().height/2)*(MAX_SIZE_NOTE-MIN_SIZE_NOTE)+MIN_SIZE_NOTE+"vw");
        controls.querySelector(".range-ball").style.left = current_left+"px";

        content.addEventListener("input", () => {
            content.plainText = content.textContent;
            if (article.hasAttribute("data-default")) {
                article.removeAttribute("data-default");
            }
            storage.notes.list.find(i => i.article === article).text = content.textContent
        });

        content.addEventListener("keydown", (e) => {
            if (e.key.toLowerCase().startsWith("arrow") && article.hasAttribute("data-default")) {
                article.removeAttribute("data-default");
            }
        });

        function latexise() {
            MathJax.typesetPromise([content]).then(()=>{
                const errors = content.querySelectorAll('g[fill="red"]');
                for (let i = 0; i < errors.length; i++) {
                    errors[i].setAttribute("fill", "rgb(176,0,32)");
                    errors[i].setAttribute("stroke", "rgb(176,0,32)");
                }
            });
        }

        function selectContents(el) {
            const range = document.createRange();
            range.selectNodeContents(el);

            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
        }

        content.addEventListener("focus", (e) => {
            // show text
            content.isFocused = true;
            if (article.dataset.default === "true") {
                content.textContent = initialText;
                try {
                    selectContents(content);
                }
                catch (e) {}
            }
        });

        content.addEventListener("blur", () => {
            // show latex
            if (article.dataset.default !== "true") content.textContent = content.plainText;
            latexise();
            content.isFocused = false;
            if (content.textContent.trim() === "") {
                article.setAttribute("data-default","true");
                content.textContent = DEFAULT_NOTE_TEXT;
                latexise();
            }
            storage.notes.list.find(i => i.article === article).text = content.textContent;
        });

        content.parentElement.addEventListener("pointerenter", (e) => {
            // Show text
            content.pointerInside = true;
            if (!article.hasAttribute("data-default")) content.textContent = content.plainText;
        });

        content.parentElement.addEventListener("pointerleave", (e) => {
            // Show latex
            content.pointerInside = false;

            if (!content.isFocused && !article.hasAttribute("data-default")) {
                latexise();
                content.blur();
            }
        });

        function pm(e) {
            if (ball.active) {
                const max = controls.querySelector(".range-line").getBoundingClientRect().width-controls.querySelector(".range-ball").getBoundingClientRect().width/2+controls.querySelector(".range-line").getBoundingClientRect().height/2;
                const newLeft = Math.min(Math.max(e.clientX-ball.start+ball.startLeft, 0), max);
                controls.querySelector(".range-ball").style.left = newLeft+"px";
                controls.querySelector(".range-line-progress").style.width = newLeft/max * controls.querySelector(".range-line").getBoundingClientRect().width+"px";
                article.style.setProperty("--note-base", newLeft/max*(MAX_SIZE_NOTE-MIN_SIZE_NOTE)+MIN_SIZE_NOTE+"vw");
                controls.querySelector(".range-ball").percentage = newLeft/max;
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }

        function pu(e) {
            if (ball.active) {
                ball.active = false;
                controls.closest(".note").classList.remove("being-resized");
                document.body.classList.remove("grabbing");
            }
        }

        const ball = {
            active: false,
            start: NaN,
            startLeft: current_left,
            progress: initial_progress
        };

        controls.querySelector(".range-ball").percentage = initial_progress;

        controls.querySelector(".range-ball").addEventListener("pointerdown", (e) => {
            if (ball.active) return;
            controls.closest(".note").classList.add("being-resized");
            document.body.classList.add("grabbing");
            ball.active = true;
            ball.startLeft = (controls.querySelector(".range-ball").getBoundingClientRect().x-controls.querySelector(".plus-minus-btns").getBoundingClientRect().x);
            ball.start = e.clientX;
            content.blur();
            const element = content;
            const selection = window.getSelection();

            if (selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                if (element.contains(range.commonAncestorContainer)) {
                    selection.removeAllRanges();
                }
            }
            e.stopImmediatePropagation();
            e.preventDefault();
        });

        document.body.addEventListener("pointermove", pm);
        document.body.addEventListener("pointerup", pu);
        document.body.addEventListener("pointercancel", pu);

        controls.querySelector(".delBtn").addEventListener("click", () => {
            storage.notes.list.splice(storage.notes.list.indexOf(storage.notes.list.find(i => i.article === article)), 1);
            article.remove();
            showHud();
            document.body.removeEventListener("pointermove", pm);
            document.body.removeEventListener("pointerup", pu);
            document.body.removeEventListener("pointercancel", pu);
        });

        setTimeout(() => {
            content.textContent = initialText;
            if (first) latexise();
            else {
                content.focus();
                placeCaretAtEnd(content);
            }
        }, 0);

        if (!isDefault) article.removeAttribute("data-default");


        return {article, content};
    }

    /* =========================
       Activity HUD & typing-to-add (unchanged)
       ========================= */
    let hudTimer = null;
    function showHud() {
        hud.classList.add("visible");
        if (hudTimer) clearTimeout(hudTimer);
        hudTimer = setTimeout(() => hud.classList.remove("visible"), 2500);
    }
    ["mousemove","keydown","pointerdown"].forEach(ev => {
        document.addEventListener(ev, () => showHud(), {passive:true});
    });
    hud.querySelector("p").addEventListener("click", () => {
        const { content } = createNote();
        content.focus();
    });

    document.addEventListener("keydown", (e) => {
        const ae = document.activeElement;
        const isField = ae && (ae.isContentEditable || /^(input|textarea|select|button)$/i.test(ae.tagName));
        if (!isField && isPrintableKey(e)) {
            e.preventDefault();
            createNote({initialText: e.key, isDefault: false});
        }
    });

    /* =========================
       Wire time controls & keyboard (size slider removed)
       ========================= */


    // [hhEl, mmEl, ssEl, ampmEl].forEach(seg => {
    //   seg.addEventListener("click", () => {
    //     setTimeEditing(true);
    //     const id = seg.id;
    //     timeState.editTarget = id;
    //     setAttrSelected(hhEl, id === "hh");
    //     setAttrSelected(mmEl, id === "mm");
    //     setAttrSelected(ssEl, id === "ss");
    //     setAttrSelected(ampmEl, id === "ampm");
    //   });
    // });

    // document.addEventListener("keydown", (e) => {
    //   if (!timeState.editing) return;
    //   if (["ArrowUp","ArrowDown","ArrowLeft","ArrowRight","Enter","Escape"].includes(e.key)) {
    //     e.preventDefault();
    //     if (e.key === "ArrowLeft") rotateTarget(-1);
    //     else if (e.key === "ArrowRight") rotateTarget(+1);
    //     else if (e.key === "ArrowUp") adjustSegment(+1);
    //     else if (e.key === "ArrowDown") adjustSegment(-1);
    //     else if (e.key === "Enter") setTimeEditing(false);
    //     else if (e.key === "Escape") { setTimeEditing(false); }
    //     tick();
    //   }
    // });

    modeToggle.addEventListener("change", (e) => {
        const on = e.target.checked;
        toggleMode(on);
    });

    [hhEl, mmEl, ssEl, ampmEl].forEach(seg => {
        seg.addEventListener("keydown", (e) => {
            if (e.key === " ") e.preventDefault();
        });
    });

    /* =========================
       NEW: Drag-to-scale time (bottom-corner handles)
       ========================= */
    const timeDrag = { active:false, startY:0, H0:0, baseNum:0, baseUnit:"", font0:0 };

    function beginTimeResize(ev) {
        ev.preventDefault();
        timeResizing = true;
        timeDrag.active = true;
        timeDrag.startY = ev.clientY;

        const rect = timeDisplay.getBoundingClientRect();
        timeDrag.H0 = rect.height;

        const baseStr = readRootVar("--time-base") || initialTimeBaseStr;
        const { num, unit } = parseNumberUnit(baseStr);
        timeDrag.baseNum = num;
        timeDrag.baseUnit = unit;

        timeDrag.font0 = parseFloat(getComputedStyle(timeDisplay).fontSize) || 1;

        document.body.classList.add("time-resizing");
        ev.currentTarget.setPointerCapture?.(ev.pointerId);
    }

    function onTimeResizeMove(ev) {
        if (!timeDrag.active || !ev.buttons) return;
        const dy = ev.clientY - timeDrag.startY;
        let targetH = Math.max(6, timeDrag.H0 + dy); // avoid collapse
        let k = targetH / Math.max(1, timeDrag.H0);  // proportional change
        // clamp to minimum font px
        const newFont = timeDrag.font0 * k;
        if (newFont < MIN_FONT_PX) {
            k = MIN_FONT_PX / timeDrag.font0;
            targetH = timeDrag.H0 * k;
        }
        const newBase = Math.max(Math.min((timeDrag.baseNum * k).toFixed(4), MAX_SIZE), MIN_SIZE) + timeDrag.baseUnit;
        document.documentElement.style.setProperty("--time-base",newBase);

        storage.time.size = newBase;
    }

    function endTimeResize(ev) {
        if (!timeDrag.active) return;
        timeDrag.active = false;
        timeResizing = false;
        document.body.classList.remove("time-resizing");
        try { ev.currentTarget.releasePointerCapture?.(ev.pointerId); } catch {}
        // Re-apply layout helpers after size change
    }

    function resetTimeSize() {
        document.documentElement.style.setProperty("--time-base", initialTimeBaseStr);
    }

    [timeHandleBL, timeHandleBR, timeHandleBC, timeHandleBL2, timeHandleBR2].forEach(h => {
        h.addEventListener("pointerdown", beginTimeResize);
        h.addEventListener("pointermove", onTimeResizeMove);
        h.addEventListener("pointerup", endTimeResize);
        h.addEventListener("pointercancel", endTimeResize);
        h.addEventListener("dblclick", resetTimeSize);
    });

    document.body.querySelectorAll(".time-hitbox").forEach(h => {
        h.addEventListener("pointerdown", beginTimeResize);
        h.addEventListener("pointermove", onTimeResizeMove);
        h.addEventListener("pointerup", endTimeResize);
        h.addEventListener("pointercancel", endTimeResize);
        h.addEventListener("dblclick", resetTimeSize);
    });

    /* =========================
       Boot
       ========================= */
    startTicking();
    showHud();
    createNote({first: true});

    // setTimeout(()=>{
    //     document.querySelector(".controls").blur();
    //     try {
    //         window.getSelection?.().removeAllRanges();
    //     }
    //     catch (e) {}
    // })


    function bootFromStorage(storage) {
        try {
            const newBase = storage.time.size;
            if (newBase) document.documentElement.style.setProperty("--time-base",newBase+"vw");

            for (let i of storage.notes.list) {
                createNote({initialText: i.text, isDefault: false, initial_progress: i.size});
            }
        }
        catch (e) {}
    }

//     Clicking on empty space inside #notes should not refocus the last note.
// Run in capture phase so it happens before the browser tries to place a caret.
    document.body.addEventListener("pointerdown", (e) => {
        // If the click isn't inside a note's editable content, clear focus & selection.
        if (!e.target.closest(".focusable")) {
            const ae = document.activeElement;
            if (ae && ae.isContentEditable) ae.blur();

            const sel = window.getSelection?.();
            try { sel && sel.removeAllRanges(); } catch {}

            e.preventDefault();
            e.stopImmediatePropagation();
        }
    }, true);

    window.addEventListener("resize", (e) => {
        const controls_list = document.body.querySelectorAll(".note .controls");
        for (let i = 0; i < controls_list.length; i++) {
            const controls = controls_list[i];
            const max = controls.querySelector(".range-line").getBoundingClientRect().width-controls.querySelector(".range-ball").getBoundingClientRect().width/2+controls.querySelector(".range-line").getBoundingClientRect().height/2;
            const percentage = controls.querySelector(".range-ball").percentage;
            const new_left = max*percentage;
            controls.querySelector(".range-ball").style.left = new_left + "px";
            controls.querySelector(".range-line-progress").style.width = percentage * controls.querySelector(".range-line").getBoundingClientRect().width+"px";
        }
    });


}

