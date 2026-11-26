export function bad(el, html, code) {
    /// ruleid: dsc-js-eval
    eval(code);

    /// ruleid: dsc-js-eval
    setTimeout(code, 10);

    /// ruleid: dsc-js-html-sink
    el.innerHTML = html;

    /// ruleid: dsc-js-html-sink
    el.insertAdjacentHTML("beforeend", html);
}

export function good(el, text) {
    /// ok: dsc-js-eval
    setTimeout(() => el.focus(), 10);

    /// ok: dsc-js-eval
    setTimeout(function () { el.focus(); }, 10);

    /// ok: dsc-js-html-sink
    el.innerHTML = "";

    /// ok: dsc-js-html-sink
    el.innerHTML = DOMPurify.sanitize(text);

    /// ok: dsc-js-html-sink
    el.textContent = text;
}
