using Microsoft.AspNetCore.Components;
using Microsoft.JSInterop;

public partial class ScriptRunner : ComponentBase
{
    [Inject] private IJSRuntime JS { get; set; } = default!;

    private const string ScrollFn = "dsc.scrollToTop";

    private async Task Bad(string userScript, string fnName)
    {
        /// ruleid: dsc-jsruntime-eval
        await JS.InvokeVoidAsync("eval", userScript);

        /// ruleid: dsc-jsruntime-eval
        var result = await JS.InvokeAsync<string>("window.eval", userScript);

        /// ruleid: dsc-jsruntime-eval
        await JS.InvokeVoidAsync("setTimeout", userScript, 100);
    }

    private async Task Dynamic(IJSRuntime js, string fnName)
    {
        /// ruleid: dsc-jsruntime-dynamic-identifier
        await js.InvokeVoidAsync(fnName);
    }

    private async Task Good(IJSRuntime js)
    {
        /// ok: dsc-jsruntime-eval
        await JS.InvokeVoidAsync("dsc.focusElement", "search");

        /// ok: dsc-jsruntime-dynamic-identifier
        await js.InvokeVoidAsync("dsc.focusElement", "search");

        /// ok: dsc-jsruntime-dynamic-identifier
        await js.InvokeVoidAsync(ScrollFn);
    }
}
