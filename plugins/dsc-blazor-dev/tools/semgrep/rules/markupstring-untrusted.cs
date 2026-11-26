using Ganss.Xss;
using Microsoft.AspNetCore.Components;

public partial class NoteView : ComponentBase
{
    [Parameter] public string Body { get; set; } = "";

    private readonly HtmlSanitizer _sanitizer = new();

    private MarkupString Unsafe()
    {
        /// ruleid: dsc-markupstring-untrusted
        return (MarkupString)Body;
    }

    private MarkupString UnsafeCtor()
    {
        /// ruleid: dsc-markupstring-untrusted
        return new MarkupString(Body);
    }

    private MarkupString Constant()
    {
        /// ok: dsc-markupstring-untrusted
        return (MarkupString)"<br />";
    }

    private MarkupString Sanitized()
    {
        /// ok: dsc-markupstring-untrusted
        return (MarkupString)_sanitizer.Sanitize(Body);
    }
}
